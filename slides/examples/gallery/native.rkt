#lang racket/base
(require "../../../main.rkt" "../../../colors.rkt"
         "../../main.rkt" "../../scene.rkt")
(provide gallery-entry-shots)
(define (gallery-entry-shots id theme fmt)
  (define inner
    (scene-play
     (scene-add
      (make-scene #:camera (make-camera #:width 800 #:height 450 #:world-width 8))
      (line (vec2 -3 0) (vec2 3 0) #:id 'track #:stroke theme-muted #:stroke-width 2)
      (circle #:id 'disc #:center (vec2 -2 0) #:radius 0.45 #:fill theme-accent #:stroke-width 0))
     (move-to 'disc (vec2 2 0)) #:duration 3 #:easing (smooth)))
  (define card
    (slide #:layout 'title+figure [title "A scene inside a slide"]
      [figure (scene-content inner)]
      [footer "The inner clock starts at play-content."]))
  (list
   (storyboard-shot id
     (build-slide card
       (beat 'introduce #:duration 1)
       (beat 'move #:duration 3 (play-content 'figure))
       (beat 'hold #:duration 1.5)))))
