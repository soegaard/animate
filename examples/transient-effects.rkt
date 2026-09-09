#lang racket/base

;;;
;;; Transient Attention Effects
;;;

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "FX-D: transient attention effects"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "a pulse writes the target while ripple rings remain temporary helpers"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define badge
    (circle #:id 'badge #:radius 1 #:center origin
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 4))
  (define base (scene-add (make-scene #:camera camera) title note badge))
  (define animated
    (scene-play
     (scene-wait base 1/2)
     (animation-group
      (pulse 'badge #:scale-factor 7/5 #:cycles 2)
      (ripple 'badge #:rings 4 #:color "gold" #:padding 1/5))
     #:duration 3))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "transient-effects.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
