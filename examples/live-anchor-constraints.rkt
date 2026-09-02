#lang racket/base

;;;
;;; SCENE-CM: Live Anchor Constraints
;;;

;; A renderer-aware attachment keeps the label's lower-left corner on the
;; card's live upper-right rendered-box corner while the card moves, rotates,
;; and scales.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CM: live anchor constraints"
                #:id 'title #:center (vec2 0 3)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "The label follows the card's live upper-right render-box corner."
                #:id 'explanation #:center (vec2 0 -3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define card
    (rectangle #:id 'card #:center (vec2 -5/2 0) #:width 2 #:height 1
               #:fill "aliceblue" #:stroke "navy" #:stroke-width 3))
  (define badge
    (attach-to
     (plain-text "attached label" #:id 'badge #:center origin
                 #:font-size 1/5 #:font-family 'swiss #:color "crimson")
     'card
     #:target-anchor 'top-right
     #:self-anchor 'bottom-left
     #:offset (vec2 1/5 1/5)))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation card badge) 1))
  (define moved
    (scene-play initial
                (move-to 'card (vec2 1/2 0))
                (scale-to 'card 3/2)
                (rotate-to 'card 1/4)
                #:duration 2))
  (define returned
    (scene-play moved
                (move-to 'card (vec2 2 0))
                (scale-to 'card 1)
                (rotate-to 'card -1/8)
                #:duration 1))
  (scene-wait returned 2))

(module+ main
  (run-demo "live-anchor-constraints.rkt" make-demo-scene))
