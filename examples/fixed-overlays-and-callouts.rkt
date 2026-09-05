#lang racket/base

;;;
;;; Fixed Overlays and Callouts Example
;;;

;; Renders a sampled quadratic while a title and annotation remain fixed in the
;; output frame. The marker traverses the same piecewise-linear samples as the
;; graph, and the annotation's leader follows that moving world-space marker
;; while the world camera pans and zooms independently.


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
;;; Example Geometry
;;;

; graph-x-min : finite-real?
;;   Gives the left numeric endpoint sampled for the quadratic graph.
(define graph-x-min
  -6)

; graph-x-max : finite-real?
;;   Gives the right numeric endpoint sampled for the quadratic graph.
(define graph-x-max
  6)

; graph-sample-count : exact-integer-at-least-2?
;;   Gives the number of equally spaced samples used by the rendered graph.
(define graph-sample-count
  181)

; marker-x-start : finite-real?
;;   Gives the marker's initial numeric x coordinate on the graph.
(define marker-x-start
  -4)

; marker-x-end : finite-real?
;;   Gives the marker's final numeric x coordinate on the graph.
(define marker-x-end
  4)

; moving-view-duration : positive-real?
;;   Gives the duration of simultaneous graph traversal and camera motion.
(define moving-view-duration
  3)

; moving-camera-center : vec2?
;;   Gives the final world-camera center after the marker traversal.
(define moving-camera-center
  (vec2 2 1))

; moving-camera-zoom-factor : positive-real?
;;   Gives the final magnification relative to the initial camera.
(define moving-camera-zoom-factor
  2)

; graph-value : finite-real? -> finite-real?
;;   Returns the quadratic graph value used by the SCENE-X example.
(define (graph-value x)
  (/ (* x x) 4))

; graph-point : axes-visual? finite-real? -> vec2?
;;   Returns the displayed graph point at numeric x.
(define (graph-point coordinate-axes x)
  (axes-coordinates->point coordinate-axes
                           x
                           (graph-value x)))

; marker-route-sample-count : exact-integer-at-least-2?
;;   Matches the rendered graph's 1/15 x sampling step from x=-4 through x=4.
(define marker-route-sample-count
  121)



;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-X overlay and callout animation.
(define (make-demo-scene)
  (define initial-camera
    (make-camera #:world-width 16
                 #:center origin
                 #:background "white"))
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range graph-x-min graph-x-max 1)
          #:y-range (axis-range -1 5 1)
          #:x-length 12
          #:y-length 6
          #:stroke "navy"
          #:stroke-width 3))
  (define graph
    (function-graph coordinate-axes
                    graph-value
                    #:id 'quadratic-graph
                    #:x-min graph-x-min
                    #:x-max graph-x-max
                    #:sample-count graph-sample-count
                    #:interpolation 'linear
                    #:stroke "cornflowerblue"
                    #:stroke-width 4))
  (define marker-route
    (sample-function-path coordinate-axes
                          graph-value
                          #:x-min marker-x-start
                          #:x-max marker-x-end
                          #:sample-count marker-route-sample-count
                          #:interpolation 'linear))
  (define marker
    (point-marker #:id 'marker
                  #:center (graph-point coordinate-axes marker-x-start)
                  #:shape 'diamond
                  #:size 2/5
                  #:fill "crimson"
                  #:stroke "darkred"
                  #:stroke-width 2))
  (define title
    (fixed-in-frame
     (plain-text "Fixed overlays and world-space callouts"
                 #:id 'title
                 #:font-size 1/2
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera initial-camera
     #:at (vec2 0 15/4)))
  (define marker-callout
    (callout
     (plain-text "This label stays in the frame"
                 #:id 'marker-callout
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "darkred")
     marker
     #:camera initial-camera
     #:at (vec2 5 5/2)
     #:connector-stroke "darkred"
     #:connector-width 3))
  (define entrance
    (scene-play
     (make-scene #:camera initial-camera)
     (fade-in coordinate-axes)
     (create graph)
     (fade-in marker)
     (fade-in title)
     (fade-in marker-callout)
     #:duration 3/2))
  (define moving-view
    (scene-play entrance
                (move-along-path marker marker-route)
                (camera-pan-to moving-camera-center)
                (camera-zoom-by moving-camera-zoom-factor)
                #:duration moving-view-duration))
  (scene-wait moving-view 1/2))


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
   #:program "fixed-overlays-and-callouts.rkt"
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
