#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define mesh
    (cube3d 2 #:id 'cube))
  (define first (mesh3d-bvh mesh))
  (define second (mesh3d-bvh mesh))
  (check-true (mesh3d-bvh? first))
  (check-eq? first second)
  ;; Geometry, not style or object identity, owns the acceleration cache.
  ;; Both independently constructed cubes remain live for this assertion, so
  ;; their equal immutable position/topology fingerprint shares one BVH.
  (define equal-geometry (cube3d 2 #:id 'styled-copy))
  (check-eq? first (mesh3d-bvh equal-geometry))
  (check-equal? (sort (bvh3d-triangle-indices first) <)
                (build-list (vector-length (mesh3d-triangles mesh)) values))
  (define candidates
    (bvh3d-ray-candidates first (ray3 (vec3 0 0 4) (vec3 0 0 -1))))
  (check-true (pair? candidates))
  (check-true (andmap exact-nonnegative-integer? candidates)))
