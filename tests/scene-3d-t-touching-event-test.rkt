#lang racket/base

;;; SCENE-3D-T: bounded isolation finds off-grid grazing contacts.

(require rackunit
         "../3d.rkt")

(define root 3/8)

(define (one-step event)
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) x-axis3)
   origin3
   #:time-range (cons 0 1)
   #:solver (fixed-rk4-solver3d #:step-size 1)
   #:events (list event)))

(module+ test
  ;; With one initial interval, 3/8 is neither endpoint nor midpoint.  The
  ;; contact is nevertheless found by the bounded adaptive isolation pass.
  (define touching
    (one-step
     (ode-event3d #:id 'off-grid-touch
                  #:terminal? #f
                  #:root-kind 'touching
                  #:initial-subdivisions 1
                  #:maximum-depth 3
                  #:function
                  (lambda (point)
                    (define distance (- (vec3-x point) root))
                    (* distance distance)))))
  (define touching-hits (ode-trajectory3d-event-hits touching))
  (check-equal? (vector-length touching-hits) 1)
  (check-= (ode-event-hit3d-time (vector-ref touching-hits 0)) root 1e-12)
  (check-equal? (ode-event-hit3d-direction (vector-ref touching-hits 0))
                'touching)

  ;; The depth control is real: without an isolation subdivision, only the
  ;; initial endpoints are observed and this off-grid touch remains hidden.
  (define shallow
    (one-step
     (ode-event3d #:id 'shallow-touch
                  #:terminal? #f
                  #:root-kind 'touching
                  #:initial-subdivisions 1
                  #:maximum-depth 0
                  #:function
                  (lambda (point)
                    (define distance (- (vec3-x point) root))
                    (* distance distance)))))
  (check-equal? (vector-length (ode-trajectory3d-event-hits shallow)) 0)

  ;; A crossing-only declaration retains its established contract: detecting
  ;; a grazing contact does not make it a directional crossing.
  (define crossing-only
    (one-step
     (ode-event3d #:id 'off-grid-crossing-only
                  #:terminal? #f
                  #:root-kind 'crossing
                  #:initial-subdivisions 1
                  #:maximum-depth 3
                  #:function
                  (lambda (point)
                    (define distance (- (vec3-x point) root))
                    (* distance distance)))))
  (check-equal? (vector-length (ode-trajectory3d-event-hits crossing-only)) 0))
