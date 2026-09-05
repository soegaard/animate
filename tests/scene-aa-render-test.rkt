#lang racket/base

;;;
;;; SCENE-AA Joined Offset Path Rendering Tests
;;;

;; Tests distinct rendered join styles, motion along round joined geometry,
;; camera following through the joined corner, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
         rackunit
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a two-to-one frame with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center (vec2 1 -1/2)
                 #:background "white"))

  ; base-route : path-geometry?
  ;;   Gives a right-angle outside corner for positive left offsets.
  (define base-route
    (polyline-path
     (list (vec2 -3 0)
           (vec2 1 0)
           (vec2 1 -3))))
  (define miter-route
    (path-geometry-offset base-route 1 #:join 'miter))
  (define bevel-route
    (path-geometry-offset base-route 1 #:join 'bevel))
  (define round-route
    (path-geometry-offset base-route 1 #:join 'round))

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

  ; route-bytes : path-geometry? -> bytes?
  ;;   Renders one joined route as a thick black semantic path.
  (define (route-bytes geometry)
    (define route
      (make-path-visual geometry
                        #:id 'route
                        #:stroke "black"
                        #:stroke-width 6))
    (define scene
      (scene-wait
       (scene-add (make-scene #:camera test-camera) route)
       1/2))
    (bitmap->argb-bytes
     (scene-frame->bitmap scene 0 #:fps 2)))

  ;; Join policies produce visibly different outside-corner geometry.
  (define miter-bytes (route-bytes miter-route))
  (define bevel-bytes (route-bytes bevel-route))
  (define round-bytes (route-bytes round-route))
  (check-false (equal? miter-bytes bevel-bytes))
  (check-false (equal? miter-bytes round-bytes))
  (check-false (equal? bevel-bytes round-bytes))

  ;; Camera following reads the actual target sampled along the joined route.
  ;; With no route drawn and no target rotation, the rider remains byte-stable
  ;; in the frame even while traversing the cubic round connector.
  (define rider-start
    (path-geometry-point-at round-route 0))
  (define follow-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center rider-start
                 #:background "white"))
  (define rider
    (rectangle #:id 'rider
               #:center rider-start
               #:width 1
               #:height 1/2
               #:fill "black"
               #:stroke #f
               #:stroke-width 0))
  (define followed-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera follow-camera) rider)
      (move-along-path rider round-route)
      (camera-follow rider)
      #:duration 3)
     1/2))
  (define followed-start
    (bitmap->argb-bytes
     (scene-frame->bitmap followed-motion 0 #:fps 6)))
  (for ([frame-index (in-range 1 19)])
    (check-equal?
     (bitmap->argb-bytes
      (scene-frame->bitmap followed-motion frame-index #:fps 6))
     followed-start))

  ; output-directory : path?
  ;;   Gives isolated storage for deterministic SCENE-AA PNG checks.
  (define output-directory
    (make-temporary-file "visual-animation-scene-aa~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define display-route
        (make-path-visual round-route
                          #:id 'round-route
                          #:stroke "navy"
                          #:stroke-width 5))
      (define display-scene
        (scene-wait
         (scene-add (make-scene #:camera test-camera)
                    display-route)
         1))
      (define paths
        (render-frames! display-scene output-directory #:fps 3))
      (define first-pass
        (for/list ([path (in-list paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! display-scene output-directory #:fps 3))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files output-directory))))
