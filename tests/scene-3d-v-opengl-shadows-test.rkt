#lang racket/base

;;; SCENE-3D-V9: OpenGL shadow-map cache and opt-in GPU execution

(require racket/file
         racket/runtime-path
         racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../colors.rkt"
         "../private/3d/opengl/limits.rkt"
         "../private/3d/opengl/shadow-cache.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")
(define-runtime-path mesh-lit-path "../private/3d/opengl/shaders/mesh-lit.frag")
(define-runtime-path shadow-vert-path "../private/3d/opengl/shaders/shadow.vert")
(define-runtime-path shadow-frag-path "../private/3d/opengl/shaders/shadow.frag")

(define receiver-material
  (material3d #:color "white" #:shading 'flat #:lighting 'lambert
              #:ambient 0 #:diffuse 1 #:specular 0 #:casts-shadow? #f))
(define caster-material
  (material3d #:color "gray" #:shading 'flat #:lighting 'lambert
              #:ambient 0 #:diffuse 1 #:specular 0))

(define (square id half-size z material #:colors [colors #f]
                #:transform [transform identity-transform3])
  (mesh3d #:id id
          #:vertices
          (vector (vec3 (- half-size) (- half-size) z)
                  (vec3 half-size (- half-size) z)
                  (vec3 half-size half-size z)
                  (vec3 (- half-size) half-size z))
          #:triangles (vector (vector 0 1 2) (vector 0 2 3))
          #:colors colors
          #:transform transform
          #:material material))

(define (shadow-view #:camera [camera
                                (orthographic-camera3d #:position (vec3 0 0 8)
                                                       #:look-at origin3
                                                       #:vertical-size 6)]
                     #:caster-z [caster-z 1]
                     #:shadow? [shadow? #t]
                     #:themed-caster-colors [themed-caster-colors #f]
                     #:persistent-caster? [persistent-caster? #f]
                     #:bias [bias #f])
  (define bounds (aabb3 (vec3 -3 -3 0) (vec3 3 3 caster-z)))
  (define settings
    (if bias
        (shadow-settings3d #:map-size 128 #:bias bias #:bounds bounds)
        (shadow-settings3d #:map-size 128 #:pcf-radius 0
                           #:depth-bias 1/100 #:normal-bias 0 #:bounds bounds)))
  (view3d
   (filter values
           (list (square 'receiver 3 0 receiver-material)
                 (square 'caster 1/3 caster-z caster-material
                         #:colors themed-caster-colors)
                 (and persistent-caster?
                      (square 'persistent-caster 1/4 caster-z caster-material
                              #:transform (make-transform3 #:translation (vec3 -2 0 0))))))
   #:id 'opengl-shadow-world #:width 6 #:height 6 #:background "black" #:render-mode 'opaque
   #:camera camera
   #:lights
   (list (directional-light3d
          (vec3 1 0 -1) #:id 'sun
          #:shadow (and shadow? (directional-shadow3d #:settings settings))))))

(define (render backend view #:theme [theme animate-light-theme])
  (define request (view3d->render3d-request view 64 64 #:theme theme))
  (renderer3d-render backend (renderer3d-prepare backend request) request))

(define (red-at result x y)
  (bytes-ref (renderer3d-render-result-argb-bytes result)
             (add1 (* 4 (+ x (* y 64))))))

(module+ test
  ;; The generic cache has no GUI/GL dependency. These observations establish
  ;; reuse, LRU reclamation, and release cleanup deterministically.
  (define destroyed '())
  (define created 0)
  (define cache (make-gl-shadow-cache #:max-bytes 8))
  (define (make-target)
    (set! created (add1 created))
    (string->symbol (format "target-~a" created)))
  (define (destroy-target target)
    (set! destroyed (cons target destroyed)))
  (define-values (first first-hit?)
    (gl-shadow-cache-ensure/current! cache 'a 4 make-target destroy-target))
  (check-false first-hit?)
  (define-values (again again-hit?)
    (gl-shadow-cache-ensure/current! cache 'a 4 make-target destroy-target))
  (check-true again-hit?)
  (check-eq? (gl-shadow-cache-entry-target first)
             (gl-shadow-cache-entry-target again))
  (call-with-values
   (lambda () (gl-shadow-cache-ensure/current! cache 'b 4 make-target destroy-target))
   (lambda _ (void)))
  ;; Touch a once more, then adding c must evict b rather than the actively
  ;; reused map a. This is the camera-only-change reuse policy in miniature.
  (call-with-values
   (lambda () (gl-shadow-cache-ensure/current! cache 'a 4 make-target destroy-target))
   (lambda _ (void)))
  (call-with-values
   (lambda () (gl-shadow-cache-ensure/current! cache 'c 4 make-target destroy-target))
   (lambda _ (void)))
  (check-equal? (hash-ref (gl-shadow-cache-statistics cache) 'entries) 2)
  (check-equal? (hash-ref (gl-shadow-cache-statistics cache) 'bytes) 8)
  (check-not-false (member 'target-2 destroyed))
  (gl-shadow-cache-clear/current! cache destroy-target)
  (check-equal? (hash-ref (gl-shadow-cache-statistics cache) 'entries) 0)
  (check-equal? (hash-ref (gl-shadow-cache-statistics cache) 'bytes) 0)

  ;; Shader names are a headless contract between the cache uploader and the
  ;; GLSL programs. The opt-in lane below additionally compiles and executes
  ;; them in the Racket 9.3 OpenGL context.
  (define mesh-shader (file->string mesh-lit-path))
  (for ([required (in-list
                  '("ANIMATE_OPENGL_MAX_SHADOW_MAPS"
                    "materialReceivesShadow"
                    "shadowMapLightIndices"
                    "shadowViewProjections"
                    "shadowTexelSizes"
                    "shadowBiasModes"
                    "shadowWorldNormalOffsets"
                    "shadowTexelWorldSizes"
                    "shadowFactor"))])
    (check-true (regexp-match? (regexp-quote required) mesh-shader)))
  (check-equal? (opengl3d-limit 'shadow-maps) 8)
  (check-true
   (regexp-match? #rx"ANIMATE_OPENGL_MAX_SHADOW_MAPS 8"
                  (opengl3d-shader-defines)))
  (check-true (regexp-match? #rx"gl_Position" (file->string shadow-vert-path)))
  (check-true (regexp-match? #rx"clipPlanes" (file->string shadow-frag-path)))
  (define request (view3d->render3d-request (shadow-view) 64 64))
  (check-true (set-member? (renderer3d-request-required-features request)
                           'directional-shadow))
  (check-equal? (hash-ref (renderer3d-request-required-limits request)
                          'maximum-shadow-lights)
                1))

;; Kept opt-in because it starts a live Racket 9.3 GL context. It proves that
;; a shadowed pixel differs from its unshadowed reference, camera-only changes
;; reuse the semantic map, caster motion invalidates it, and release succeeds.
(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-opengl-renderer
      (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-opengl-spec
      (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define renderer-statistics
      (dynamic-require opengl-module-path 'opengl-renderer3d-statistics))
    (define renderer-release
      (dynamic-require opengl-module-path 'opengl-renderer3d-release!))
    (define renderer
      (make-opengl-renderer
       (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define caps (renderer3d-capabilities-of renderer))
       (check-true (renderer3d-supports? caps '(directional-shadow)))
       (check-equal? (renderer3d-capability-limit caps 'maximum-shadow-lights) 8)
       (define view (shadow-view))
       (define actual (render renderer view))
       (define lit (render renderer (shadow-view #:shadow? #f)))
       (define probe-x 43)
       (define probe-y 32)
       (check-true (< (red-at actual probe-x probe-y)
                      (- (red-at lit probe-x probe-y) 80)))
       ;; A finite map must not turn the receiver uniformly black: this probe
       ;; is on the lit side of the same broad receiver. It also distinguishes
       ;; a real sampled depth map from a missing/zero texture binding.
       (check-true (<= (abs (- (red-at actual 20 probe-y)
                               (red-at lit 20 probe-y)))
                       12))
       ;; This invokes the semantic, world-space bias path in the live shader.
       ;; It need not have the legacy scene's pixels, but it must agree with
       ;; the software interpretation at an interior receiver sample.
       (define semantic-view
         (shadow-view
          #:bias (shadow-bias3d #:world-normal-offset 1/200
                                #:slope-scale 1/2
                                #:constant-depth-offset 1/1000
                                #:pcf-radius-texels 0)))
       (define semantic-software (render (software-renderer3d) semantic-view))
       (define semantic-opengl (render renderer semantic-view))
       (check-true
        (<= (abs (- (red-at semantic-opengl probe-x probe-y)
                    (red-at semantic-software probe-x probe-y)))
            12))
       (define allocations
         (hash-ref (hash-ref (renderer-statistics renderer) 'shadow-cache) 'allocations))
       (render renderer (shadow-view
                         #:camera (orthographic-camera3d #:position (vec3 1 1 8)
                                                        #:look-at origin3
                                                        #:vertical-size 6)))
       (check-equal? (hash-ref (hash-ref (renderer-statistics renderer) 'shadow-cache)
                               'allocations)
                     allocations)
       (render renderer (shadow-view #:caster-z 3/2))
       (check-equal? (hash-ref (hash-ref (renderer-statistics renderer) 'shadow-cache)
                               'allocations)
                     (add1 allocations))
       ;; Vertex alpha is a shadow-caster eligibility input. The fixed bounds
       ;; and persistent opaque caster force both appearances through a real
       ;; cache lookup, so retained/fresh equality detects an old depth map.
       (define alpha-colors
         (vector (role-color 'shadow-caster) (role-color 'shadow-caster)
                 (role-color 'shadow-caster) (role-color 'shadow-caster)))
       (define opaque-theme
         (color-theme #:id 'same-shadow-theme #:extends animate-light-theme
                      #:roles (hash 'shadow-caster "white")))
       (define translucent-theme
         (color-theme #:id 'same-shadow-theme #:extends animate-light-theme
                      #:roles (hash 'shadow-caster (color-with-alpha white 1/2))))
       (define alpha-view
         (shadow-view #:themed-caster-colors alpha-colors #:persistent-caster? #t))
       (void (render renderer alpha-view #:theme opaque-theme))
       (define retained-b (render renderer alpha-view #:theme translucent-theme))
       (define fresh-b-renderer
         (make-opengl-renderer
          (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
       (dynamic-wind
        void
        (lambda ()
          (define fresh-b (render fresh-b-renderer alpha-view #:theme translucent-theme))
          (check-equal? (renderer3d-render-result-argb-bytes retained-b)
                        (renderer3d-render-result-argb-bytes fresh-b)))
        (lambda () (renderer-release fresh-b-renderer)))
       (define retained-a (render renderer alpha-view #:theme opaque-theme))
       (define fresh-a-renderer
         (make-opengl-renderer
          (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
       (dynamic-wind
        void
        (lambda ()
          (define fresh-a (render fresh-a-renderer alpha-view #:theme opaque-theme))
          (check-equal? (renderer3d-render-result-argb-bytes retained-a)
                        (renderer3d-render-result-argb-bytes fresh-a)))
        (lambda () (renderer-release fresh-a-renderer))))
     (lambda () (renderer-release renderer)))
    (check-equal? (hash-ref (hash-ref (renderer-statistics renderer) 'shadow-cache)
                            'entries)
                  0)))
