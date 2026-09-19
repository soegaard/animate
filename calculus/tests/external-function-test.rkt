#lang racket/base

;;;
;;; Calculus External Function Tests
;;;

;; Exercises the deliberate lexical escape hatch used for a deterministic
;; procedure provider. The ordinary lambda must not be parsed as DSL syntax.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt")

;; Exports
(provide run-calculus-external-function-tests)


;;;
;;; Fixture
;;;

;; external-function-model : calculus-model?
;;   Holds a provider function whose procedure is supplied through external.
(define-calculus-model external-function-model
  (model
    [f (procedure-function (external (lambda (x) (+ (* x x) 1)))
                           #:domain (closed -2 2)
                           #:key 'square-plus-one)]
    [inside (value-at f 2)]
    [outside (value-at f 3)]))


;;;
;;; Tests
;;;

;; run-calculus-external-function-tests : -> void?
;;   Verifies provider values and declared-domain partiality remain distinct.
(define (run-calculus-external-function-tests)
  (define snapshot (calculus-model-at external-function-model))
  (check-equal? (calculus-result-value (calculus-snapshot-ref snapshot 'inside)) 5)
  (check-equal? (calculus-result-status (calculus-snapshot-ref snapshot 'outside))
                'outside-domain))

(module+ test
  (run-calculus-external-function-tests))
