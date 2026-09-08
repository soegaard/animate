#lang racket/base

;;; Regression for accepted-step terminal-event monitoring.
;;;
;;; A trial step may evaluate an endpoint past a root so that the dense Hermite
;;; segment can isolate it.  Once isolated, however, no later step may be
;;; accepted or evaluated.  This is stronger than merely clipping a completed
;;; trajectory after it has been integrated to its requested horizon.

(require rackunit
         "../3d.rkt")

(define (recording-field calls)
  (lambda (time _x _y _z)
    (set-box! calls (cons time (unbox calls)))
    (vec3 1 0 0)))

(module+ test
  (define forward-calls (box '()))
  (define forward
    (prepare-ode-trajectory3d
     (recording-field forward-calls) origin3
     #:time-range (cons 0 3)
     #:step-size 1
     #:events
     (list (ode-event3d #:id 'stop-at-three-quarters
                         #:function (lambda (point) (- (vec3-x point) 3/4))))))
  (check-equal? (ode-trajectory3d-time-range forward) (cons 0 3/4))
  (check-equal? (ode-trajectory3d-position forward 3/4) (vec3 3/4 0 0))
  (check-equal? (ode-trajectory3d-diagnostics-accepted-steps
                 (ode-trajectory3d-diagnostics forward))
                1)
  (check-equal? (ode-trajectory3d-diagnostics-dense-segment-count
                 (ode-trajectory3d-diagnostics forward))
                1)
  ;; The sole trial reaches time 1, but nothing after that trial is evaluated.
  (check-true (andmap (lambda (time) (<= time 1)) (unbox forward-calls)))

  (define backward-calls (box '()))
  (define backward
    (prepare-ode-trajectory3d
     (recording-field backward-calls) origin3
     #:time-range (cons -3 0)
     #:step-size 1
     #:events
     (list (ode-event3d #:id 'stop-at-negative-three-quarters
                         #:function (lambda (point) (+ (vec3-x point) 3/4))))))
  (check-equal? (ode-trajectory3d-time-range backward) (cons -3/4 0))
  (check-equal? (ode-trajectory3d-position backward -3/4) (vec3 -3/4 0 0))
  (check-equal? (ode-trajectory3d-diagnostics-accepted-steps
                 (ode-trajectory3d-diagnostics backward))
                1)
  ;; As above, the first backward trial reaches -1 but no later trial occurs.
  (check-true (andmap (lambda (time) (>= time -1)) (unbox backward-calls))))
