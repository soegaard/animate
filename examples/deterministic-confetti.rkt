#lang racket/base

;;;
;;; Deterministic Confetti
;;;

;; The particle plan belongs to the request, not to playback. Re-rendering or
;; seeking the same frame therefore keeps every piece in the same position.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define badge
    (circle #:id 'badge #:radius 1 #:center (vec2 0 0)
            #:fill "mediumorchid" #:stroke "indigo" #:stroke-width 4))
  (define title
    (fixed-in-frame
     (plain-text "FX-F: deterministic confetti"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 3)))
  (define note
    (fixed-in-frame
     (plain-text "an explicit seed gives the same closed-form particle plan on every seek"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -3)))
  (define base (scene-add (make-scene #:camera camera) title note badge))
  (define animated
    (scene-play
     (scene-wait base 1/2)
     (confetti 'badge #:count 48 #:seed 20260909 #:spread 5 #:height 5
               #:gravity 7 #:id 'celebration)
     #:duration 3))
  (scene-wait animated 1/2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "deterministic-confetti.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
