#lang racket/base

(require racket/runtime-path
         "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  (define rocket
    (svg-image (build-path assets-directory "roadmap-rocket.svg")
               #:id 'rocket #:center (vec2 -3 0) #:width 3 #:height 5))
  (define caption
    (plain-text "SCENE-BO/BP: cached SVG renderer resources" #:id 'caption
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (define detail
    (plain-text "The same source stays reusable while it moves." #:id 'detail
                #:center (vec2 0 -7/2) #:font-size 1/3 #:color "dimgray"))
  (define start
    (scene-add (scene-add (scene-add (make-scene) rocket) caption) detail))
  (scene-wait
   (scene-play
    start
    (animation-group (move-to rocket (vec2 3 0)) (rotate-by rocket 1/12)
                     (fade-to detail 1/2))
    #:duration 2)
   1/2))

(module+ main (run-demo "renderer-resources.rkt" make-demo-scene #:diagnostics? #t))
