#lang racket/base

;;;
;;; Point Markers, Scatter Plots, and Filled Areas Example
;;;

;; Renders the canonical SCENE-V marker, scatter, filled-area, path, and camera
;; example as PNG frames and optionally assembles them as an MP4 file.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/cmdline
         animate
         animate/render)

;; Exports
(provide make-demo-scene)


;;;
;;; Scene Definition
;;;

; demo-function : finite-real? -> finite-real?
;;   Gives the smooth polynomial used by the line and area plots.
(define (demo-function x)
  (/ (* x (- x 2) (+ x 2)) 6))

; make-demo-scene : -> scene?
;;   Builds the canonical scatter, filled-area, graph, and camera animation.
(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -4 4 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 8
          #:y-length 6
          #:stroke "navy"
          #:stroke-width 3
          #:tick-size 1/5
          #:x-tip? #t
          #:y-tip? #t))
  (define grid
    (axes-grid-lines coordinate-axes
                     #:id 'coordinate-grid
                     #:stroke "lightgray"
                     #:stroke-width 1))
  (define shaded-area
    (function-area coordinate-axes
                   demo-function
                   #:id 'shaded-area
                   #:sample-count 241
                   #:interpolation 'smooth
                   #:opacity 2/5
                   #:fill "cornflowerblue"))
  (define graph
    (function-graph coordinate-axes
                    demo-function
                    #:id 'graph
                    #:sample-count 241
                    #:interpolation 'smooth
                    #:stroke "royalblue"
                    #:stroke-width 4))
  (define observations
    (scatter-plot
     coordinate-axes
     (list (vec2 -3 (demo-function -3))
           (vec2 -2 (demo-function -2))
           (vec2 -1 (demo-function -1))
           (vec2 0 (demo-function 0))
           (vec2 1 (demo-function 1))
           (vec2 2 (demo-function 2))
           (vec2 3 (demo-function 3)))
     #:id 'observations
     #:shape 'diamond
     #:size 1/4
     #:fill "crimson"
     #:stroke "darkred"
     #:stroke-width 1))
  (define entrance
    (scene-play (make-scene)
                (fade-in grid)
                (fade-in shaded-area)
                (create graph)
                (fade-in observations)
                (fade-in coordinate-axes)
                #:duration 2))
  (define focus
    ;; The camera zoom emphasizes the observations without changing their
    ;; numeric coordinates, so every marker remains on y = demo-function(x).
    (scene-play entrance
                (fade-to shaded-area 1/5)
                (camera-pan-to (vec2 1/2 0))
                (camera-zoom-by 5/4)
                #:duration 3/2))
  (scene-wait focus 1/2))


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
   #:program "markers-scatter-areas.rkt"
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
