#lang racket/base

;;;
;;; Hard-Clip Reveal Effects
;;;

;; Linear wipes and radial irises are readable constructors over reveal-in and
;; reveal-out. Their local layout boxes are frozen at each play-clip boundary.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define panel
    (rectangle #:id 'panel #:width 5 #:height 5/2 #:center (vec2 -9/4 0)
               #:fill "gold" #:stroke "sienna" #:stroke-width 4))
  (define orb
    (circle #:id 'orb #:radius 5/4 #:center (vec2 13/4 0)
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 4))
  (define title
    (fixed-in-frame
     (plain-text "FX-C: hard-clip wipes and irises"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "layout freezes once per clip; enter restores exactly and leave removes exactly"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define base (scene-add (make-scene #:camera camera) title note))
  (define entered
    (scene-play
     (scene-wait base 1/2)
     (animation-group (wipe-in panel 'right)
                      (iris-in orb))
     #:duration 2))
  (define after-leave
    (scene-play
     (scene-wait entered 1/2)
     (animation-group (wipe-out 'panel 'left)
                      (iris-out 'orb))
     #:duration 2))
  (scene-wait after-leave 1/2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "clip-reveals.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
