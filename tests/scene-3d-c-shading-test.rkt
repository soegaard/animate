#lang racket/base

;;; SCENE-3D-C Flat-lighting and Normal-transform Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/3d/light3d.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/raster-triangle3d.rkt")

(define (pixel-red target)
  (bytes-ref (raster-target3d-color-bytes target) (+ (* 4 9) 1)))

(module+ test
  (define target (make-raster-target3d 4 4 "black"))
  (define triangle
    (vector (raster-vertex3d (vec2 -1 -1) 1 (vec3 0 0 1) (material3d-color (material3d #:color "red")) #f)
            (raster-vertex3d (vec2 1 -1) 1 (vec3 0 0 1) (material3d-color (material3d #:color "red")) #f)
            (raster-vertex3d (vec2 0 1) 1 (vec3 0 0 1) (material3d-color (material3d #:color "red")) #f)))
  (void (raster-triangle3d! target triangle (material3d #:color "red" #:shading 'flat)
                            (list (ambient-light3d #:intensity 1)) 0))
  (check-equal? (pixel-red target) 255)
  ;; The command path uses the inverse-transpose normal map, so nonuniform
  ;; spatial scales remain renderable instead of silently using a position map.
  (define normal-map
    (affine3-normal-transform
     (transform3->affine3 (make-transform3 #:scale (vec3 2 1 1/2)))))
  (check-true (vec3? (linear3-apply-vector normal-map (vec3 1 1 1))))
  ;; Alpha is semantic material data; SCENE-3D-I's separate transparent pass
  ;; determines how it is composited rather than rejecting it at construction.
  (check-equal?
   (rgba-color-alpha (material3d-color (material3d #:color (rgba-color 1 2 3 1/2))))
   1/2))
