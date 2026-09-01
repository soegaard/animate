#lang racket/base

;;;
;;; Unified Style Transition Example
;;;

;; SCENE-AU bundles fill, stroke, stroke width, and opacity changes with style-to
;; while leaving each property an independent scheduler component.

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
            #:center (vec2 -5 1)
            #:radius 1
            #:fill "royalblue"
            #:stroke "midnightblue"
            #:stroke-width 3))
  (define box
    (rectangle #:id 'box
               #:center (vec2 -5 -2)
               #:width 2
               #:height 3/2
               #:fill "seagreen"
               #:stroke "darkgreen"
               #:stroke-width 3))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AU: unified style transitions"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define base
    (scene-add (make-scene #:camera camera) disk box title))
  (define intro
    (scene-wait base 1))
  (define first-pass
    (scene-play
     intro
     (animation-group
      (move-to disk (vec2 4 1))
      (style-to disk
                #:fill "tomato"
                #:stroke "darkred"
                #:stroke-width 10
                #:opacity 3/4))
     (timed
      (animation-group
       (move-to box (vec2 4 -2))
       (style-to box
                 #:fill "cornflowerblue"
                 #:stroke "navy"
                 #:stroke-width 8
                 #:opacity 1/2))
      #:start 1
      #:duration 3)
     #:duration 4
     #:easing smoothstep))
  (define settle
    (scene-wait first-pass 1))
  (scene-play
   settle
   (succession
    (style-to 'disk
              #:fill "gold"
              #:stroke "saddlebrown"
              #:stroke-width 5
              #:opacity 1)
    (style-to 'box
              #:fill "plum"
              #:stroke "purple"
              #:stroke-width 5
              #:opacity 1))
   #:duration 3
   #:easing smoothstep))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "unified-style-transitions.rkt"
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
