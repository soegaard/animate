#lang racket/base

;;;
;;; SCENE-3D-A Rotation Tests
;;;

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt")

(define (check-vec3= actual expected [tolerance 1e-9])
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  (define quarter-turn (axis-angle z-axis3 (/ pi 2)))
  (check-vec3= (rotation3-apply quarter-turn x-axis3) y-axis3)
  (check-vec3=
   (rotation3-apply (rotation3-from-to x-axis3 y-axis3) x-axis3)
   y-axis3)
  (check-vec3=
   (rotation3-apply (rotation3-from-to x-axis3 (vec3 -1 0 0)) x-axis3)
   (vec3 -1 0 0))
  ;; Equivalent q and -q rotations canonicalize to the same visible matrix.
  (check-equal?
   (rotation3-components (axis-angle z-axis3 (/ pi 2)))
   (rotation3-components (axis-angle (vec3 0 0 -1) (- (/ pi 2)))))
  ;; A 270° endpoint chooses the shorter -90° route; halfway is -45°.
  (check-vec3=
   (rotation3-apply
    (rotation3-slerp identity-rotation3 (axis-angle z-axis3 (* 3/2 pi)) 1/2)
    x-axis3)
   (vec3 (/ (sqrt 2) 2) (- (/ (sqrt 2) 2)) 0))
  (check-eq? (rotation3-slerp identity-rotation3 quarter-turn 0)
             identity-rotation3)
  (check-eq? (rotation3-slerp identity-rotation3 quarter-turn 1)
             quarter-turn)
  (check-vec3= (rotation3-apply (rotation3-look-at z-axis3) z-axis3)
               z-axis3)
  (check-exn exn:fail? (lambda () (axis-angle origin3 1)))
  (check-exn exn:fail? (lambda () (rotation3-look-at z-axis3 #:up z-axis3))))
