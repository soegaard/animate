#lang racket/base

;;;
;;; Effectful 3D Renderer Backends
;;;

;; `animate/3d` remains the pure spatial model.  This separate module exposes
;; renderer instances, retained cache controls, and bitmap conversion for
;; applications that deliberately choose an implementation backend.

(require "../private/3d/compiled-view3d.rkt"
         "../private/3d/geometry-fingerprint3d.rkt"
         "../private/3d/renderer3d.rkt")

(provide gen:renderer3d
         renderer3d?
         renderer3d-id
         renderer3d-capabilities
         renderer3d-fingerprint
         renderer3d-prepare
         renderer3d-render
         renderer3d-release
         (struct-out geometry-key3d)
         (struct-out compiled-geometry3d)
         (struct-out compiled-instance3d)
         (struct-out compiled-stroke3d)
         (struct-out compiled-point-marker3d)
         (struct-out compiled-arrow-marker3d)
         (struct-out compiled-edge-overlay3d)
         (struct-out compiled-view3d)
         (struct-out frame3d-spec)
         compile-view3d
         compiled-view3d-primitives
         view3d->frame3d-spec
         (struct-out renderer3d-capability-set)
         (struct-out render3d-request)
         view3d->render3d-request
         (struct-out renderer3d-render-result)
         renderer3d-render-result->bitmap
         (struct-out renderer3d-statistics)
         renderer3d-statistics-reset!
         renderer3d-statistics-snapshot
         software-renderer3d
         software-renderer3d?
         retained-software-renderer3d
         retained-software-renderer3d?
         retained-software-renderer3d-cache-hits
         retained-software-renderer3d-cache-misses
         retained-software-renderer3d-cache-size
         default-software-renderer3d
         current-view3d-renderer3d)
