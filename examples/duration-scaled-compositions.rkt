#lang racket/base

;;;
;;; Duration-Scaled Composition Example
;;;

;; SCENE-AR lets timed wrappers live inside composition trees and lets timed wrap
;; an entire composition. In the left-to-right succession below, direct child
;; spans are 1, 2, and 1, so an eight-second play gives durations 2, 4, and 2.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 18
                 #:background "white"))
  (define blue
    (circle #:id 'blue
            #:radius 7/10
            #:center (vec2 -6 2)
            #:fill "royalblue"
            #:stroke "midnightblue"
            #:stroke-width 3))
  (define green
    (rectangle #:id 'green
               #:width 7/5
               #:height 7/5
               #:center (vec2 -6 0)
               #:fill "seagreen"
               #:stroke "darkgreen"
               #:stroke-width 3))
  (define red
    (circle #:id 'red
            #:radius 7/10
            #:center (vec2 -6 -2)
            #:fill "tomato"
            #:stroke "darkred"
            #:stroke-width 3))
  (define gold
    (rectangle #:id 'gold
               #:width 6/5
               #:height 6/5
               #:center (vec2 5 0)
               #:fill "gold"
               #:stroke "darkgoldenrod"
               #:stroke-width 3))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AR: duration-scaled composition"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "sequence weights 1 : 2 : 1; timed composite runs from t=1 to t=7"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera)
               blue green red gold title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (succession
      (move-to blue (vec2 2 2))
      (timed (move-to green (vec2 2 0)) #:duration 2)
      (move-to red (vec2 2 -2)))
     (timed
      (succession
       (rotate-by gold 2)
       (scale-by gold 3/2))
      #:start 1
      #:duration 6
      #:easing smoothstep)
     #:duration 8
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "duration-scaled-compositions.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
