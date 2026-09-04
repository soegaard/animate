#lang racket/base

;;;
;;; SCENE-EE: Animated secondary cameras
;;;

;; Two live viewports observe the same world. The rounded detail view follows
;; the rover while zooming; the rectangular overview includes every world layer
;; and pans independently. A renderer-aware fit then returns the detail view to
;; the whole route.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define main-camera
  (make-camera #:width 960 #:height 540 #:world-width 14 #:background "white"))

(define (make-demo-scene)
  (define detail-camera
    (make-camera #:width 480 #:height 270
                 #:world-width 4 #:center (vec2 -3 -1)
                 #:background "ivory"))
  (define overview-camera
    (make-camera #:width 480 #:height 270
                 #:world-width 10 #:center origin
                 #:background "aliceblue"))

  ;; The terrain group is deliberately selected by the detail view, while the
  ;; overview has no #::targets argument and therefore sees all world layers.
  (define terrain-lines
    (append
     (for/list ([x (in-range -4 5)])
       (line (vec2 x -5/2) (vec2 x 3/2)
             #:id (string->symbol (format "vertical-~a" x))
             #:stroke "lightsteelblue" #:stroke-width 1))
     (for/list ([y (in-range -2 2)])
       (line (vec2 -5 y) (vec2 5 y)
             #:id (string->symbol (format "horizontal-~a" y))
             #:stroke "lightsteelblue" #:stroke-width 1))))
  (define terrain
    (group terrain-lines #:id 'terrain #:center origin))
  (define route-path
    (polyline-path (list (vec2 -3 -1)
                         (vec2 -1 1/2)
                         (vec2 1 -1/4)
                         (vec2 3 1))))
  (define route
    (make-path-visual route-path #:id 'route
                      #:fill #f #:stroke "mediumpurple" #:stroke-width 4))
  (define beacon
    (star #:id 'beacon #:center (vec2 3 1)
          #:points 5 #:outer-radius 2/5 #:inner-radius 1/6
          #:fill "gold" #:stroke "darkgoldenrod" #:stroke-width 2))
  (define rover
    (rounded-rectangle #:id 'rover #:center (vec2 -3 -1)
                       #:width 4/5 #:height 1/2 #:corner-radius 1/8
                       #:fill "tomato" #:stroke "firebrick" #:stroke-width 2))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-EE: animated secondary cameras"
                 #:id 'title #:center origin
                 #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                 #:color "navy")
     #:camera main-camera #:at (vec2 0 18/5)))
  (define explanation
    (fixed-in-frame
     (plain-text "One rounded close-up follows the rover; one overview pans across every world layer."
                 #:id 'explanation #:center origin
                 #:font-size 1/5 #:font-family 'swiss #:color "darkslategray")
     #:camera main-camera #:at (vec2 0 31/10)))
  (define detail-view
    (camera-view #:id 'detail
                 ;; Explicit targets retain this declaration order as their
                 ;; paint order, so keep it identical to the scene order.
                 #:targets '(terrain route beacon rover)
                 #:camera detail-camera
                 #:frame-camera main-camera
                 #:at (vec2 19/5 2)
                 #:width 18/5
                 #:clip 'rounded))
  (define overview-view
    (camera-view #:id 'overview
                 #:camera overview-camera
                 #:frame-camera main-camera
                 #:at (vec2 -19/5 2)
                 #:width 18/5))
  (define initial
    (scene-add (make-scene #:camera main-camera)
               terrain route beacon rover
               title explanation
               detail-view overview-view))
  ;; The fit is measured for the detailed camera's pixel aspect ratio. It is a
  ;; snapshot of the complete route and destination beacon, not an image.
  (define route-fit
    (camera-fit-visuals (list route beacon)
                        #:camera detail-camera
                        #:padding 1/2))
  (define following
    (scene-play
     (scene-wait initial 1)
     (animation-group
      (move-along-path 'rover route-path)
      (camera-view-follow 'detail 'rover)
      (camera-view-zoom-by 'detail 2)
      (camera-view-pan-to 'overview (vec2 1/2 0)))
     #:duration 3
     #:easing (smooth)))
  (define fitted
    (scene-play
     following
     (animation-group
      (camera-view-fit 'detail route-fit)
      (camera-view-zoom-by 'overview 3/2))
     #:duration 2
     #:easing (smooth)))
  (scene-wait fitted 1))

(module+ main
  (run-demo "secondary-camera-views.rkt" make-demo-scene))
