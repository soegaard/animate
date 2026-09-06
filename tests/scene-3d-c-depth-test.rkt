#lang racket/base

;;; SCENE-3D-C Depth and Stable-tie Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt")

(define normal (vec3 0 0 1))
(define (triangle depth color)
  (vector (raster-vertex3d (vec2 -1 -1) depth normal color #f)
          (raster-vertex3d (vec2 1 -1) depth normal color #f)
          (raster-vertex3d (vec2 0 1) depth normal color #f)))
(define red (rgb-color 255 0 0))
(define blue (rgb-color 0 0 255))
(define (unlit color) (material3d #:color color #:shading 'unlit #:double-sided? #t))
(define (pixel-rgb target)
  (define bytes (raster-target3d-color-bytes target))
  (list (bytes-ref bytes (+ (* 4 9) 1)) (bytes-ref bytes (+ (* 4 9) 2))
        (bytes-ref bytes (+ (* 4 9) 3))))

(module+ test
  (define target (make-raster-target3d 4 4 "black"))
  ;; Draw order cannot hide a nearer triangle.
  (void (raster-triangle3d! target (triangle 4 red) (unlit red) '() 0))
  (void (raster-triangle3d! target (triangle 2 blue) (unlit blue) '() 1))
  (check-equal? (pixel-rgb target) '(0 0 255))
  ;; Exact co-planar depth intentionally selects the later owner.
  (raster-target3d-clear! target "black")
  (void (raster-triangle3d! target (triangle 2 red) (unlit red) '() 4))
  (void (raster-triangle3d! target (triangle 2 blue) (unlit blue) '() 5))
  (check-equal? (pixel-rgb target) '(0 0 255)))
