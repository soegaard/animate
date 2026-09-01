#lang racket/base

;;;
;;; Parametric Curves and Data Plots Example
;;;

;; Builds Cartesian axes, a smooth parametric curve, and a smooth ordered data
;; plot, then animates them through the existing path and opacity operations.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Creates and animates one parametric-and-data coordinate diagram.
(define (make-demo-scene)
  ; coordinate-axes : axes-visual?
  ;;   Gives an eight-by-six coordinate system with regular unit ticks.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -4 4 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 8
          #:y-length 6
          #:stroke "navy"
          #:stroke-width 3))

  ; loop-curve : path-visual?
  ;;   Gives one smooth nodal cubic with a non-monotone x coordinate.
  (define loop-curve
    (parametric-curve
     coordinate-axes
     (lambda (parameter)
       (define x
         (- (* parameter parameter) 2))
       (vec2 x (/ (* parameter x) 2)))
     #:id 'loop-curve
     #:parameter-range (parameter-range -2 2)
     #:sample-count 181
     #:interpolation 'smooth
     #:stroke "crimson"
     #:stroke-width 4))

  ; observations : path-visual?
  ;;   Gives a smooth plot through one significant ordered series of data points.
  (define observations
    (data-plot
     coordinate-axes
     (list (vec2 -3 -3/2)
           (vec2 -2 1/2)
           (vec2 -1 1)
           (vec2 0 1/4)
           (vec2 1 -1)
           (vec2 2 -1/2)
           (vec2 3 3/2))
     #:id 'observations
     #:interpolation 'smooth
     #:opacity 4/5
     #:stroke "seagreen"
     #:stroke-width 4))

  ; x-label : text-visual?
  ;;   Gives an x label beside the measured axes box.
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
  ;;   Gives a y label above the measured axes box.
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
  ;;   Fades in the coordinate frame while drawing both ordered curves.
  (define entrance
    (scene-play (make-scene)
                (fade-in coordinate-axes)
                (fade-in x-label)
                (fade-in y-label)
                (create loop-curve)
                (create observations)
                #:duration 5/2))

  ; emphasis : scene?
  ;;   Dims the data plot to emphasize the parametric curve.
  (define emphasis
    (scene-play entrance
                (fade-to observations 1/3)
                (rotate-by loop-curve 1/12)
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
   #:program "parametric-data-plots.rkt"
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
