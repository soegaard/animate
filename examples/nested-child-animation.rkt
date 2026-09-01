#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define left (circle #:id 'left #:center (vec2 -3 0) #:radius 1/2 #:fill "royalblue"))
  (define middle (circle #:id 'middle #:center origin #:radius 1/2 #:fill "gold"))
  (define right (circle #:id 'right #:center (vec2 3 0) #:radius 1/2 #:fill "seagreen"))
  (define dots (group (list left middle right) #:id 'dots))
  (define title
    (plain-text "SCENE-BC: animate group children" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (scene-add (scene-add (make-scene) dots) title)
               (animation-group
                (move-to '(dots left) (vec2 -3 1))
                (move-to '(dots middle) (vec2 0 -1))
                (move-to '(dots right) (vec2 3 1))
                (fill-color-to '(dots left) "red")
                (fill-color-to '(dots right) "purple"))
               #:duration 2)
   1/2))

(module+ main (run-demo "nested-child-animation.rkt" make-demo-scene))
