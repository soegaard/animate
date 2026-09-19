#lang racket/base

;;;
;;; Calculus Core Smoke Tests
;;;

;; Exercises the first end-to-end headless reading lesson without importing a
;; renderer, font backend, or scene adapter.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt")

;; Exports
(provide run-calculus-core-smoke-tests)


;;;
;;; Fixtures
;;;

(define-calculus-lesson reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R))])
  (initially (show G))
  (step read-output (read R))
  (step vary-input (vary a #:to -2 #:duration 4)))

;; invalid-parameter-path : calculus-lesson?
;;   Deliberately targets a value outside its declared parameter domain.
(define-calculus-lesson invalid-parameter-path
  (model
    [a (parameter 0 #:domain (closed -1 1))]
    [f (function (x) x)]
    [G (graph f)])
  (views [plot (graph-view #:x (closed -1 1) #:y (closed -1 1) #:objects (G))])
  (initially (show G))
  (step leave-domain (vary a #:to 2 #:duration 1)))


;;;
;;; Tests
;;;

;; run-calculus-core-smoke-tests : -> void?
;;   Verifies exact function attachment, deterministic sampling, and parameter motion.
(define (run-calculus-core-smoke-tests)
  (define plan (compile-calculus-lesson reading-square))
  (define initial (calculus-plan-sample plan #:at 'initial))
  (check-equal? (calculus-result-value (calculus-snapshot-ref initial '(R output))) 4)
  (check-true (calculus-snapshot-visible? initial 'G))
  (check-false (calculus-snapshot-visible? initial 'R))
  (define final (calculus-plan-sample plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref final 'a)) -2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref final '(R output))) 4)
  (check-true (calculus-snapshot-visible? final 'R))
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson invalid-parameter-path)))
                1))

(module+ test
  (run-calculus-core-smoke-tests))
