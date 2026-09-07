#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
  (define trajectory
    (prepare-ode-trajectory3d (lambda (x y z) (vec3 1 0 0)) (vec3 0 0 0)
                              #:time-range (cons 0 1)
                              #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (check-equal? (hash-ref (trajectory-inspection3d trajectory) 'kind) 'trajectory)
  (define map (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0))
                                  (explicit-seeds3d (list (vec3 0 0 0)))))
  (check-equal? (hash-ref (flow-map-inspection3d map 0) 'source) (vec3 0 0 0))
  (define linear (linearize3d (lambda (x y z) (vec3 x y z)) (vec3 0 0 0)
                              #:jacobian (lambda (x y z) (linear3 1 0 0 0 2 0 0 0 3))))
  (check-equal? (hash-ref (linearization-inspection3d linear) 'classification) 'source))
