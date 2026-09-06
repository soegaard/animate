#lang racket/base

;;; SCENE-3D-H Standard Solid Tests

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (check-equal? (vector-length (mesh3d-vertices cube)) 8)
  (check-equal? (vector-length (mesh3d-triangles cube)) 12)
  (check-not-false (mesh3d-normals cube))
  (check-equal? (vector-length (mesh3d-triangles (tetrahedron3d 1 #:id 'tetra))) 4)
  (check-equal? (vector-length (mesh3d-triangles (octahedron3d 1 #:id 'octa))) 8)
  (check-equal? (vector-length (mesh3d-triangles (icosahedron3d 1 #:id 'icosa))) 20)
  (check-equal? (vector-length (mesh3d-vertices (sphere3d 1 #:id 'sphere #:latitude-segments 3 #:longitude-segments 4))) 10)
  (check-equal? (vector-length (mesh3d-triangles (torus3d 2 1 #:id 'torus #:major-segments 4 #:minor-segments 3))) 24))
