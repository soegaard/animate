#lang racket/base

;;; SCENE-3D-O: a depth-only surface occludes hidden-line classification

(require rackunit
         "../3d.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define visible (stroke3d #:width 2 #:depth-mode 'test))
  (define hidden (stroke3d #:width 1 #:dash '(3 3) #:depth-mode 'hidden))
  (define view
    (view3d
     (list
      (with-edges3d (cube3d 2 #:id 'cube #:color "aliceblue")
                    #:edges 'feature #:visible visible #:hidden hidden
                    #:surface 'depth-only))
     #:id 'world #:render-mode 'opaque #:background "white"
     #:camera (perspective-camera3d #:position (vec3 5 3 7) #:look-at origin3)))
  (define diagnostics
    (software-render-result-diagnostics (render-view3d-opaque view 160 90)))
  (check-true (positive? (software-render-diagnostics-visible-stroke-pixel-count diagnostics)))
  (check-true (positive? (software-render-diagnostics-hidden-stroke-pixel-count diagnostics)))
  ;; Depth-only surfaces rasterize depth but deliberately never contribute a
  ;; surface color sample.  The pixel counter still records that raster work.
  (check-true (positive? (software-render-diagnostics-pixel-count diagnostics))))
