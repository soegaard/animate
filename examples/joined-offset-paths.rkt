#lang racket/base

;;;
;;; Joined Offset Paths Example
;;;

;; Renders miter, bevel, and round continuous offsets of the same right-angle
;; polyline. A directional arrow then traverses the round joined offset using
;; the ordinary SCENE-Y/SCENE-Z path-motion and orientation operations.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-AA joined-offset animation.
(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 24
                 #:center origin
                 #:background "white"))
  (define base
    (polyline-path
     (list (vec2 -4 2)
           (vec2 0 2)
           (vec2 0 -1)
           (vec2 4 -1))))
  (define miter-geometry
    (path-geometry-translate
     (path-geometry-offset base 2/3 #:join 'miter)
     (vec2 0 4)))
  (define bevel-geometry
    (path-geometry-offset base 2/3 #:join 'bevel))
  (define round-geometry
    (path-geometry-translate
     (path-geometry-offset base 2/3 #:join 'round)
     (vec2 0 -4)))
  (define miter-route
    (make-path-visual miter-geometry
                      #:id 'miter-route
                      #:stroke "slateblue"
                      #:stroke-width 4))
  (define bevel-route
    (make-path-visual bevel-geometry
                      #:id 'bevel-route
                      #:stroke "darkorange"
                      #:stroke-width 4))
  (define round-route
    (make-path-visual round-geometry
                      #:id 'round-route
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define miter-label
    (plain-text "miter"
                #:id 'miter-label
                #:center (vec2 -6 5)
                #:font-size 1/2
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "slateblue"))
  (define bevel-label
    (plain-text "bevel"
                #:id 'bevel-label
                #:center (vec2 -6 1)
                #:font-size 1/2
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "darkorange"))
  (define round-label
    (plain-text "round"
                #:id 'round-label
                #:center (vec2 -6 -3)
                #:font-size 1/2
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "seagreen"))
  (define round-start
    (path-geometry-point-at round-geometry 0))
  (define rider
    (arrow (vec2- round-start (vec2 2/5 0))
           (vec2+ round-start (vec2 2/5 0))
           #:id 'rider
           #:stroke "crimson"
           #:stroke-width 4
           #:tip-length 1/3
           #:tip-width 2/5))
  (define title
    (fixed-in-frame
     (plain-text "Continuous offset joins: miter / bevel / round"
                 #:id 'title
                 #:font-size 1/2
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera camera
     #:at (vec2 0 6)))
  (define entrance
    (scene-play
     (make-scene #:camera camera)
     (create miter-route)
     (create bevel-route)
     (create round-route)
     (fade-in title)
     (fade-in miter-label)
     (fade-in bevel-label)
     (fade-in round-label)
     (fade-in rider)
     #:duration 2))
  (define traversal
    (scene-play entrance
                (move-along-path rider round-route)
                (orient-along-path rider round-route)
                #:duration 5))
  (scene-wait traversal 1/2))


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
   #:program "joined-offset-paths.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))

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
