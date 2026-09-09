#lang racket/base

;;;
;;; Persistent OpenGL Cache Identity
;;;

;; This small pure boundary keeps persistent-cache identity separate from the
;; retained renderer's mutable GL resources.  It is deliberately testable
;; without constructing a GUI/OpenGL context.

(provide make-opengl-live-cache-identity
         make-opengl-fallback-cache-identity)

;; make-opengl-live-cache-identity : exact-positive-integer? datum? datum?
;;                                      -> immutable-datum?
;; The implementation datum contains the driver/vendor/profile information and
;; shader datum contains immutable shader-source digests.  Resource-cache
;; capacity is intentionally absent: it affects performance, never pixels.
(define (make-opengl-live-cache-identity samples implementation shaders)
  (list 'animate-opengl-renderer3d-cache-v2
        'backend 'opengl-racket
        'samples samples
        'implementation implementation
        'shaders shaders))

;; make-opengl-fallback-cache-identity : immutable-datum? -> immutable-datum?
;; An OpenGL request that fell back must identify the renderer that actually
;; made pixels; the requested OpenGL specification alone is not meaningful.
(define (make-opengl-fallback-cache-identity fallback-identity)
  (and fallback-identity
       (list 'animate-opengl-renderer3d-cache-v2
             'backend 'software-fallback
             'delegate fallback-identity)))
