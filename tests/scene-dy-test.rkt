#lang racket/base

;;;
;;; SCENE-DY visual clipping tests
;;;

(require racket/class
         rackunit
         "../main.rkt")

(define (pixel-rgb bitmap x y)
  (define width (send bitmap get-width))
  (define pixels (make-bytes (* 4 width (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 width (send bitmap get-height) pixels)
  (define offset (* 4 (+ x (* y width))))
  (list (bytes-ref pixels (+ offset 1))
        (bytes-ref pixels (+ offset 2))
        (bytes-ref pixels (+ offset 3))))

(module+ test
  (define camera
    (make-camera #:width 200 #:height 200 #:world-width 4 #:background "white"))
  (define content
    (rectangle #:id 'content #:center origin #:width 2 #:height 2
               #:fill "red" #:stroke #f))
  (define left-half
    (polygon-path
     (list (vec2 -1 -1) (vec2 0 -1) (vec2 0 1) (vec2 -1 1))))
  (define clipped (clip-to content left-half #:id 'crop))
  (define masked (mask-with content left-half #:id 'mask))

  (check-true (clipped-visual? clipped))
  (check-eq? (clipped-visual-content clipped) content)
  (check-equal? (clipped-visual-path clipped) left-half)
  (check-true (clipped-visual? masked))

  ;; The geometry overload remains a pure Boolean operation.
  (check-true (path-geometry? (clip-to left-half left-half)))
  (check-true (path-geometry? (mask-with left-half left-half)))

  (define static
    (scene-wait
     (scene-add (make-scene #:camera camera) clipped)
     1))
  (define static-bitmap (scene-frame->bitmap static 0 #:fps 1))
  ;; world x=-1/2 is red, while world x=+1/2 has been clipped away.
  (check-equal? (pixel-rgb static-bitmap 75 100) '(255 0 0))
  (check-equal? (pixel-rgb static-bitmap 125 100) '(255 255 255))

  ;; The wrapper itself remains an ordinary affine target. Moving it translates
  ;; content and the clipping path together, without rasterizing either.
  (define shifted
    (scene-play static (move-to 'crop (vec2 1 0)) #:duration 1))
  (define shifted-bitmap
    ;; Frame 7 at 4fps is three quarters through the second scene second.
    (scene-frame->bitmap shifted 7 #:fps 4))
  (check-equal? (pixel-rgb shifted-bitmap 75 100) '(255 255 255))
  (check-equal? (pixel-rgb shifted-bitmap 125 100) '(255 0 0)))
