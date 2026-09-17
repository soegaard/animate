#lang racket/base

;;;
;;; Small Mathematical Gallery Recipes
;;;
;; Supplies ordinary held states, styles, and transparent named recipes shared by
;; demonstrations. No typesetter, CAS, renderer, filesystem, or worker is loaded.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt")
(provide gallery-state gallery-style replace-style gallery-history-style subtract-and-cancel
         linear-recipe linear-problem linear-solution gallery-history-solution one-view-plate)

; gallery-state : symbol? math-datum? [#:real list?] [#:assuming list?] -> math?
;;   Gives each independently authored demonstration an explicit root identity.
(define (gallery-state id datum #:real [real '(x a b c Δ)] #:assuming [facts '()])
  (math datum #:id id #:context (math-context #:real real #:assuming facts)))

; gallery-style : presentation-style?
;;   Uses a readable classroom history with at most three formula rows per plate.
(define gallery-style (math-presentation #:max-visible-rows 3 #:duration 1 #:pause-between-groups 4/5))

; replace-style : presentation-style?
;;   Emphasizes a local replacement without making a second working-row copy.
(define replace-style (math-presentation #:history 'replace #:max-visible-rows 3
                                        #:duration 1 #:pause-between-groups 4/5))

; gallery-history-style : presentation-style?
;;   Gives the five history/grouping comparisons one readable four-row policy.
(define gallery-history-style
  (math-presentation #:max-visible-rows 4 #:duration 1 #:pause-between-groups 4/5))

; subtract-and-cancel : math-datum? -> step-sequence?
;;   Returns an inspectable two-step recipe; conditions and ambiguity are checked on use.
(define (subtract-and-cancel term)
  (steps [subtract (both-sides 'subtract term)]
         [cancel (cancel-addends #:at (lhs))]))

; linear-recipe : math-datum? math-datum? -> step-sequence?
;;   Explicitly removes a constant and coefficient without invoking an automatic solver.
(define (linear-recipe constant coefficient)
  (steps
    [remove-constant
     (steps [subtract (both-sides 'subtract constant)]
            [cancel (cancel-addends #:at (lhs))]
            [evaluate (evaluate #:at (rhs))])]
    [remove-coefficient
     (steps [divide (both-sides 'divide coefficient)]
            [cancel (cancel-factor #:at (lhs) #:factor coefficient #:keep-one? #t)]
            [remove-unit (remove-unit #:at (lhs))]
            [evaluate (evaluate #:at (rhs))])]))

; linear-problem : math?
;;   Supplies the identical held problem reused by the presentation comparisons.
(define linear-problem (gallery-state 'gallery-linear '(= (+ (* 3 x) 5) 17)))

; linear-solution : derivation?
;;   Supplies exactly the same derivation object for grouping and history comparisons.
(define linear-solution
  (derive linear-problem
    [remove-constant
     (steps [subtract (both-sides 'subtract 5)] [cancel (cancel-addends #:at (lhs))]
            [evaluate (evaluate #:at (rhs))])]
    [remove-coefficient
     (steps [divide (both-sides 'divide 3)]
            [cancel (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
            [remove-unit (remove-unit #:at (lhs))] [evaluate (evaluate #:at (rhs))])]))

; gallery-history-solution : derivation?
;;   Keeps the comparison fixture short while retaining two named moves and four checkpoints.
(define gallery-history-solution
  (derive (gallery-state 'gallery-history '(+ (+ 2 3) (* 2 4)) #:real '())
    [evaluate-parts
     (steps [evaluate-first (evaluate #:at (at-path '(0)))]
            [evaluate-second (evaluate #:at (at-path '(1)))])]
    [finish (evaluate)]))

; one-view-plate : symbol? symbol? string? string? presentation-plan? list? -> gallery-plate?
;;   Avoids duplicated catalogue boilerplate for a single-plan demonstration.
(define (one-view-plate id chapter title caption plan api)
  (make-gallery-plate id chapter title caption
    (list (make-gallery-view 'main "" plan #:caption caption #:api api))))
