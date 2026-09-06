#lang racket/base

;;; SCENE-3D-O: arrowheads are camera-sized markers, not conical meshes

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/marker-raster3d.rkt")

(module+ test
  (define camera
    (perspective-camera3d #:position (vec3 0 0 8) #:look-at origin3))
  (define style (arrow-style3d #:length 15 #:width 10))
  (define marker
    (prepare-arrow-marker3d '(world arrow) (vec3 -1 0 0) (vec3 1 0 0)
                            identity-affine3 style 1 '() camera 16/9 320 180 3))
  (check-true (prepared-arrow-marker3d? marker))
  (check-equal? (prepared-arrow-marker3d-half-width marker) 5)
  (define compiled
    (compile-view3d
     (view3d (list (arrow3d (vec3 -1 0 0) (vec3 1 0 0) #:id 'arrow
                            #:tip-style style))
             #:id 'world #:camera camera)))
  (check-equal? (vector-length (compiled-view3d-arrow-markers compiled)) 1)
  (check-equal? (vector-length (compiled-view3d-instances compiled)) 0))
