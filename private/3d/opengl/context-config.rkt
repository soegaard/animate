#lang racket/base

;;;
;;; OpenGL Context Configuration
;;;

;; This module is deliberately below `animate/3d/opengl`.  The public spatial
;; model must remain usable in a headless Racket process; only an author who
;; explicitly asks for the OpenGL backend loads racket/gui/base.

(require racket/class
         racket/gui/base)

(provide make-opengl-config)

; make-opengl-config : -> gl-config%
;; Requests the baseline context used by the retained OpenGL backend.  Actual
;; realization is reported by the capability probe because window systems are
;; permitted to supply a stronger or weaker implementation than requested.
(define (make-opengl-config)
  (define config (new gl-config%))
  ;; `#f` requests the non-legacy/profile-based context on platforms where the
  ;; Racket GUI implementation can distinguish it.
  (send config set-legacy? #f)
  (send config set-depth-size 24)
  (send config set-stencil-size 8)
  (send config set-double-buffered #t)
  (send config set-multisample-size 0)
  (when (eq? (system-type) 'macosx)
    (send config set-hires-mode #t))
  config)
