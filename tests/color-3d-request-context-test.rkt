#lang racket/base

;;; A 3D request owns the color interpretation selected at construction

(require racket/set
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../colors.rkt"
         "../private/render-color-context.rkt")

(define (themed-view)
  (view3d
   (list
    (mesh3d #:id 'context-triangle
            #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
            #:triangles (vector (vector 0 1 2))
            #:material (material3d #:color theme-accent #:shading 'unlit)))
   #:id 'context-world #:width 4 #:height 4 #:background black #:render-mode 'opaque
   #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)
   #:lights '()))

(define (render-request renderer request)
  (define preparation (renderer3d-prepare renderer request))
  (renderer3d-render-result-argb-bytes
   (renderer3d-render renderer preparation request)))

(module+ test
  ;; Equal IDs intentionally prove that request identity follows resolved
  ;; appearance, not display/provenance metadata or ambient dynamic state.
  (define opaque-theme
    (color-theme #:id 'same-id #:extends animate-light-theme
                 #:roles (hash 'accent pure-blue)))
  (define translucent-theme
    (color-theme #:id 'same-id #:extends animate-light-theme
                 #:roles (hash 'accent (color-with-alpha pure-red 1/2))))
  (define request-a (view3d->render3d-request (themed-view) 64 64 #:theme opaque-theme))
  (define request-b (view3d->render3d-request (themed-view) 64 64 #:theme translucent-theme))
  (check-false (set-member? (renderer3d-request-required-features request-a) 'transparency))
  (check-true (set-member? (renderer3d-request-required-features request-b) 'transparency))

  (parameterize ([current-render-color-context
                  (make-render-color-context translucent-theme)])
    (define renderer (software-renderer3d))
    (dynamic-wind
     void
     (lambda ()
       ;; The ambient context is B, but A's request was already complete.
       (define preparation-a (renderer3d-prepare renderer request-a))
       (define bytes-a
         (renderer3d-render-result-argb-bytes
          (renderer3d-render renderer preparation-a request-a)))
       (define bytes-b (render-request renderer request-b))
       (check-not-equal? bytes-a bytes-b)
       (check-not-equal? (renderer3d-fingerprint renderer request-a)
                         (renderer3d-fingerprint renderer request-b))
       ;; Combining A's resolved preparation with B's request is never an
       ;; implicit theme switch: the backend makes the mismatch explicit.
       (check-exn exn:fail?
                  (lambda () (renderer3d-render renderer preparation-a request-b))))
     (lambda () (renderer3d-release renderer)))))
