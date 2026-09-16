#lang racket/base

;;;
;;; Lazy Mathematical Example Sources
;;;
;; Exposes the restartable source callbacks without loading the parent project
;; renderer while an author inspects a mathematical lesson.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/lazy-require lazy-require))
(lazy-require ["library-example-runtime.rkt"
               ([math-render-preparer prepare-source!]
                [math-render-builder build-source!])])

;; Exports
(provide math-render-preparer math-render-builder)

; math-render-preparer : any/c immutable-hash? -> any/c
;;   Preserves the fixed parent-preparation contract while deferring native dependencies.
(define (math-render-preparer context options)
  (prepare-source! context options))

; math-render-builder : any/c immutable-hash? immutable-hash? -> any/c
;;   Preserves the fixed worker-build contract and consumes the supplied portable payload.
(define (math-render-builder context options payload)
  (build-source! context options payload))
