#lang racket/base

;;;
;;; Parallel Animation Groups Example
;;;

;; SCENE-AP composes Visual animations in parallel. Each direct animation-group
;; child receives the same interval, while nested successions subdivide it.

(require racket/cmdline
         racket/math
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
  (define disk
    (circle #:id 'disk
            #:radius 4/5
            #:center (vec2 -6 1)
            #:fill "royalblue"
            #:stroke "midnightblue"
            #:stroke-width 3))
  (define card
    (rectangle #:id 'card
               #:width 2
               #:height 1
               #:center (vec2 -6 -2)
               #:fill "seagreen"
               #:stroke "darkgreen"
               #:stroke-width 3))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AP: parallel animation groups"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "two successions share one six-second group interval"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera) disk card title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (animation-group
      (succession
       (move-to disk (vec2 3 1))
       (rotate-by disk (* 2 pi)))
      (succession
       (move-to card (vec2 3 -2))
       (scale-by card 3/2)))
     #:duration 6
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "parallel-animation-groups.rkt"
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
