#lang racket/base

;;; SCENE-3D-G Fixed Surface Grid Tests

(require rackunit
         "../3d.rkt"
         "../private/3d/surface-grid.rkt")

(module+ test
  (define grid
    (make-surface-grid (lambda (u v) (vec3 u v (+ u v)))
                       #:u-range (list -1 1) #:v-range (list 0 2)
                       #:resolution (list 3 4)))
  (check-equal? (surface-grid-u-count grid) 3)
  (check-equal? (surface-grid-v-count grid) 4)
  (check-equal? (surface-grid-ref grid 2 3) (vec3 1 2 3))
  (check-equal? (vector-length (surface-grid-triangles grid)) 12)
  (check-equal? (vector-ref (surface-grid-triangles grid) 0) (vector 0 4 5)))
