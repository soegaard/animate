#lang racket/base

;;; SCENE-3D-G Surface Renderer Integration Tests

(require rackunit
         "../3d.rkt"
         "../private/3d/raster-target3d.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define saddle
    (surface-color-by-height
     (function-surface3d (lambda (x y) (- (* x x) (* y y)))
                         #:x-range (list -1 1) #:y-range (list -1 1)
                         #:resolution (list 9 9) #:id 'saddle
                         #:material (material3d #:color "steelblue" #:shading 'smooth
                                                #:double-sided? #t))
     #:low "midnightblue" #:high "gold"))
  (define world
    (view3d (list saddle) #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 3 3 5) #:look-at origin3)))
  (define rendered (render-view3d-opaque world 64 48))
  (check-true (positive? (software-render-diagnostics-pixel-count
                          (software-render-result-diagnostics rendered))))
  (check-equal? (raster-target3d-width (software-render-result-target rendered)) 64))
