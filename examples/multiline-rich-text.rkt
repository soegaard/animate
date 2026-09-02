#lang racket/base

;;;
;;; SCENE-CS: Multiline and Rich Text
;;;

;; A renderer-measured explanatory paragraph sits beside a tagged equation.
;; Its styled inline terms are regular immutable text spans; the formula keeps
;; its own semantic term colours during the fixed-equals rewrite.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define term-colors
  (hash 'unknown "royalblue"
        'constant "firebrick"
        'result "forestgreen"))

(define (before-subtracting)
  (tagged-formula
   #:id 'equation #:center (vec2 2 0)
   #:font-size 3/5 #:color-map term-colors
   (formula-fragment 'unknown "2x")
   (formula-fragment 'plus " + ")
   (formula-fragment 'constant "3")
   (formula-fragment 'equals " = ")
   (formula-fragment 'result "7")))

(define (after-subtracting)
  (tagged-formula
   #:id 'equation #:center (vec2 2 0)
   #:font-size 3/5 #:color-map term-colors
   (formula-fragment 'unknown "2x")
   (formula-fragment 'equals " = ")
   (formula-fragment 'result "7")
   (formula-fragment 'minus " - ")
   (formula-fragment 'constant "3")))

(define (make-demo-scene)
  (define before (before-subtracting))
  (define after (after-subtracting))
  (define title
    (plain-text "SCENE-CS: multiline and rich text"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Measured wrapping and inline styles support mathematical narration."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define instruction
    (rich-text
     #:id 'instruction #:center (vec2 -3 7/5)
     #:width 4 #:line-spacing 6/5 #:line-alignment 'left
     #:horizontal-alignment 'center #:vertical-alignment 'top
     #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"
     (text-span "Step 1\n" #:font-weight 'bold #:color "navy")
     "Subtract "
     (text-span "3" #:font-weight 'bold #:color "firebrick")
     " from both sides.\nThe "
     (text-span "unknown" #:font-weight 'bold #:color "royalblue")
     " stays visible while the equation changes."))
  (define note
    (paragraph "One immutable text visual: explicit lines, measured wrapping, and styled spans."
               #:id 'note #:center (vec2 -3 -12/5)
               #:width 4 #:line-alignment 'center #:line-spacing 11/10
               #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title explanation instruction note before))
  (define rewritten
    (scene-play
     (scene-wait initial 3/2)
     (rewrite-formula
      before after
      #:anchor 'equals
      #:matches
      (list (formula-part-match 'unknown 'unknown)
            (formula-part-match 'equals 'equals)
            (formula-part-match 'result 'result)
            (formula-part-match 'constant 'constant)))
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "multiline-rich-text.rkt" make-demo-scene))
