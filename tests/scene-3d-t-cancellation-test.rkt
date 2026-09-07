#lang racket/base

;; T-8 cancellation occurs at deterministic numerical boundaries and never
;; returns a partially prepared trajectory or flow-map value.

(require rackunit
         "../3d.rkt"
         "../private/preview-cancellation.rkt")

(module+ test
  (define already-cancelled (make-cancellation-token))
  (cancel! already-cancelled 'test)
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (prepare-ode-trajectory3d
                (lambda (_x _y _z) x-axis3) origin3 #:time-range (cons 0 1)
                #:cancellation-token already-cancelled)))
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (prepare-flow-map3d
                (lambda (_x _y _z) x-axis3)
                (explicit-seeds3d (list origin3 (vec3 0 1 0)))
                #:cancellation-token already-cancelled)))
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (prepare-streamlines3d
                (lambda (_x _y _z) x-axis3)
                (explicit-seeds3d (list origin3 (vec3 0 1 0)))
                #:cancellation-token already-cancelled)))
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (equilibrium-points3d
                (lambda (x y z) (vec3 x y z))
                (explicit-seeds3d (list origin3))
                #:cancellation-token already-cancelled)))
  ;; Cancelling inside an author field is observed before the next accepted
  ;; fixed RK4 step can be installed.
  (define in-flight (make-cancellation-token))
  (define calls 0)
  (check-exn exn:fail:preview-canceled?
             (lambda ()
               (prepare-ode-trajectory3d
                (lambda (_x _y _z)
                  (set! calls (add1 calls))
                  (when (= calls 5) (cancel! in-flight 'superseded))
                  x-axis3)
                origin3 #:time-range (cons 0 2)
                #:solver (fixed-rk4-solver3d #:step-size 1/4)
                #:cancellation-token in-flight)))
  (check-true (cancellation-requested? in-flight)))
