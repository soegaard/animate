#lang racket/base

;;; SCENE-3D-P: the portable half of the dual-backend benchmark contract

(require rackunit
         "../3d/render.rkt"
         "../tools/benchmark-3d.rkt")

(module+ test
  ;; Software is intentionally the default and must exercise the benchmark
  ;; without loading the optional GUI/OpenGL backend.
  (define report
    (run-3d-benchmarks #:width 48 #:height 27 #:warm-up 0))
  (check-eq? (hash-ref report 'stage) 'SCENE-3D-P)
  (check-eq? (hash-ref report 'renderer) 'retained-software-reference)
  (check-equal? (length (hash-ref report 'workloads))
                (length benchmark-3d-workloads))
  (for ([workload (in-list (hash-ref report 'workloads))])
    (check-true (symbol? (hash-ref workload 'name)))
    (check-true (positive? (hash-ref workload 'frame-count)))
    (check-equal? (length (hash-ref workload 'frame-milliseconds))
                  (hash-ref workload 'frame-count))
    (check-true (renderer3d-statistics? (hash-ref workload 'statistics)))))
