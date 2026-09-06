#lang racket/base

;;;
;;; Effectful 3D Renderer Backends
;;;

;; `animate/3d` remains the pure spatial model.  This separate module exposes
;; renderer instances, retained cache controls, and bitmap conversion for
;; applications that deliberately choose an implementation backend.

(require "../private/3d/renderer3d.rkt")

(provide gen:renderer3d
         renderer3d?
         renderer3d-id
         renderer3d-capabilities
         renderer3d-fingerprint
         renderer3d-prepare
         renderer3d-render
         renderer3d-release
         (struct-out renderer3d-capability-set)
         (struct-out render3d-request)
         (struct-out renderer3d-render-result)
         renderer3d-render-result->bitmap
         software-renderer3d
         software-renderer3d?
         retained-software-renderer3d
         retained-software-renderer3d?
         retained-software-renderer3d-cache-hits
         retained-software-renderer3d-cache-misses
         retained-software-renderer3d-cache-size
         default-software-renderer3d
         current-view3d-renderer3d)
