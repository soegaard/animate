#lang racket/base

;;; SCENE-3D-N: benchmark registry is semantic, never a timing assertion

(require rackunit
         "../tools/benchmark-3d-n.rkt")

(module+ test
  (check-equal?
   (map benchmark3d-workload-name benchmark-3d-n-workloads)
   '(static-high-surface camera-orbit moving-instance shared-geometry
     many-instances many-unique-geometries transparent-overlap clipped-surface
     geometry-cache-churn screen-strokes))
  (for ([workload (in-list benchmark-3d-n-workloads)])
    (check-true (pair? (benchmark3d-workload-views workload)))
    (check-true (positive? (benchmark3d-workload-renderer-capacity workload))))
  (define screen-result
    (for/first ([result (in-list (run-3d-n-benchmarks #:width 64 #:height 36))]
                #:when (eq? (hash-ref result 'name) 'screen-strokes))
      result))
  (check-true (hash? screen-result))
  (check-true
   (for/and ([diagnostics (in-list (hash-ref screen-result 'stroke-diagnostics))])
     (positive? (hash-ref diagnostics 'visible-stroke-pixels)))))
