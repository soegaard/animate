#lang racket/base

;;; SCENE-3D-F Axes and Vector Diagram Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define axes (axes3d #:id 'axes #:x-range (list -2 3) #:y-range (list -2 3)
                       #:z-range (list -2 3)))
  (define world (view3d (list axes) #:id 'world))
  (for ([path (in-list (list '(world axes x-axis)
                              '(world axes y-axis)
                              '(world axes z-axis)
                              '(world axes x-ticks)
                              '(world axes labels x)))])
    (check-true (view3d-spatial-has? world path) (format "stable path ~a" path)))
  (define components (vector-components3d (vec3 2 1 3) #:id 'components))
  (check-equal? (map spatial-id (group3d-children components))
                '(x-component y-component z-component resultant))
  (check-true (group3d? (grid-plane3d 'xy #:id 'grid)))
  (check-true (mesh3d? (coordinate-plane3d 'xz #:id 'plane))))
