#lang racket/base

;;;
;;; Path Shapes Example
;;;

;; Renders the canonical SCENE-E line and polygon animation as PNG frames and
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
;;   Creates a polygon and line that move, rotate, scale, and hold their endpoints.
(define (make-demo-scene)
  (define moving-polygon
    (polygon (list (vec2 -4 -1)
                   (vec2 -2 -2)
                   (vec2 0 -1)
                   (vec2 -2 2))
             #:id 'moving-polygon
             #:fill "cornflowerblue"
             #:stroke "navy"
             #:stroke-width 3))
  (define moving-line
    (line (vec2 2 -2)
          (vec2 4 2)
          #:id 'moving-line
          #:stroke "crimson"
          #:stroke-width 5))
  (scene-wait
   (scene-play
    (scene-add (make-scene)
               moving-polygon
               moving-line)
    (move-to moving-polygon (vec2 2 0))
    (rotate-by moving-polygon 3/2)
    (scale-to moving-polygon (vec2 1/2 3/2))
    (move-to moving-line (vec2 -2 0))
    (rotate-by moving-line -1)
    (scale-by moving-line (vec2 3/2 1/2))
    #:duration 2)
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
   #:program "path-shapes.rkt"
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
