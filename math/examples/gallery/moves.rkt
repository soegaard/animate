#lang racket/base

;;;
;;; Named Moves and Reusable Recipes
;;;
;; Demonstrates nested semantic organization while retaining every elementary step.
;; Comparison variants share derivations rather than reauthoring equivalent formulas.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt" "common.rkt")
(provide move-plates)

; named-solution : derivation?
;;   Groups three elementary operations into one inspectable mathematical move.
(define named-solution
  (derive linear-problem
    [remove-constant (steps [subtract (both-sides 'subtract 5)]
                            [cancel (cancel-addends #:at (lhs))]
                            [evaluate (evaluate #:at (rhs))])]))

; nested-solution : derivation?
;;   Reuses an ordinary function returning nested steps under one outer solve move.
(define nested-solution (derive linear-problem [isolate-x (linear-recipe 5 3)]))

; recipe-example : symbol? number? number? number? -> derivation?
;;   Instantiates the same transparent recipe in a different held problem.
(define (recipe-example id coefficient constant right)
  (derive (gallery-state id `(= (+ (* ,coefficient x) ,constant) ,right))
    [remove-constant (subtract-and-cancel constant)]
    [calculate (evaluate #:at (rhs))]))

; move-plates : (listof gallery-plate?)
;;   Shows composite moves, nesting, reusable functions, and independent grouping.
(define move-plates
  (list
    (make-gallery-plate 'named-moves 'moves "A named mathematical move"
      "One move contains explicit elementary steps, not an opaque automatic solution."
      (list (make-gallery-view 'main "" (present named-solution #:style replace-style)
              #:caption "Remove the constant: subtract, cancel, then calculate. Every checkpoint survives."
              #:api '(steps derive derivation-tree) #:tree? #t)))
    (make-gallery-plate 'nested-moves 'moves "Moves can contain moves"
      "The active path in the inspector follows the mathematical hierarchy."
      (list (make-gallery-view 'main "" (present nested-solution #:style replace-style)
              #:caption "The hierarchy organizes the method; elementary operations still justify each change."
              #:api '(steps derivation-tree derivation-step) #:tree? #t)))
    (make-gallery-plate 'reusable-recipe 'moves "A recipe is an ordinary Racket function"
      "Apply subtract-and-cancel to two equations without hiding its child operations."
      (list
        (make-gallery-view 'five "Subtract and cancel five"
          (present (recipe-example 'recipe-five 3 5 17) #:style gallery-style)
          #:caption "The recipe returns named steps. This application subtracts and cancels five."
          #:api '(steps both-sides cancel-addends))
        (make-gallery-view 'seven "The same recipe with seven"
          (present (recipe-example 'recipe-seven 2 7 19) #:style gallery-style)
          #:caption "Only the recipe argument changes. All conditions are checked in this problem's context."
          #:api '(steps both-sides cancel-addends))))
    (make-gallery-plate 'grouping 'moves "One derivation, two groupings"
      "Both replays animate all steps; only the completed rows kept as history differ."
      (list
        (make-gallery-view 'moves "Group by mathematical moves"
          (present linear-solution #:style gallery-style #:groups 'top-level)
          #:caption "One completed row per top-level move; no elementary step is skipped."
          #:api '(present steps))
        (make-gallery-view 'leaves "Group by elementary steps"
          (present linear-solution #:style gallery-style #:groups 'steps)
          #:caption "The same derivation and endpoints, with a separate history group for every leaf."
          #:api '(present derivation-steps))))))
