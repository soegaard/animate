#lang racket/base

;;;
;;; Held Expressions and Precise Operations
;;;
;; Six small checked examples separate introducing, cancelling, evaluating, and
;; reordering. Intermediate arithmetic remains held until the specified operation.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt" "common.rkt")
(provide held-plates)

; held-plates : (listof gallery-plate?)
;;   Lists the six elementary-action plates in teaching order.
(define held-plates
  (list
    (one-view-plate 'held-arithmetic 'held "Held arithmetic"
      "Writing an expression does not evaluate or simplify it."
      (present (derive (gallery-state 'held-arithmetic '(= (- (+ (* 3 x) 5) 5) (- 17 5))))
               #:style replace-style) '(math derive))
    (one-view-plate 'both-sides 'held "Operate on both sides"
      "Subtract the same amount on both sides; do not simplify yet."
      (present (derive linear-problem [subtract-five (both-sides 'subtract 5)])
               #:style gallery-style) '(both-sides prepare-space reveal-created))
    (one-view-plate 'additive-cancellation 'held "Cancel opposite addends"
      "The opposite constants cancel. The plus between the surviving terms stays."
      (choreograph
        (present (derive (gallery-state 'additive-cancellation '(- (+ (expt x 2) (* 6 x) 5) 5))
                   [cancel-five (cancel-addends)]) #:style replace-style)
        [cancel-five (retire-cancelled #:duration 3/5) (hold 3/5) (compact #:duration 3/5)])
      '(cancel-addends retire-cancelled compact))
    (one-view-plate 'factor-cancellation 'held "Cancel a common factor"
      "Cancelling a factor and removing the remaining unit are separate steps."
      (present (derive (gallery-state 'factor-cancellation '(/ (* 3 x) 3))
                 [divide-out (cancel-factor #:factor 3 #:keep-one? #t)]
                 [remove-one (remove-unit)]) #:style replace-style #:groups 'steps)
      '(cancel-factor remove-unit))
    (one-view-plate 'focused-evaluation 'held "Evaluate inside a fraction"
      "Compute the numerator first, then the quotient. Each replacement stays coherent."
      (present (derive (gallery-state 'focused-evaluation '(/ (- 17 5) 3))
                 [numerator (evaluate #:at (numerator))] [quotient (evaluate)])
               #:style replace-style #:groups 'steps)
      '(numerator evaluate))
    (one-view-plate 'signed-reorder 'held "Reorder signed terms"
      "The minus belongs to b. Replace the focus as a whole, not as loose signs."
      (present (derive (gallery-state 'signed-reorder '(- (sqrt Δ) b) #:assuming '((>= Δ 0)))
                 [negative-first (reorder-addends #:order '(1 0))]) #:style replace-style)
      '(reorder-addends))))
