#lang racket/base

;;; SCENE-3D-O: every declared join has deterministic finite coverage

(require rackunit
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/stroke-raster3d.rkt")

(module+ test
  (define camera
    (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                           #:vertical-size 4))
  (define points (vector (vec3 -1 -1 0) origin3 (vec3 1 -1/4 0)))
  (define (coverage join miter-limit)
    (define target (make-raster-target3d 120 90 "white"))
    (define style (stroke3d #:width 8 #:join join #:miter-limit miter-limit
                            #:cap 'butt #:depth-mode 'always))
    (rasterize-prepared-strokes!
     target
     (prepare-stroke3d-segments '(world join) identity-affine3 points #f
                                style 1 '() camera (/ 4 3) 120 90 0)
     'always))
  (for ([join '(miter bevel round)])
    (check-true (positive? (coverage join 8))))
  ;; An over-limit miter follows its documented deterministic bevel fallback.
  (check-equal? (coverage 'miter 1) (coverage 'bevel 8)))
