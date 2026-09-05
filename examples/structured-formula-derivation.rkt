#lang racket/base

;;;
;;; SCENE-CF: Structured Formula Derivation
;;;

;; An explicit algebraic derivation uses formula-step records for the intended
;; correspondence and formula-derivation for notes, pauses, and anchored
;; rewrite sequencing. It does not ask Animate to infer the algebra.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (start-equation)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-3x "3x")
   (formula-fragment 'plus "+")
   (formula-fragment 'left-six "6")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-twenty-one "21")))

(define (after-subtracting-six)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-3x "3x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-twenty-one "21")
   (formula-fragment 'minus "-")
   (formula-fragment 'right-six "6")))

(define (after-evaluating)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-3x "3x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-fifteen "15")))

(define (solution)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-x "x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-five "5")))

(define (make-demo-scene)
  (define initial-equation (start-equation))
  (define subtraction (after-subtracting-six))
  (define evaluated (after-evaluating))
  (define final-equation (solution))
  (define title
    (plain-text "SCENE-CF: an explicit formula derivation"
                #:id 'title
                #:center (vec2 0 5/2)
                #:font-size 1/3
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define initial
    (scene-wait
     (scene-add (make-scene) title initial-equation)
     1))
  (define derived
    (formula-derivation
     initial
     initial-equation
     #:anchor 'equals
     #:explanation-position (vec2 0 -5/2)
     #:explanation-font-size 1/5
     #:steps
     (list
      (formula-step
       subtraction
       #:matches
       (list (formula-part-match 'left-3x 'left-3x)
             (formula-part-match 'equals 'equals)
             (formula-part-match 'right-twenty-one 'right-twenty-one))
       #:duration 3/2
       #:pause 1
       #:explanation "Subtract 6 from both sides")
      (formula-step
       evaluated
       #:duration 1
       #:pause 1
       #:explanation "Evaluate 21 - 6")
      (formula-step
       final-equation
       #:matches
       (list (formula-part-match 'left-3x 'left-x)
             (formula-part-match 'equals 'equals)
             (formula-part-match 'right-fifteen 'right-five))
       #:mismatch-mode 'fade-transform
       #:duration 3/2
       #:pause 1
       #:explanation "Divide both sides by 3"))))
  (scene-wait derived 1))

(module+ main
  (run-demo "structured-formula-derivation.rkt" make-demo-scene))
