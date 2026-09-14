#lang racket/base

;;;
;;; Quadratic Concrete Lesson
;;;
;; Defines the held problem, explicit derivation, and presentation. Requiring this
;; module does not render frames or execute TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "../main.rkt" "../render.rkt")

;; Exports
(provide problem solution plan negative-one-check negative-five-check make-demo-scene)

;;;
;;; Construction and Operations
;;;
; problem : math?
;;   Gives the held original problem and its declared real-scalar context.
(define problem
  (math
    '(= (+ (expt x 2) (* 6 x) 5) 0)
    #:id 'quadratic-concrete
    #:context (math-context #:real '(x))))

; solution : (or/c derivation? case-derivation?)
;;   Gives the explicit worked derivation, including parameter branches where needed.
(define solution
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [negative-five (evaluate #:at (rhs))]
    [add-nine (both-sides 'add 9)]
    [make-square (rewrite-to '(expt (+ x 3) 2) #:at (lhs) #:using 'perfect-square)]
    [evaluate-four (evaluate #:at (rhs))]
    [split-roots (square-solutions)]
    [evaluate-roots (each-branch (evaluate #:at (rhs)))]
    [subtract-three (each-branch (both-sides 'subtract 3))]
    [cancel-three (each-branch (cancel-addends #:at (lhs)))]
    [evaluate-answers (each-branch (evaluate #:at (rhs)))]))

; plan : presentation-plan?
;;   Gives the deterministic classroom presentation for the worked solution.
(define plan
  (choreograph
    (present solution
      #:groups
      '((subtract-five cancel-five negative-five)
        (add-nine make-square evaluate-four)
        (split-roots evaluate-roots)
        (subtract-three cancel-three evaluate-answers)))
    [add-nine
      (explain-math '(= (expt (/ 6 2) 2) 9)
                    #:caption "Half the coefficient of x, then square it"
                    #:duration 2)
      (prepare-space #:duration 11/25)
      (reveal-created #:duration 9/25)]))

; negative-one-check : solution-check?
;;   Checks the root minus one against the original equation.
(define negative-one-check
  (check-solution problem #:for 'x #:value -1))

; negative-five-check : solution-check?
;;   Checks the root minus five against the original equation.
(define negative-five-check
  (check-solution problem #:for 'x #:value -5))

; make-demo-scene : -> scene?
;;   Prepares this lesson and constructs its native scene when explicitly called.
(define (make-demo-scene)
  (math-plan->scene! plan #:title "Completing the square"))

(module+ main (require "private/run.rkt") (run-math-example! plan "quadratic-concrete"))
