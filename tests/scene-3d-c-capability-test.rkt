#lang racket/base

;;; SCENE-3D-C Capability Declaration Tests

(require rackunit
         "../project.rkt")

(module+ test
  (define spatial
    (renderer3d-capability-set #t #t #t #t #t #t #f #f #t))
  (define capabilities
    (renderer-capabilities #t #t #t #t #f #t #t #t spatial))
  (check-true (renderer3d-capability-set-opaque-triangles spatial))
  (check-true (renderer3d-capability-set-depth-buffer spatial))
  (check-false (renderer3d-capability-set-transparency spatial))
  (check-eq? (renderer-capabilities-three-dimensional capabilities) spatial))
