#lang racket/base

;;; SCENE-3D-H Solid Render Integration Tests

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define solid
    (revolve3d (list (vec2 0 0) (vec2 1 1) (vec2 1 0))
               #:id 'cone #:axis 'x #:segments 16 #:color "tomato"))
  (define world
    (view3d (list solid) #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 4 3 5) #:look-at (vec3 1/2 0 0))))
  (define rendered (render-view3d-opaque world 96 72))
  (check-true (positive? (software-render-diagnostics-pixel-count
                          (software-render-result-diagnostics rendered)))))
