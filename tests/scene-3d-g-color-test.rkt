#lang racket/base

;;; SCENE-3D-G Surface Colour Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define surface
    (function-surface3d (lambda (x y) (- (* x x) (* y y)))
                        #:x-range (list -1 1) #:y-range (list -1 1)
                        #:resolution (list 3 3) #:id 'saddle))
  (define coloured (surface-color-by-height surface #:low "blue" #:high "red"))
  (check-equal? (vector-length (surface3d-colors coloured)) 9)
  (check-not-equal? (vector-ref (surface3d-colors coloured) 0)
                    (vector-ref (surface3d-colors coloured) 1))
  (check-true (material3d-wireframe? (surface3d-material (surface-wireframe coloured)))))
