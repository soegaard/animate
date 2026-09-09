#lang racket/base

;;;
;;; Deterministic Camera Shake
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
     (plain-text "FX-D: deterministic camera shake"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "the explicit seed determines a finite camera-offset plan that returns exactly"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define grid
    (group
     (for*/list ([x (in-list '(-3 0 3))]
                 [y (in-list '(-1 1))])
       (circle #:id (string->symbol (format "dot-~a-~a" x y))
               #:radius 2/5 #:center (vec2 x y)
               #:fill "mediumturquoise" #:stroke "teal" #:stroke-width 3))
     #:id 'grid))
  (define base (scene-add (make-scene #:camera camera) title note grid))
  (define shaken
    (scene-play
     (scene-wait base 1/2)
     (camera-shake #:amplitude 2/5 #:samples 12 #:seed 20260909 #:decay 'smooth)
     #:duration 3))
  (scene-wait shaken 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "deterministic-camera-shake.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
