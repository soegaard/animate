#lang racket/base

;;;
;;; Serializable Relation Specifications
;;;

;; A relation specification is transparent immutable data interpreted by a
;; library-owned resolver.  In contrast to an arbitrary relation lambda, it
;; can safely contribute to a persistent cache identity and can be displayed by
;; inspection tools without inventing a fake procedure fingerprint.

(require racket/generic)

(provide gen:relation-spec
         relation-spec?
         resolve-relation-spec)

;; resolve-relation-spec : relation-spec? relation-context? visual? -> visual?
;; `context` intentionally remains abstract here to avoid a dependency cycle:
;; individual built-in specification modules import the relation-context API
;; they need, while relation-visual merely dispatches the opaque value.
(define-generics relation-spec
  (resolve-relation-spec relation-spec context template))
