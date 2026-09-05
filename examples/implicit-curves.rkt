#lang racket/base

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -3 3 1) #:y-range (axis-range -3 3 1)
          #:x-length 8 #:y-length 6 #:stroke "navy" #:stroke-width 3))
  (define grid
    (axes-grid-lines coordinate-axes #:id 'grid
                     #:stroke "lightgray" #:stroke-width 1))
  (define diagram (group (list grid coordinate-axes) #:id 'diagram))
  (define circle-curve
    (implicit-curve coordinate-axes
                    (lambda (x y) (- (+ (* x x) (* y y)) 4))
                    #:id 'circle-curve #:x-count 81 #:y-count 61
                    #:stroke "red" #:stroke-width 4))
  (define diagonal-curve
    (implicit-curve coordinate-axes
                    (lambda (x y) (- (* x y) 1))
                    #:id 'hyperbola-curve #:x-count 81 #:y-count 61
                    #:stroke "seagreen" #:stroke-width 3))
  (define title
    (plain-text "SCENE-BL: implicit curves" #:id 'title
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (make-scene)
               (animation-group (fade-in diagram)
                                (create circle-curve) (create diagonal-curve)
                                (fade-in title))
               #:duration 5/2)
   1/2))

(module+ main (run-demo "implicit-curves.rkt" make-demo-scene))
