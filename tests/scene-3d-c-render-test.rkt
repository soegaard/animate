#lang racket/base

;;; SCENE-3D-C Renderer Integration Tests

(require racket/class
         racket/draw
         (only-in pict pict? pict->bitmap)
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(define triangle
  (mesh3d #:id 'triangle
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))
          #:material (material3d #:color "tomato" #:shading 'flat)))
(define view
  (view3d (list triangle) #:id 'world #:width 6 #:height 4 #:render-mode 'opaque
          #:camera (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3)))

(module+ test
  (define report (render-view3d-opaque view 32 24))
  (check-true (positive? (software-render-diagnostics-pixel-count
                          (software-render-result-diagnostics report))))
  (check-equal? (raster-target3d-width (software-render-result-target report)) 32)
  (check-true (is-a? (software-render-result->bitmap report) bitmap%))
  (define scene (scene-wait (scene-add (make-scene) view) 1))
  (check-true
   (pict? (scene->pict scene 0
                        #:camera (make-camera #:width 160 #:height 90 #:world-width 10)))))
