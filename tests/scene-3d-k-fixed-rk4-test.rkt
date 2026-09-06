#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(define (check-vec3-close actual expected [tolerance 1e-9])
  (check-= (vec3-x actual) (vec3-x expected) tolerance)
  (check-= (vec3-y actual) (vec3-y expected) tolerance)
  (check-= (vec3-z actual) (vec3-z expected) tolerance))

(module+ test
  (define constant-field (lambda (_x _y _z) (vec3 2 -1 4)))
  (define trajectory
    (prepare-ode-trajectory3d
     constant-field (vec3 1 3 -2)
     #:time-range (cons -2 3) #:step-size 1/4 #:checkpoint-every 3))
  (check-true (ode-trajectory3d? trajectory))
  (check-equal? (ode-trajectory3d-time-range trajectory) (cons -2 3))
  (check-equal? (ode-trajectory3d-step-size trajectory) 1/4)
  (check-equal? (ode-trajectory3d-checkpoint-every trajectory) 3)
  (check-eq? (ode-trajectory3d-solver trajectory) 'fixed-rk4)
  (for ([time (in-list (list -2 -3/4 0 9/8 3))])
    (check-vec3-close
     (ode-trajectory3d-position trajectory time)
     (vec3 (+ 1 (* 2 time)) (- 3 time) (+ -2 (* 4 time)))))

  ;; The four-argument form receives the physical integration time at every
  ;; stage.  x' = t gives x(t) = t²/2 in fixed RK4 exactly.
  (define time-trajectory
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z) (vec3 time 0 0)) origin3
     #:time-range (cons -2 3) #:step-size 1/4))
  (check-vec3-close (ode-trajectory3d-position time-trajectory 3) (vec3 9/2 0 0))
  (check-vec3-close (ode-trajectory3d-position time-trajectory -2) (vec3 2 0 0))
  (check-exn exn:fail:contract?
             (lambda () (ode-trajectory3d-position trajectory 4)))
  (check-exn exn:fail:contract?
             (lambda ()
               (prepare-ode-trajectory3d (lambda (_x _y) origin3) origin3
                                         #:time-range (cons 0 1)))))
