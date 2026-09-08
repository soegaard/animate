#lang racket/base

;;; SCENE-3D-U: structural topology identity is connectivity-aware

(require rackunit
         "../3d.rkt")

(define vertices
  (vector origin3 (vec3 1 0 0) (vec3 1 1 0) (vec3 0 1 0)))

(define (mesh id triangles #:transform [transform identity-transform3]
              #:vertex-ids [vertex-ids #f])
  (mesh3d #:id id #:vertices vertices #:triangles triangles
          #:transform transform #:vertex-ids vertex-ids))

(module+ test
  (define first
    (mesh 'first (vector (vector 0 1 2) (vector 0 2 3))))
  (define different-connectivity
    (mesh 'different-connectivity (vector (vector 0 1 3) (vector 1 2 3))))
  (define reordered
    (mesh 'reordered (vector (vector 0 2 3) (vector 0 1 2))))
  (define reversed-winding
    (mesh 'reversed-winding (vector (vector 0 2 1) (vector 0 3 2))))

  ;; Connectivity, face order, and winding are part of the immutable geometry
  ;; identity, so their topology skeletons cannot alias in the weak cache.
  (check-not-equal? (mesh3d-geometry-key first)
                    (mesh3d-geometry-key different-connectivity))
  (check-not-equal? (mesh3d-geometry-key first)
                    (mesh3d-geometry-key reordered))
  (check-not-equal? (mesh3d-geometry-key first)
                    (mesh3d-geometry-key reversed-winding))
  (check-not-equal? (mesh3d-topology first)
                    (mesh3d-topology different-connectivity))

  ;; Semantic labels are deliberately layered after cache lookup, so they do
  ;; not contaminate structural geometry identity but remain observable in the
  ;; returned topology.
  (define named
    (mesh 'named (mesh3d-triangles first) #:vertex-ids '#(a b c d)))
  (check-equal? (mesh3d-geometry-key first) (mesh3d-geometry-key named))
  (check-eq? (mesh-vertex-topology3d-id
              (vector-ref (mesh-topology3d-vertices (mesh3d-topology named)) 0))
             'a)

  ;; Placement is excluded from local mesh topology, but it is baked into each
  ;; polyhedral complex's analysis mesh before world-space face mathematics.
  (define translated
    (mesh 'translated (mesh3d-triangles first)
          #:transform (make-transform3 #:translation (vec3 10 0 0))))
  (check-equal? (mesh3d-geometry-key first) (mesh3d-geometry-key translated))
  (define local-complex (polyhedral-complex3d first #:faces 'triangles))
  (define translated-complex (polyhedral-complex3d translated #:faces 'triangles))
  (check-not-equal?
   (mesh3d-geometry-key (polyhedral-complex3d-analysis-mesh local-complex))
   (mesh3d-geometry-key (polyhedral-complex3d-analysis-mesh translated-complex))))
