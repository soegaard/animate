#lang racket/base

;;;
;;; SCENE-CK: Live Attention and Callout Anchors
;;;

;; The outline is measured after the card's sampled motion and scale. The
;; fixed annotation's leader follows the card's live rendered right edge.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CK: live attention follows its target"
                #:id 'title #:center (vec2 0 3)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Both the outline and leader follow the card as its box changes."
                #:id 'explanation #:center (vec2 0 -3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define card
    (rectangle #:id 'card #:center (vec2 -5/2 0) #:width 2 #:height 1
               #:fill "aliceblue" #:stroke "navy" #:stroke-width 3))
  (define card-label
    (plain-text "moving card" #:id 'card-label #:center (vec2 -5/2 0)
                #:font-size 1/5 #:font-family 'swiss #:color "navy"))
  (define note
    (callout
     (plain-text "live right edge" #:id 'note #:center (vec2 2 3/2)
                 #:font-size 1/5 #:font-family 'swiss #:color "darkslategray")
     'card
     #:target-anchor 'right
     #:connector-stroke "darkslategray"
     #:connector-width 2))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation card card-label note) 1))
  (define moved
    (scene-play initial
                ;; Attention appears before card motion in source order, but
                ;; is sampled after it so the outline has the current box.
                (circumscribe 'card #:padding 1/5 #:color "crimson" #:stroke-width 3)
                (move-to 'card (vec2 1/2 0))
                (move-to 'card-label (vec2 1/2 0))
                (scale-to 'card 3/2)
                #:duration 2))
  (define indicated
    (scene-play moved
                (indicate 'card #:padding 1/5 #:color "goldenrod" #:stroke-width 3)
                (move-to 'card (vec2 3/2 0))
                (move-to 'card-label (vec2 3/2 0))
                #:duration 1))
  (scene-wait indicated 2))

(module+ main
  (run-demo "live-attention-follow.rkt" make-demo-scene))
