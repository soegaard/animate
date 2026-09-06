#lang racket/base

(require rackunit
         racket/list
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/stroke-raster3d.rkt")

(module+ test
  (define camera
    (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3 #:vertical-size 6))
  (define dashed
    (stroke3d #:width 2 #:dash '(8 8) #:dash-space 'screen #:cap 'butt))
  (define segments
    (prepare-stroke3d-segments '(world dashed) identity-affine3
                               (vector (vec3 -2 0 0) (vec3 2 0 0)) #f
                               dashed 1 '() camera (/ 200 100) 200 100 0))
  (check-true (> (length segments) 2))
  (check-equal? (prepared-stroke-segment3d-source-start-progress (car segments)) 0)
  (check-true (<= (prepared-stroke-segment3d-source-end-progress (last segments)) 1))
  ;; A clipped world-space pattern keeps its source phase rather than treating
  ;; the clip boundary as a fresh authored dash origin.
  (define clipped
    (prepare-stroke3d-segments
     '(world clipped) identity-affine3 (vector (vec3 -2 0 0) (vec3 2 0 0)) #f
     (stroke3d #:dash '(1 1) #:dash-space 'world)
     1 (list (clip-plane3d (plane3 origin3 x-axis3) #:keep 'positive))
     camera (/ 200 100) 200 100 0))
  (check-true (pair? clipped))
  (check-true (> (prepared-stroke-segment3d-source-start-progress (car clipped)) 0)))
