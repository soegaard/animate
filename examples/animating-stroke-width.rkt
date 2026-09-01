#lang racket/base

;;;
;;; Stroke-Width Animation Example
;;;

;; SCENE-AS adds a semantic stroke-width Visual protocol and stroke-width-to.
;; The same request composes with the AN-AR timing tree just like motion/opacity.

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
  (define ring
    (circle #:id 'ring
            #:center (vec2 -5 2)
            #:radius 4/5
            #:fill #f
            #:stroke "royalblue"
            #:stroke-width 1))
  (define box
    (rectangle #:id 'box
               #:center (vec2 -5 0)
               #:width 8/5
               #:height 7/5
               #:fill #f
               #:stroke "seagreen"
               #:stroke-width 1))
  (define route
    (line (vec2 -6 -2)
          (vec2 -4 -2)
          #:id 'route
          #:stroke "tomato"
          #:stroke-width 1))
  (define vector
    (arrow (vec2 1 -2)
           (vec2 3 -2)
           #:id 'vector
           #:stroke "darkorange"
           #:stroke-width 1
           #:tip-length 1/2
           #:tip-width 2/5))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AS: stroke-width animation"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "width is an independent animation component"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera)
               ring box route vector title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (lagged-start
      (animation-group
       (move-to ring (vec2 3 2))
       (stroke-width-to ring 14))
      (animation-group
       (move-to box (vec2 3 0))
       (stroke-width-to box 14))
      (animation-group
       (move-to route (vec2 3 -1))
       (rotate-by route 1/2)
       (stroke-width-to route 14))
      #:lag-ratio 1/3)
     (timed
      (animation-group
       (move-to vector (vec2 5 -2))
       (stroke-width-to vector 12))
      #:start 1
      #:duration 3)
     #:duration 5
     #:easing smoothstep))
  (define settle
    (scene-wait animated 1))
  (scene-play
   settle
   (animation-group
    (stroke-width-to ring 2)
    (stroke-width-to box 2)
    (stroke-width-to route 2)
    (stroke-width-to vector 2))
   #:duration 2
   #:easing smoothstep))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "animating-stroke-width.rkt"
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
