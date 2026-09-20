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
         "../main.rkt"
         (only-in "../private/core.rkt"
                  calculus-snapshot-function-breaks))

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

;; external-break-model : calculus-model?
;; Declared topology supplements an opaque provider without pretending that a
;; finite return value at the break proves continuity through it.
(define-calculus-model external-break-model
  (model
    [f (procedure-function (external (lambda (x) x))
                           #:domain (closed -1 1)
                           #:key 'identity-with-hole
                           #:breaks (list 1/2))]))


;;;
;;; Tests
;;;

;; run-calculus-external-function-tests : -> void?
;;   Verifies provider values and declared-domain partiality remain distinct.
(define (run-calculus-external-function-tests)
  (define snapshot (calculus-model-at external-function-model))
  (check-equal? (calculus-result-value (calculus-snapshot-ref snapshot 'inside)) 5)
  (check-equal? (calculus-result-status (calculus-snapshot-ref snapshot 'outside))
                'outside-domain)
  (define break-snapshot (calculus-model-at external-break-model))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-function-breaks break-snapshot
                                       (calculus-result-value
                                        (calculus-snapshot-ref break-snapshot 'f))))
   (list 1/2))
  (check-exn
   #px"requires #:key"
   (lambda ()
     (let ()
       (define-calculus-model missing-provider-key
         (model
           [f (procedure-function (external (lambda (x) x))
                                  #:domain (closed 0 1))]))
       missing-provider-key))))

(module+ test
  (run-calculus-external-function-tests))
