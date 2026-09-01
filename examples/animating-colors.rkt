#lang racket/base

;;;
;;; Fill and Stroke Color Animation Example
;;;

;; SCENE-AT adds renderer-independent semantic RGBA interpolation plus separate
;; fill-color and stroke-color animation components.

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
  (define disk
    (circle #:id 'disk
            #:center (vec2 -5 2)
            #:radius 4/5
            #:fill "royalblue"
            #:stroke "midnightblue"
            #:stroke-width 4))
  (define box
    (rectangle #:id 'box
               #:center (vec2 -5 0)
               #:width 8/5
               #:height 7/5
               #:fill "seagreen"
               #:stroke "darkgreen"
               #:stroke-width 4))
  (define vector
    (arrow (vec2 -6 -2)
           (vec2 -4 -2)
           #:id 'vector
           #:stroke "darkorange"
           #:stroke-width 5
           #:tip-length 1/2
           #:tip-width 2/5))
  (define marker
    (point-marker #:id 'marker
                  #:center (vec2 5 -2)
                  #:shape 'diamond
                  #:size 6/5
                  #:fill "gold"
                  #:stroke "saddlebrown"
                  #:stroke-width 4))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AT: fill and stroke color animation"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "semantic RGBA interiors; exact named-color endpoints"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera)
               disk box vector marker title note))
  (define intro (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (lagged-start
      (animation-group
       (move-to disk (vec2 3 2))
       (fill-color-to disk "tomato")
       (stroke-color-to disk "darkred"))
      (animation-group
       (move-to box (vec2 3 0))
       (fill-color-to box "cornflowerblue")
       (stroke-color-to box "navy"))
      (animation-group
       (move-to vector (vec2 3 -2))
       (stroke-color-to vector "purple"))
      #:lag-ratio 1/3)
     (timed
      (animation-group
       (fill-color-to marker (rgba-color 255 0 0 1/4))
       (stroke-color-to marker "black")
       (rotate-by marker 1))
      #:start 1
      #:duration 3)
     #:duration 5
     #:easing smoothstep))
  (define settle (scene-wait animated 1))
  (scene-play
   settle
   (animation-group
    (fill-color-to disk "royalblue")
    (stroke-color-to disk "midnightblue")
    (fill-color-to box "seagreen")
    (stroke-color-to box "darkgreen")
    (stroke-color-to vector "darkorange")
    (fill-color-to marker "gold")
    (stroke-color-to marker "saddlebrown"))
   #:duration 2
   #:easing smoothstep))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "animating-colors.rkt"
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
