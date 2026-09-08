#lang racket/base

;;; SCENE-3D-T: low-speed termination observes Hermite interior extrema.

(require rackunit
         "../3d.rkt")

(module+ test
  ;; The stored derivative is (t - 1/3, 0, 0). Its zero lies strictly inside
  ;; this one-second RK4 step, so node/midpoint-only sampling would miss the
  ;; requested 1/10 threshold.
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z) (vec3 (- time 1/3) 0 0))
     origin3
     #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1)
     #:termination (trajectory-termination3d #:minimum-speed 1/10)))
  (define hit (vector-ref (ode-trajectory3d-termination trajectory) 0))
  (check-equal? (trajectory-termination-hit3d-reason hit) 'minimum-speed)
  ;; The first threshold crossing is t = 1/3 - 1/10.
  (check-= (trajectory-termination-hit3d-time hit) 7/30 1e-8)
  (check-equal? (car (reverse (trajectory-termination-hit3d-details hit)))
                'dense-speed-bisection))
