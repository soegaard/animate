#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define view
    (view3d (list (line3d (vec3 -2 0 0) (vec3 2 0 0) #:id 'line
                          #:style (stroke3d #:width 4)))
            #:id 'world #:width 8 #:height 9/2 #:render-mode 'opaque
            #:camera (orthographic-camera3d #:position (vec3 0 0 8)
                                             #:look-at origin3 #:vertical-size 6)))
  (define hit (view3d-pixel-pick view 80 45 #:width 160 #:height 90))
  (check-true (spatial-pick? hit))
  (check-equal? (spatial-pick-kind hit) 'stroke-segment)
  (check-equal? (spatial-pick-path hit) '(world line))
  (check-true (real? (hash-ref (spatial-pick-metadata hit) 'segment-progress))))
