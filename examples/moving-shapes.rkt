#lang racket/base

;;;
;;; Moving Shapes Example
;;;

;; Renders the canonical SCENE-B mixed-Visual movement as PNG frames and
;; optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Creates a rectangle and circle that cross and then hold their endpoints.
(define (make-demo-scene)
  (define moving-rectangle
    (rectangle #:id 'moving-rectangle
               #:center (vec2 -3 0)
               #:width 2
               #:height 4/3
               #:fill "goldenrod"
               #:stroke "saddlebrown"
               #:stroke-width 3))
  (define moving-circle
    (circle #:id 'moving-circle
            #:center (vec2 3 0)
            #:radius 2/3
            #:fill "dodgerblue"
            #:stroke "navy"
            #:stroke-width 3))
  (scene-wait
   (scene-play
    (scene-add (make-scene)
               moving-rectangle
               moving-circle)
    (move-to moving-rectangle (vec2 3 0))
    (move-to moving-circle (vec2 -3 0))
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
   #:program "moving-shapes.rkt"
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
