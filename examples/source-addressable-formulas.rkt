#lang racket/base

;;;
;;; SCENE-EJ: Source-Addressable Formulas
;;;

;; A source selection is a query over a formula's retained TeX source.  It is
;; not a temporary group or a new scene Visual: the same source formula remains
;; in the scene while attention effects address its selected rendered leaves.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define equation
    (math-tex #:id 'equation #:font-size 3/5 #:source-map 'tokens
              "x^2 + x = 6"))
  ;; `formula-find` would return both `x` occurrences. `source-occurrence`
  ;; narrows the same selector to one source match, so the video can show its
  ;; mapped rendered leaf without a union box spanning the full equation.
  (define second-x
    (formula-source-select equation (source-occurrence "x" 1)))
  (define leading-digit
    (formula-source-select equation (source-occurrence #px"[0-9]" 0)))
  (define plus (formula-source-select equation (source-span 4 5)))
  (define title
    (plain-text "SCENE-EJ: source-addressable formulas"
                #:id 'title #:center (vec2 0 11/5)
                #:font-size 3/10 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define source
    (plain-text "source: x^2 + x = 6"
                #:id 'source #:center (vec2 0 6/5)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define literal-note
    (plain-text "(source-occurrence \"x\" 1) selects the second x"
                #:id 'literal-note #:center (vec2 0 -7/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title source literal-note equation))
  (define literal-highlighted
    (scene-play (scene-wait initial 1)
                (indicate second-x #:color "goldenrod" #:padding 1/10 #:stroke-width 3)
                #:duration 3/2))
  (define number-note
    (plain-text "regexp #px\"[0-9]\" maps to the rendered x^2 token"
                #:id 'number-note #:center (vec2 0 -7/5)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define number-stage
    (scene-play
     (scene-add (scene-remove literal-highlighted 'literal-note) number-note)
     (indicate leading-digit #:color "tomato" #:padding 1/10 #:stroke-width 3)
     #:duration 3/2))
  (define span-note
    (plain-text "(source-span 4 5) selects the + source character"
                #:id 'span-note #:center (vec2 0 -7/5)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define span-stage
    (scene-play
     (scene-add (scene-remove number-stage 'number-note) span-note)
     (circumscribe plus #:color "royalblue" #:padding 1/10 #:stroke-width 3)
     #:duration 3/2))
  (scene-wait span-stage 1))

(module+ main
  (run-demo "source-addressable-formulas.rkt" make-demo-scene))
