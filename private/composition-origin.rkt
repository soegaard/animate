#lang racket/base

;;;
;;; Deterministic composition expansion provenance
;;;

(provide (struct-out expansion-origin)
         effect-helper-id)

;; `request-path` is a stable path through the flattened local schedule. The
;; remaining indexes make delayed/mapped expansion inspectable without relying
;; on allocation order or a mutable global counter.
(struct expansion-origin
  (clip-index request-path source-index scheduled-index local-index kind)
  #:transparent)

(define (effect-helper-id effect-kind target origin local-index [explicit-id #f])
  (unless (symbol? effect-kind)
    (raise-argument-error 'effect-helper-id "symbol? as effect kind" effect-kind))
  (unless (or (not explicit-id) (symbol? explicit-id))
    (raise-argument-error 'effect-helper-id "#f or symbol? as explicit id" explicit-id))
  (unless (exact-nonnegative-integer? local-index)
    (raise-argument-error 'effect-helper-id "exact nonnegative integer" local-index))
  (or explicit-id
      (string->symbol
       (format "__~a-~s-~s-~a"
               effect-kind
               target
               origin
               local-index))))
