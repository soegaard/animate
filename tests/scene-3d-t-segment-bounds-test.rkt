#lang racket/base

;;; SCENE-3D-T: dense segment bounds cover interior Hermite extrema.

(require rackunit
         "../3d.rkt")

(module+ test
  ;; p(t) = t - t^2 on this one-second Hermite segment.  Its endpoints are
  ;; both at x = 0, while its interior maximum is x = 1/4 at t = 1/2.
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z) (vec3 (- 1 (* 2 time)) 0 0))
     origin3
     #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1)))
  (define bounds
    (trajectory-segment3d-bounds
     (vector-ref (ode-trajectory3d-segments trajectory) 0)))
  (check-true (aabb3? bounds))
  (check-equal? (aabb3-minimum bounds) origin3)
  (check-= (vec3-x (aabb3-maximum bounds)) 1/4 1e-12)
  (check-true (aabb3-contains? bounds (ode-trajectory3d-position trajectory 1/2)))

  ;; The stored curve p(t) = (t, t^2, 0) has known length
  ;; sqrt(5)/2 + asinh(2)/4.  This distinguishes adaptive integration from a
  ;; fixed chord count and exercises the same value used by inverse lookup.
  (define curved
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z) (vec3 1 (* 2 time) 0))
     origin3
     #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1)))
  (define curved-length (+ (/ (sqrt 5) 2) (/ (log (+ 2 (sqrt 5))) 4)))
  (define measured-length (ode-trajectory3d-arc-length-at curved 1))
  (check-= measured-length curved-length 1e-9)
  (check-= (ode-trajectory3d-time-at-arc-length curved measured-length) 1 1e-9))
