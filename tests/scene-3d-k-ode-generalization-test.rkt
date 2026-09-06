#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../private/ode-state-space.rkt")

(module+ test
  (check-equal? (ode-state-space-dimension real-ode-state-space) 1)
  (check-equal? (ode-state-space-dimension vec2-ode-state-space) 2)
  (check-equal? (ode-state-space-dimension vec3-ode-state-space) 3)

  ;; The same generic RK4 operation accepts the established 2D representation
  ;; and the new spatial representation; neither pathway has a bespoke RK4.
  (check-equal?
   (ode-state-space-rk4-step
    vec2-ode-state-space (lambda (_time _point) (vec2 2 -1)) 0 origin 3/4)
   (vec2 3/2 -3/4))
  (check-equal?
   (ode-state-space-rk4-step
    vec3-ode-state-space (lambda (_time _point) (vec3 2 -1 4)) 0 origin3 3/4)
   (vec3 3/2 -3/4 3))

  (define vectors (numeric-vector-ode-state-space 3))
  (define vector-seed (vector-immutable 1 2 3))
  (define vector-result
    (ode-state-space-rk4-step
     vectors (lambda (_time _point) (vector-immutable 2 -1 4)) 0 vector-seed 3/4))
  (check-true (immutable? vector-result))
  (check-equal? vector-result (vector-immutable 5/2 5/4 6))
  (check-exn exn:fail:contract?
             (lambda () (ode-state-space-check-state 'test vectors (vector 1 2 3))))

  ;; The public two-dimensional wrapper still delegates to the generic core.
  (check-equal?
   (ode-flow-position (lambda (_x _y) (vec2 2 -1)) origin 3/4 #:step-size 1/4)
   (vec2 3/2 -3/4)))
