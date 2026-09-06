#lang racket/base

;;; SCENE-3D-C Winding and Double-sided Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt")

(define normal (vec3 0 0 1))
(define color (rgb-color 255 255 255))
(define (vertex x y) (raster-vertex3d (vec2 x y) 1 normal color #f))
(define ccw (vector (vertex -1 -1) (vertex 1 -1) (vertex 0 1)))
(define cw (vector (vertex -1 -1) (vertex 0 1) (vertex 1 -1)))

(module+ test
  (define target (make-raster-target3d 8 8 "black"))
  (define one-sided (material3d #:color "white" #:shading 'unlit))
  (check-true (positive? (raster-triangle3d! target ccw one-sided '() 0)))
  (raster-target3d-clear! target "black")
  (check-equal? (raster-triangle3d! target cw one-sided '() 0) 0)
  (define two-sided (material3d #:color "white" #:shading 'unlit #:double-sided? #t))
  (check-true (positive? (raster-triangle3d! target cw two-sided '() 0))))
