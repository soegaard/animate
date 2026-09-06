#lang racket/base

;;; SCENE-3D-G Surface Calculus Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define surface
    (function-surface3d (lambda (x y) (+ (* x x) (* y y)))
                        #:x-range (list -1 1) #:y-range (list -1 1)
                        #:resolution (list 9 9) #:id 'paraboloid
                        #:derivative-x (lambda (x _y) (* 2 x))
                        #:derivative-y (lambda (_x y) (* 2 y))))
  (check-equal? (surface3d-position-at surface 0 0) origin3)
  (check-= (vec3-z (surface3d-normal-at surface 0 0)) 1 1e-12)
  (check-true (group3d? (surface-tangent-u surface 0 0 #:id 'tu)))
  (check-true (group3d? (surface-gradient-arrow surface 1 0 #:id 'gradient)))
  (check-true (curve3d? (surface-coordinate-curve surface #:u 0 #:id 'curve)))
  (check-true (group3d? (surface-level-curve surface 1/2 #:id 'level))))
