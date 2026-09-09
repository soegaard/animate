#lang racket/base

;;;
;;; FX-A Mapped Staggering Render Tests
;;;

(require racket/class
         rackunit
         "../main.rkt"
         "../render.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define first
    (circle #:id 'first #:radius 1/2 #:center (vec2 -4 2) #:fill "royalblue"))
  (define second
    (rectangle #:id 'second #:width 1 #:height 1 #:center (vec2 -4 0) #:fill "seagreen"))
  (define third
    (circle #:id 'third #:radius 1/2 #:center (vec2 -4 -2) #:fill "tomato"))
  (define camera
    (make-camera #:width 320 #:height 200 #:world-width 12 #:background "white"))
  (define base (scene-add (make-scene #:camera camera) first second third))
  (define (request target source-index)
    (move-to target (vec2 (+ 2 source-index)
                          (vec2-y (visual-position target)))))
  (define mapped-scene
    (scene-play base
                (eager-stagger-map (vector first second third) request #:lag-ratio 1/2)
                #:duration 4))
  (define manual-scene
    (scene-play base
                (lagged-start (request first 0)
                              (request second 1)
                              (request third 2)
                              #:lag-ratio 1/2)
                #:duration 4))

  ;; The eager expansion renders byte-for-byte like its handwritten tree, even
  ;; when requested frame indexes are not monotonic.
  (for ([frame-index (in-list '(0 2 4 6 7 1 3 5))])
    (check-equal?
     (bitmap->argb-bytes (scene-frame->bitmap mapped-scene frame-index #:fps 2))
     (bitmap->argb-bytes (scene-frame->bitmap manual-scene frame-index #:fps 2)))))
