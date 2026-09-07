#lang racket/base

;;; SCENE-3D-U3: deterministic, provenance-preserving convex hulls

(require rackunit
         racket/list
         "../3d.rkt")

(define tetra-points
  (vector origin3 (vec3 2 0 0) (vec3 0 2 0) (vec3 0 0 2) (vec3 1/4 1/4 1/4)))

(define cube-points
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)
          origin3))

(define (signed-volume first second third fourth)
  (vec3-dot (vec3-cross (vec3- second first) (vec3- third first))
            (vec3- fourth first)))

(define (mesh-centroid mesh)
  (define vertices (vector->list (mesh3d-vertices mesh)))
  (vec3-scale (/ 1 (length vertices))
              (for/fold ([sum origin3]) ([point (in-list vertices)]) (vec3+ sum point))))

(module+ test
  ;; A tetrahedron retains its four source corners and classifies the interior
  ;; input point truthfully. The triangle mesh is a closed orientable surface.
  (define tetra-result (convex-hull3d tetra-points))
  (define tetra-mesh (convex-hull3d-result-mesh tetra-result))
  (check-equal? (convex-hull3d-result-dimension tetra-result) 3)
  (check-equal? (vector-length (mesh3d-vertices tetra-mesh)) 4)
  (check-equal? (vector-length (mesh3d-triangles tetra-mesh)) 4)
  (check-equal? (convex-hull3d-result-source-point-indices tetra-result) '#(0 3 2 1))
  (check-equal? (convex-hull3d-result-interior-indices tetra-result) '#(4))
  (define tetra-topology (mesh3d-topology tetra-mesh))
  (check-true (mesh-topology3d-manifold? tetra-topology))
  (check-true (mesh-topology3d-closed? tetra-topology))
  (check-true (mesh-topology3d-orientable? tetra-topology))

  ;; Every output face points away from its own hull centroid, and every input
  ;; point is inside or on every oriented hull half-space.
  (define tetra-centre (mesh-centroid tetra-mesh))
  (for ([triangle (in-vector (mesh3d-triangles tetra-mesh))])
    (define vertices (mesh3d-vertices tetra-mesh))
    (define first (vector-ref vertices (vector-ref triangle 0)))
    (define second (vector-ref vertices (vector-ref triangle 1)))
    (define third (vector-ref vertices (vector-ref triangle 2)))
    (check-true (negative? (signed-volume first second third tetra-centre)))
    (for ([point (in-vector tetra-points)])
      (check-true (<= (signed-volume first second third point) 0))) )

  ;; The shuffled cube produces a canonical coordinate/triangle mesh and six
  ;; merged coplanar supporting faces; its centre is the only interior source.
  (define cube-result (convex-hull3d cube-points))
  (define cube-mesh (convex-hull3d-result-mesh cube-result))
  (check-equal? (convex-hull3d-result-dimension cube-result) 3)
  (check-equal? (vector-length (mesh3d-vertices cube-mesh)) 8)
  (check-equal? (vector-length (mesh3d-triangles cube-mesh)) 12)
  (check-equal? (convex-hull3d-result-interior-indices cube-result) '#(8))
  (check-equal? (vector-length (convex-hull3d-result-coplanar-groups cube-result)) 6)
  (for ([group (in-vector (convex-hull3d-result-coplanar-groups cube-result))])
    (check-equal? (vector-length (convex-hull3d-coplanar-group3d-triangle-indices group)) 2)
    (check-equal? (vector-length (convex-hull3d-coplanar-group3d-boundary-vertex-indices group)) 4))
  (define shuffled-result
    (convex-hull3d
     (vector (vector-ref cube-points 6) (vector-ref cube-points 0) (vector-ref cube-points 8)
             (vector-ref cube-points 4) (vector-ref cube-points 1) (vector-ref cube-points 7)
             (vector-ref cube-points 3) (vector-ref cube-points 5) (vector-ref cube-points 2))))
  (check-equal? (mesh3d-vertices cube-mesh)
                (mesh3d-vertices (convex-hull3d-result-mesh shuffled-result)))
  (check-equal? (mesh3d-triangles cube-mesh)
                (mesh3d-triangles (convex-hull3d-result-mesh shuffled-result)))

  ;; Exact duplicate inputs retain one canonical mesh vertex and report the
  ;; duplicate source index as interior provenance.
  (define duplicate-result
    (convex-hull3d (vector origin3 origin3 (vec3 1 0 0) (vec3 0 1 0) (vec3 0 0 1))))
  (check-equal? (convex-hull3d-result-dimension duplicate-result) 3)
  (check-equal? (convex-hull3d-result-interior-indices duplicate-result) '#(1))
  (check-equal? (hash-ref (convex-hull3d-result-diagnostics duplicate-result)
                          'duplicate-point-count)
                1)

  ;; No small fake tetrahedron is created for a planar square or a collinear
  ;; set. Their returned meshes are a planar fan and a segment respectively.
  (define square-result
    (convex-hull3d (vector origin3 (vec3 2 0 0) (vec3 2 2 0) (vec3 0 2 0)
                            (vec3 1 1 0))))
  (check-equal? (convex-hull3d-result-dimension square-result) 2)
  (check-equal? (vector-length (mesh3d-vertices (convex-hull3d-result-mesh square-result))) 4)
  (check-equal? (vector-length (mesh3d-triangles (convex-hull3d-result-mesh square-result))) 2)
  (check-equal? (convex-hull3d-result-interior-indices square-result) '#(4))
  (define line-result (convex-hull3d (vector (vec3 2 0 0) origin3 (vec3 1 0 0))))
  (check-equal? (convex-hull3d-result-dimension line-result) 1)
  (check-equal? (mesh3d-edges (convex-hull3d-result-mesh line-result)) '#(#(0 1)))
  (check-exn exn:fail?
             (lambda () (convex-hull3d (vector origin3 (vec3 1 0 0))
                                        #:on-degenerate 'error)))

  ;; An inexact fourth point can be classified either as planar or solid under
  ;; the author's declared tolerance, with that policy retained in diagnostics.
  (define nearly-planar
    (vector origin3 (vec3 1.0 0.0 0.0) (vec3 0.0 1.0 0.0) (vec3 0.0 0.0 1e-12)))
  (check-equal? (convex-hull3d-result-dimension
                 (convex-hull3d nearly-planar #:tolerance 1e-9))
                2)
  (check-equal? (convex-hull3d-result-dimension
                 (convex-hull3d nearly-planar #:tolerance 1e-15))
                3)
  (define triangulated-cube (convex-hull3d cube-points #:coplanar 'triangulate))
  (check-equal? (convex-hull3d-result-coplanar-groups triangulated-cube) '#()))
