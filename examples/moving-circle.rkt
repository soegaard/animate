#lang racket/base

;;;
;;; Moving Circle Example
;;;

;; Renders the canonical SCENE-A movement as PNG frames and optionally MP4.


;;;
;;; Imports
;;;

(require racket/cmdline
         animate
         animate/render)


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Creates a circle that moves right and then waits for half a second.
(define (make-demo-scene)
  (define moving-circle
    (circle #:id 'moving-circle
            #:center (vec2 -3 0)
            #:radius 3/4
            #:fill "dodgerblue"
            #:stroke "navy"
            #:stroke-width 3))
  (scene-wait
   (scene-play
    (scene-add (make-scene) moving-circle)
    (move-to moving-circle (vec2 3 0))
    #:duration 1)
   1/2))


;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; output-directory : path-string?
  ;;   Gives the directory that receives numbered PNG frames.
  (define output-directory
    "frames")

  ; output-video : (or/c path-string? false/c)
  ;;   Gives the optional MP4 output path.
  (define output-video
    #f)

  (command-line
   #:program "moving-circle.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))

  ; frame-paths : (listof path?)
  ;;   Gives the numbered PNG paths written for the demo.
  (define frame-paths
    (render-frames! (make-demo-scene)
                    output-directory
                    #:fps 30))

  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)

  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
