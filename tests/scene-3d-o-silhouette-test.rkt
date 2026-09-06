#lang racket/base

;;; SCENE-3D-O: camera-dependent silhouettes and transformed creases

(require rackunit
         racket/list
         "../3d.rkt"
         "../private/3d/affine3.rkt"
         "../private/3d/feature-edges3d.rkt")

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define near-x (perspective-camera3d #:position (vec3 8 2 1) #:look-at origin3))
  (define near-z (perspective-camera3d #:position (vec3 1 2 8) #:look-at origin3))
  (define silhouette-style (edge-style3d #:edges 'silhouette))
  (define x-edges
    (select-feature-edges3d cube identity-affine3 identity-linear3 near-x silhouette-style))
  (define z-edges
    (select-feature-edges3d cube identity-affine3 identity-linear3 near-z silhouette-style))
  (check-true (pair? x-edges))
  (check-true (pair? z-edges))
  ;; Classification is a prepared-frame decision: stable edge indices can
  ;; change as the camera changes, while each result remains duplicate-free.
  (for ([edges (list x-edges z-edges)])
    (check-equal? (length edges)
                  (length (remove-duplicates
                           (map prepared-feature-edge3d-edge-index edges)))))
  (define nonuniform
    (affine3 (linear3 2 0 0 0 1 0 0 0 1) origin3))
  (check-true
   (pair?
    (select-feature-edges3d cube nonuniform (linear3-normal-transform (affine3-linear nonuniform))
                            near-x (edge-style3d #:edges 'crease #:crease-angle 0)))))
