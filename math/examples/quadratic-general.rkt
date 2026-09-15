#lang racket/base

;;;
;;; Quadratic General Lesson
;;;
;; Defines the held problem, explicit derivation, and presentation. Requiring this
;; module does not render frames or execute TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "../main.rkt" "../render.rkt" "private/library-example.rkt")

;; Exports
(provide problem solution plan make-demo-scene
         math-render-preparer math-render-builder)

;;;
;;; Construction and Operations
;;;
; problem : math?
;;   Gives the held original problem and its declared real-scalar context.
(define problem
  (math
    '(= (+ (* a (expt x 2)) (* b x) c) 0)
    #:id 'quadratic-general
    #:context (math-context #:real '(a b c x) #:definitions '((Δ (- (expt b 2) (* 4 a c)))))))

; quadratic-branch : math? -> any/c
;;   Gives the nondegenerate quadratic branch and its discriminant cases.
(define (quadratic-branch state)
  (define square
    (derive state
      [subtract-c (both-sides 'subtract 'c)]
      [cancel-c (cancel-addends #:at (lhs))]
      [negative-c (reduce-identities #:at (rhs))]
      [multiply-four-a (both-sides 'multiply '(* 4 a))]
      [expand-products
       (rewrite-to
         '(= (+ (* 4 (expt a 2) (expt x 2)) (* 4 a b x)) (* -4 a c))
         #:using 'expand-products)]
      [add-b-squared (both-sides 'add '(expt b 2))]
      [make-square
       (rewrite-to '(expt (+ (* 2 a x) b) 2) #:at (lhs) #:using 'perfect-square)]
      [order-rhs (reorder-addends #:at (rhs) #:order '(1 0))]
      [name-discriminant (abbreviate 'Δ #:at (rhs))]))
  (derive-cases square
    [two-real-roots
     '(> Δ 0)
     [split (square-solutions)]
     [subtract-b (each-branch (both-sides 'subtract 'b))]
     [cancel-b (each-branch (cancel-addends #:at (lhs)))]
     [divide-two-a (each-branch (both-sides 'divide '(* 2 a)))]
     [cancel-two-a (each-branch (cancel-factor #:at (lhs) #:factor '(* 2 a)))]
     [order-numerators
      (each-branch (reorder-addends #:at (numerator (rhs)) #:order '(1 0)))]]
    [one-real-root
     '(= Δ 0)
     [single-root (square-solutions)]
     [subtract-b (both-sides 'subtract 'b)]
     [cancel-b (cancel-addends #:at (lhs))]
     [divide-two-a (both-sides 'divide '(* 2 a))]
     [cancel-two-a (cancel-factor #:at (lhs) #:factor '(* 2 a))]
     [reduce-numerator (reduce-identities #:at (numerator (rhs)))]]
    [no-real-roots '(< Δ 0) [impossible-square (square-solutions)]]))

; solution : (or/c derivation? case-derivation?)
;;   Gives the explicit worked derivation, including parameter branches where needed.
(define solution
  (derive-cases problem
    [quadratic '(not (= a 0)) #:then quadratic-branch]
    [linear
     '(and (= a 0) (not (= b 0)))
     [specialize-a (substitute '((a . 0)))]
     [reduce (reduce-identities)]
     [subtract-c (both-sides 'subtract 'c)]
     [cancel-c (cancel-addends #:at (lhs))]
     [negative-c (reduce-identities #:at (rhs))]
     [divide-b (both-sides 'divide 'b)]
     [cancel-b (cancel-factor #:at (lhs) #:factor 'b)]]
    [all-real '(and (= a 0) (= b 0) (= c 0)) [all-values (conclude 'all-real #:for 'x)]]
    [none
     '(and (= a 0) (= b 0) (not (= c 0)))
     [no-values (conclude 'no-solutions #:for 'x)]]))

; prefix-groups : list?
;;   Gives ordered step groups shared by quadratic discriminant branches.
(define prefix-groups
  '((subtract-c cancel-c negative-c)
     (multiply-four-a expand-products)
     (add-b-squared make-square order-rhs name-discriminant)))

; plan : presentation-plan?
;;   Gives the deterministic classroom presentation for the worked solution.
(define plan
  (present solution
    #:case-layout 'shared-prefix
    #:groups
    (hash '(quadratic two-real-roots)
      (append prefix-groups
        '((split) (subtract-b cancel-b) (divide-two-a cancel-two-a order-numerators)))
      '(quadratic one-real-root)
      (append prefix-groups
        '((single-root) (subtract-b cancel-b) (divide-two-a cancel-two-a reduce-numerator)))
      '(quadratic no-real-roots)
      (append prefix-groups '((impossible-square)))
      '(linear)
      '((specialize-a reduce subtract-c cancel-c negative-c) (divide-b cancel-b))
      '(all-real)
      '((all-values))
      '(none)
      '((no-values)))))

; make-demo-scene : -> scene?
;;   Prepares this lesson and constructs its native scene when explicitly called.
(define (make-demo-scene)
  (math-plan->scene! plan #:title "The quadratic formula and all coefficient cases"))

(module+ main (require "private/run.rkt") (run-math-example! plan "quadratic-general"))
