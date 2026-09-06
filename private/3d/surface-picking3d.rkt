#lang racket/base

;;;
;;; Surface-specific Picking Result
;;;

;; The generic picker owns ray traversal and nearest-hit selection.  This
;; small, dependency-free record is deliberately separate so surface lowering
;; can retain source data without making the core spatial picker depend on a
;; particular surface implementation.

(provide (struct-out surface-pick3d))

;; `spatial-pick` is the exact renderer-facing hit.  `parameter` is #(u v)
;; for a parametric surface or #f for an implicit surface.  `trim-boundary`
;; and `source-cell` are provenance values (or #f) rather than approximations
;; reconstructed from display pixels.
(struct surface-pick3d
  (spatial-pick surface-kind parameter trim-boundary source-cell interpolated-normal)
  #:transparent)
