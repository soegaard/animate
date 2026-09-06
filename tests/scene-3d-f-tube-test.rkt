#lang racket/base

;;; SCENE-3D-F Tube Construction Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define tube
    (tube3d (list (vec3 0 0 0) (vec3 0 0 1) (vec3 1 0 1))
            #:id 'tube #:radius 1/4 #:sides 6 #:color "tomato"))
  ;; Three six-sided rings plus two cap centres.
  (check-equal? (vector-length (mesh3d-vertices tube)) 20)
  (check-equal? (vector-length (mesh3d-edges tube)) 30)
  (check-true (positive? (vector-length (mesh3d-triangles tube))))
  (check-true (material3d-double-sided? (mesh3d-material tube)))
  ;; A vanishing centred tangent at a sharp U-turn remains renderable.
  (check-not-exn
   (lambda ()
     (tube3d (list origin3 (vec3 1 0 0) origin3) #:id 'u-turn)))
  (check-exn exn:fail?
             (lambda () (tube3d (list origin3 (vec3 1 0 0))
                                 #:id 'screen #:width-mode 'screen))))
