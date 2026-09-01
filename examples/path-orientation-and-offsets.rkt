#lang racket/base

;;;
;;; Path Orientation and Offsets Example
;;;

;; Renders two directional arrows traversing one cubic route at constant arc
;; length. One rides directly on the route; the other stays one world unit to
;; the left of the traversal tangent. Both rotate from semantic path tangents.


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
;;   Constructs the canonical SCENE-Z tangent-orientation animation.
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
       (vec2 -3 -2)
       (vec2 -2 3)
       (vec2 0 2))
      (cubic-bezier-path-segment
       (vec2 2 1)
       (vec2 3 -3)
       (vec2 5 -1)))))
  (define route
    (make-path-visual route-geometry
                      #:id 'route
                      #:stroke "cornflowerblue"
                      #:stroke-width 4))
  ;; The route begins with a +x tangent, so both arrows start with rotation 0.
  (define rider
    (arrow (vec2 -23/4 -2)
           (vec2 -17/4 -2)
           #:id 'rider
           #:stroke "crimson"
           #:stroke-width 4
           #:tip-length 2/5
           #:tip-width 1/2))
  (define offset-rider
    (arrow (vec2 -23/4 -1)
           (vec2 -17/4 -1)
           #:id 'offset-rider
           #:stroke "darkorange"
           #:stroke-width 3
           #:tip-length 2/5
           #:tip-width 1/2))
  (define title
    (fixed-in-frame
     (plain-text "Tangent orientation + normal offset"
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
     (fade-in rider)
     (fade-in offset-rider)
     (fade-in title)
     #:duration 3/2))
  (define traversal
    (scene-play entrance
                (move-along-path rider route)
                (orient-along-path rider route)
                (move-along-path offset-rider
                                 route
                                 #:normal-offset 1)
                (orient-along-path offset-rider route)
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
   #:program "path-orientation-and-offsets.rkt"
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
