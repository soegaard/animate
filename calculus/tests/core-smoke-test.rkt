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

;; coincident-geometry-model : calculus-model?
;;   Distinguishes the valid degenerate segment from undefined directed lines.
(define-calculus-model coincident-geometry-model
  (model
    [P (point 1 1)]
    [S (segment P P)]
    [L (line-through P P)]
    [R (ray-through P P)]))

;; integer-variation : calculus-lesson?
;;   Deliberately attempts to interpolate a discrete parameter.
(define-calculus-lesson integer-variation
  (model
    [n (parameter 2 #:domain (integers 1 8) #:kind 'integer)])
  (views [numbers (number-line-view #:objects (n))])
  (step interpolate-count (vary n #:to 4 #:duration 1)))

;; excluded-path : calculus-lesson?
;;   Deliberately crosses a declared hole while both endpoints are valid.
(define-calculus-lesson excluded-path
  (model
    [u (parameter 0 #:domain (domain-except (closed 0 2) 1))])
  (views [number-line (number-line-view #:objects (u))])
  (step cross-hole (vary u #:to 2 #:duration 1)))

;; incomplete-approach : calculus-lesson?
;;   Omits the finite authored stopping value required by approach.
(define-calculus-lesson incomplete-approach
  (model
    [u (parameter 0 #:domain (closed 0 2))])
  (views [number-line (number-line-view #:objects (u))])
  (step missing-stop (approach u #:to 1 #:side 'right #:duration 1)))

;; wrong-side-after-assignment : calculus-lesson?
;;   Verifies side validation uses the preceding assignment, not initial state.
(define-calculus-lesson wrong-side-after-assignment
  (model
    [u (parameter 0 #:domain (closed 0 2))])
  (views [number-line (number-line-view #:objects (u))])
  (step move-right (set-parameter u 2))
  (step approach-from-wrong-side
    (approach u #:to 1 #:side 'left #:until 9/10 #:duration 1)))

;; partition-model : calculus-model?
;;   Covers explicit endpoint/tag checks and an exact trapezoidal quantity.
(define-calculus-model partition-model
  (model
    [f (function (x) (* x x))]
    [P (partition (list 0 1 2))]
    [bad-P (partition (list 0 1 1))]
    [tags (tag-partition P #:tags (list 0 3/2))]
    [bad-tags (tag-partition P #:tags (list 1/2 3))]
    [S (riemann-sum f tags)]
    [bad-S (riemann-sum f bad-tags)]
    [q (sum-value S)]
    [bad-q (sum-value bad-S)]
    [T (trapezoidal-sum f P)]
    [bad-T (trapezoidal-sum f bad-P)]))

;; numeric-integral-model : calculus-model?
;;   Exercises bounded numerical integration independently of a supplied rule.
(define-calculus-model numeric-integral-model
  (model
    [f (function (x) (* x x))]
    [I (definite-integral f #:from 0 #:to 2)]))


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
                1)
  (define coincident (calculus-model-at coincident-geometry-model))
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'S)) 'defined)
  (check-equal? (calculus-result-value (calculus-snapshot-ref coincident 'S))
                (list 'segment (cons 1 1) (cons 1 1)))
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'L)) 'undefined)
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'R)) 'undefined)
  (define integer-plan (compile-calculus-lesson integer-variation))
  (check-equal? (length (calculus-plan-diagnostics integer-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample integer-plan #:at 'final) 'n))
                2)
  (define excluded-plan (compile-calculus-lesson excluded-path))
  (check-equal? (length (calculus-plan-diagnostics excluded-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample excluded-plan #:at 'final) 'u))
                0)
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson incomplete-approach)))
                1)
  (define wrong-side-plan (compile-calculus-lesson wrong-side-after-assignment))
  (check-equal? (length (calculus-plan-diagnostics wrong-side-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample wrong-side-plan #:at 'final) 'u))
                2)
  (define partition-snapshot (calculus-model-at partition-model))
  (check-equal? (calculus-result-value (calculus-snapshot-ref partition-snapshot 'q)) 9/4)
  (check-equal? (calculus-result-status (calculus-snapshot-ref partition-snapshot 'bad-q)) 'undefined)
  (check-equal? (calculus-result-value (calculus-snapshot-ref partition-snapshot 'T)) 3)
  (check-equal? (calculus-result-status (calculus-snapshot-ref partition-snapshot 'bad-T)) 'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref
                  (calculus-model-at numeric-integral-model
                                     #:computation (calculus-computation #:integration-budget 2))
                  'I))
                'unresolved))

(module+ test
  (run-calculus-core-smoke-tests))
