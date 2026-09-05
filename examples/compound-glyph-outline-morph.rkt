#lang racket/base

;;;
;;; SCENE-CA: Compound dvisvgm Glyph Outline Morphing
;;;

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (glyph index)
  (string->symbol (format "glyph-~a" index)))

(define (make-demo-scene)
  ;; Multiplying an inequality by -1 reverses its relation.  The \leq and
  ;; \geq glyphs each have several closed dvisvgm contours, so this is a
  ;; useful real formula step for SCENE-CA's compound-outline morph.
  (define before
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "-x \\leq 3"))
  (define after
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "x \\geq -3"))
  (define title
    (plain-text
     "SCENE-CA: compound glyph outline morph"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "multiply both sides by -1"
     #:id 'explanation
     #:center (vec2 0 6/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define note
    (plain-text
     "The multi-contour inequality relation morphs while the terms move."
     #:id 'note
     #:center (vec2 0 -7/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title explanation note before))
  (define shown
    (scene-wait initial 1))
  (define rewritten
    (scene-play
     shown
     (transform-matching-glyphs
      before
      after
      ;; Move the terms and the minus sign; map the changed relation explicitly.
      #:matches
      (list (formula-part-match (glyph 0) (glyph 2))
            (formula-part-match (glyph 1) (glyph 0))
            (formula-part-match (glyph 2) (glyph 1))
            (formula-part-match (glyph 3) (glyph 3)))
      #:changed-mode 'morph)
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "compound-glyph-outline-morph.rkt" make-demo-scene))
