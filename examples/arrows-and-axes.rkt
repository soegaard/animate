#lang racket/base

;;;
;;; Arrows and Axes Example
;;;

;; Builds Cartesian axes, single- and double-tipped arrows, renderer-aware
;; labels, and an animated semantic diagram.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Builds and animates one labeled coordinate diagram.
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

  ; vector-arrow : arrow-visual?
  ;;   Gives the vector from numeric coordinate (0, 0) to (3, 2).
  (define vector-arrow
    (arrow (axes-coordinates->point coordinate-axes 0 0)
           (axes-coordinates->point coordinate-axes 3 2)
           #:id 'vector-arrow
           #:stroke "crimson"
           #:stroke-width 4
           #:tip-length 2/5
           #:tip-width 1/3))

  ; interval-arrow : arrow-visual?
  ;;   Gives a double-tipped comparison arrow below the x axis.
  (define interval-arrow
    (arrow (axes-coordinates->point coordinate-axes -4 -2)
           (axes-coordinates->point coordinate-axes -1 -2)
           #:id 'interval-arrow
           #:stroke "seagreen"
           #:stroke-width 3
           #:tip-length 3/10
           #:tip-width 1/4
           #:start-tip? #t
           #:end-tip? #t))

  ; x-label : text-visual?
  ;;   Gives an x label placed to the right of the measured axes box.
  (define x-label
    (visual-place-right-of
     (plain-text "x"
                 #:id 'x-label
                 #:font-size 2/5
                 #:font-family 'roman
                 #:font-style 'italic
                 #:color "navy")
     coordinate-axes
     #:gap 1/5
     #:vertical-alignment 'center))

  ; y-label : text-visual?
  ;;   Gives a y label placed above the measured axes box.
  (define y-label
    (visual-place-above
     (plain-text "y"
                 #:id 'y-label
                 #:font-size 2/5
                 #:font-family 'roman
                 #:font-style 'italic
                 #:color "navy")
     coordinate-axes
     #:gap 1/5
     #:horizontal-alignment 'center))

  ; vector-label : text-visual?
  ;;   Gives a label above and right-aligned with the vector arrow.
  (define vector-label
    (visual-place-above
     (plain-text "v = (3, 2)"
                 #:id 'vector-label
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "crimson")
     vector-arrow
     #:gap 1/5
     #:horizontal-alignment 'right))

  ; diagram : group-visual?
  ;;   Gives axes, arrows, and labels in significant back-to-front order.
  (define diagram
    (group (list coordinate-axes
                 interval-arrow
                 vector-arrow
                 x-label
                 y-label
                 vector-label)
           #:id 'coordinate-diagram
           #:center (vec2 -6 0)
           #:rotation -1/12
           #:scale 4/5
           #:opacity 4/5))

  ; entrance : scene?
  ;;   Moves the complete coordinate diagram into place.
  (define entrance
    (scene-play (make-scene)
                (move-to diagram origin)
                (rotate-to diagram 0)
                (scale-to diagram 1)
                (fade-in diagram)
                #:duration 2))

  ; emphasis : scene?
  ;;   Gives the diagram a small final rotation and scale emphasis.
  (define emphasis
    (scene-play entrance
                (rotate-to diagram 1/48)
                (scale-to diagram 21/20)
                (fade-to diagram 1)
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
   #:program "arrows-and-axes.rkt"
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
