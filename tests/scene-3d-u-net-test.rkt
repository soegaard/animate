#lang racket/base
(require rackunit "../3d.rkt"
         "../private/3d/net-overlap3d.rkt")
(define pts (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1) (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))
(module+ test
 (define c (polyhedral-complex3d (convex-hull3d-result-mesh (convex-hull3d pts))))
 (define net (prepare-polyhedron-net3d c))
 (check-equal? (polyhedron-net3d-root-face net) 0)
 (check-equal? (vector-length (polyhedron-net3d-hinge-tree net)) 5)
 (check-equal? (vector-length (polyhedron-net3d-cut-edges net)) 7)
 (check-equal? (vector-length (polyhedron-net3d-face-transforms net)) 6)
 (for ([p (in-vector (polyhedron-net3d-flat-polygons net))]) (check-equal? (vector-length p) 4))
 (check-equal? (polyhedron-net3d-overlaps net) '#())
 (check-equal? (hash-ref (polyhedron-net3d-diagnostics net) 'total-overlap-area) 0)
 (define minimum-overlap-net
   (prepare-polyhedron-net3d c #:strategy 'minimum-overlap #:search-limit 1000))
 (check-equal? (polyhedron-net3d-overlaps minimum-overlap-net) '#())
 (check-true (hash-ref (polyhedron-net3d-diagnostics minimum-overlap-net)
                        'search-complete?))
 (check-equal? (hash-ref (polyhedron-net3d-diagnostics minimum-overlap-net)
                         'candidate-count)
               384)
 (define bounded-search-net
   (prepare-polyhedron-net3d c #:strategy 'minimum-overlap #:search-limit 1))
 (check-false (hash-ref (polyhedron-net3d-diagnostics bounded-search-net)
                         'search-complete?))
 (check-equal? (hash-ref (polyhedron-net3d-diagnostics bounded-search-net)
                         'candidate-count)
               1)
 (define square-a
   (vector (vec3 0 0 0) (vec3 2 0 0) (vec3 2 2 0) (vec3 0 2 0)))
 (define square-b
   (vector (vec3 1 1 0) (vec3 3 1 0) (vec3 3 3 0) (vec3 1 3 0)))
 (define square-sharing-hinge
   (vector (vec3 2 0 0) (vec3 4 0 0) (vec3 4 2 0) (vec3 2 2 0)))
 (define overlap
   (net-polygons-overlaps3d (vector square-a square-b)
                            origin3 x-axis3 y-axis3))
 (check-equal? (vector-length overlap) 1)
 (check-equal? (net-overlap3d-area (vector-ref overlap 0)) 1)
 (check-equal? (net-polygons-overlaps3d (vector square-a square-sharing-hinge)
                                        origin3 x-axis3 y-axis3)
               '#()))
