#lang racket/base

;;; Theme changes preserve semantic geometry caches

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../colors.rkt"
         "../private/render-color-context.rkt")

(define mesh
  (mesh3d #:id 'shared-geometry
          #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 0 2 0))
          #:triangles (vector (vector 0 1 2))
          #:material (material3d #:color aqua-c #:shading 'unlit)))

(define view
  (view3d (list mesh) #:id 'shared-world #:width 4 #:height 4 #:background black
          #:render-mode 'opaque
          #:camera (orthographic-camera3d #:position (vec3 0 0 3) #:look-at origin3)))

(define (render! renderer theme)
  (parameterize ([current-render-color-context (make-render-color-context theme)])
    (define request (view3d->render3d-request view 64 64))
    (renderer3d-render renderer (renderer3d-prepare renderer request) request)))

(module+ test
  (define alternate-theme
    (color-theme #:id 'alternate-geometry-theme #:extends animate-light-theme
                 #:palette
                 (color-palette #:id 'alternate-geometry-palette #:extends animate-palette
                                #:colors (hash 'aqua-c "#e02020"))))
  (define renderer (retained-software-renderer3d))
  (void (render! renderer animate-light-theme))
  (define after-first (renderer3d-statistics-snapshot renderer))
  (void (render! renderer alternate-theme))
  (define after-second (renderer3d-statistics-snapshot renderer))
  ;; Prepared frame colours are different cache entries, but the reusable
  ;; geometry resource is hit rather than reconstructed.
  (check-true (> (renderer3d-statistics-geometry-cache-hits after-second)
                 (renderer3d-statistics-geometry-cache-hits after-first)))
  (check-equal? (mesh3d-vertices mesh)
                (mesh3d-vertices
                 (compiled-geometry3d-mesh
                  (vector-ref (compiled-view3d-geometries (compile-view3d view)) 0))))
  (check-equal? (mesh3d-triangles mesh)
                (mesh3d-triangles
                 (compiled-geometry3d-mesh
                  (vector-ref (compiled-view3d-geometries (compile-view3d view)) 0)))))
