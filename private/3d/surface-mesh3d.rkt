#lang racket/base

;;;
;;; Immutable Surface Lowering Records
;;;

;; Separates renderer-ready indexed geometry from how a surface was sampled.
;; The provenance vectors align exactly with mesh vertices and triangles.

(require "mesh3d.rkt")

(provide (struct-out surface-mesh3d))

(struct surface-mesh3d
  (mesh vertex-provenance triangle-provenance topology-key diagnostics)
  #:transparent
  #:guard
  (lambda (mesh vertex-provenance triangle-provenance topology-key diagnostics who)
    (unless (mesh3d? mesh)
      (raise-argument-error who "mesh3d?" mesh))
    (unless (and (vector? vertex-provenance)
                 (= (vector-length vertex-provenance)
                    (vector-length (mesh3d-vertices mesh))))
      (raise-argument-error who "vertex provenance matching mesh vertices" vertex-provenance))
    (unless (and (vector? triangle-provenance)
                 (= (vector-length triangle-provenance)
                    (vector-length (mesh3d-triangles mesh))))
      (raise-argument-error who "triangle provenance matching mesh triangles" triangle-provenance))
    (values mesh
            (vector->immutable-vector
             (for/vector ([value (in-vector vertex-provenance)]) value))
            (vector->immutable-vector
             (for/vector ([value (in-vector triangle-provenance)]) value))
            topology-key diagnostics)))
