#lang racket/base

;;;
;;; SCENE-BZ: Compatible dvisvgm Glyph Outline Morphing
;;;

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (glyph index)
  (string->symbol (format "glyph-~a" index)))

(define (make-demo-scene)
  ;; Subtracting 2b from both sides changes the left binary operator while
  ;; retaining a genuine algebraic equality: a + b = c -> a - b = c - 2b.
  (define before
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "a + b = c"))
  (define after
    (glyph-tex
     #:id 'equation
     #:font-size 3/5
     "a - b = c - 2b"))
  (define title
    (plain-text
     "SCENE-BZ: glyph outline morph"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "subtract 2b from both sides"
     #:id 'explanation
     #:center (vec2 0 6/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define note
    (plain-text
     "The changed + and - have compatible outlines; other changed glyphs cross-fade."
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
      ;; Only the changed binary operator needs a declared correspondence.
      #:matches (list (formula-part-match (glyph 1) (glyph 1)))
      #:changed-mode 'morph)
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "glyph-outline-morph.rkt" make-demo-scene))
