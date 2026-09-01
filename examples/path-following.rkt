#lang racket/base

;;;
;;; Path Following Example
;;;

;; Renders a marker moving at constant arc-length speed along a cubic route.
;; The return traversal demonstrates reverse fractions together with camera
;; following that tracks the actual sampled curved motion.


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
;;   Constructs the canonical SCENE-Y path-following animation.
(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 14
                 #:center origin
                 #:background "white"))
  (define route-geometry
    (cubic-bezier-path
     (vec2 -5 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 -4 4)
       (vec2 -1 4)
       (vec2 0 0))
      (cubic-bezier-path-segment
       (vec2 1 -4)
       (vec2 4 -4)
       (vec2 5 2)))))
  (define route
    (make-path-visual route-geometry
                      #:id 'route
                      #:stroke "cornflowerblue"
                      #:stroke-width 4))
  (define marker
    (point-marker #:id 'marker
                  #:center (path-geometry-point-at route-geometry 0)
                  #:shape 'diamond
                  #:size 1/2
                  #:fill "crimson"
                  #:stroke "darkred"
                  #:stroke-width 2))
  (define title
    (fixed-in-frame
     (plain-text "Arc-length path following"
                 #:id 'title
                 #:font-size 1/2
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera camera
     #:at (vec2 0 3)))
  (define entrance
    (scene-play
     (make-scene #:camera camera)
     (create route)
     (fade-in marker)
     (fade-in title)
     #:duration 3/2))
  (define outward
    (scene-play entrance
                (move-along-path marker route)
                #:duration 4))
  (define returning
    (scene-play outward
                (move-along-path marker route #:start 1 #:end 0)
                (camera-follow marker)
                (camera-zoom-by 3/2)
                #:duration 3))
  (scene-wait returning 1/2))


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
   #:program "path-following.rkt"
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
