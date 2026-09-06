#lang racket/base

;;;
;;; SCENE-3D-B Mesh Validation Tests
;;;

(require rackunit
         "../3d.rkt")

(module+ test
  (define source-vertices
    (vector (vec3 -1 -2 -3) (vec3 4 5 6) (vec3 0 1 2)))
  (define mesh
    (mesh3d #:id 'mesh
            #:vertices source-vertices
            #:triangles (vector (vector 0 1 2))))
  (vector-set! source-vertices 0 origin3)
  (check-true (immutable? (mesh3d-vertices mesh)))
  (check-true (immutable? (mesh3d-triangles mesh)))
  (check-true (immutable? (mesh3d-edges mesh)))
  (check-equal? (vector-ref (mesh3d-vertices mesh) 0) (vec3 -1 -2 -3))
  (check-equal? (vector-length (mesh3d-edges mesh)) 3)
  (check-equal? (aabb3-minimum (mesh3d-local-bounds mesh)) (vec3 -1 -2 -3))
  (check-equal? (aabb3-maximum (mesh3d-local-bounds mesh)) (vec3 4 5 6))
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices (vector origin3)
                       #:edges (vector (vector 0 1)))))
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices (vector origin3 (vec3 1 0 0))
                       #:triangles (vector (vector 0 0 1)))))
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices (vector origin3)
                       #:normals (vector (vec3 0 0 1) (vec3 0 0 1))))))
