#lang racket/base

;;; SCENE-3D-N: immutable mesh topology diagnostics and explicit repair

(require rackunit
         "../3d.rkt")

(define tetra-vertices
  (vector (vec3 0 0 0)
          (vec3 1 0 0)
          (vec3 0 1 0)
          (vec3 0 0 1)))

(define outward-tetra-triangles
  (vector (vector 0 2 1)
          (vector 0 1 3)
          (vector 0 3 2)
          (vector 1 2 3)))

(define (test-mesh id vertices triangles #:edges [edges #f])
  (mesh3d #:id id #:vertices vertices #:triangles triangles #:edges edges))

(module+ test
  (define tetra (test-mesh 'tetra tetra-vertices outward-tetra-triangles))
  (define tetra-analysis (analyze-mesh3d tetra))
  (check-equal? (mesh3d-analysis-vertex-count tetra-analysis) 4)
  (check-equal? (mesh3d-analysis-triangle-count tetra-analysis) 4)
  (check-equal? (mesh3d-analysis-edge-count tetra-analysis) 6)
  (check-true (mesh3d-analysis-watertight? tetra-analysis))
  (check-true (mesh3d-analysis-orientable? tetra-analysis))
  (check-true (mesh3d-analysis-consistently-wound? tetra-analysis))
  (check-equal? (vector-length (mesh3d-analysis-boundary-edges tetra-analysis)) 0)
  (check-equal? (vector-length (mesh3d-analysis-connected-components tetra-analysis)) 1)
  (check-true (positive? (vector-ref (mesh3d-analysis-signed-component-volumes tetra-analysis) 0)))

  (define open-triangle
    (test-mesh 'open tetra-vertices (vector (vector 0 1 2))))
  (define open-analysis (mesh3d-validate open-triangle))
  (check-false (mesh3d-analysis-watertight? open-analysis))
  (check-equal? (vector-length (mesh3d-analysis-boundary-edges open-analysis)) 3)
  (check-equal? (vector-ref (mesh3d-analysis-boundary-loops open-analysis) 0)
                (vector 0 1 2 0))
  (check-equal? (mesh3d-analysis-isolated-vertices open-analysis) (vector 3))

  (define mixed
    (test-mesh 'mixed tetra-vertices
               (vector (vector 0 2 1)
                       (vector 0 1 3)
                       (vector 0 3 2)
                       (vector 1 3 2))))
  (define mixed-analysis (analyze-mesh3d mixed))
  (check-false (mesh3d-analysis-consistently-wound? mixed-analysis))
  (check-true (positive?
               (vector-length (mesh3d-analysis-inconsistent-winding-edges mixed-analysis))))
  (define-values (consistent consistent-report) (mesh3d-orient-consistently mixed))
  (check-true (mesh3d-analysis-consistently-wound?
               (mesh3d-orientation-report-final-analysis consistent-report)))
  (check-equal? (mesh3d-orientation-report-flipped-triangle-indices consistent-report)
                (vector 3))

  (define inward
    (test-mesh 'inward tetra-vertices
               (for/vector ([triangle (in-vector outward-tetra-triangles)])
                 (vector (vector-ref triangle 0)
                         (vector-ref triangle 2)
                         (vector-ref triangle 1)))))
  (define-values (outward outward-report) (mesh3d-orient-outward inward))
  (check-true (mesh3d-orientation-report-outward? outward-report))
  (check-true (positive?
               (vector-ref (mesh3d-analysis-signed-component-volumes
                            (mesh3d-orientation-report-final-analysis outward-report))
                           0)))
  (check-exn exn:fail?
             (lambda () (mesh3d-orient-outward open-triangle)))

  (define nonmanifold
    (test-mesh 'nonmanifold
               (vector (vec3 0 0 0) (vec3 1 0 0) (vec3 0 1 0)
                       (vec3 0 0 1) (vec3 0 -1 0))
               (vector (vector 0 1 2) (vector 1 0 3) (vector 0 1 4))))
  (check-equal? (vector-length
                 (mesh3d-analysis-nonmanifold-edges (analyze-mesh3d nonmanifold)))
                1)
  (check-exn exn:fail?
             (lambda () (mesh3d-orient-consistently nonmanifold)))

  (define degenerate
    (test-mesh 'degenerate
               (vector (vec3 0 0 0) (vec3 1 0 0) (vec3 2 0 0))
               (vector (vector 0 1 2))))
  (check-equal? (mesh3d-analysis-degenerate-triangles (analyze-mesh3d degenerate))
                (vector 0))

  (define duplicate
    (test-mesh 'duplicate tetra-vertices
               (vector (vector 0 1 2) (vector 1 2 0) (vector 0 2 1))))
  (define duplicates (mesh3d-analysis-duplicate-triangles (analyze-mesh3d duplicate)))
  (check-equal? (vector-length duplicates) 2)
  (check-eq? (mesh3d-duplicate-triangle-winding (vector-ref duplicates 0)) 'same)
  (check-eq? (mesh3d-duplicate-triangle-winding (vector-ref duplicates 1)) 'reversed)

  (define crossing
    (test-mesh 'crossing
               (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0)
                       (vec3 -1 1 0) (vec3 1 1 0) (vec3 0 -1 0))
               (vector (vector 0 1 2) (vector 3 4 5))))
  (check-equal? (mesh3d-self-intersection-candidates crossing) (vector (vector 0 1))))
