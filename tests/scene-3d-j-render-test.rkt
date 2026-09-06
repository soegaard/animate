#lang racket/base

(require rackunit
         "../3d.rkt"
         "../private/3d/affine-map3d-visual.rkt"
         "../private/3d/software-render-diagnostics.rkt"
         "../private/3d/software-renderer3d.rkt")

(module+ test
  (define diagram
    (affine-map3d
     (linear-transformation-diagram3d #:id 'diagram)
     (affine3 (linear3 1 0 1 0 1 0 0 0 1) origin3)))
  (define world
    (view3d (list diagram) #:id 'world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 5 4 7)
                                           #:look-at (vec3 1/2 1/2 1/2))))
  (define rendered (render-view3d-opaque world 128 96))
  (check-true (positive? (software-render-diagnostics-pixel-count
                          (software-render-result-diagnostics rendered))))

  ;; Singular affine maps are semantic operations too. They can collapse
  ;; triangles, but must not fail while the renderer tries to invert a normal
  ;; transform that does not exist.
  (define collapsed
    (affine-map3d
     (box3d 1 1 1 #:id 'collapsed)
     (affine3 (linear3 1 0 0 0 1 0 0 0 0) origin3)))
  (define collapsed-world
    (view3d (list collapsed) #:id 'collapsed-world #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 3 3 6)
                                           #:look-at origin3)))
  (check-not-exn
   (lambda () (render-view3d-opaque collapsed-world 128 96))))
