#lang racket/base

;;;
;;; SCENE-3D-U Polyhedral Fold/Unfold Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define cube-points
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))

(define complex
  (polyhedral-complex3d (convex-hull3d-result-mesh (convex-hull3d cube-points))))
(define prepared-net (prepare-polyhedron-net3d complex))
(define face-ids (polyhedron-net3d-face-child-ids prepared-net))
(define source-scene
  (scene-add
   (make-scene)
   (view3d (list (polyhedron-net3d-group complex prepared-net #:id 'net))
           #:id 'world)))

(define (face-at scene time face-id)
  (view3d-spatial-ref
   (scene-state-ref (scene-sample scene time) 'world)
   `(world net ,face-id)))

(define (check-vec3-close? actual expected [epsilon 1e-8])
  (check-= (vec3-x actual) (vec3-x expected) epsilon)
  (check-= (vec3-y actual) (vec3-y expected) epsilon)
  (check-= (vec3-z actual) (vec3-z expected) epsilon))

(module+ test
  ;; The public group exposes the six mathematical faces as stable direct
  ;; children, rather than twelve implementation triangles.
  (check-equal? (vector-length face-ids) 6)
  (for ([face-id (in-vector face-ids)])
    (check-true (mesh3d? (face-at source-scene 0 face-id))))

  (define unfolded
    (scene-play source-scene
                (unfold-polyhedron3d '(world net) prepared-net)
                #:duration 1))
  (define flat-transforms (polyhedron-net3d-sample-transforms prepared-net 1))

  ;; Exact clip endpoints use the captured source/final transforms.
  (for ([face-id (in-vector face-ids)] [flat (in-vector flat-transforms)])
    (check-equal? (spatial-transform (face-at unfolded 0 face-id))
                  identity-transform3)
    (check-equal? (spatial-transform (face-at unfolded 1 face-id)) flat))

  ;; At a middle frame, both endpoints of each hinge coincide.  This would not
  ;; hold for independent translation/matrix interpolation of the face meshes.
  (for ([hinge (in-vector (polyhedron-net3d-hinge-tree prepared-net))])
    (define child-index (net-hinge3d-child hinge))
    (define parent-index (net-hinge3d-parent hinge))
    (define child-frame
      (vector-ref (polyhedron-net3d-face-transforms prepared-net) child-index))
    (define first (net-face-transform3d-source-origin child-frame))
    (define second
      (vec3+ first (net-face-transform3d-source-e child-frame)))
    (define parent-transform
      (spatial-transform (face-at unfolded 1/2 (vector-ref face-ids parent-index))))
    (define child-transform
      (spatial-transform (face-at unfolded 1/2 (vector-ref face-ids child-index))))
    (check-vec3-close? (transform3-apply-point parent-transform first)
                       (transform3-apply-point child-transform first))
    (check-vec3-close? (transform3-apply-point parent-transform second)
                       (transform3-apply-point child-transform second)))

  ;; Folding starts at the exact net endpoint and recovers the exact source
  ;; transforms.  Sampling the middle frame directly is deterministic.
  (define refolded
    (scene-play unfolded
                (fold-polyhedron3d '(world net) prepared-net)
                #:duration 1))
  (for ([face-id (in-vector face-ids)])
    (check-equal? (spatial-transform (face-at refolded 2 face-id))
                  identity-transform3)
    (check-equal? (spatial-transform (face-at refolded 3/2 face-id))
                  (spatial-transform (face-at unfolded 1/2 face-id)))))
