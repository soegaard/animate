#lang racket/base

;;;
;;; SCENE-EF: Numeric animation II
;;;

;; A counter and three measurement formats are all derived from immutable scene
;; values. The digit wheels, formatting, and sampled values are reproducible at
;; any requested frame; no display stores a previous rendered number.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (label id text center)
  (plain-text text #:id id #:center center
              #:font-size 1/4 #:font-family 'swiss
              #:font-weight 'bold #:color "darkslategray"))

(define (make-demo-scene)
  (define counter (parameter 'counter 0))
  (define acceleration (parameter 'acceleration 0))
  (define ratio (parameter 'ratio 0))
  (define phasor (parameter 'phasor 1-1i))
  (define acceleration-unit
    (unit-product (unit "m") (unit "s" #:power -2)))

  (define title
    (plain-text "SCENE-EF: numeric animation II"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Every display is derived directly from its sampled immutable numeric value."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))

  ;; The counter uses clipped digit wheels. Its declared slots make the visual
  ;; range explicit, while its right edge stays in a stable position.
  (define counter-card
    (rounded-rectangle #:id 'counter-card #:center (vec2 -3/2 1/4)
                       #:width 13/3 #:height 5/2 #:corner-radius 1/4
                       #:fill "aliceblue" #:stroke "steelblue" #:stroke-width 2))
  (define counter-label (label 'counter-label "rolling counter" (vec2 -3/2 13/10)))
  (define counter-display
    (rolling-number-display counter #:id 'counter-display #:center (vec2 -3/2 -1/10)
                            #:integer-digits 2 #:decimal-places 1
                            #:font-size 7/10 #:color "navy"))
  (define counter-note
    (plain-text "count-from 0 to 42.7" #:id 'counter-note #:center (vec2 -3/2 -9/10)
                #:font-size 1/5 #:font-family 'swiss #:color "steelblue"))

  ;; These fields exercise the formatters that ordinary parameter-display
  ;; values share with static numeric labels.
  (define acceleration-label
    (label 'acceleration-label "scientific" (vec2 5/4 6/5)))
  (define acceleration-display
    (parameter-display acceleration #:id 'acceleration-display #:center (vec2 22/5 6/5)
                       #:kind 'scientific #:significant-figures 3
                       #:unit acceleration-unit #:anchor 'right
                       #:font-size 7/20 #:color "firebrick"))
  (define ratio-label (label 'ratio-label "rational" (vec2 5/4 0)))
  (define ratio-display
    (parameter-display ratio #:id 'ratio-display #:center (vec2 22/5 0)
                       #:kind 'rational #:max-denominator 12 #:anchor 'right
                       #:font-size 7/20 #:color "darkgreen"))
  (define phasor-label (label 'phasor-label "complex" (vec2 5/4 -6/5)))
  (define phasor-display
    (parameter-display phasor #:id 'phasor-display #:center (vec2 22/5 -6/5)
                       #:kind 'complex #:decimal-places 1 #:anchor 'right
                       #:font-size 7/20 #:color "mediumpurple"))

  (define initial
    (scene-add
     (scene-set-value
      (scene-set-value
       (scene-set-value
        (scene-set-value (make-scene) counter)
        acceleration)
       ratio)
      phasor)
     title explanation
     counter-card counter-label counter-display counter-note
     acceleration-label acceleration-display
     ratio-label ratio-display
     phasor-label phasor-display))
  (define animated
    (scene-play
     (scene-wait initial 1)
     (animation-group
      (count-from counter 0 42.7)
      (change-number-to acceleration 12700)
      (change-number-to ratio 2/3)
      (change-number-to phasor 3+4i))
     #:duration 4 #:easing (smooth)))
  (scene-wait animated 2))

(module+ main
  (run-demo "numeric-animation-ii.rkt" make-demo-scene))
