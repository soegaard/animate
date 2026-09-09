#lang racket/base

;;; Software 3D theme rendering and alpha-pass selection

(require racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../colors.rkt"
         "../private/render-color-context.rkt")

(define (themed-view material)
  (view3d
   (list
    (mesh3d #:id 'themed-triangle
            #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
            #:triangles (vector (vector 0 1 2))
            #:material material))
   #:id 'themed-world #:width 4 #:height 4 #:background black #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)
   #:lights '()))

(define (render-bytes theme view)
  (parameterize ([current-render-color-context (make-render-color-context theme)])
    (define renderer (software-renderer3d))
    (define request (view3d->render3d-request view 64 64))
    (define result (renderer3d-render renderer (renderer3d-prepare renderer request) request))
    (renderer3d-render-result-argb-bytes result)))

(module+ test
  (define warm-palette
    (color-palette #:id 'render-warm #:extends animate-palette
                   #:colors (hash 'aqua-c "#e02020")))
  (define cool-palette
    (color-palette #:id 'render-cool #:extends animate-palette
                   #:colors (hash 'aqua-c "#2060e0")))
  (define warm-theme
    (color-theme #:id 'render-warm-theme #:extends animate-light-theme
                 #:palette warm-palette))
  (define cool-theme
    (color-theme #:id 'render-cool-theme #:extends animate-light-theme
                 #:palette cool-palette))
  (define opaque-view
    (themed-view (material3d #:color aqua-c #:shading 'unlit)))
  (define warm-bytes (render-bytes warm-theme opaque-view))
  (define cool-bytes (render-bytes cool-theme opaque-view))
  ;; A safely interior pixel differs under the palette switch.
  (check-not-equal? (subbytes warm-bytes (* 4 (+ 32 (* 32 64)))
                                (+ (* 4 (+ 32 (* 32 64))) 4))
                    (subbytes cool-bytes (* 4 (+ 32 (* 32 64)))
                                (+ (* 4 (+ 32 (* 32 64))) 4)))

  (define translucent-theme
    (color-theme #:id 'render-translucent #:extends animate-light-theme
                 #:roles (hash 'accent (color-with-alpha pure-blue 1/2))))
  (parameterize ([current-render-color-context
                  (make-render-color-context translucent-theme)])
    (define request
      (view3d->render3d-request
       (themed-view (material3d #:color theme-accent #:shading 'unlit)) 64 64))
    (check-true (set-member? (renderer3d-request-required-features request)
                             'transparency))))
