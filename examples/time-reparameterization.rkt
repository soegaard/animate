#lang racket/base

;;;
;;; SCENE-DZ: Time Reparameterization
;;;

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DZ: time reparameterization"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "The upper dot spends more of its distance in the middle."
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define upper-track
    (line (vec2 -4 1) (vec2 4 1) #:id 'upper-track
          #:stroke "lightsteelblue" #:stroke-width 2))
  (define lower-track
    (line (vec2 -4 -1) (vec2 4 -1) #:id 'lower-track
          #:stroke "lightsteelblue" #:stroke-width 2))
  (define upper
    (circle #:id 'speed-profile #:center (vec2 -4 1) #:radius 1/5
            #:fill "crimson" #:stroke "firebrick" #:stroke-width 2))
  (define lower
    (circle #:id 'uniform #:center (vec2 -4 -1) #:radius 1/5
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define upper-label
    (plain-text "change-speed" #:id 'upper-label #:center (vec2 -4 3/2)
                #:font-size 1/4 #:color "firebrick"))
  (define lower-label
    (plain-text "linear" #:id 'lower-label #:center (vec2 -4 -1/2)
                #:font-size 1/4 #:color "navy"))
  (define middle-fast
    (change-speed '((0 1/2) (1/3 3) (2/3 3) (1 1/2))))
  (scene-wait
   (scene-play
    (scene-add (make-scene)
               title explanation upper-track lower-track upper lower
               upper-label lower-label)
    (timed (move-to 'speed-profile (vec2 4 1))
           #:duration 4 #:easing middle-fast)
    (move-to 'uniform (vec2 4 -1))
    #:duration 4)
   1))

(module+ main
  (run-demo "time-reparameterization.rkt" make-demo-scene))
