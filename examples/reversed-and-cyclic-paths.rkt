#lang racket/base

;;;
;;; Reversed and Cyclic Paths Example
;;;

;; Shows two arrows traversing the same closed loop in opposite directions and
;; a third arrow traversing an equivalent copy whose stored start has been moved
;; to an arbitrary arc-length phase.


;;;
;;; Imports and Exports
;;;

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)


;;;
;;; Helpers
;;;

; make-route : -> path-geometry?
;;   Creates one asymmetric closed loop whose start is visually identifiable.
(define (make-route)
  (polygon-path
   (list (vec2 -5 1)
         (vec2 0 3)
         (vec2 4 1)
         (vec2 2 -1)
         (vec2 -4 -1))))

; make-route-arrow : symbol? path-geometry? any/c -> arrow-visual?
;;   Creates one short arrow centered and tangent-aligned at route fraction zero.
(define (make-route-arrow identifier route color)
  (define point
    (path-geometry-point-at route 0))
  (define tangent
    (path-geometry-tangent-at route 0))
  (arrow (vec2 (- (vec2-x point) 9/20)
               (vec2-y point))
         (vec2 (+ (vec2-x point) 9/20)
               (vec2-y point))
         #:id identifier
         #:rotation (atan (vec2-y tangent) (vec2-x tangent))
         #:stroke color
         #:stroke-width 4
         #:tip-length 7/20
         #:tip-width 9/20))


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Constructs the canonical SCENE-AB reversal/phase animation.
(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 18
                 #:center (vec2 0 -1/2)
                 #:background "white"))

  ;; Top panel: the same visible loop is traversed from the same start in both
  ;; directions. Reversal changes semantics, not the drawn geometry.
  (define top-route
    (make-route))
  (define reversed-top-route
    (path-geometry-reverse top-route))
  (define top-route-visual
    (make-path-visual top-route
                      #:id 'top-route
                      #:fill #f
                      #:stroke "lightgray"
                      #:stroke-width 5))
  (define forward-arrow
    (make-route-arrow 'forward-arrow top-route "crimson"))
  (define reverse-arrow
    (make-route-arrow 'reverse-arrow reversed-top-route "royalblue"))
  (define top-label
    (plain-text "same start, opposite traversal"
                #:id 'top-label
                #:center (vec2 0 3.7)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "black"))

  ;; Bottom panel: moving the stored start by 0.30 of total arc length leaves
  ;; the loop itself unchanged. Both start positions are marked explicitly.
  (define bottom-route
    (path-geometry-translate top-route (vec2 0 -4)))
  (define cycled-bottom-route
    (path-geometry-cycle-start bottom-route 3/10))
  (define bottom-route-visual
    (make-path-visual bottom-route
                      #:id 'bottom-route
                      #:fill #f
                      #:stroke "lightgray"
                      #:stroke-width 5))
  (define original-start
    (point-marker #:id 'original-start
                  #:center (path-geometry-point-at bottom-route 0)
                  #:shape 'square
                  #:size 7/20
                  #:fill "navy"
                  #:stroke #f
                  #:stroke-width 0))
  (define cycled-start
    (point-marker #:id 'cycled-start
                  #:center (path-geometry-point-at cycled-bottom-route 0)
                  #:shape 'diamond
                  #:size 9/20
                  #:fill "darkorange"
                  #:stroke #f
                  #:stroke-width 0))
  (define phase-arrow
    (make-route-arrow 'phase-arrow cycled-bottom-route "darkorange"))
  (define bottom-label
    (plain-text "same loop, cyclic start = 0.30"
                #:id 'bottom-label
                #:center (vec2 0 -1.3)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "black"))

  (define title
    (fixed-in-frame
     (plain-text "Path reversal + cyclic starts"
                 #:id 'title
                 #:font-size 1/2
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera camera
     #:at (vec2 0 4.25)))

  (define scene
    (scene-add (make-scene #:camera camera)
               top-route-visual
               bottom-route-visual
               original-start
               cycled-start
               forward-arrow
               reverse-arrow
               phase-arrow
               top-label
               bottom-label
               title))

  (define traversal
    (scene-play scene
                (move-along-path forward-arrow top-route)
                (orient-along-path forward-arrow top-route)
                (move-along-path reverse-arrow reversed-top-route)
                (orient-along-path reverse-arrow reversed-top-route)
                (move-along-path phase-arrow cycled-bottom-route)
                (orient-along-path phase-arrow cycled-bottom-route)
                #:duration 6))
  (scene-wait traversal 1))


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
   #:program "reversed-and-cyclic-paths.rkt"
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
