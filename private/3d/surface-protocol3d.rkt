#lang racket/base

;;;
;;; Common Immutable Surface Protocol
;;;

;; This focused re-export marks the renderer-facing surface protocol. Regular,
;; adaptive, trimmed, and implicit surface constructors live in separate
;; modules but share these queries and the same surface-mesh lowering value.

(require "parametric-surface3d.rkt"
         "surface-mesh3d.rkt")

(provide gen:surface3d
         surface3d?
         surface3d-kind
         surface3d-mesh
         surface3d-material
         surface3d-with-material
         surface3d-local-mesh
         surface3d-local-bounds
         surface3d-diagnostics
         surface3d-provenance
         surface3d-domain
         surface3d-evaluate
         surface3d-frame-at
         surface3d->mesh3d
         (struct-out surface-domain3d)
         (struct-out surface-diagnostics3d)
         (struct-out surface-frame3d)
         (struct-out surface-mesh3d))
