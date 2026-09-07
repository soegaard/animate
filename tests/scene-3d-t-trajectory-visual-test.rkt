#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
  (define calls 0)
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (x y z) (set! calls (add1 calls)) (vec3 1 0 0))
     (vec3 0 0 0) #:time-range (cons 0 1)
     #:solver (fixed-rk4-solver3d #:step-size 1/10)))
  (define calls-after-preparation calls)
  (check-equal? (vector-length (trajectory-samples3d trajectory #:count 8)) 8)
  (check-equal? calls calls-after-preparation)
  (check-true (mesh3d? (trajectory-tube3d trajectory #:id 'tube #:samples 8)))
  (check-equal? calls calls-after-preparation)
  (define ribbon (trajectory-ribbon3d trajectory #:id 'ribbon #:samples 8 #:width 1/4))
  (check-equal? (vector-length (mesh3d-vertices ribbon)) 16)
  (check-equal? (vector-length (mesh3d-triangles ribbon)) 14)
  (define bundle
    (trajectory-bundle3d
     (prepare-flow-map3d (lambda (x y z) (vec3 1 0 0))
                         (explicit-seeds3d (list (vec3 0 0 0) (vec3 0 1 0)))
                         #:solver (fixed-rk4-solver3d #:step-size 1/10))
     #:id 'bundle #:samples 8))
  (check-true (group3d? bundle))
  (check-equal? (length (group3d-children bundle)) 2)
  (check-exn exn:fail:contract?
             (lambda () (trajectory-bundle3d trajectory #:style 'tube)))
  (check-equal? calls calls-after-preparation))
