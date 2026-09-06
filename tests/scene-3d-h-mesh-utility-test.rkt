#lang racket/base

;;; SCENE-3D-H Mesh Utility Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define triangle
    (polyhedron3d (vector origin3 (vec3 1 0 0) (vec3 0 1 0))
                  (vector (vector 0 1 2)) #:id 'triangle))
  (check-equal? (vector-length (mesh3d-boundary-edges triangle)) 3)
  (check-equal? (vector-ref (vector-ref (mesh3d-triangles (mesh3d-reverse-winding triangle)) 0) 1) 2)
  (check-equal? (vector-length (mesh3d-vertices (mesh3d-flat-normals triangle))) 3)
  (check-not-false (mesh3d-normals (mesh3d-smooth-normals triangle)))
  (check-true (material3d-wireframe? (mesh3d-material (mesh3d-wireframe triangle))))
  (check-equal? (vector-length (mesh3d-vertices (mesh3d-merge (list triangle triangle) #:id 'pair))) 6)
  (check-equal? (vec3-x (vector-ref (mesh3d-vertices (mesh3d-transform triangle (make-transform3 #:translation (vec3 2 0 0)))) 0)) 2))
