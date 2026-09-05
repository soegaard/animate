#lang racket/base

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define dots
    (group
     (list (circle #:id 'left #:center (vec2 -4 -1) #:radius 1/2 #:fill "royalblue")
           (circle #:id 'middle #:center origin #:radius 1/2 #:fill "gold")
           (circle #:id 'right #:center (vec2 4 1) #:radius 1/2 #:fill "red"))
     #:id 'dots))
  (define title
    (plain-text "SCENE-BQ/BR: parallel frame output" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define start (scene-add (scene-add (make-scene) dots) title))
  (scene-wait
   (scene-play
    start
    (animation-group (move-to '(dots left) (vec2 -1 1))
                     (move-to '(dots middle) (vec2 0 -1))
                     (move-to '(dots right) (vec2 1 1))
                     (fade-to title 1/2))
    #:duration 2)
   1/2))

(module+ main (run-demo "render-diagnostics.rkt" make-demo-scene #:workers 4 #:diagnostics? #t))
