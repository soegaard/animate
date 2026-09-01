#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -4 4 1) #:y-range (axis-range -3 3 1)
          #:x-length 8 #:y-length 6 #:stroke "navy" #:stroke-width 3))
  (define grid
    (axes-grid-lines coordinate-axes #:id 'grid
                     #:stroke "lightgray" #:stroke-width 1))
  (define diagram (group (list grid coordinate-axes) #:id 'diagram))
  (define field
    (vector-field coordinate-axes (lambda (x y) (vec2 (- y) x))
                  #:id 'rotation-field #:x-count 9 #:y-count 7 #:scale 1/4
                  #:stroke "red" #:stroke-width 2))
  (define title
    (plain-text "SCENE-BM: a rotational vector field" #:id 'title
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (make-scene)
               (animation-group (fade-in diagram)
                                (fade-in field) (fade-in title))
               #:duration 2)
   1/2))

(module+ main (run-demo "vector-fields.rkt" make-demo-scene))
