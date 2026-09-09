#lang racket/base

;;;
;;; Exact Entry and Leave Effects
;;;

;; FX-B combines affine placement, rotation, scale, opacity, and lifecycle in
;; one exact request.  The small presets below are merely readable ways to
;; construct those same requests.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define card
    (rectangle #:id 'card #:width 3 #:height 3/2 #:center (vec2 -2 0)
               #:fill "gold" #:stroke "sienna" #:stroke-width 4))
  (define badge
    (circle #:id 'badge #:radius 4/5 #:center (vec2 3 0)
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 4))
  (define title
    (fixed-in-frame
     (plain-text "FX-B: exact enter and leave"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "slide and spin preserve authored endpoints; shrink and slide remove exactly on time"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define base (scene-add (make-scene #:camera camera) title note))
  (define entered
    (scene-play
     (scene-wait base 1/2)
     (animation-group (slide-in card 'left #:distance 6)
                      (spin-in badge #:turns 1))
     #:duration 2))
  (define after-leave
    (scene-play
     (scene-wait entered 1/2)
     (animation-group (shrink-out 'card)
                      (slide-out 'badge 'right #:distance 6))
     #:duration 2))
  (scene-wait after-leave 1/2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "enter-leave-effects.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
