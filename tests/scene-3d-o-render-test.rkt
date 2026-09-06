#lang racket/base

(require rackunit
         "../3d.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define view
    (view3d
     (list
      (with-edges3d
       (tetrahedron3d 2 #:id 'tetrahedron #:color "aliceblue")
       #:edges 'feature
       #:visible (stroke3d #:width 2 #:depth-mode 'test)
       #:hidden (stroke3d #:width 1 #:dash '(3 3) #:depth-mode 'hidden)
       #:surface 'visible))
     #:id 'world #:render-mode 'opaque #:background "white"
     #:camera (perspective-camera3d #:position (vec3 6 4 8) #:look-at origin3)))
  (define result (render-view3d-opaque view 160 90))
  (define diagnostics (software-render-result-diagnostics result))
  (check-true (positive? (software-render-diagnostics-stroke-command-count diagnostics)))
  (check-true (positive? (software-render-diagnostics-dash-segment-count diagnostics)))
  (check-true (positive? (software-render-diagnostics-visible-stroke-pixel-count diagnostics))))
