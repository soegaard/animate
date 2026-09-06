#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define bounds (aabb3 (vec3 -1 -1 -1) (vec3 1 1 1)))
  (define hit (ray3-intersect-aabb (ray3 (vec3 0 0 3) (vec3 0 0 -1)) bounds))
  (check-true (ray3-aabb-hit? hit))
  (check-= (ray3-aabb-hit-entry hit) 2 1e-12)
  (check-= (ray3-aabb-hit-exit hit) 4 1e-12)
  (check-false
   (ray3-intersect-aabb (ray3 (vec3 2 0 3) (vec3 0 0 -1)) bounds)))
