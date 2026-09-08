#lang racket/base

;;; SCENE-3D-U4: combinatorial and polar dual polyhedra

(require rackunit
         racket/list
         "../3d.rkt")

(define cube-points
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1) (vec3 1 1 1) (vec3 -1 1 1)))

(define (cube-complex)
  (polyhedral-complex3d (convex-hull3d-result-mesh (convex-hull3d cube-points))))

(module+ test
  (define cube (cube-complex))
  (define combinatorial (combinatorial-dual3d cube))
  (define combinatorial-mesh (dual-polyhedron3d-result-mesh combinatorial))

  ;; Six cube faces become six octahedron vertices; eight cube vertices become
  ;; eight triangular dual faces. The result is itself closed and orientable.
  (check-equal? (vector-length (mesh3d-vertices combinatorial-mesh)) 6)
  (check-equal? (vector-length (mesh3d-triangles combinatorial-mesh)) 8)
  (define combinatorial-topology (mesh3d-topology combinatorial-mesh))
  (check-true (mesh-topology3d-manifold? combinatorial-topology))
  (check-true (mesh-topology3d-closed? combinatorial-topology))
  (check-true (mesh-topology3d-orientable? combinatorial-topology))
  (check-equal? (dual-polyhedron3d-result-primal-face->dual-vertex combinatorial)
                '#(0 1 2 3 4 5))
  (check-equal? (vector-length (dual-polyhedron3d-result-primal-vertex->dual-face combinatorial)) 8)
  (check-equal? (hash-ref (dual-polyhedron3d-result-diagnostics combinatorial)
                          'rejected-render-faces)
                '#())
  (for ([face (in-vector (dual-polyhedron3d-result-primal-vertex->dual-face combinatorial))])
    (check-equal? (vector-length (dual-polyhedron-face3d-triangle-indices face)) 1)
    (check-equal? (vector-length (dual-polyhedron-face3d-boundary-vertex-indices face)) 3))

  ;; The twelve mathematical cube edges receive dual-edge indexes. The six
  ;; renderer diagonals inside grouped square faces explicitly remain #f.
  (define edge-map (dual-polyhedron3d-result-primal-edge->dual-edge combinatorial))
  (check-equal? (vector-length edge-map) 18)
  (check-equal? (for/sum ([entry (in-vector edge-map)]) (if entry 1 0)) 12)
  (check-equal? (hash-ref (dual-polyhedron3d-result-diagnostics combinatorial)
                          'primal-render-diagonal-count)
                6)

  ;; The polar dual of the centred side-two cube is the unit octahedron.
  (define polar (polar-dual3d cube #:center origin3 #:scale 1))
  (define polar-mesh (dual-polyhedron3d-result-mesh polar))
  (check-equal? (vector-length (mesh3d-vertices polar-mesh)) 6)
  (check-equal? (vector-length (mesh3d-triangles polar-mesh)) 8)
  (check-equal?
   (sort (vector->list (mesh3d-vertices polar-mesh))
         (lambda (a b)
           (or (< (vec3-x a) (vec3-x b))
               (and (= (vec3-x a) (vec3-x b))
                    (or (< (vec3-y a) (vec3-y b))
                        (and (= (vec3-y a) (vec3-y b)) (< (vec3-z a) (vec3-z b))))))))
   (list (vec3 -1.0 0 0) (vec3 0 -1.0 0) (vec3 0 0 -1.0)
         (vec3 0 0 1.0) (vec3 0 1.0 0) (vec3 1.0 0 0)))
  (check-eq? (hash-ref (dual-polyhedron3d-result-diagnostics polar) 'kind) 'polar)

  ;; The centre must be strictly interior; a face point cannot be quietly
  ;; accepted as a polar centre.
  (check-exn exn:fail?
             (lambda () (polar-dual3d cube #:center (vec3 1 0 0))))

  ;; A tetrahedron is combinatorially self-dual.
  (define tetra (polyhedral-complex3d (tetrahedron3d 1 #:id 'tetra) #:faces 'triangles))
  (define tetra-dual (combinatorial-dual3d tetra))
  (check-equal? (vector-length (mesh3d-vertices (dual-polyhedron3d-result-mesh tetra-dual))) 4)
  (check-equal? (vector-length (mesh3d-triangles (dual-polyhedron3d-result-mesh tetra-dual))) 4))
