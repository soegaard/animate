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
  (check-true (andmap (lambda (time) (>= time -1)) (unbox backward-calls)))

  ;; Bounds, arc limits, and low-speed limits use the same accepted-step
  ;; monitor as terminal events.  They may require the first trial endpoint,
  ;; but must never allow a later trial after the limit has been isolated.
  (define bounds-calls (box '()))
  (define bounded
    (prepare-ode-trajectory3d
     (recording-field bounds-calls) origin3
     #:time-range (cons 0 3)
     #:step-size 1
     #:termination
     (trajectory-termination3d
      #:bounds (aabb3 (vec3 -1 -1 -1) (vec3 3/4 1 1)))))
  (check-equal? (car (ode-trajectory3d-time-range bounded)) 0)
  (check-= (cdr (ode-trajectory3d-time-range bounded)) 3/4 1e-10)
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination bounded) 0))
                'bounds-exit)
  (check-true (andmap (lambda (time) (<= time 1)) (unbox bounds-calls)))

  (define arc-calls (box '()))
  (define arc-limited
    (prepare-ode-trajectory3d
     (recording-field arc-calls) origin3
     #:time-range (cons 0 3)
     #:step-size 1
     #:termination (trajectory-termination3d #:arc-length-limit 3/4)))
  (check-= (cdr (ode-trajectory3d-time-range arc-limited)) 3/4 1e-10)
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination arc-limited) 0))
                'arc-length-limit)
  (check-true (andmap (lambda (time) (<= time 1)) (unbox arc-calls)))

  (define slow-calls (box '()))
  (define slow
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z)
       (set-box! slow-calls (cons time (unbox slow-calls)))
       (vec3 (- time 1/3) 0 0))
     origin3
     #:time-range (cons 0 3)
     #:step-size 1
     #:termination (trajectory-termination3d #:minimum-speed 1/10)))
  (check-= (cdr (ode-trajectory3d-time-range slow)) 7/30 1e-8)
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination slow) 0))
                'minimum-speed)
  (check-true (andmap (lambda (time) (<= time 1)) (unbox slow-calls)))

  ;; A trial field value may be unavailable beyond a terminal root.  The
  ;; solver backs the trial off, reaches the root on a valid segment, and
  ;; reports the event rather than treating the speculative endpoint failure
  ;; as the result of preparation.
  (define field-error-after-root
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z)
       (if (> time 3/4)
           (error 'field "outside the event domain")
           x-axis3))
     origin3
     #:time-range (cons 0 3)
     #:step-size 1
     #:events
     (list (ode-event3d #:id 'domain-edge
                         #:function (lambda (point) (- (vec3-x point) 1/2))))))
  (check-equal? (ode-trajectory3d-time-range field-error-after-root) (cons 0 1/2))
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination field-error-after-root) 0))
                'terminal-event)

  ;; The adaptive branch uses the same controlled backoff path.
  (define adaptive-field-error-after-root
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z)
       (if (> time 3/4)
           (error 'field "outside the event domain")
           x-axis3))
     origin3
     #:time-range (cons 0 3)
     #:solver (adaptive-rk45-solver3d #:initial-step 1 #:maximum-step 1
                                    #:minimum-step 1/100)
     #:events
     (list (ode-event3d #:id 'adaptive-domain-edge
                         #:function (lambda (point) (- (vec3-x point) 1/2))))))
  (check-equal? (ode-trajectory3d-time-range adaptive-field-error-after-root)
                (cons 0 1/2))
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination
                              adaptive-field-error-after-root)
                             0))
                'terminal-event))
