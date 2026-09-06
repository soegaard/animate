#lang racket/base

;;;
;;; SCENE-3D-A Linear Map Tests
;;;

(require rackunit
         "../3d.rkt")

(define (check-vec3= actual expected [tolerance 1e-10])
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  (define scale
    (linear3 2 0 0
             0 3 0
             0 0 4))
  (define swap-and-negate
    (linear3 0 -1 0
             1 0 0
             0 0 1))
  ;; Composition is outer ∘ inner, so scale happens before the quarter turn.
  (check-vec3=
   (linear3-apply-vector (linear3-compose swap-and-negate scale) (vec3 1 2 3))
   (vec3 -6 2 12))
  (check-equal? (linear3-determinant scale) 24)
  (check-vec3=
   (linear3-apply-vector (linear3-invert scale) (vec3 2 3 4))
   (vec3 1 1 1))
  (check-equal?
   (linear3-compose scale (linear3-invert scale))
   identity-linear3)
  ;; Normal maps use the inverse transpose, not the model-space scale itself.
  (check-vec3=
   (linear3-apply-vector (linear3-normal-transform scale) (vec3 2 3 4))
   (vec3 1 1 1))
  (check-equal?
   (linear3-transpose swap-and-negate)
   (linear3 0 1 0
            -1 0 0
            0 0 1))
  (check-exn
   exn:fail?
   (lambda ()
     (linear3-invert
      (linear3 1 0 0
               0 0 0
               0 0 1))))
  (check-exn exn:fail:contract? (lambda () (linear3 +nan.0 0 0 0 1 0 0 0 1))))
