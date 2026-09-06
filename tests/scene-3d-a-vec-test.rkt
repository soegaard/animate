#lang racket/base

;;;
;;; SCENE-3D-A Spatial Vector Tests
;;;

(require rackunit
         "../3d.rkt")

(define (check-vec3= actual expected [tolerance 1e-10])
  (check-true (vec3? actual))
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  ;; Animate's spatial basis is right-handed: x × y points toward the viewer.
  (check-equal? (vec3-cross x-axis3 y-axis3) z-axis3)
  (check-equal? (vec3-cross y-axis3 x-axis3) (vec3 0 0 -1))
  (check-equal? (vec3+ (vec3 1 2 3) (vec3 -4 5 -6)) (vec3 -3 7 -3))
  (check-equal? (vec3* (vec3 2 3 4) (vec3 5 6 7)) (vec3 10 18 28))
  (check-equal? (vec3-dot (vec3 1 2 3) (vec3 4 -5 6)) 12)
  (check-equal? (vec3-length (vec3 3 0 4)) 5)
  (check-equal? (vec3-distance origin3 (vec3 3 0 4)) 5)
  (define normalized (vec3-normalize (vec3 3 0 4)))
  (check-true (inexact? (vec3-x normalized)))
  (check-vec3= normalized (vec3 3/5 0 4/5))
  (check-equal? (vec3-lerp origin3 (vec3 2 4 6) 1/2) (vec3 1 2 3))
  (check-true (vec3-finite? (vec3 1.0 2.0 3.0)))
  (check-false (vec3-finite? 'not-a-vector))
  (check-exn exn:fail:contract? (lambda () (vec3 +inf.0 0 0)))
  (check-exn exn:fail? (lambda () (vec3-normalize origin3))))
