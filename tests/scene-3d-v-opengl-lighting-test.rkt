#lang racket/base

;;; SCENE-3D-V6: OpenGL finite-light shader interface and selected-pixel parity

(require racket/file
         racket/runtime-path
         racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/3d/opengl/limits.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")
(define-runtime-path mesh-lit-path "../private/3d/opengl/shaders/mesh-lit.frag")

(define white-lambert
  (material3d #:color "white" #:shading 'flat #:lighting 'lambert
              #:ambient 1 #:diffuse 1 #:specular 0))

;; One large, planar triangle makes the selected interior pixel independent of
;; mesh normal interpolation and edge coverage.  Its two finite sources both
;; point at the camera-facing surface, so this one render exercises packed
;; point and spot records as well as the ambient contribution.
(define (finite-light-view #:point-intensity [point-intensity 1])
  (define mesh
    (mesh3d #:id 'surface
            #:vertices (vector (vec3 -3 -3 0) (vec3 3 -3 0) (vec3 0 3 0))
            #:triangles (vector (vector 0 1 2))
            #:material white-lambert))
  (view3d
   (list mesh) #:id 'world #:width 4 #:height 4 #:background "black" #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)
   #:lights
   (list (ambient-light3d #:intensity 1/10)
         (point-light3d (vec3 0 0 2) #:id 'point #:intensity point-intensity
                        #:attenuation (constant-attenuation3d #:factor 7/20))
         (spot-light3d (vec3 0 0 2) (vec3 0 0 -1) #:id 'spot #:intensity 1
                       #:inner-angle 1/4 #:outer-angle 1/2
                       #:attenuation (constant-attenuation3d #:factor 1/4)))))

(define (render backend view)
  (define request (view3d->render3d-request view 64 64))
  (renderer3d-render backend (renderer3d-prepare backend request) request))

(define (argb-pixel bytes index)
  (define offset (* 4 index))
  (vector (bytes-ref bytes offset)
          (bytes-ref bytes (add1 offset))
          (bytes-ref bytes (+ offset 2))
          (bytes-ref bytes (+ offset 3))))

(module+ test
  ;; This source-level contract is intentionally headless: it protects the
  ;; binding names shared by the Racket uploader and GLSL from accidental
  ;; drift, while the lane below compiles and executes the shader on a GPU.
  (define shader (file->string mesh-lit-path))
  (for ([required (in-list
                  '("ANIMATE_OPENGL_MAX_NON_AMBIENT_LIGHTS"
                    "nonAmbientLightKinds"
                    "nonAmbientLightPositions"
                    "nonAmbientLightAttenuationModes"
                    "finiteLightAttenuation"
                    "spotConeFactor"))])
    (check-true (regexp-match? (regexp-quote required) shader)))
  (check-equal? (opengl3d-limit 'directional-lights) 4)
  (check-equal? (opengl3d-limit 'point-lights) 8)
  (check-equal? (opengl3d-limit 'spot-lights) 4)
  (check-equal? (hash-ref (opengl3d-capability-limits) 'non-ambient-lights) 16)
  (check-true
   (regexp-match? #rx"ANIMATE_OPENGL_MAX_NON_AMBIENT_LIGHTS 16"
                  (opengl3d-shader-defines)))
  (define request (view3d->render3d-request (finite-light-view) 64 64))
  (check-true (set-member? (renderer3d-request-required-features request) 'point-light))
  (check-true (set-member? (renderer3d-request-required-features request) 'spot-light))
  (check-equal? (hash-ref (renderer3d-request-required-limits request)
                          'maximum-point-lights)
                1)
  (check-equal? (hash-ref (renderer3d-request-required-limits request)
                          'maximum-spot-lights)
                1))

;; The normal suite remains GUI-free.  This opt-in Racket 9.3 GRacket lane
;; compiles the amended GLSL and compares an interior pixel with the software
;; reference.  It also proves the public eight-point-light limit is enforced
;; before a fixed uniform array could silently truncate the authored list.
(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-opengl-renderer
      (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-opengl-spec
      (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define renderer-statistics
      (dynamic-require opengl-module-path 'opengl-renderer3d-statistics))
    (define renderer
      (make-opengl-renderer
       (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define capabilities (renderer3d-capabilities-of renderer))
       (check-true (renderer3d-supports? capabilities '(point-light spot-light)))
       (check-equal? (renderer3d-capability-limit capabilities 'maximum-point-lights) 8)
       (check-equal? (renderer3d-capability-limit capabilities 'maximum-spot-lights) 4)
       (define view (finite-light-view))
       (define expected (render (software-renderer3d) view))
       (define actual (render renderer view))
       (define index (+ 32 (* 32 64)))
       (define expected-pixel
         (argb-pixel (renderer3d-render-result-argb-bytes expected) index))
       (define actual-pixel
         (argb-pixel (renderer3d-render-result-argb-bytes actual) index))
       (for ([expected-channel (in-vector expected-pixel)]
             [actual-channel (in-vector actual-pixel)])
         (check-true (<= (abs (- expected-channel actual-channel)) 8)))
       (define uploads-before-light-change
         (hash-ref (hash-ref (renderer-statistics renderer) 'geometry-cache) 'uploads))
       ;; Light-only change uploads new uniforms but reuses the immutable mesh.
       (render renderer (finite-light-view #:point-intensity 1/2))
       (check-equal?
        (hash-ref (hash-ref (renderer-statistics renderer) 'geometry-cache) 'uploads)
        uploads-before-light-change)
       (define too-many-points
         (view3d
          (list (cube3d 1 #:id 'cube #:material white-lambert))
          #:id 'point-limit #:width 4 #:height 3 #:render-mode 'opaque
          #:lights
          (for/list ([index (in-range 9)])
            (point-light3d (vec3 0 0 2)
                           #:id (string->symbol (format "point-~a" index))))))
       (check-exn
        exn:fail?
        (lambda ()
          (renderer3d-prepare renderer
                              (view3d->render3d-request too-many-points 64 48)))))
     (lambda () (renderer3d-release renderer)))))
