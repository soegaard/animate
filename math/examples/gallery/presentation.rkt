#lang racket/base

;;;
;;; Presentation Policy Demonstrations
;;;
;; Replays the same mathematics with different history or pacing, and demonstrates
;; independent explanatory insets and a real shared-prefix case derivation.

;;;
;;; Imports and Exports
;;;
(require "../../main.rkt" "model.rkt" "common.rkt")
(provide presentation-plates shared-cases cancellation-solution)

; cancellation-solution : derivation?
;;   Uses separated opposite constants and preserves the surviving variables
;;   for the hold before compaction in both timing variants.
(define cancellation-solution
  (derive (gallery-state 'timing '(- (+ x 5 y) 5) #:real '(x y))
    [cancel-five (cancel-addends)]))

; timed-cancellation : nonnegative-real? -> presentation-plan?
;;   Changes only the pause between retirement and compaction, never the mathematics.
(define (timed-cancellation seconds)
  (choreograph (present cancellation-solution #:style replace-style)
    [cancel-five (retire-cancelled #:duration 3/5) (hold seconds) (compact #:duration 3/5)]))

; shared-prefix : derivation?
;;   Removes a constant before any assumptions about the coefficient are needed.
(define shared-prefix
  (derive (gallery-state 'shared-prefix '(= (+ (* a x) 1) b))
    [remove-constant (steps [subtract (both-sides 'subtract 1)]
                            [cancel (cancel-addends #:at (lhs))])]))

; shared-cases : case-derivation?
;;   Branches only after the shared derivation, with exhaustive real parameter guards.
(define shared-cases
  (derive-cases shared-prefix
    [ordinary '(not (= a 0))
     [divide (both-sides 'divide 'a)] [cancel (cancel-factor #:at (lhs) #:factor 'a)]]
    [all-real '(and (= a 0) (= b 1))
     [specialize (substitute '((a . 0) (b . 1)))] [reduce (reduce-identities)]
     [calculate (evaluate)] [all-values (conclude 'all-real #:for 'x)]]
    [none '(and (= a 0) (not (= b 1)))
     [specialize (substitute '((a . 0)))] [reduce (reduce-identities)]
     [no-values (conclude 'no-solutions #:for 'x)]]))

; presentation-plates : (listof gallery-plate?)
;;   Lists history, timing, independent explanations, and common-work presentation.
(define presentation-plates
  (list
    (make-gallery-plate 'history 'presentation "Choose what remains on screen"
      "The three replays share one derivation; history changes, mathematics does not."
      (for/list ([mode (in-list '(replace keep-completed-groups keep-all-checkpoints))]
                 [title (in-list '("Replace the working row" "Keep completed groups" "Keep elementary checkpoints"))])
        (make-gallery-view mode title
          (present gallery-history-solution #:groups 'top-level
                   #:style (math-presentation #:history mode #:max-visible-rows 4
                                              #:duration 1 #:pause-between-groups 4/5))
          #:caption "Same mathematical operations and answer, with a different retained-history policy."
          #:api '(math-presentation present) #:layout-family 'history-comparison)))
    (make-gallery-plate 'cancellation-timing 'presentation "Pause before closing the gap"
      "Cancel opposite constants, hold the separated survivors, then close the gap."
      (list
        (make-gallery-view 'ordinary "A short pause" (timed-cancellation 1/5)
          #:caption "Cancel the two constants, briefly hold the separated survivors, then compact."
          #:api '(choreograph retire-cancelled compact))
        (make-gallery-view 'deliberate "Time to notice the cancellation" (timed-cancellation 6/5)
          #:caption "Hold the separated survivors longer before closing the gap."
          #:api '(choreograph hold compact))))
    (one-view-plate 'explanatory-inset 'presentation "Explain the choice before acting"
      "The inset motivates adding nine. It is separate from the working equation."
      (choreograph
        (present
          (derive (gallery-state 'explanatory-inset '(= (+ (expt x 2) (* 6 x)) -5))
            [complete-square
             (steps [add-nine (both-sides 'add 9)]
                    [make-square (rewrite-to '(expt (+ x 3) 2) #:at (lhs) #:using 'perfect-square)]
                    [calculate (evaluate #:at (rhs))])])
          #:style gallery-style)
        [(complete-square add-nine)
         (explain-math '(= (expt (/ 6 2) 2) 9) #:caption "Half the coefficient, then square" #:duration 3)
         (prepare-space #:duration 3/5) (reveal-created #:duration 1/2)])
      '(explain-math choreograph))
    (one-view-plate 'shared-prefix 'presentation "Common work, then parameter cases"
      "Present the common subtraction once, then continue each guarded branch."
      (present shared-cases #:style gallery-style #:case-layout 'shared-prefix #:groups 'top-level)
      '(derive-cases present))))
