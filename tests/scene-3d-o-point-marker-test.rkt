#lang racket/base

(require rackunit
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/marker-raster3d.rkt")

(module+ test
  (define near-camera (perspective-camera3d #:position (vec3 0 0 8) #:look-at origin3))
  (define far-camera (perspective-camera3d #:position (vec3 0 0 16) #:look-at origin3))
  (define point-style (point-style3d #:size 10))
  (define near-point
    (prepare-point-marker3d '(world point) origin3 identity-affine3 point-style 1 '()
                            near-camera (/ 160 90) 160 90 0))
  (define far-point
    (prepare-point-marker3d '(world point) origin3 identity-affine3 point-style 1 '()
                            far-camera (/ 160 90) 160 90 0))
  (check-equal? (prepared-point-marker3d-radius near-point)
                (prepared-point-marker3d-radius far-point))
  (define arrow-style (arrow-style3d #:length 14 #:width 9))
  (define near-arrow
    (prepare-arrow-marker3d '(world arrow) (vec3 -1 0 0) (vec3 1 0 0)
                            identity-affine3 arrow-style 1 '()
                            near-camera (/ 160 90) 160 90 0))
  (define far-arrow
    (prepare-arrow-marker3d '(world arrow) (vec3 -1 0 0) (vec3 1 0 0)
                            identity-affine3 arrow-style 1 '()
                            far-camera (/ 160 90) 160 90 0))
  (check-equal? (prepared-arrow-marker3d-half-width near-arrow)
                (prepared-arrow-marker3d-half-width far-arrow))
  (check-equal? (- (prepared-arrow-marker3d-tip-x near-arrow)
                   (prepared-arrow-marker3d-base-x near-arrow))
                (- (prepared-arrow-marker3d-tip-x far-arrow)
                   (prepared-arrow-marker3d-base-x far-arrow))))
