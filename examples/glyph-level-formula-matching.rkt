#lang racket/base

;;;
;;; SCENE-BY: Automatic Glyph-Level Formula Matching
;;;

;; dvisvgm decomposes this complete TeX expression into visible glyph leaves.
;; The unchanged x, 3, =, and 7 glyphs are matched automatically; the explicit
;; + to - correspondence makes the sign change visible as the 3 moves right.

(require (only-in racket/math pi)
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (glyph index)
  (string->symbol (format "glyph-~a" index)))

(define (make-demo-scene)
  ;; Glyph positions in `x + 3 = 7`: x, +, 3, =, 7.
  (define before
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "x + 3 = 7"))
  ;; Glyph positions in `x = 7 - 3`: x, =, 7, -, 3.
  (define after
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "x = 7 - 3"))
  (define title
    (plain-text
     "SCENE-BY: automatic glyph matching"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "x + 3 = 7     subtract 3 from both sides     x = 7 - 3"
     #:id 'explanation
     #:center (vec2 0 6/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define note
    (plain-text
     "dvisvgm glyph leaves match automatically; only + to - is declared."
     #:id 'note
     #:center (vec2 0 -7/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define initial
    (scene-add
     (make-scene)
     title
     explanation
     note
     before))
  (define shown
    (scene-wait initial 1))
  (define rewritten
    (scene-play
     shown
     (rewrite-formula
      before
      after
      ;; The equality glyph is in position 3 before and position 1 after.
      #:anchor (formula-part-match (glyph 3) (glyph 1))
      ;; The changed sign is the only non-automatic correspondence.
      #:matches (list (formula-part-match (glyph 1) (glyph 3)))
      #:part-paths
      (list
       (formula-part-path
        (glyph 1)
        (glyph 3)
        (formula-arc #:angle (- (/ pi 2))))))
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "glyph-level-formula-matching.rkt" make-demo-scene))
