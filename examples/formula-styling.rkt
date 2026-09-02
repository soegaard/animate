#lang racket/base

;;;
;;; SCENE-CR: Semantic Formula Styling
;;;

;; The colours belong to named mathematical fragments rather than TeX source
;; spelling.  The blue unknown, red constant, and green result therefore keep
;; their identities while the subtraction step rearranges the equation.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define term-colors
  (hash 'left-term "royalblue"
        'constant "firebrick"
        'result "forestgreen"))

(define (before-subtracting)
  (tagged-formula
   #:id 'equation
   #:font-size 3/5
   #:color-map term-colors
   (formula-fragment 'left-term "2x")
   (formula-fragment 'plus " + ")
   (formula-fragment 'constant "3")
   (formula-fragment 'equals " = ")
   (formula-fragment 'result "7")))

(define (after-subtracting)
  (tagged-formula
   #:id 'equation
   #:font-size 3/5
   #:color-map term-colors
   (formula-fragment 'left-term "2x")
   (formula-fragment 'equals " = ")
   (formula-fragment 'result "7")
   (formula-fragment 'minus " - ")
   (formula-fragment 'constant "3")))

(define (make-demo-scene)
  (define before (before-subtracting))
  (define after (after-subtracting))
  (define title
    (plain-text
     "SCENE-CR: semantic formula styling"
     #:id 'title #:center (vec2 0 2)
     #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "Named terms keep their colour when the equation is rewritten."
     #:id 'explanation #:center (vec2 0 6/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define note
    (plain-text
     "Highlight +3, then subtract 3 from both sides."
     #:id 'note #:center (vec2 0 -7/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title explanation note before))
  (define highlighted
    (scene-play
     (scene-wait initial 1)
     (indicate (formula-select before 'constant)
               #:color "goldenrod" #:padding 1/6 #:stroke-width 3)
     #:duration 1))
  (define rewritten
    (scene-play
     (scene-wait highlighted 1/2)
     (rewrite-formula
      before after
      #:anchor 'equals
      #:matches
      (list (formula-part-match 'left-term 'left-term)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'result 'result)
            (formula-part-match 'constant 'constant)))
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "formula-styling.rkt" make-demo-scene))
