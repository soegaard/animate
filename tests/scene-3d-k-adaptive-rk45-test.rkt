#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(define (check-vec3-close actual expected [tolerance 1e-6])
  (check-= (vec3-x actual) (vec3-x expected) tolerance)
  (check-= (vec3-y actual) (vec3-y expected) tolerance)
  (check-= (vec3-z actual) (vec3-z expected) tolerance))

(module+ test
  (define calls (box 0))
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z)
       (set-box! calls (add1 (unbox calls)))
       (vec3 time 0 1))
     origin3
     #:time-range (cons -2 3)
     #:solver (adaptive-rk45 #:relative-tolerance 1e-9
                             #:absolute-tolerance 1e-11
                             #:initial-step 1/10)))
  (check-true (adaptive-rk45? (ode-trajectory3d-solver trajectory)))
  (define diagnostics (ode-trajectory3d-diagnostics trajectory))
  (check-true (ode-trajectory3d-diagnostics? diagnostics))
  (check-true (positive? (ode-trajectory3d-diagnostics-accepted-steps diagnostics)))
  (check-vec3-close (ode-trajectory3d-position trajectory 3) (vec3 9/2 0 3))
  (check-vec3-close (ode-trajectory3d-position trajectory -2) (vec3 2 0 -2))
  ;; Dense lookup reads only accepted nodes and their stored derivatives.
  (set-box! calls 0)
  (for ([time (in-list (list -2 -3/4 0 9/8 3))])
    (ode-trajectory3d-position trajectory time))
  (check-equal? (unbox calls) 0))
