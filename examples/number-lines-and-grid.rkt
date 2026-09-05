#lang racket/base

;;;
;;; Number Lines and Axis Decorations Example
;;;

;; Renders automatic grid lines, numeric labels, and a separate number line.


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

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-T coordinate-decoration animation.
(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -4 4 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 8
          #:y-length 6
          #:stroke "navy"
          #:stroke-width 3))
  (define grid
    (axes-grid-lines coordinate-axes
                     #:id 'coordinate-grid
                     #:stroke "lightgray"
                     #:stroke-width 1))
  (define axis-labels
    (axes-number-labels coordinate-axes
                        #:id-prefix 'axis-label
                        #:font-size 3/10
                        #:color "navy"))
  (define scale-line
    (number-line (axis-range -3 5 1)
                 #:id 'scale-line
                 #:center (vec2 0 -4)
                 #:length 8
                 #:stroke "crimson"
                 #:stroke-width 3
                 #:end-tip? #t))
  (define scale-labels
    (number-line-number-labels scale-line
                               #:id-prefix 'scale-label
                               #:font-size 3/10
                               #:color "crimson"))
  (define diagram
    (group
     (append
      (list grid coordinate-axes scale-line)
      axis-labels
      scale-labels)
     #:id 'coordinate-diagram
     #:center (vec2 -5 0)
     #:rotation -1/20
     #:scale 9/10
     #:opacity 1))
  (define entrance
    (scene-play (make-scene)
                (move-to diagram origin)
                (rotate-to diagram 0)
                (scale-to diagram 1)
                (fade-in diagram)
                #:duration 2))
  (define emphasis
    (scene-play entrance
                (rotate-by diagram 1/24)
                (scale-to diagram 11/10)
                #:duration 1))
  (scene-wait emphasis 1/2))


;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; output-directory : path-string?
  ;;   Gives the directory that receives numbered PNG frames.
  (define output-directory "frames")

  ; output-video : (or/c path-string? false/c)
  ;;   Gives the optional MP4 output path.
  (define output-video #f)

  (command-line
   #:program "number-lines-and-grid.rkt"
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
