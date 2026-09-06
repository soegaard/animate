#lang racket/base

;;; SCENE-3D-O: visible, hidden, and overlay predicates use the opaque depth target

(require rackunit
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/stroke-raster3d.rkt")

(module+ test
  (define camera
    (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                           #:vertical-size 4))
  (define (coverage mode stored-depth)
    (define target (make-raster-target3d 100 80 "white"))
    ;; A uniform opaque depth is a tiny exact stand-in for a filled occluder.
    (for ([index (in-range (vector-length (raster-target3d-depth-values target)))])
      (vector-set! (raster-target3d-depth-values target) index stored-depth))
    (define style (stroke3d #:width 4 #:depth-mode mode #:cap 'butt))
    (define segments
      (prepare-stroke3d-segments '(world depth) identity-affine3
                                 (vector (vec3 -1 0 0) (vec3 1 0 0)) #f
                                 style 1 '() camera 5/4 100 80 0))
    (rasterize-prepared-strokes! target segments mode))
  ;; The centreline is eight units from the camera: it is behind depth 4 and
  ;; in front of depth 12.  `always` deliberately ignores both values.
  (check-equal? (coverage 'test 4) 0)
  (check-true (positive? (coverage 'hidden 4)))
  (check-true (positive? (coverage 'test 12)))
  (check-equal? (coverage 'hidden 12) 0)
  (check-true (positive? (coverage 'always 4))))
