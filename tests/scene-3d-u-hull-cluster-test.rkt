#lang racket/base

;;; SCENE-3D-U: independent hull tolerances and transitive source clustering

(require rackunit
         "../3d.rkt")

(module+ test
  ;; Each adjacent pair is within 7/10, but the endpoints are 6/5 apart.
  ;; Greedy representative-only merging leaves two clusters here; hull input
  ;; normalization must instead retain the one transitive equivalence class.
  (define chained-points
    (vector origin3
            (vec3 3/5 0 0)
            (vec3 6/5 0 0)
            (vec3 0 2 0)
            (vec3 0 0 2)))
  (define chained-result
    (convex-hull3d chained-points
                   #:merge-tolerance 7/10
                   #:orientation-tolerance 0
                   #:coplanar-tolerance 0))
  (define chained-diagnostics (convex-hull3d-result-diagnostics chained-result))
  (check-equal? (convex-hull3d-result-dimension chained-result) 2)
  (check-equal? (hash-ref chained-diagnostics 'input-point-count) 5)
  (check-equal? (hash-ref chained-diagnostics 'unique-point-count) 3)
  (check-equal? (hash-ref chained-diagnostics 'duplicate-point-count) 2)
  (check-equal? (hash-ref chained-diagnostics 'merge-tolerance) 7/10)
  (check-equal? (hash-ref chained-diagnostics 'orientation-tolerance) 0)
  (check-equal? (hash-ref chained-diagnostics 'coplanar-tolerance) 0)
  (check-equal? (convex-hull3d-result-interior-indices chained-result) '#(1 2))

  ;; The three policies are independently selectable.  The point only 1e-12
  ;; off the base plane must not be swallowed by the deliberately separate
  ;; merge policy while the strict orientation policy recognizes a solid.
  (define nearly-planar
    (vector origin3
            (vec3 1.0 0.0 0.0)
            (vec3 0.0 1.0 0.0)
            (vec3 0.0 0.0 1e-12)))
  (define separate-policy-result
    (convex-hull3d nearly-planar
                   #:tolerance 1e-9
                   #:merge-tolerance 0
                   #:orientation-tolerance 1e-15
                   #:coplanar-tolerance 0))
  (define separate-policy-diagnostics
    (convex-hull3d-result-diagnostics separate-policy-result))
  (check-equal? (convex-hull3d-result-dimension separate-policy-result) 3)
  (check-equal? (hash-ref separate-policy-diagnostics 'merge-tolerance) 0)
  (check-equal? (hash-ref separate-policy-diagnostics 'orientation-tolerance) 1e-15)
  (check-equal? (hash-ref separate-policy-diagnostics 'coplanar-tolerance) 0))
