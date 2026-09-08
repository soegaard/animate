#lang racket/base

;;; SCENE-3D-T: explicit Poincare initial-hit policy.

(require rackunit
         "../3d.rkt")

(module+ test
  (define starts-on-plane
    (prepare-ode-trajectory3d
     (lambda (_x _y _z) x-axis3) origin3
     #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1/2)))
  (define section (plane3 origin3 x-axis3))

  ;; A return map normally excludes its domain point from reported crossings.
  (check-equal? (vector-length (poincare-section3d starts-on-plane section)) 0)
  (define included
    (poincare-section3d starts-on-plane section #:initial-hit 'include))
  (check-equal? (vector-length included) 1)
  (check-equal? (poincare-hit3d-time (vector-ref included 0)) 0)
  (check-equal?
   (vector-length
    (poincare-section3d starts-on-plane section #:initial-hit 'require))
   1)

  ;; `require` makes a missing domain crossing an explicit author error.
  (define starts-away
    (prepare-ode-trajectory3d
     (lambda (_x _y _z) x-axis3) (vec3 1 0 0)
     #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (poincare-section3d starts-away section #:initial-hit 'require))))
