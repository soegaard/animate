#lang racket/base

;;;
;;; Solving a Linear Equation with a Fixed Equals Sign
;;;

;; A staged tagged-formula example. Every endpoint is laid out by TeX, then
;; translated as a whole so that the equals sign remains in one fixed place.

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

(define (formula-part-position assembly name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly name))))

;; Reposition a TeX-laid-out equation as one rigid unit so `=` stays fixed,
;; while retaining TeX's spacing between all of its own fragments.
(define (formula-with-equals-at assembly position)
  (define shift
    (vec2- position (formula-part-position assembly 'equals)))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (formula-part
      (formula-part-name part)
      (visual-with-position
       (formula-part-formula part)
       (vec2+ (formula-part-position assembly (formula-part-name part))
              shift))))))

(define (make-demo-scene)
  (define initial-equation (equation-with-one))
  (define equals-position (formula-part-position initial-equation 'equals))
  (define after-subtracting-one
    (formula-with-equals-at (equation-after-subtracting-one) equals-position))
  (define after-evaluating
    (formula-with-equals-at (equation-with-four) equals-position))
  (define after-dividing
    (formula-with-equals-at (equation-divided-by-two) equals-position))
  (define solution
    (formula-with-equals-at (solution-equation) equals-position))
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
     (transform-matching-formula
      initial-equation
      after-subtracting-one
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
     (transform-matching-formula after-subtracting-one after-evaluating)
     #:duration 1))
  (define before-dividing
    (scene-wait after-evaluation 1))
  (define after-division
    (scene-play
     before-dividing
     (transform-matching-formula
      after-evaluating
      after-dividing
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
     (transform-matching-formula
      after-dividing
      solution
      #:matches
      (list (formula-part-match 'left-fraction 'left-x)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'right-fraction 'right-two)))
     #:duration 3/2))
  (scene-wait solved 1))

(module+ main
  (run-demo "solving-linear-equation.rkt" make-demo-scene))
