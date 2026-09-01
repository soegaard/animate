#lang racket/base

;;;
;;; SCENE-Z Path Orientation Rendering Tests
;;;

;; Tests rendered tangent alignment, rendered normal-offset placement, camera
;; following of offset motion, and deterministic PNG output without external
;; font or formula dependencies.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
         (only-in racket/math pi)
         rackunit
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a two-to-one frame with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "white"))

  ; elbow-route : path-geometry?
  ;;   Gives equal-length horizontal and vertical traversal edges.
  (define elbow-route
    (polyline-path
     (list origin
           (vec2 2 0)
           (vec2 2 2))))

  ; marker : rectangle-visual?
  ;;   Gives asymmetric solid geometry so a quarter-turn changes exact pixels.
  (define marker
    (rectangle #:id 'marker
               #:center origin
               #:width 1
               #:height 1/2
               #:fill "black"
               #:stroke #f
               #:stroke-width 0))

  ; bitmap->argb-bytes : bitmap% -> bytes?
  ;;   Returns exact rendered pixels for deterministic comparisons.
  (define (bitmap->argb-bytes bitmap)
    (define width
      (send bitmap get-width))
    (define height
      (send bitmap get-height))
    (define pixels
      (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  ; static-marker-bytes : vec2? finite-real? camera? -> bytes?
  ;;   Renders marker at one expected position and rotation.
  (define (static-marker-bytes position rotation camera)
    (define placed-marker
      (visual-with-rotation
       (visual-with-position marker position)
       rotation))
    (define static-scene
      (scene-wait
       (scene-add (make-scene #:camera camera)
                  placed-marker)
       1/2))
    (bitmap->argb-bytes
     (scene-frame->bitmap static-scene 0 #:fps 2)))

  ;; At three-quarter progress the route is vertical. The rendered moving
  ;; marker is exactly the equivalent statically positioned quarter-turn.
  (define oriented-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 marker)
      (move-along-path marker elbow-route)
      (orient-along-path marker elbow-route)
      #:duration 2)
     1/2))
  (check-equal?
   (bitmap->argb-bytes
    (scene-frame->bitmap oriented-motion 3 #:fps 2))
   (static-marker-bytes (vec2 2 1) (/ pi 2) test-camera))

  ;; Positive normal offset is visibly applied perpendicular to the current
  ;; traversal direction. At quarter progress the raw point is (1, 0), so the
  ;; offset marker is centered at (1, 1).
  (define offset-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 marker)
      (move-along-path marker elbow-route #:normal-offset 1)
      #:duration 2)
     1/2))
  (check-equal?
   (bitmap->argb-bytes
    (scene-frame->bitmap offset-motion 1 #:fps 2))
   (static-marker-bytes (vec2 1 1) 0 test-camera))

  ;; camera-follow tracks the offset target itself. With a camera initially
  ;; centered at the marker's offset start, all horizontal-traversal frames are
  ;; pixel-identical despite changing world positions.
  (define offset-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center (vec2 0 1)
                 #:background "white"))
  (define followed-marker
    (rectangle #:id 'followed-marker
               #:center (vec2 0 1)
               #:width 1
               #:height 1/2
               #:fill "black"
               #:stroke #f
               #:stroke-width 0))
  (define followed-offset-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera offset-camera)
                 followed-marker)
      (move-along-path followed-marker
                       (polyline-path (list origin (vec2 4 0)))
                       #:normal-offset 1)
      (camera-follow followed-marker)
      #:duration 2)
     1/2))
  (check-equal?
   (bitmap->argb-bytes
    (scene-frame->bitmap followed-offset-motion 0 #:fps 2))
   (bitmap->argb-bytes
    (scene-frame->bitmap followed-offset-motion 2 #:fps 2)))

  ; output-directory : path?
  ;;   Gives isolated storage for deterministic SCENE-Z PNG checks.
  (define output-directory
    (make-temporary-file "visual-animation-scene-z~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define paths
        (render-frames! oriented-motion
                        output-directory
                        #:fps 2))
      (define first-pass
        (for/list ([path (in-list paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! oriented-motion
                        output-directory
                        #:fps 2))
      (check-equal? first-pass
                    (for/list ([path (in-list second-paths)])
                      (file->bytes path))))
    (lambda ()
      (delete-directory/files output-directory))))
