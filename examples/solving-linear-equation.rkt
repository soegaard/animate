#lang racket/base

;;;
;;; Solving a Linear Equation with a Fixed Equals Sign
;;;

;; A staged tagged-formula example. `rewrite-formula` lays out each endpoint
;; with TeX, then anchors the equals sign at the current scene position.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equation-with-one)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'plus "+")
   (formula-fragment 'left-one "1")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-five "5")))

(define (equation-after-subtracting-one)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-five "5")
   (formula-fragment 'right-minus "-")
   (formula-fragment 'right-one "1")))

(define (equation-with-four)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-2x "2x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-four "4")))

(define (equation-divided-by-two)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-fraction "\\frac{2x}{2}")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-fraction "\\frac{4}{2}")))

(define (solution-equation)
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'left-x "x")
   (formula-fragment 'equals "=")
   (formula-fragment 'right-two "2")))

(define (make-demo-scene)
  (define initial-equation (equation-with-one))
  (define after-subtracting-one (equation-after-subtracting-one))
  (define after-evaluating (equation-with-four))
  (define after-dividing (equation-divided-by-two))
  (define solution (solution-equation))
  (define title
    (plain-text
     "Solving 2x + 1 = 5 with a fixed equals sign"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define initial
    (scene-add (scene-add (make-scene) title) initial-equation))
  (define before-subtracting-one
    (scene-wait initial 1))
  ;; The left-side +1 fades out; the right-side -1 is introduced separately.
  ;; Explicit matches prevent the identical 1 from appearing to cross =.
  (define after-subtraction
    (scene-play
     before-subtracting-one
     (rewrite-formula
      initial-equation
      after-subtracting-one
      #:anchor 'equals
      #:matches
      (list (formula-part-match 'left-2x 'left-2x)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'right-five 'right-five)))
     #:duration 3/2))
  (define before-evaluating
    (scene-wait after-subtraction 1))
  (define after-evaluation
    (scene-play
     before-evaluating
     (rewrite-formula
      after-subtracting-one
      after-evaluating
      #:anchor 'equals)
     #:duration 1))
  (define before-dividing
    (scene-wait after-evaluation 1))
  (define after-division
    (scene-play
     before-dividing
     (rewrite-formula
      after-evaluating
      after-dividing
      #:anchor 'equals
      #:matches
      (list (formula-part-match 'left-2x 'left-fraction)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'right-four 'right-fraction)))
     #:duration 3/2))
  (define before-simplifying
    (scene-wait after-division 1))
  (define solved
    (scene-play
     before-simplifying
     (rewrite-formula
      after-dividing
      solution
      #:anchor 'equals
      #:matches
      (list (formula-part-match 'left-fraction 'left-x)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'right-fraction 'right-two)))
     #:duration 3/2))
  (scene-wait solved 1))

(module+ main
  (run-demo "solving-linear-equation.rkt" make-demo-scene))
