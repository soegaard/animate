#lang racket/base

;;;
;;; Persistent OpenGL Cache Identity
;;;

;; This small pure boundary keeps persistent-cache identity separate from the
;; retained renderer's mutable GL resources.  It is deliberately testable
;; without constructing a GUI/OpenGL context.

(provide opengl-effective-samples
         make-opengl-live-cache-identity
         make-opengl-fallback-cache-identity)

;; opengl-effective-samples : exact-positive-integer? exact-nonnegative-integer?
;;                            -> exact-positive-integer?
;; The framebuffer and persistent-cache key must agree on the MSAA count that
;; can actually affect pixels. A requested count above a driver's limit is
;; indistinguishable from that limit; zero available samples means the normal
;; one-sample framebuffer.
(define (opengl-effective-samples requested maximum)
  (unless (exact-positive-integer? requested)
    (raise-argument-error 'opengl-effective-samples "exact-positive-integer?" requested))
  (unless (exact-nonnegative-integer? maximum)
    (raise-argument-error 'opengl-effective-samples "exact-nonnegative-integer?" maximum))
  (cond [(<= requested 1) 1]
        [(<= maximum 1) 1]
        [else (min requested maximum)]))

;; make-opengl-live-cache-identity : exact-positive-integer? datum? datum?
;;                                      -> immutable-datum?
;; The implementation datum contains the driver/vendor/profile information and
;; shader datum contains immutable shader-source digests.  Resource-cache
;; capacity is intentionally absent: it affects performance, never pixels.
(define (make-opengl-live-cache-identity samples implementation shaders)
  (list 'animate-opengl-renderer3d-cache-v3
        'backend 'opengl-racket
        'samples samples
        'implementation implementation
        'shaders shaders))

;; make-opengl-fallback-cache-identity : immutable-datum? -> immutable-datum?
;; An OpenGL request that fell back must identify the renderer that actually
;; made pixels; the requested OpenGL specification alone is not meaningful.
(define (make-opengl-fallback-cache-identity fallback-identity)
  (and fallback-identity
       (list 'animate-opengl-renderer3d-cache-v3
             'backend 'software-fallback
             'delegate fallback-identity)))
