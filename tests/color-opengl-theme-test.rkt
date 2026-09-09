#lang racket/base

;;; Opt-in OpenGL theme integration

(require rackunit
         racket/runtime-path
         "../3d.rkt"
         "../3d/render.rkt"
         "../colors.rkt"
         "../private/render-color-context.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define (theme-view #:vertex-colors? [vertex-colors? #f])
  (view3d
   (list
    (mesh3d #:id (if vertex-colors? 'themed-attributes 'themed-material)
            #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
            #:triangles (vector (vector 0 1 2))
            #:colors (and vertex-colors? (vector aqua-c aqua-c aqua-c))
            #:material (material3d #:color aqua-c #:shading 'unlit)))
   #:id 'themed-opengl-world #:width 4 #:height 4 #:background black
   #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)))

(define (lit-light-view light-colour)
  (view3d
   (list
    (mesh3d #:id 'lit-light-triangle
            #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
            #:triangles (vector (vector 0 1 2))
            #:material (material3d #:color white #:shading 'flat
                                   #:lighting 'lambert #:ambient 1/4 #:diffuse 3/4)))
   #:id 'themed-opengl-lights #:width 4 #:height 4 #:background black
   #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)
   #:lights
   (list (ambient-light3d #:id 'ambient #:color light-colour #:intensity 1/4)
         (directional-light3d (vec3 0 0 -1) #:id 'directional
                              #:color light-colour #:intensity 1/4)
         (point-light3d (vec3 0 0 3) #:id 'point
                        #:color light-colour #:intensity 1/4)
         (spot-light3d (vec3 0 0 3) (vec3 0 0 -1) #:id 'spot
                       #:color light-colour #:intensity 1/4))))

(define (render! renderer theme view)
  (parameterize ([current-render-color-context (make-render-color-context theme)])
    (define request (view3d->render3d-request view 64 64))
    (renderer3d-render renderer (renderer3d-prepare renderer request) request)))

(module+ test
  ;; The normal suite is headless. CI's designated OpenGL lane supplies a real
  ;; GRacket context and turns this into a software/GL interior-pixel check.
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-renderer (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-spec (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define statistics (dynamic-require opengl-module-path 'opengl-renderer3d-statistics))
    (define release! (dynamic-require opengl-module-path 'opengl-renderer3d-release!))
    (define warm-theme
      (color-theme #:id 'gl-warm #:extends animate-light-theme
                   #:palette (color-palette #:id 'gl-warm-palette #:extends animate-palette
                                            #:colors (hash 'aqua-c "#e02020"))))
    (define cool-theme
      (color-theme #:id 'gl-cool #:extends animate-light-theme
                   #:palette (color-palette #:id 'gl-cool-palette #:extends animate-palette
                                            #:colors (hash 'aqua-c "#2060e0"))))
    (define renderer (make-renderer (make-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define material-view (theme-view))
       (define warm (render! renderer warm-theme material-view))
       (define uploads-before
         (hash-ref (hash-ref (statistics renderer) 'geometry-cache) 'uploads))
       (define cool (render! renderer cool-theme material-view))
       ;; A material-only palette change updates uniforms; its VBO is reused.
       (check-equal? (hash-ref (hash-ref (statistics renderer) 'geometry-cache) 'uploads)
                     uploads-before)
       (check-not-equal?
        (subbytes (renderer3d-render-result-argb-bytes warm) (* 4 (+ 32 (* 32 64)))
                  (+ (* 4 (+ 32 (* 32 64))) 4))
        (subbytes (renderer3d-render-result-argb-bytes cool) (* 4 (+ 32 (* 32 64)))
                  (+ (* 4 (+ 32 (* 32 64))) 4)))
       ;; Interleaved semantic vertex colours use an appearance-sensitive VBO
       ;; key, so they repack rather than falsely reporting a stale cache hit.
       (define attribute-view (theme-view #:vertex-colors? #t))
       (void (render! renderer warm-theme attribute-view))
       (define attribute-uploads
         (hash-ref (hash-ref (statistics renderer) 'geometry-cache) 'uploads))
       (void (render! renderer cool-theme attribute-view))
       (check-true (> (hash-ref (hash-ref (statistics renderer) 'geometry-cache) 'uploads)
                      attribute-uploads))
       ;; Each light kind follows the preparation-owned context. A tokenized
       ;; list agrees with an explicitly resolved literal reference, and A/B/A
       ;; reuse cannot consult a newer ambient theme while uploading uniforms.
       (define warm-lights (render! renderer warm-theme (lit-light-view aqua-c)))
       (define warm-literal
         (render! renderer animate-light-theme
                  (lit-light-view (resolve-color aqua-c warm-theme))))
       (check-equal? (renderer3d-render-result-argb-bytes warm-lights)
                     (renderer3d-render-result-argb-bytes warm-literal))
       (define cool-lights (render! renderer cool-theme (lit-light-view aqua-c)))
       (check-not-equal? (renderer3d-render-result-argb-bytes warm-lights)
                         (renderer3d-render-result-argb-bytes cool-lights))
       (define warm-again (render! renderer warm-theme (lit-light-view aqua-c)))
       (check-equal? (renderer3d-render-result-argb-bytes warm-lights)
                     (renderer3d-render-result-argb-bytes warm-again)))
     (lambda () (release! renderer)))))
