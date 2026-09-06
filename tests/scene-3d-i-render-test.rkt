#lang racket/base

;;; SCENE-3D-I Render Integration Test

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define sphere
    (sphere3d 3/2 #:id 'sphere
              #:material (material3d #:color (rgba-color 65 150 255 1/2)
                                     #:shading 'smooth #:double-sided? #t)))
  (define cut (clip3d sphere (plane3 origin3 x-axis3) #:id 'half-sphere))
  (define section (section-curve3d sphere (plane3 origin3 x-axis3) #:id 'section
                                   #:style (tube-style3d #:color "gold" #:radius 1/30)))
  (define world
    (view3d (list cut section) #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 4 3 5)
                                           #:look-at origin3)))
  (define rendered (render-view3d-opaque world 96 72))
  (check-true (positive? (software-render-diagnostics-pixel-count
                          (software-render-result-diagnostics rendered)))))
