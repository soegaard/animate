#lang racket/base

;;;
;;; Camera Pan and Zoom Example
;;;

;; Renders a coordinate diagram while the scene camera pans and changes its
;; visible world width.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/cmdline
         "../main.rkt")

;; Exports
(provide make-demo-scene)


;;;
;;; Scene Definition
;;;

; graph-value : finite-real? -> finite-real?
;;   Returns the quadratic value used by the canonical camera example.
(define (graph-value x)
  (- (/ (* x x) 4)
     2))

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-U camera pan-and-zoom animation.
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
                    #:id 'quadratic-graph
                    #:sample-count 241
                    #:interpolation 'smooth
                    #:stroke "crimson"
                    #:stroke-width 4))
  (define marker
    (circle #:id 'marker
            #:center (axes-coordinates->point
                      coordinate-axes
                      -4
                      (graph-value -4))
            #:radius 1/6
            #:fill "gold"
            #:stroke "crimson"
            #:stroke-width 3))
  (define title
    (plain-text "Camera pan and zoom"
                #:id 'title
                #:center (vec2 0 7/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define initial-camera
    (make-camera #:world-width 14
                 #:center origin
                 #:background "white"))
  (define entrance
    (scene-play
     (make-scene #:camera initial-camera)
     (fade-in diagram)
     (create graph)
     (fade-in marker)
     (fade-in title)
     #:duration 3/2))
  (define focus-left
    (scene-play
     entrance
     (camera-pan-to (vec2 -2 -1))
     (camera-zoom-by 2)
     (move-to marker
              (axes-coordinates->point
               coordinate-axes
               -2
               (graph-value -2)))
     #:duration 3/2))
  (define follow-right
    (scene-play
     focus-left
     (camera-pan-to (vec2 3 1/4))
     (move-to marker
              (axes-coordinates->point
               coordinate-axes
               3
               (graph-value 3)))
     #:duration 3/2))
  (define overview
    (scene-play
     follow-right
     (camera-pan-to origin)
     (camera-zoom-to 14)
     (move-to marker
              (axes-coordinates->point
               coordinate-axes
               0
               (graph-value 0)))
     #:duration 3/2))
  (scene-wait overview 1/2))


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
   #:program "camera-pan-and-zoom.rkt"
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
