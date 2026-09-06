#lang racket/base

;;;
;;; SCENE-3D-A Decomposed Transform Tests
;;;

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt")

(define (check-vec3= actual expected [tolerance 1e-9])
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  ;; The public semantic order is scale, then rotate, then translate.
  (define transform
    (make-transform3 #:translation (vec3 10 20 30)
                     #:rotation (axis-angle z-axis3 (/ pi 2))
                     #:scale (vec3 2 3 4)))
  (check-vec3= (transform3-apply-point transform (vec3 1 2 3))
               (vec3 4 22 42))
  (define inner
    (make-transform3 #:translation (vec3 1 0 0)
                     #:scale (vec3 2 2 2)))
  (define outer
    (make-transform3 #:translation (vec3 0 5 0)
                     #:rotation (axis-angle z-axis3 (/ pi 2))))
  ;; Composition returns affine3 so a future nonuniform combination cannot
  ;; silently discard a shear component.
  (check-true (affine3? (transform3-compose outer inner)))
  (check-vec3=
   (affine3-apply-point (transform3-compose outer inner) (vec3 1 0 0))
   (vec3 0 8 0))
  (check-eq? (transform3-lerp identity-transform3 transform 0)
             identity-transform3)
  (check-eq? (transform3-lerp identity-transform3 transform 1)
             transform)
  (check-exn
   exn:fail?
   (lambda ()
     (transform3-lerp
      identity-transform3
      (make-transform3 #:scale (vec3 -1 1 1))
      1/4)))
  (check-exn exn:fail:contract?
             (lambda () (make-transform3 #:scale (vec3 1 0 1)))))
