#lang racket/base

;;;
;;; Animated-Write Adapter Protocol
;;;

;; Defines the small extension point used by `write-in`.  Core animation code
;; knows how to reveal semantic path and group Visuals.  Specialised Visuals
;; such as tagged TeX fragments can implement this protocol to supply an
;; equivalent path-only proxy for the animated interval, while the original
;; Visual remains the exact endpoint.

(require racket/generic)

(provide gen:write-path-source
         write-path-source?
         write-path-source->visual)

;; write-path-source->visual : write-path-source? -> visual?
;; Produces a path/group-only proxy with the same root identity as the source.
;; The proxy is sampled only during a `write-in` animation.
(define-generics write-path-source
  (write-path-source->visual write-path-source))
