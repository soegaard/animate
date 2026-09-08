#lang racket/base

;;; SCENE-3D-T: segment-local multi-root and touching event isolation.

(require rackunit
         "../3d.rkt")

(define (one-step events)
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) x-axis3) origin3
   #:time-range (cons 0 1)
   #:solver (fixed-rk4-solver3d #:step-size 1)
   #:events events))

(define (hit-times trajectory)
  (for/list ([hit (in-vector (ode-trajectory3d-event-hits trajectory))])
    (ode-event-hit3d-time hit)))

(module+ test
  ;; Two and three sign-changing roots are retained even though the accepted
  ;; solver step has same-sign endpoints.
  (define two-roots
    (ode-event3d #:id 'two #:terminal? #f
                 #:function (lambda (point)
                              (* (- (vec3-x point) 1/5)
                                 (- (vec3-x point) 4/5)))))
  (define two-root-times (hit-times (one-step (list two-roots))))
  (check-equal? (length two-root-times) 2)
  (check-= (car two-root-times) 1/5 1e-8)
  (check-= (cadr two-root-times) 4/5 1e-8)

  (define three-roots
    (ode-event3d #:id 'three #:terminal? #f
                 #:function (lambda (point)
                              (* (- (vec3-x point) 1/8)
                                 (- (vec3-x point) 1/2)
                                 (- (vec3-x point) 7/8)))))
  (check-equal? (hit-times (one-step (list three-roots)))
                (list 1/8 1/2 7/8))

  ;; A root at a sample point with equal positive neighbours is a touching
  ;; contact. It is only reported when the event says to retain touches.
  (define touching-function
    (lambda (point)
      (define distance (- (vec3-x point) 1/2))
      (* distance distance)))
  (check-equal?
   (vector-length
    (ode-trajectory3d-event-hits
     (one-step (list (ode-event3d #:id 'crossing-only #:terminal? #f
                                  #:function touching-function)))))
   0)
  (define touching
    (one-step
     (list (ode-event3d #:id 'touch #:terminal? #f #:root-kind 'touching
                         #:function touching-function))))
  (check-equal? (hit-times touching) (list 1/2))
  (check-equal? (ode-event-hit3d-direction
                 (vector-ref (ode-trajectory3d-event-hits touching) 0))
                'touching)

  ;; The monitor stops an accepted step at its first terminal root rather
  ;; than allowing a later root in that same step to win by postprocessing.
  (define terminal
    (one-step (list (ode-event3d #:id 'first-root #:function
                                  (ode-event3d-function two-roots)))))
  (check-= (cdr (ode-trajectory3d-time-range terminal)) 1/5 1e-8)
  (define terminal-times (hit-times terminal))
  (check-equal? (length terminal-times) 1)
  (check-= (car terminal-times) 1/5 1e-8))
