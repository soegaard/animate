#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
  (define saddle
    (linearize3d (lambda (x y z) (vec3 x (- y) (- (* 2 z))) )
                 (vec3 0 0 0)
                 #:jacobian (lambda (x y z) (linear3 1 0 0 0 -1 0 0 0 -2))))
  (check-equal? (linearization3d-classification saddle) 'saddle)
  (check-equal? (vector-length (linearization3d-real-directions saddle)) 3)
  (define spiral
    (linearize3d (lambda (x y z) (vec3 (- x y) (+ x (- y)) (- (* 2 z))))
                 (vec3 0 0 0)
                 #:jacobian (lambda (x y z) (linear3 -1 -1 0 1 -1 0 0 0 -2))))
  (check-equal? (linearization3d-classification spiral) 'spiral-sink)
  (check-equal? (vector-length (linearization3d-invariant-planes spiral)) 1)
  (check-true (plane3? (vector-ref (linearization3d-invariant-planes spiral) 0)))
  (define center
    (linearize3d (lambda (x y z) (vec3 (- y) x 0)) (vec3 0 0 0)
                 #:jacobian (lambda (x y z) (linear3 0 -1 0 1 0 0 0 0 0))))
  (check-equal? (linearization3d-classification center) 'center-like)
  (check-true (group3d? (linearization-diagram3d saddle #:id 'saddle-diagram))))
