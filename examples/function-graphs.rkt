#lang racket/base

;;;
;;; Sampled Function Graphs Example
;;;

;; Builds Cartesian axes and two coordinate-aware piecewise-linear function
;; graphs, including one graph with an explicit discontinuity.


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
;;   Creates and animates one sampled coordinate graph diagram.
(define (make-demo-scene)
  ; coordinate-axes : axes-visual?
  ;;   Gives a ten-by-six coordinate system with regular unit ticks.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -5 5 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 10
          #:y-length 6
          #:stroke "navy"
          #:stroke-width 3))

  ; cubic-graph : path-visual?
  ;;   Gives a clipped cubic polynomial sampled across the full x range.
  (define cubic-graph
    (function-graph
     coordinate-axes
     (lambda (x)
       (/ (* x (- x 2) (+ x 2)) 4))
     #:id 'cubic-graph
     #:sample-count 241
     #:stroke "crimson"
     #:stroke-width 4))

  ; reciprocal-graph : path-visual?
  ;;   Gives a reciprocal graph split explicitly at x = 0.
  (define reciprocal-graph
    (function-graph
     coordinate-axes
     (lambda (x)
       (if (zero? x)
           #f
           (/ 1 x)))
     #:id 'reciprocal-graph
     #:sample-count 241
     #:max-jump 3
     #:opacity 4/5
     #:stroke "seagreen"
     #:stroke-width 4))

  ; x-label : text-visual?
  ;;   Gives an x label beside the complete measured axes box.
  (define x-label
    (visual-place-right-of
     (plain-text "x"
                 #:id 'x-label
                 #:font-size 2/5
                 #:font-family 'roman
                 #:font-style 'italic
                 #:color "navy")
     coordinate-axes
     #:gap 1/5))

  ; y-label : text-visual?
  ;;   Gives a y label above the complete measured axes box.
  (define y-label
    (visual-place-above
     (plain-text "y"
                 #:id 'y-label
                 #:font-size 2/5
                 #:font-family 'roman
                 #:font-style 'italic
                 #:color "navy")
     coordinate-axes
     #:gap 1/5))

  ; entrance : scene?
  ;;   Fades in the axes and labels while drawing both sampled graphs.
  (define entrance
    (scene-play (make-scene)
                (fade-in coordinate-axes)
                (fade-in x-label)
                (fade-in y-label)
                (create cubic-graph)
                (create reciprocal-graph)
                #:duration 5/2))

  ; emphasis : scene?
  ;;   Dims the reciprocal graph to emphasize the cubic polynomial.
  (define emphasis
    (scene-play entrance
                (fade-to reciprocal-graph 1/3)
                #:duration 1))

  (scene-wait emphasis 1/2))


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
   #:program "function-graphs.rkt"
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
