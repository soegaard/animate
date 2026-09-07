#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  ;; The automatic central stencil recovers a linear field to floating-point
  ;; accuracy, and records one base plus two samples per coordinate.
  (define field
    (lambda (x y z)
      (vec3 (+ (* 2 x) (* 3 y) (* -1 z))
            (+ (* -4 x) (* 5 y) (* 6 z))
            (+ (* 7 x) (* -8 y) (* 9 z)))))
  (define central (jacobian3d field (vec3 2 -3 1)))
  (define matrix (jacobian3d-result-matrix central))
  (check-equal? (jacobian3d-result-method central) 'central)
  (check-equal? (jacobian3d-result-evaluations central) 7)
  (check-true (vec3? (jacobian3d-result-step central)))
  (check-= (linear3-m00 matrix) 2 1e-7)
  (check-= (linear3-m01 matrix) 3 1e-7)
  (check-= (linear3-m02 matrix) -1 1e-7)
  (check-= (linear3-m10 matrix) -4 1e-7)
  (check-= (linear3-m11 matrix) 5 1e-7)
  (check-= (linear3-m12 matrix) 6 1e-7)
  (check-= (linear3-m20 matrix) 7 1e-7)
  (check-= (linear3-m21 matrix) -8 1e-7)
  (check-= (linear3-m22 matrix) 9 1e-7)
  (check-true (real? (jacobian3d-result-error-estimate central)))
  (check-true (immutable? (hash-ref (jacobian3d-result-diagnostics central)
                                     'coordinate-methods)))

  ;; An analytic derivative does not call the field and preserves time-aware
  ;; author procedures in the same 4-argument convention as `ode-field3d`.
  (define field-calls 0)
  (define analytic
    (jacobian3d
     (lambda (time x y z)
       (set! field-calls (add1 field-calls))
       (vec3 x y z))
     (vec3 1 2 3)
     #:time 8
     #:derivative
     (lambda (time x y z)
       (check-equal? time 8)
       (linear3 1 0 0 0 1 0 0 0 1))))
  (check-equal? field-calls 0)
  (check-equal? (jacobian3d-result-method analytic) 'analytic)
  (check-equal? (jacobian3d-result-evaluations analytic) 1)
  (check-false (jacobian3d-result-step analytic))
  (check-false (jacobian3d-result-error-estimate analytic))
  (check-equal? (jacobian3d-result-matrix analytic) identity-linear3)

  ;; One-sided differences occur only because an explicit domain says that the
  ;; symmetric neighbour is unavailable.
  (define one-sided
    (jacobian3d (lambda (x y z) (vec3 (* x x) y z))
                (vec3 0 2 3)
                #:step 1/1000
                #:domain (lambda (point) (>= (vec3-x point) 0))))
  (check-equal? (jacobian3d-result-method one-sided) 'one-sided)
  (check-equal? (vector->list
                 (hash-ref (jacobian3d-result-diagnostics one-sided)
                           'coordinate-methods))
                '(forward central central))
  (check-equal? (vector->list
                 (hash-ref (jacobian3d-result-diagnostics one-sided)
                           'one-sided-axes))
                '(0))
  (check-= (linear3-m00 (jacobian3d-result-matrix one-sided)) 1/1000 1e-9)
  (check-false (jacobian3d-result-error-estimate one-sided))

  (check-exn exn:fail:contract?
             (lambda ()
               (jacobian3d field (vec3 0 0 0)
                           #:derivative (lambda (x y z) (vec3 x y z)))))
  (check-exn exn:fail:contract?
             (lambda ()
               (jacobian3d field (vec3 0 0 0)
                           #:domain (lambda (point) #f)))))
