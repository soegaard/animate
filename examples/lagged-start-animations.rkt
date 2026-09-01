#lang racket/base

;;;
;;; Lagged-Start Animations Example
;;;

;; SCENE-AQ staggers direct composition children. A lag ratio of 1/2 means each
;; child starts half one child-duration after the previous child starts.

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
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AQ: lagged-start"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "lag-ratio 1/2: each move begins halfway through the previous one"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera) blue green red title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (lagged-start
      (move-to blue (vec2 5 2))
      (move-to green (vec2 5 0))
      (move-to red (vec2 5 -2))
      #:lag-ratio 1/2)
     #:duration 6
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "lagged-start-animations.rkt"
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
