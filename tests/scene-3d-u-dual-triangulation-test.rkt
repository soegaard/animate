#lang racket/base

;;; SCENE-3D-U: dual topology survives an invalid geometric face embedding

(require rackunit
         "../3d.rkt")

(module+ test
  ;; This has the octahedron's closed orientable incidence, but its deliberately
  ;; crossed equatorial geometry gives the top/bottom dual-face cycles a
  ;; self-intersecting tangent-plane projection. A dual may still expose the
  ;; exact cycles; it must not silently fabricate fan triangles for them.
  (define crossed-octahedron
    (mesh3d #:id 'crossed-octahedron
            #:vertices (vector (vec3 0 0 2) (vec3 0 0 -2)
                               (vec3 -2 -1 0) (vec3 2 1 0)
                               (vec3 -2 1 0) (vec3 2 -1 0))
            #:triangles (vector (vector 0 2 3) (vector 0 3 4)
                                (vector 0 4 5) (vector 0 5 2)
                                (vector 1 3 2) (vector 1 4 3)
                                (vector 1 5 4) (vector 1 2 5))))
  (define complex (polyhedral-complex3d crossed-octahedron #:faces 'triangles))
  (define topology (polyhedral-complex3d-topology complex))
  (check-true (mesh-topology3d-manifold? topology))
  (check-true (mesh-topology3d-closed? topology))
  (check-true (mesh-topology3d-orientable? topology))
  (define result (combinatorial-dual3d complex))
  (define rejected
    (hash-ref (dual-polyhedron3d-result-diagnostics result) 'rejected-render-faces))
  (check-true (positive? (vector-length rejected)))
  (for ([report (in-vector rejected)])
    (check-eq? (hash-ref report 'reason) 'invalid-projected-dual-polygon)
    (define face-index (hash-ref report 'primal-vertex-index))
    (check-equal?
     (vector-length
      (dual-polyhedron-face3d-triangle-indices
       (vector-ref (dual-polyhedron3d-result-primal-vertex->dual-face result)
                   face-index)))
     0)))
