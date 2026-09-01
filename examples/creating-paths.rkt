#lang racket/base

;;;
;;; Creating Paths Example
;;;

;; Renders the canonical SCENE-F Create and Uncreate animation as PNG frames and
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
;;   Creates two paths, transforms them, removes one, and holds the result.
(define (make-demo-scene)
  (define panel
    (polygon (list (vec2 -4 -1)
                   (vec2 -2 -2)
                   (vec2 0 -1)
                   (vec2 -2 2))
             #:id 'panel
             #:fill "cornflowerblue"
             #:stroke "navy"
             #:stroke-width 3))
  (define diagonal
    (line (vec2 2 -2)
          (vec2 4 2)
          #:id 'diagonal
          #:stroke "crimson"
          #:stroke-width 5))
  (define created
    (scene-play (make-scene)
                (create panel)
                (create diagonal)
                #:duration 2))
  (define transformed
    (scene-play created
                (move-to panel (vec2 2 0))
                (rotate-by panel 1)
                (move-to diagonal (vec2 -2 0))
                (rotate-by diagonal -1)
                #:duration 1))
  (define removed
    (scene-play transformed
                (uncreate diagonal)
                #:duration 1))
  (scene-wait removed 1/2))


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
   #:program "creating-paths.rkt"
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
