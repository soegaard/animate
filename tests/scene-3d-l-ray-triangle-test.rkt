#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define first (vec3 -1 -1 0))
  (define second (vec3 1 -1 0))
  (define third (vec3 0 1 0))
  (define hit
    (ray3-intersect-triangle (ray3 (vec3 0 0 3) (vec3 0 0 -1)) first second third))
  (check-true (ray3-triangle-hit? hit))
  (check-equal? (ray3-triangle-hit-point hit) origin3)
  (check-equal? (ray3-triangle-hit-distance hit) 3)
  (check-= (+ (vec3-x (ray3-triangle-hit-barycentric hit))
              (vec3-y (ray3-triangle-hit-barycentric hit))
              (vec3-z (ray3-triangle-hit-barycentric hit)))
           1 1e-12)
  (check-= (vec3-z (ray3-triangle-hit-normal hit)) 1 1e-12)
  ;; Picking remains double-sided even when a renderer would cull this face.
  (check-true
   (ray3-triangle-hit?
    (ray3-intersect-triangle (ray3 (vec3 0 0 -3) (vec3 0 0 1)) first second third)))
  (check-false
   (ray3-intersect-triangle (ray3 (vec3 3 3 3) (vec3 0 0 -1)) first second third)))
