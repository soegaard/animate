#lang racket/base

;;; SCENE-3D-U1: deterministic navigable triangle topology

(require rackunit
         "../3d.rkt")

(define (triangle-mesh id #:extra-vertex? [extra-vertex? #f])
  (mesh3d #:id id
          #:vertices (if extra-vertex?
                         (vector origin3 (vec3 1 0 0) (vec3 0 1 0) (vec3 4 4 4))
                         (vector origin3 (vec3 1 0 0) (vec3 0 1 0)))
          #:triangles (vector (vector 0 1 2))))

(define annulus
  (mesh3d #:id 'annulus
          #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 2 2 0) (vec3 -2 2 0)
                            (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 1 1 0) (vec3 -1 1 0))
          #:triangles (vector (vector 0 1 5) (vector 0 5 4)
                              (vector 1 2 6) (vector 1 6 5)
                              (vector 2 3 7) (vector 2 7 6)
                              (vector 3 0 4) (vector 3 4 7))))

;; Three rectangular bands with the final identification reversed are a
;; triangulated Möbius strip. Its edge-incidence parity has no global solution.
(define mobius
  (mesh3d #:id 'mobius
          #:vertices (vector (vec3 0 0 0) (vec3 0 1 0)
                            (vec3 1 0 0) (vec3 1 1 0)
                            (vec3 2 0 0) (vec3 2 1 0))
          #:triangles (vector (vector 0 2 3) (vector 0 3 1)
                              (vector 2 4 5) (vector 2 5 3)
                              (vector 4 1 0) (vector 4 0 5))))

(module+ test
  (define tetra (tetrahedron3d 1 #:id 'tetra))
  (define tetra-topology (mesh3d-topology tetra))
  (check-equal? (vector-length (mesh-topology3d-vertices tetra-topology)) 4)
  (check-equal? (vector-length (mesh-topology3d-edges tetra-topology)) 6)
  (check-equal? (vector-length (mesh-topology3d-triangles tetra-topology)) 4)
  (check-equal? (vector-length (mesh-topology3d-halfedges tetra-topology)) 12)
  (check-equal? (mesh3d-euler-characteristic tetra-topology) 2)
  (check-equal? (mesh3d-boundary-count tetra-topology) 0)
  (check-true (mesh-topology3d-manifold? tetra-topology))
  (check-true (mesh-topology3d-closed? tetra-topology))
  (check-true (mesh-topology3d-orientable? tetra-topology))
  (check-equal? (mesh-topology3d-vertex-neighbours tetra-topology 0) '#(1 2 3))
  (check-equal? (mesh-topology3d-incident-edges tetra-topology 0) '#(0 2 3))
  (check-equal? (mesh-topology3d-incident-faces tetra-topology 0) '#(0 1 2))
  (check-equal? (mesh-topology3d-face-neighbours tetra-topology 0) '#(1 3 2))
  (for ([halfedge (in-vector (mesh-topology3d-halfedges tetra-topology))])
    (check-true (exact-nonnegative-integer? (mesh-halfedge3d-opposite halfedge))))
  (define tetra-genus (mesh3d-genus tetra-topology))
  (check-true (mesh3d-genus-report-valid? tetra-genus))
  (check-equal? (mesh3d-component-invariants3d-genus
                 (vector-ref (mesh3d-genus-report-components tetra-genus) 0))
                0)

  ;; Repeated construction returns equal source-index topology. A semantically
  ;; named equal mesh shares only the structural cache and receives its own IDs.
  (check-equal? tetra-topology (mesh3d-topology tetra))
  (define named-tetra
    (mesh3d #:id 'named-tetra
            #:vertices (mesh3d-vertices tetra) #:triangles (mesh3d-triangles tetra)
            #:vertex-ids '#(v0 v1 v2 v3)
            #:edge-ids '#(e0 e1 e2 e3 e4 e5)
            #:face-ids '#(f0 f1 f2 f3)))
  (define named-topology (mesh3d-topology named-tetra))
  (check-eq? (mesh-vertex-topology3d-id
              (vector-ref (mesh-topology3d-vertices named-topology) 0))
             'v0)
  (check-eq? (mesh-triangle-topology3d-id
              (vector-ref (mesh-topology3d-triangles named-topology) 2))
             'f2)
  (check-not-equal? named-topology tetra-topology)

  (define cube-topology (mesh3d-topology (cube3d 2 #:id 'cube)))
  (check-equal? (mesh3d-euler-characteristic cube-topology) 2)
  (check-equal? (mesh3d-boundary-count cube-topology) 0)
  (check-true (mesh-topology3d-closed? cube-topology))

  (define torus-topology
    (mesh3d-topology (torus3d 3 1 #:id 'torus #:major-segments 6 #:minor-segments 5)))
  (check-equal? (mesh3d-euler-characteristic torus-topology) 0)
  (check-equal? (mesh3d-boundary-count torus-topology) 0)
  (check-equal? (mesh3d-component-invariants3d-genus
                 (vector-ref (mesh3d-genus-report-components (mesh3d-genus torus-topology)) 0))
                1)

  (define annulus-topology (mesh3d-topology annulus))
  (check-equal? (mesh3d-euler-characteristic annulus-topology) 0)
  (check-equal? (mesh3d-boundary-count annulus-topology) 2)
  (check-equal? (mesh3d-component-invariants3d-genus
                 (vector-ref (mesh3d-genus-report-components (mesh3d-genus annulus-topology)) 0))
                0)
  (check-true (for/and ([boundary (in-vector (mesh-topology3d-boundaries annulus-topology))])
                (mesh-boundary-component3d-closed? boundary)))

  (define disconnected
    (mesh3d-merge (list (triangle-mesh 'a) (triangle-mesh 'b)) #:id 'two-triangles))
  (define disconnected-topology (mesh3d-topology disconnected))
  (check-equal? (vector-length (mesh-topology3d-connected-components disconnected-topology)) 2)
  (check-equal? (mesh3d-euler-characteristic disconnected-topology) 2)

  (define isolated-topology (mesh3d-topology (triangle-mesh 'isolated #:extra-vertex? #t)))
  (check-equal? (vector-length (mesh-topology3d-connected-components isolated-topology)) 2)
  (check-equal? (mesh3d-euler-characteristic isolated-topology) 2)

  (define nonmanifold
    (mesh3d #:id 'nonmanifold
            #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0)
                              (vec3 0 0 1) (vec3 0 -1 0))
            #:triangles (vector (vector 0 1 2) (vector 1 0 3) (vector 0 1 4))))
  (define nonmanifold-topology (mesh3d-topology nonmanifold))
  (check-false (mesh-topology3d-manifold? nonmanifold-topology))
  (define nonmanifold-edge
    (vector-ref (mesh-topology3d-edges nonmanifold-topology) 0))
  (check-true (mesh-edge-topology3d-nonmanifold? nonmanifold-edge))
  (check-equal? (vector-length (mesh-edge-topology3d-halfedges nonmanifold-edge)) 3)
  (check-true (vector? (mesh-halfedge3d-opposite
                        (vector-ref (mesh-topology3d-halfedges nonmanifold-topology) 0))))
  (check-false (mesh3d-genus-report-valid? (mesh3d-genus nonmanifold-topology)))

  (define mobius-topology (mesh3d-topology mobius))
  (check-false (mesh-topology3d-orientable? mobius-topology))
  (check-false (mesh3d-genus-report-valid? (mesh3d-genus mobius-topology))))
