#lang racket/base

;;;
;;; SCENE-CL: Stationary Formula Parts
;;;

;; A derivation can retain more than its main anchor. Here `2x`, `=`, and the
;; existing `5` remain still while the subtraction is introduced on the right.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (start-equation)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'plus "+")
   (formula-fragment 'left-one "1")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-five "5")))

(define (after-subtracting-one)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-five "5")
   (formula-fragment 'minus "-")
   (formula-fragment 'right-one "1")))

(define (after-evaluating)
  (tagged-formula
   #:id 'equation #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-four "4")))

(define (make-demo-scene)
  (define initial-equation (start-equation))
  (define subtraction (after-subtracting-one))
  (define evaluated (after-evaluating))
  (define title
    (plain-text "SCENE-CL: keep selected formula parts still"
                #:id 'title #:center (vec2 0 5/2)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define initial
    (scene-wait (scene-add (make-scene) title initial-equation) 1))
  (define derived
    (formula-derivation
     initial initial-equation
     #:anchor 'equals
     #:explanation-position (vec2 0 -5/2)
     #:explanation-font-size 1/5
     #:steps
     (list
      (formula-step
       subtraction
       #:matches
       (list (formula-part-match 'left-2x 'left-2x)
             (formula-part-match 'equals 'equals)
             (formula-part-match 'right-five 'right-five))
       #:stationary '(left-2x right-five)
       #:pause 1 #:duration 3/2
       #:explanation "Keep 2x, =, and 5 fixed; subtract 1 on both sides")
      (formula-step
       evaluated
       #:matches
       (list (formula-part-match 'left-2x 'left-2x)
             (formula-part-match 'equals 'equals))
       #:stationary '(left-2x)
       #:pause 1 #:duration 1
       #:explanation "Evaluate 5 - 1"))))
  (scene-wait derived 2))

(module+ main
  (run-demo "stationary-formula-derivation.rkt" make-demo-scene))
