#lang racket/base

;;;
;;; Selection and Mathematical Provenance
;;;
;; Demonstrates occurrence selection, structural focus, explicit copy lineage,
;; and a checked endpoint whose detailed provenance is deliberately not invented.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt" "common.rkt")
(provide selection-plates distribute-rule)

; distribute-rule : math-rule?
;;   Gives a checked template in which one source factor has two descendants.
(define-math-rule distribute-rule
  #:metavariables (a b c)
  #:from (* a (+ b c))
  #:to (+ (* a b) (* a c)))

; selection-plates : (listof gallery-plate?)
;;   Orders the selection demonstrations before the two distinct rewrite witnesses.
(define selection-plates
  (list
    (one-view-plate 'occurrence-selection 'selection "Select one occurrence"
      "Replace only the middle x with 2: a local specialization, not an identity."
      (present (derive (gallery-state 'occurrence-selection '(+ x x x))
                 [middle (substitute '((x . 2)) #:at (matching 'x #:occurrence 2))])
               #:style replace-style)
      '(matching substitute))
    (one-view-plate 'structural-selection 'selection "Select by mathematical structure"
      "Evaluate only the numerator on the right. Keep the denominator and relation."
      (present (derive (gallery-state 'structural-selection '(= x (/ (+ 2 4) 3)))
                 [numerator (evaluate #:at (numerator (rhs)))]) #:style replace-style)
      '(rhs numerator evaluate))
    (one-view-plate 'distribution 'selection "Distribution with a witness"
      "The rule records two descendants of a; correspondence is explicit, not guessed."
      (present (derive (gallery-state 'distribution '(* a (+ b c)))
                 [distribute (use-rule distribute-rule)]) #:style replace-style)
      '(define-math-rule use-rule trace-descendants))
    (one-view-plate 'checked-replacement 'selection "A checked target replacement"
      "The perfect-square identity is checked; no fine-grained motion proof is invented."
      (present (derive (gallery-state 'checked-replacement '(+ (expt x 2) (* 6 x) 9))
                 [square (rewrite-to '(expt (+ x 3) 2) #:using 'perfect-square)])
               #:style replace-style)
      '(rewrite-to))))
