#lang racket/base

;;; SCENE-3D-T0: dense prepared trajectories are immutable lookup data.

(require rackunit
         "../3d.rkt")

(define (check-vec3-close actual expected [tolerance 1e-8])
  (check-= (vec3-x actual) (vec3-x expected) tolerance)
  (check-= (vec3-y actual) (vec3-y expected) tolerance)
  (check-= (vec3-z actual) (vec3-z expected) tolerance))

(module+ test
  (define calls (box 0))
  (define field
    (ode-field3d
     (lambda (_x _y _z)
       (set-box! calls (add1 (unbox calls)))
       (vec3 2 -1 4))
     #:cache-key 'constant-flow))
  (define trajectory
    (prepare-ode-trajectory3d
     field (vec3 1 3 -2)
     #:time-range (cons -2 3)
     #:solver (fixed-rk4-solver3d #:step-size 1/4)))

  (check-true (prepared-trajectory3d? trajectory))
  (check-true (fixed-rk4-solver3d? (ode-trajectory3d-solver trajectory)))
  (check-true (positive?
               (ode-trajectory3d-diagnostics-dense-segment-count
                (ode-trajectory3d-diagnostics trajectory))))
  (check-equal? (ode-field3d-cache-key field) 'constant-flow)
  (check-true (positive? (unbox calls)))

  ;; Neither lookup path may reach the author procedure after preparation.
  (set-box! calls 0)
  (for ([time (in-list (list 3 -2 9/8 -3/4 0 2 1 -1))])
    (check-vec3-close
     (ode-trajectory3d-position trajectory time)
     (vec3 (+ 1 (* 2 time)) (- 3 time) (+ -2 (* 4 time))))
    (check-vec3-close (ode-trajectory3d-derivative trajectory time) (vec3 2 -1 4))
    (check-= (ode-trajectory3d-speed trajectory time) (sqrt 21) 1e-8)
    (ode-trajectory3d-segment-index trajectory time))
  (check-equal? (unbox calls) 0)

  ;; Arc-length queries are computed from the same dense segment table and
  ;; invert one another without a new integration pass.
  (define three-time-units (* 3 (sqrt 21)))
  (check-= (ode-trajectory3d-arc-length-at trajectory 1) three-time-units 1e-8)
  (check-= (ode-trajectory3d-time-at-arc-length trajectory three-time-units) 1 1e-7)
  (check-equal? (unbox calls) 0))
