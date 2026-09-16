#lang racket/base
(require animate animate/slides animate/slides/scene)
(provide film)
(define moving-scene
  (scene-play
   (scene-add (make-scene #:camera (make-camera #:width 160 #:height 90 #:world-width 8))
              (circle #:id 'dot #:center (vec2 -2 0) #:radius 0.5 #:fill "red"))
   (move-to 'dot (vec2 2 0)) #:duration 2 #:easing linear))
(define component (scene-content moving-scene))
(define (panel at)
  (semantic-group #:width 8 #:height 5
    (semantic-part 'motion (content-state component #:at at) #:x 0 #:y 0 #:width 8 #:height 4)
    (semantic-part 'caption "A native semantic child" #:x 0 #:y 4 #:width 8 #:height 1 #:fit 'natural)))
(define (card at) (slide #:layout 'figure-full [figure #:key 'work (panel at)]))
(define film
  (storyboard
    (storyboard-shot 'before (hold-slide (card 0) #:duration 1/4))
    (slide-transition #:effect 'match #:keys '(work) #:depth 'semantic #:duration 1/2)
    (storyboard-shot 'after (hold-slide (card 2) #:duration 1/4))))
