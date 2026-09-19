#lang racket/base

;;;
;;; Calculus Component Declaration Tests
;;;

;; Ensures component declarations remain lexical data and can be referenced by
;; a lesson model without exposing their private implementation names.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt")

;; Exports
(provide run-calculus-component-declaration-tests)


;;;
;;; Fixture
;;;

;; secant-study : calculus-component?
;;   A Guide-shaped reusable declaration with private chord construction.
(define-calculus-component secant-study
  (inputs [G : Graph] [a : Scalar] [h : Scalar])
  (model
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)]
    [S (secant G P Q)])
  (exports P Q S)
  (constraints (not (= h 0))))

;; component-client : calculus-lesson?
;;   Instantiates the component through its lexical Racket binding.
(define-calculus-lesson component-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'S)))])
  (initially (show G))
  (step explain-study (explain study #:mode 'collapsed)))


;;;
;;; Tests
;;;

;; run-calculus-component-declaration-tests : -> void?
;;   Checks lexical component storage and client plan construction.
(define (run-calculus-component-declaration-tests)
  (check-true (calculus-component? secant-study))
  (check-true (calculus-lesson? component-client))
  (check-true (calculus-plan? (compile-calculus-lesson component-client))))

(module+ test
  (run-calculus-component-declaration-tests))
