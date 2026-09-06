#lang racket/base

;;; SCENE-3D-G Surface Normal Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define plane
    (parametric-surface3d (lambda (u v) (vec3 u v 0))
                          #:u-range (list -1 1) #:v-range (list -1 1)
                          #:resolution (list 3 3) #:id 'plane
                          #:derivative-u (lambda (_u _v) x-axis3)
                          #:derivative-v (lambda (_u _v) y-axis3)))
  (check-equal? (surface3d-resolution plane) (list 3 3))
  (check-equal? (vector-length (surface3d-normals plane)) 9)
  (check-= (vec3-z (surface3d-normal-at plane 0 0)) 1 1e-12)
  ;; A fully collapsed parameterization must report a finite fallback rather
  ;; than leak a NaN through a later renderer.
  (define collapsed
    (parametric-surface3d (lambda (_u _v) origin3)
                          #:resolution (list 3 3) #:id 'collapsed))
  (check-equal? (length (surface3d-unresolved-normal-indices collapsed)) 9)
  (check-true (andmap vec3-finite? (vector->list (surface3d-normals collapsed)))))
