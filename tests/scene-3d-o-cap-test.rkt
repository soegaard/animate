#lang racket/base

(require rackunit
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/stroke-raster3d.rkt")

(module+ test
  (define camera
    (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3 #:vertical-size 4))
  (define (pixels style points)
    (define target (make-raster-target3d 120 80 "white"))
    (define segments
      (prepare-stroke3d-segments '(world line) identity-affine3 (list->vector points) #f
                                 style 1 '() camera (/ 120 80) 120 80 0))
    (rasterize-prepared-strokes! target segments 'always))
  (check-true (positive? (pixels (stroke3d #:cap 'butt #:depth-mode 'always)
                                (list (vec3 -1 0 0) (vec3 1 0 0)))))
  (check-true (positive? (pixels (stroke3d #:cap 'square #:depth-mode 'always)
                                (list (vec3 -1 0 0) (vec3 1 0 0)))))
  (check-true (positive? (pixels (stroke3d #:cap 'round #:join 'round #:depth-mode 'always)
                                (list (vec3 -1 0 0) origin3 (vec3 0 1 0)))))
  ;; An acute miter over its limit deterministically falls back to a bevel;
  ;; both choices must be finite and rasterizable.
  (check-true (positive? (pixels (stroke3d #:join 'miter #:miter-limit 1 #:depth-mode 'always)
                                (list (vec3 -1 0 0) origin3 (vec3 1 1/20 0))))))
