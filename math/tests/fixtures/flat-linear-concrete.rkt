#lang racket/base

;;;
;;; Frozen Pre-Moves Linear Concrete Lesson
;;;
;; Defines the held problem, explicit derivation, and presentation. Requiring this
;; module does not render frames or execute TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "../../main.rkt")

;; Exports
(provide problem solution plan answer-check)

;;;
;;; Construction and Operations
;;;
; problem : math?
;;   Gives the held original problem and its declared real-scalar context.
(define problem
  (math '(= (+ (* 3 x) 5) 17) #:id 'linear-concrete #:context (math-context #:real '(x))))

; solution : (or/c derivation? case-derivation?)
;;   Gives the explicit worked derivation, including parameter branches where needed.
(define solution
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-twelve (evaluate #:at (rhs))]
    [divide-three (both-sides 'divide 3)]
    [reduce-left (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
    [remove-one (remove-unit #:at (lhs))]
    [evaluate-four (evaluate #:at (rhs))]))

; plan : presentation-plan?
;;   Gives the deterministic classroom presentation for the worked solution.
(define plan
  (choreograph
    (present solution
      #:style classroom
      #:groups
      '((subtract-five cancel-five evaluate-twelve)
         (divide-three reduce-left remove-one evaluate-four)))
    [subtract-five (prepare-space #:duration 1/2) (reveal-created #:duration 2/5)]
    [cancel-five (retire-cancelled #:duration 2/5) (hold 1/2) (compact #:duration 2/5)]
    [remove-one (retire-removed #:duration 3/10) (hold 1/2) (compact #:duration 3/10)]))

; answer-check : solution-check?
;;   Checks the isolated root against the original equation.
(define answer-check
  (check-solution problem #:for 'x #:value 4))
