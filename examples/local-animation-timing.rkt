#lang racket/base

;;;
;;; Local Animation Timing Example
;;;

;; SCENE-AN keeps one enclosing play clip while giving individual Visual
;; requests their own local start times, durations, and optional easing.

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
  (define a
    (circle #:id 'a
            #:radius 3/4
            #:center (vec2 -6 2)
            #:fill "slateblue"))
  (define b
    (rectangle #:id 'b
               #:width 3/2
               #:height 3/2
               #:center (vec2 -6 0)
               #:fill "seagreen"))
  (define c
    (circle #:id 'c
            #:radius 3/4
            #:center (vec2 -6 -2)
            #:fill "tomato"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AN: local animation timing"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "one play clip; three independent local intervals"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera) a b c title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (timed (move-to a (vec2 6 2))
            #:start 0
            #:duration 3
            #:easing smoothstep)
     (timed (move-to b (vec2 6 0))
            #:start 1
            #:duration 3
            #:easing smoothstep)
     (timed (move-to c (vec2 6 -2))
            #:start 2
            #:duration 3
            #:easing smoothstep)
     #:duration 5))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "local-animation-timing.rkt"
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
