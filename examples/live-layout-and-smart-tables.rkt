#lang racket/base

;;;
;;; SCENE-DE/DF: Acyclic Live Layout and Smart Tables
;;;

;; The two annotations form a renderer-measured attachment chain above the
;; moving card. The table independently snapshots measured text widths into its
;; ordinary addressable row/column group tree.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (entry id text)
  (plain-text text #:id id #:font-size 1/5 #:font-family 'swiss
              #:color "darkslategray"))

(define (make-demo-scene)
  (define card
    (rectangle #:id 'card #:center (vec2 -1 3/5)
               #:width 3 #:height 7/5
               #:fill "aliceblue" #:stroke "steelblue" #:stroke-width 3))
  (define caption
    (keep-above
     (plain-text "measured anchor"
                 #:id 'caption #:font-size 1/4 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     'card #:gap 1/5))
  (define detail
    (keep-above
     (plain-text "the second label follows the first"
                 #:id 'detail #:font-size 1/5 #:font-family 'swiss
                 #:color "darkslategray")
     'caption #:gap 1/10))
  (define results
    (table
     (list (list (entry 'heading-term "quantity")
                 (entry 'heading-value "measured value"))
           (list (entry 'row-term "wide label")
                 (entry 'row-value "12.50 cm")))
     #:id 'results #:center (vec2 0 -11/5)
     #:cell-width 'auto #:cell-height 'auto #:cell-padding 1/8
     #:column-gap 1/10 #:row-gap 1/10
     #:stroke "slategray" #:stroke-width 2))
  (define title
    (plain-text "SCENE-DE/DF: live layout and measured tables"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "The card moves; the labels remain attached. Table columns fit their content."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-wait
     (scene-add (make-scene) title explanation card caption detail results)
     1))
  (define moved
    (scene-play initial
                (move-to 'card (vec2 1 4/5))
                (scale-to 'card 6/5)
                #:duration 3))
  (scene-wait moved 1))

(module+ main
  (run-demo "live-layout-and-smart-tables.rkt" make-demo-scene))
