#lang racket/base

;;;
;;; Live-Tracking Ripple Effects
;;;

;; Each ripple ring is an ordinary lagged temporary overlay. The target moves
;; underneath it, so the renderer-measured ring follows the target rather than
;; being frozen at its initial position.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define beacon
    (circle #:id 'beacon #:radius 3/4 #:center (vec2 -4 0)
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 4))
  (define title
    (fixed-in-frame
     (plain-text "FX-D: live-tracking ripple"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 3)))
  (define note
    (fixed-in-frame
     (plain-text "each staggered ring reads the moving target; every helper disappears at its endpoint"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -3)))
  (define base (scene-add (make-scene #:camera camera) title note beacon))
  (define animated
    (scene-play
     (scene-wait base 1/2)
     (move-to 'beacon (vec2 4 0))
     (ripple 'beacon #:rings 4 #:spacing 3/5 #:lag-ratio 1/5
             #:color "gold" #:stroke-width 3 #:id 'beacon-ripple)
     #:duration 3))
  (scene-wait animated 1/2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "ripple-effects.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
