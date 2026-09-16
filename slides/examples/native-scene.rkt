#lang racket/base
(require animate animate/colors animate/slides animate/slides/scene)
(provide moving-disc card film)
(define moving-disc
  (scene-play
   (scene-add (make-scene #:camera (make-camera #:world-width 8 #:width 800 #:height 500))
              (circle #:id 'disc #:center (vec2 -2 0) #:radius 0.6
                      #:fill theme-accent #:stroke-width 0))
   (move-to 'disc (vec2 2 0)) #:duration 3 #:easing linear))
(define card
  (slide #:id 'motion #:layout 'title+figure
    [title "A layout does not replace animation"]
    [body (bullets [native "The figure is an ordinary Scene."]
                    [clock "Its local clock starts when requested."])]
    [figure (scene-content moving-disc #:poster 'end)]))
(define film
  (storyboard #:id 'native-disc #:theme lecture-dark
    (storyboard-shot 'motion
      (build-slide card
        (beat 'introduce #:duration 2)
        (beat 'move #:duration 3 (play-content 'figure))
        (beat 'hold #:duration 2)))))
