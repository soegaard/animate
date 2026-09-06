#lang racket/base

(require rackunit
         "../3d.rkt"
         "../private/3d/edge-adjacency3d.rkt"
         "../private/3d/feature-edges3d.rkt")

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define camera (perspective-camera3d #:position (vec3 6 4 8) #:look-at origin3))
  (define all
    (select-feature-edges3d cube identity-affine3 identity-linear3 camera
                            (edge-style3d #:edges 'all)))
  (define feature
    (select-feature-edges3d cube identity-affine3 identity-linear3 camera
                            (edge-style3d #:edges 'feature)))
  (check-equal? (length all) (vector-length (mesh3d-edge-adjacency cube)))
  (check-true (pair? feature))
  (check-equal?
   (select-feature-edges3d cube identity-affine3 identity-linear3 camera
                           (edge-style3d #:edges 'boundary))
   '())
  (define wrapped
    (with-edges3d cube #:edges 'silhouette #:surface 'depth-only))
  (check-eq? (spatial-id wrapped) 'cube)
  (check-equal? (edge-style3d-surface (edge-overlay3d-style wrapped)) 'depth-only))
