#lang racket/base

;;; SCENE-3D-U: shared source/result part provenance

(require rackunit
         "../3d.rkt")

(define (entry-for-source entries source)
  (for/first ([entry (in-vector entries)]
              #:when (equal? (mesh-part-provenance-entry3d-source-part entry) source))
    entry))

(define (part-vector . parts)
  (vector->immutable-vector (list->vector parts)))

(module+ test
  ;; Two source point identities merge into one hull vertex while the interior
  ;; point is honestly discarded. The inverse query retains both sources.
  (define hull
    (convex-hull3d
     (vector origin3 origin3 (vec3 1 0 0) (vec3 0 1 0) (vec3 0 0 1)
             (vec3 1/4 1/4 1/4))))
  (define hull-provenance
    (hash-ref (convex-hull3d-result-diagnostics hull) 'part-provenance))
  (define merged-source (mesh-part-reference3d 'vertex 1))
  (define merged-results
    (mesh-part-provenance3d-source-results hull-provenance merged-source))
  (check-equal? (vector-length merged-results) 1)
  (define merged-entry
    (entry-for-source (mesh-part-provenance3d-vertices hull-provenance) merged-source))
  (check-eq? (mesh-part-provenance-entry3d-relation merged-entry) 'merged)
  (check-equal?
   (mesh-part-provenance3d-result-sources hull-provenance (vector-ref merged-results 0))
   (part-vector (mesh-part-reference3d 'vertex 0)
                (mesh-part-reference3d 'vertex 1)))
  (define discarded-entry
    (entry-for-source (mesh-part-provenance3d-vertices hull-provenance)
                      (mesh-part-reference3d 'vertex 5)))
  (check-eq? (mesh-part-provenance-entry3d-relation discarded-entry) 'discarded)
  (check-equal? (mesh-part-provenance-entry3d-result-parts discarded-entry) '#())
  (check-eq? (mesh-part-provenance-entry3d-relation
              (vector-ref (mesh-part-provenance3d-faces hull-provenance) 0))
             'generated)

  ;; A dual makes the cross-kind correspondences explicit: primal faces create
  ;; dual vertices, and primal vertices own dual polygonal faces.
  (define cube (polyhedral-complex3d (cube3d 2 #:id 'provenance-cube)))
  (define dual (combinatorial-dual3d cube))
  (define dual-provenance
    (hash-ref (dual-polyhedron3d-result-diagnostics dual) 'part-provenance))
  (check-equal?
   (mesh-part-provenance3d-source-results
    dual-provenance (mesh-part-reference3d 'face 0))
   (part-vector (mesh-part-reference3d 'vertex 0)))
  (check-equal?
   (mesh-part-provenance3d-source-results
    dual-provenance (mesh-part-reference3d 'vertex 0))
   (part-vector (mesh-part-reference3d 'face 0)))
  (check-eq? (mesh-part-provenance-entry3d-relation
              (entry-for-source (mesh-part-provenance3d-faces dual-provenance)
                                (mesh-part-reference3d 'face 0)))
             'derived)

  ;; Flattening a net splits one shared source vertex into its face-local
  ;; polygon copies, while a polygonal face keeps its source identity.
  (define net (prepare-polyhedron-net3d cube))
  (define net-provenance
    (hash-ref (polyhedron-net3d-diagnostics net) 'part-provenance))
  (define net-vertex-entry
    (entry-for-source (mesh-part-provenance3d-vertices net-provenance)
                      (mesh-part-reference3d 'vertex 0)))
  (check-eq? (mesh-part-provenance-entry3d-relation net-vertex-entry) 'split)
  (check-equal? (vector-length (mesh-part-provenance-entry3d-result-parts net-vertex-entry)) 3)
  (check-equal?
   (mesh-part-provenance3d-source-results
    net-provenance (mesh-part-reference3d 'face 0))
   (part-vector (mesh-part-reference3d 'face 0))))
