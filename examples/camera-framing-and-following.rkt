#lang racket/base

;;;
;;; Camera Framing and Following Example
;;;

;; Renders a coordinate diagram using renderer-aware camera fitting and follows
;; one moving marker while preserving its position in the output frame.


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

; graph-value : finite-real? -> finite-real?
;;   Returns the linear graph value used by the camera-following example.
(define (graph-value x)
  (/ x 2))

; graph-point : axes-visual? finite-real? -> vec2?
;;   Returns the displayed point on the example graph at x.
(define (graph-point coordinate-axes x)
  (axes-coordinates->point coordinate-axes
                           x
                           (graph-value x)))

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-W framing and following animation.
(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -6 6 1)
          #:y-range (axis-range -4 4 1)
          #:x-length 12
          #:y-length 8
          #:stroke "navy"
          #:stroke-width 3))
  (define grid
    (axes-grid-lines coordinate-axes
                     #:id 'coordinate-grid
                     #:stroke "lightgray"
                     #:stroke-width 1))
  (define labels
    (axes-number-labels coordinate-axes
                        #:id-prefix 'axis-label
                        #:font-size 1/4
                        #:color "navy"))
  (define diagram
    (group (append (list grid coordinate-axes)
                   labels)
           #:id 'coordinate-diagram))
  (define graph
    (function-graph coordinate-axes
                    graph-value
                    #:id 'linear-graph
                    #:sample-count 121
                    #:stroke "cornflowerblue"
                    #:stroke-width 4))
  (define marker
    (point-marker #:id 'marker
                  #:center (graph-point coordinate-axes -4)
                  #:shape 'diamond
                  #:size 1/3
                  #:fill "crimson"
                  #:stroke "darkred"
                  #:stroke-width 2))
  (define title
    (plain-text "Automatic camera framing and following"
                #:id 'title
                #:center (vec2 0 7/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define initial-camera
    (make-camera #:world-width 24
                 #:center (vec2 -3 2)
                 #:background "white"))
  (define entrance
    (scene-play
     (make-scene #:camera initial-camera)
     (fade-in diagram)
     (create graph)
     (fade-in marker)
     (fade-in title)
     (camera-fit-visuals (list diagram graph marker title)
                         #:camera initial-camera
                         #:padding 1/2)
     #:duration 3/2))
  (define following
    (scene-play
     entrance
     (move-to marker
              (graph-point coordinate-axes 4))
     (camera-follow marker)
     (camera-zoom-by 2)
     #:duration 2))
  (define overview
    (scene-play
     following
     (camera-fit-scene following #:padding 1/2)
     #:duration 3/2))
  (scene-wait overview 1/2))


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
   #:program "camera-framing-and-following.rkt"
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
