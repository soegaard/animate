#lang racket/base

;; The GUI layer consumes the public immutable records; this headless smoke
;; gate ensures they can be required through animate/3d without gui-lib.
(require rackunit
         "../3d.rkt")

(module+ test
  (check-true (procedure? view3d-spatial-inspections))
  (check-true (procedure? view3d-pixel-pick))
  (check-true (procedure? view3d-pick)))
