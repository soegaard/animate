#lang racket/base

;;;
;;; Typewriter and Semantic Text Decorations
;;;

;; The typewriter keeps one final shaped layout and masks prepared fragments of
;; it. The three subsequent decorations are separate semantic Visuals, not
;; raster marks.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define heading
    (plain-text "FX-F: stable text effects"
                #:id 'title #:center (vec2 0 3)
                #:font-size 2/5 #:font-family 'swiss
                #:font-weight 'bold #:color "navy"))
  (define note
    (plain-text "typewrite clips one shaped layout; decorations are ordinary scene Visuals"
                #:id 'note #:center (vec2 0 -3)
                #:font-size 7/20 #:font-family 'swiss #:color "dimgray"))
  (define message
    (plain-text "frozen layout" #:id 'message #:center (vec2 0 0)
                #:font-size 1 #:font-family 'swiss #:color "midnightblue"))
  (define base
    (scene-add (make-scene #:camera camera) heading note))
  (define typed
    (scene-play (scene-wait base 1/2)
                (typewrite message #:unit 'grapheme
                           #:cursor? #t #:cursor-style "tomato")
                #:duration 2))
  (define decorated
    (scene-play (scene-wait typed 1/2)
                (highlight-sweep 'message #:retain? #t #:padding 1/10)
                (underline-sweep 'message #:color "tomato" #:stroke-width 3)
                (strike-through 'message #:color "mediumorchid" #:stroke-width 3)
                #:duration 2))
  (scene-wait decorated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "typewriter-and-decorations.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
