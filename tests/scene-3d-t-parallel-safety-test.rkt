#lang racket/base

;;; SCENE-3D-T: metadata-gated automatic preparation parallelism.

(require rackunit
         "../3d.rkt")

(define seeds
  (explicit-seeds3d (list origin3 (vec3 1 0 0) (vec3 2 0 0))))

(define termination
  (trajectory-termination3d #:time-limit 1))

(module+ test
  ;; Autonomy follows unambiguous arity when the author leaves it on 'auto.
  (check-true (ode-field3d-autonomous?
               (ode-field3d (lambda (_x _y _z) x-axis3))))
  (check-false (ode-field3d-autonomous?
                (ode-field3d (lambda (_time _x _y _z) x-axis3))))
  (check-exn exn:fail:contract?
             (lambda ()
               (ode-field3d
                (case-lambda
                  [(_x _y _z) x-axis3]
                  [(_time _x _y _z) x-axis3]))))

  ;; Opaque author procedures stay serial under automatic scheduling.
  (define unsafe
    (ode-field3d (lambda (_x _y _z) x-axis3)))
  (define serial-result
    (prepare-streamlines3d unsafe seeds
                           #:solver (fixed-rk4-solver3d #:step-size 1/2)
                           #:termination termination))
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics serial-result))
                'serial-unsafe-procedure)

  ;; A field and every event must opt in before automatic preparation uses
  ;; workers. The explicit safety declaration does not change the trajectory
  ;; data or its canonical seed order.
  (define safe
    (ode-field3d (lambda (_x _y _z) x-axis3) #:parallel-safe? #t))
  (define threaded-result
    (prepare-streamlines3d safe seeds
                           #:solver (fixed-rk4-solver3d #:step-size 1/2)
                           #:termination termination))
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics threaded-result))
                'threaded)
  (check-equal? (prepared-streamline-set3d-streamlines threaded-result)
                (prepared-streamline-set3d-streamlines
                 (prepare-streamlines3d safe seeds
                                        #:solver (fixed-rk4-solver3d #:step-size 1/2)
                                        #:termination termination
                                        #:parallel? #f)))

  ;; An unsafe event correctly pulls an otherwise safe field back to serial.
  (define unsafe-event
    (ode-event3d #:id 'opaque #:terminal? #f
                 #:function (lambda (_point) 1)))
  (define event-result
    (prepare-streamlines3d safe seeds
                           #:solver (fixed-rk4-solver3d #:step-size 1/2)
                           #:termination
                           (trajectory-termination3d #:time-limit 1
                                                    #:events (list unsafe-event))))
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics event-result))
                'serial-unsafe-procedure))
