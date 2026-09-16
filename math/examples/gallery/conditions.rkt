#lang racket/base

;;;
;;; Conditions, Alternatives, and Candidate Checks
;;;
;; Keeps domain exclusions and logical relationships visible. Independent gallery
;; plates are not encoded as mathematical cases; genuine cases occur only within a plate.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt" "common.rkt")
(provide condition-plates parameter-solution)

; parameter-solution : case-derivation?
;;   Splits ax=b into exhaustive nonzero, identity, and inconsistent parameter cases.
(define parameter-solution
  (derive-cases (gallery-state 'parameter-cases '(= (* a x) b))
    [ordinary '(not (= a 0))
     [divide (both-sides 'divide 'a)] [cancel (cancel-factor #:at (lhs) #:factor 'a)]]
    [all-real '(and (= a 0) (= b 0))
     [specialize (substitute '((a . 0) (b . 0)))] [reduce (reduce-identities)]
     [all-values (conclude 'all-real #:for 'x)]]
    [none '(and (= a 0) (not (= b 0)))
     [specialize (substitute '((a . 0)))] [reduce (reduce-identities)]
     [no-values (conclude 'no-solutions #:for 'x)]]))

; condition-plates : (listof gallery-plate?)
;;   Shows restrictions, sign-sensitive algebra, alternatives, and one-way reasoning.
(define condition-plates
  (list
    (one-view-plate 'domain-restriction 'conditions "Keep the original domain"
      "x/x becomes 1, but x must still be nonzero. Cancellation does not enlarge the domain."
      (present (derive (gallery-state 'domain-restriction '(/ x x))
                 [cancel (cancel-factor #:factor 'x)]) #:style replace-style)
      '(math-context cancel-factor))
    (one-view-plate 'negative-inequality 'conditions "Divide an inequality by a negative"
      "Dividing by negative two reverses the inequality."
      (choreograph (present (derive (gallery-state 'negative-inequality '(< (* -2 x) 6))
                 [divide (both-sides 'divide -2)]
                 [cancel (cancel-factor #:at (lhs) #:factor -2)]
                 [evaluate (evaluate #:at (rhs))])
               #:style gallery-style #:groups '((divide cancel evaluate)))
        [divide (transition #:duration 6/5)])
      '(both-sides cancel-factor evaluate choreograph))
    (one-view-plate 'zero-product 'conditions "Zero-product alternatives"
      "A real product is zero exactly when at least one factor is zero."
      (present (derive (gallery-state 'zero-product '(= (* (- x 1) (+ x 2)) 0))
                 [split (zero-product)]) #:style replace-style)
      '(zero-product))
    (one-view-plate 'square-roots 'conditions "Both square-root alternatives"
      "A positive square has positive and negative roots. Both alternatives are retained."
      (present (derive (gallery-state 'square-roots '(= (expt (+ x 3) 2) 4))
                 [split (square-solutions)]
                 [evaluate (each-branch (evaluate #:at (rhs)))])
               #:style replace-style #:groups '((split evaluate)))
      '(square-solutions each-branch))
    (one-view-plate 'parameter-cases 'conditions "Parameters determine the valid method"
      "When a is zero, dividing by a is invalid: distinguish all values from no solutions."
      (present parameter-solution #:style replace-style)
      '(derive-cases context-assume conclude))
    (one-view-plate 'candidate-check 'conditions "Check a candidate in the original problem"
      "Substitute x=4 into the original equation. Membership alone does not prove completeness."
      (present (check-solution linear-problem #:for 'x #:value 4) #:style replace-style)
      '(check-solution))
    (make-gallery-plate 'implication 'conditions "Implication is not equivalence"
      "Squaring preserves solutions forward, but the reverse direction needs care."
      (list
        (make-gallery-view 'forward "Forward implication"
          (present (derive (gallery-state 'implication '(= x 2))
                     [square (both-sides 'power 2 #:relationship 'implication)]
                     [evaluate (evaluate #:at (rhs))]) #:style gallery-style)
          #:caption "x=2 implies x squared = 4. The squared equation also admits x=-2."
          #:api '(both-sides rewrite-step-relation))
        (make-gallery-view 'reject-extra "Check the extra candidate"
          (present (check-solution (gallery-state 'original '(= x 2)) #:for 'x #:value -2)
                   #:style replace-style)
          #:caption "The extra candidate -2 fails the original equation; the converse is not automatic."
          #:api '(check-solution))))))
