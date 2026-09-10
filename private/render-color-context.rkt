#lang racket/base

;;;
;;; Explicit Render Color Context
;;;

;; An authored scene contains only color specifications.  This descriptor
;; captures the immutable theme snapshot chosen for one rendering operation;
;; renderer caches may key on its appearance fingerprint but never store mutable
;; state in the context or in the scene.

(require "color-theme.rkt"
         "color-theme-data.rkt"
         "color-style.rkt")

(provide (struct-out render-color-context)
         render-color-resolver-version
         make-render-color-context
         resolve-color-in-context
         current-render-color-context
         current-or-default-render-color-context)

;; Version 3 made palette appearance data construction-history independent.
;; Version 4 adds Animate-owned meanings for named literals such as "crimson"
;; and "indigo". A raw path Visual can retain one of those strings, so it now
;; follows Animate semantic color resolution rather than backend-name
;; passthrough. Accepted named-literal vocabulary is renderer semantics, not
;; theme appearance data; advance this version whenever that vocabulary changes
;; so persisted pixel caches cannot cross the boundary.
(define render-color-resolver-version 4)

(struct render-color-context
  (theme resolved-role-table appearance-fingerprint resolver-version)
  #:transparent)

;; make-render-color-context : color-theme? -> render-color-context?
;; Creates the immutable complete color snapshot for exactly one render pass.
(define (make-render-color-context theme)
  (unless (color-theme? theme)
    (raise-argument-error 'make-render-color-context "color-theme?" theme))
  (render-color-context theme
                        (color-theme-resolved-roles theme)
                        (color-theme-fingerprint theme)
                        render-color-resolver-version))

;; resolve-color-in-context : color-spec? render-color-context? -> rgba-color?
;; Resolves one authored color under the context-owned immutable theme.
(define (resolve-color-in-context color context)
  (unless (color-spec? color)
    (raise-argument-error 'resolve-color-in-context "color-spec?" color))
  (unless (render-color-context? context)
    (raise-argument-error 'resolve-color-in-context "render-color-context?" context))
  ;; Use the captured role table rather than recomputing it through the theme.
  ;; This makes the context a complete, self-contained render snapshot.
  (resolve-color-in-theme color
                          (render-color-context-theme context)
                          (render-color-context-resolved-role-table context)))

;; The parameter carries an explicit lexical rendering operation through Pict
;; callbacks.  It is not a mutable process-wide selected theme: entry points
;; install a fresh immutable context, and returned Picts capture it.
(define current-render-color-context (make-parameter #f))

(define (current-or-default-render-color-context)
  (or (current-render-color-context)
      (make-render-color-context animate-light-theme)))
