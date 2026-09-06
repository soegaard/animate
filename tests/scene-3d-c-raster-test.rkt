#lang racket/base

;;; SCENE-3D-C Pixel-centre Raster Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt")

(define material (material3d #:color "white" #:shading 'unlit #:double-sided? #t))
(define normal (vec3 0 0 1))
(define white (rgb-color 255 255 255))
(define (vertex x y)
  (raster-vertex3d (vec2 x y) 1 normal white #f))

(module+ test
  (define target (make-raster-target3d 16 16 "black"))
  ;; Two triangles share a diagonal.  The top-left rule gives every pixel one
  ;; owner rather than a crack or a declaration-order-dependent double edge.
  (void (raster-triangle3d! target (vector (vertex -1 -1) (vertex 1 -1) (vertex 1 1))
                            material '() 0))
  (void (raster-triangle3d! target (vector (vertex -1 -1) (vertex 1 1) (vertex -1 1))
                            material '() 1))
  (check-true
   (for/and ([index (in-range 16 256)])
     (= (bytes-ref (raster-target3d-color-bytes target) (* 4 index)) 255)))
  (check-equal? (vector-length (raster-target3d-depth-values target)) 256))
