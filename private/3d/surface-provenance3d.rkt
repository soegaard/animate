#lang racket/base

;;;
;;; Stable Surface Sample Provenance
;;;

(require "vec3.rkt")

(provide (struct-out dyadic-coordinate)
         (struct-out uv-key)
         (struct-out parametric-sample3d)
         (struct-out implicit-cell-provenance3d))

(struct dyadic-coordinate (numerator level) #:transparent)
(struct uv-key (u v) #:transparent)

;; Status is one of valid, non-finite, exception, degenerate-normal, or
;; excluded. Invalid samples preserve their coordinates for diagnostics.
(struct parametric-sample3d
  (uv position tangent-u tangent-v normal status diagnostic)
  #:transparent)

(struct implicit-cell-provenance3d
  (cell tetrahedron iso-value normal-source)
  #:transparent)
