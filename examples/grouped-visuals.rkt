#lang racket/base

;;;
;;; Grouped Visuals Example
;;;

;; Renders the canonical SCENE-K group and nested-transform example as PNG
;; frames and optionally assembles them as an MP4 file.


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
;;   Animates one nested composite through inherited transforms and opacity.
(define (make-demo-scene)
  (define badge
    (group
     (list
      (circle #:id 'badge-disc
              #:radius 3/5
              #:fill "gold"
              #:stroke "darkorange"
              #:stroke-width 3)
      (rectangle #:id 'badge-bar
                 #:width 4/5
                 #:height 1/5
                 #:fill "crimson"
                 #:stroke #f
                 #:stroke-width 0))
     #:id 'badge
     #:center (vec2 3/2 0)
     #:rotation 1/5
     #:scale 4/5))
  (define assembly
    (group
     (list
      (rectangle #:id 'body
                 #:width 5
                 #:height 2
                 #:fill "cornflowerblue"
                 #:stroke "navy"
                 #:stroke-width 4)
      (circle #:id 'left-port
              #:center (vec2 -3/2 0)
              #:radius 2/5
              #:fill "white"
              #:stroke "navy"
              #:stroke-width 3)
      (circle #:id 'right-port
              #:center (vec2 0 0)
              #:radius 2/5
              #:fill "white"
              #:stroke "navy"
              #:stroke-width 3)
      badge)
     #:id 'assembly
     #:center (vec2 -5 0)
     #:opacity 4/5))
  (define entrance
    (scene-play (make-scene)
                (move-to assembly origin)
                (rotate-to assembly 1/2)
                (scale-to assembly 3/2)
                (fade-in assembly)
                #:duration 2))
  (define exit
    (scene-play entrance
                (move-to assembly (vec2 5 0))
                (rotate-by assembly 1)
                (scale-to assembly 3/4)
                (fade-out assembly)
                #:duration 3/2))
  (scene-wait exit 1/2))


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
   #:program "grouped-visuals.rkt"
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
