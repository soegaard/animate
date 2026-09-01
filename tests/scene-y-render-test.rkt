#lang racket/base

;;;
;;; SCENE-Y Path-Following Rendering Tests
;;;

;; Tests rendered path-motion placement, sampled-state camera following, and
;; deterministic PNG output without external font or formula dependencies.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
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
  ;;   Gives equal-length horizontal and vertical motion edges.
  (define elbow-route
    (polyline-path
     (list origin
           (vec2 2 0)
           (vec2 2 2))))

  ; marker : rectangle-visual?
  ;;   Gives deterministic solid geometry whose reference point is its center.
  (define marker
    (rectangle #:id 'marker
               #:center origin
               #:width 1
               #:height 1
               #:fill "black"
               #:stroke #f
               #:stroke-width 0))

  ; bitmap->argb-bytes : bitmap% -> bytes?
  ;;   Returns exact rendered pixels for deterministic frame comparisons.
  (define (bitmap->argb-bytes bitmap)
    (define width
      (send bitmap get-width))
    (define height
      (send bitmap get-height))
    (define pixels
      (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  ; static-marker-bytes : vec2? -> bytes?
  ;;   Renders marker at one expected world position under test-camera.
  (define (static-marker-bytes position)
    (define static-scene
      (scene-wait
       (scene-add (make-scene #:camera test-camera)
                  (visual-with-position marker position))
       1/2))
    (bitmap->argb-bytes
     (scene-frame->bitmap static-scene 0 #:fps 2)))

  ;; With a static camera, the rendered middle frame is exactly the marker at
  ;; the arc-length elbow rather than the straight endpoint interpolation.
  (define static-camera-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 marker)
      (move-along-path marker elbow-route)
      #:duration 2)
     1/2))
  (check-equal? (scene-frame-count static-camera-motion #:fps 2) 5)
  (check-equal?
   (bitmap->argb-bytes
    (scene-frame->bitmap static-camera-motion 2 #:fps 2))
   (static-marker-bytes (vec2 2 0)))
  (check-false
   (bytes=?
    (bitmap->argb-bytes
     (scene-frame->bitmap static-camera-motion 0 #:fps 2))
    (bitmap->argb-bytes
     (scene-frame->bitmap static-camera-motion 2 #:fps 2))))

  ;; camera-follow consumes the sampled path position. The marker therefore
  ;; stays pixel-identical at the start, elbow, and completed endpoint.
  (define followed-motion
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 marker)
      (move-along-path marker elbow-route)
      (camera-follow marker)
      #:duration 2)
     1/2))
  (define followed-start-bytes
    (bitmap->argb-bytes
     (scene-frame->bitmap followed-motion 0 #:fps 2)))
  (define followed-elbow-bytes
    (bitmap->argb-bytes
     (scene-frame->bitmap followed-motion 2 #:fps 2)))
  (define followed-end-bytes
    (bitmap->argb-bytes
     (scene-frame->bitmap followed-motion 4 #:fps 2)))
  (check-equal? followed-start-bytes followed-elbow-bytes)
  (check-equal? followed-start-bytes followed-end-bytes)

  ; output-directory : path?
  ;;   Gives isolated storage for deterministic path-motion PNG checks.
  (define output-directory
    (make-temporary-file "visual-animation-scene-y~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define paths
        (render-frames! static-camera-motion
                        output-directory
                        #:fps 2))
      (check-equal? (length paths) 5)
      (define first-pass
        (for/list ([path (in-list paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! static-camera-motion
                        output-directory
                        #:fps 2))
      (check-equal? (length second-paths) 5)
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files output-directory))))
