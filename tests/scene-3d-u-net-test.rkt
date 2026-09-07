#lang racket/base
(require rackunit "../3d.rkt")
(define pts (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1) (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))
(module+ test
 (define c (polyhedral-complex3d (convex-hull3d-result-mesh (convex-hull3d pts))))
 (define net (prepare-polyhedron-net3d c))
 (check-equal? (polyhedron-net3d-root-face net) 0)
 (check-equal? (vector-length (polyhedron-net3d-hinge-tree net)) 5)
 (check-equal? (vector-length (polyhedron-net3d-cut-edges net)) 7)
 (check-equal? (vector-length (polyhedron-net3d-face-transforms net)) 6)
 (for ([p (in-vector (polyhedron-net3d-flat-polygons net))]) (check-equal? (vector-length p) 4)))
