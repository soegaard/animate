#lang racket/base

(require racket/runtime-path
         "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  (define badge
    (image (build-path assets-directory "roadmap-bitmap.xpm")
           #:id 'badge #:center (vec2 -3 0) #:width 3 #:height 9/4))
  (define title
    (plain-text "SCENE-BH: bitmap image Visual" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define start (scene-add (scene-add (make-scene) badge) title))
  (scene-wait
   (scene-play
    start
    (animation-group
     (move-to badge (vec2 3 0))
     (rotate-by badge 1/12)
     (scale-to badge 6/5)
     (fade-to title 2/5))
    #:duration 2)
   1/2))

(module+ main (run-demo "bitmap-image-visual.rkt" make-demo-scene))
