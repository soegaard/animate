#lang racket/base

;; Categorical indexes are tied to the author-supplied list order, not to
;; hash order or the order in which a renderer happens to draw the points.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes #:x-range (axis-range -4 4 1) #:y-range (axis-range -2 2 1)
          #:x-length 8 #:y-length 4))
  (define points
    (for/list ([point (in-list (list (vec2 -3 -1) (vec2 -1 1) (vec2 1 -1/2) (vec2 3 3/4)))]
               [index (in-naturals)])
      (circle #:id (string->symbol (format "category-~a" index))
              #:center point #:radius 1/5 #:fill (series-color index)
              #:stroke theme-axis #:stroke-width 1)))
  (scene-wait
   (apply scene-add (make-scene) coordinate-axes
          (axes-grid-lines coordinate-axes #:id 'grid)
          points)
   1))

(module+ main
  (run-demo "colors/themed-plots-and-series.rkt" make-demo-scene))
