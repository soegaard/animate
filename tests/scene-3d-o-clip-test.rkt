#lang racket/base

;;; SCENE-3D-O: stroke clipping keeps authored identity and finite geometry

(require rackunit
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/stroke-raster3d.rkt")

(module+ test
  (define camera
    (perspective-camera3d #:position (vec3 0 0 4) #:look-at origin3
                          #:near 1 #:far 12))
  ;; The first endpoint is between the camera and its near plane.  The
  ;; surviving portion must retain its original source progress rather than
  ;; becoming a new segment beginning at zero.
  (define near-clipped
    (prepare-stroke3d-segments
     '(world near) identity-affine3
     (vector (vec3 -1 0 7/2) (vec3 1 0 -2)) #f
     (stroke3d #:width 3 #:cap 'round) 1 '() camera 1 160 90 0))
  (check-true (pair? near-clipped))
  (check-true (> (prepared-stroke-segment3d-source-start-progress
                  (car near-clipped))
                 0))
  (check-true
   (for/and ([segment (in-list near-clipped)])
     (and (real? (prepared-stroke-segment3d-start-x segment))
          (real? (prepared-stroke-segment3d-end-x segment))
          (positive? (prepared-stroke-segment3d-start-depth segment))
          (positive? (prepared-stroke-segment3d-end-depth segment)))))
  ;; A centreline just outside a side plane remains eligible: raster bounds,
  ;; not a pre-projection side-plane test, decide whether its width is visible.
  (check-true
   (pair?
    (prepare-stroke3d-segments
     '(world side) identity-affine3
     (vector (vec3 5/2 0 0) (vec3 5/2 1 0)) #f
     (stroke3d #:width 12 #:cap 'round) 1 '() camera 1 160 90 1))))
