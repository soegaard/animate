#lang racket/base

;; The selection record is pure preview-only data. It is derived from a sampled
;; view and does not append any geometry to the view's immutable child list.
(require rackunit
         "../3d.rkt")

(module+ test
  (define view
    (view3d (list (point3d origin3 #:id 'dot #:radius 1/2))
            #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4) #:look-at origin3)))
  (define before (view3d-children view))
  (define pick (view3d-pixel-pick view 80 80 #:width 160 #:height 160))
  (check-true (spatial-pick? pick))
  (check-equal? (view3d-children view) before)
  (check-equal? (spatial-pick-path pick) '(world dot)))
