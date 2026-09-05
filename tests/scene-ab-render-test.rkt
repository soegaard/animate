#lang racket/base

;;;
;;; SCENE-AB Path Reversal and Cyclic Start Rendering Tests
;;;

;; Tests rendering invariance of equivalent closed-path traversal order,
;; camera following over a reversed loop, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
         rackunit
         "../main.rkt"
         "../render.rkt")


(module+ test
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

  (define test-camera
    (make-camera #:width 240
                 #:height 140
                 #:world-width 12
                 #:center origin
                 #:background "white"))

  (define route
    (polygon-path
     (list (vec2 -4 -2)
           (vec2 3 -2)
           (vec2 4 1)
           (vec2 0 3)
           (vec2 -3 1))))
  (define reversed-route
    (path-geometry-reverse route))
  (define cycled-route
    (path-geometry-cycle-start route 2/7))

  ; geometry-bytes : path-geometry? -> bytes?
  ;;   Renders one filled/stroked closed route at a fixed camera.
  (define (geometry-bytes geometry)
    (define visual
      (make-path-visual geometry
                        #:id 'route
                        #:fill "lightgray"
                        #:stroke "black"
                        #:stroke-width 4))
    (bitmap->argb-bytes
     (scene-frame->bitmap
      (scene-wait
       (scene-add (make-scene #:camera test-camera) visual)
       1/2)
      0
      #:fps 2)))

  ;; Reversal and phase changes alter traversal semantics, not the visible loop.
  (check-equal? (geometry-bytes reversed-route)
                (geometry-bytes route))
  (check-equal? (geometry-bytes cycled-route)
                (geometry-bytes route))

  ;; Camera follow tracks the sampled target over reversed traversal. With only
  ;; the target visible, its frame pixels remain stable for the whole clip.
  (define start
    (path-geometry-point-at reversed-route 0))
  (define follow-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 10
                 #:center start
                 #:background "white"))
  (define rider
    (circle #:id 'rider
            #:center start
            #:radius 2/5
            #:fill "black"
            #:stroke #f
            #:stroke-width 0))
  (define followed
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera follow-camera) rider)
      (move-along-path rider reversed-route)
      (camera-follow rider)
      #:duration 3)
     1/2))
  (define stable-frame
    (bitmap->argb-bytes
     (scene-frame->bitmap followed 0 #:fps 6)))
  (for ([frame-index (in-range 1 19)])
    (check-equal?
     (bitmap->argb-bytes
      (scene-frame->bitmap followed frame-index #:fps 6))
     stable-frame))

  ; output-directory : path?
  ;;   Gives isolated storage for deterministic SCENE-AB PNG checks.
  (define output-directory
    (make-temporary-file "visual-animation-scene-ab~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define visible-route
        (make-path-visual cycled-route
                          #:id 'cycled-route
                          #:stroke "navy"
                          #:stroke-width 5))
      (define display-scene
        (scene-wait
         (scene-add (make-scene #:camera test-camera)
                    visible-route)
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
