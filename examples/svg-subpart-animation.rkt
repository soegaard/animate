#lang racket/base

(require racket/runtime-path
         "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  (define rocket
    (svg->visual (build-path assets-directory "roadmap-rocket.svg")
                 #:id 'diagram #:center origin #:scale 1))
  (define title
    (plain-text "SCENE-BG/BI: animate imported SVG parts" #:id 'title
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (define start
    (scene-add (scene-add (make-scene) rocket) title))
  (scene-wait
   (scene-play
    start
    (animation-group
     (fill-color-to '(diagram rocket flame) "gold")
     (stroke-color-to '(diagram rocket body) "red")
     (scale-to '(diagram rocket flame) (vec2 3/2 3/2)))
    #:duration 2)
   1/2))

(module+ main (run-demo "svg-subpart-animation.rkt" make-demo-scene))
