#lang racket/base

;;;
;;; Manim-Style Formula Matching
;;;

;; `math-tex` retains one TeX layout per endpoint. Source selections make the
;; intended matchable pieces explicit without coordinating generated part IDs.

(require (only-in racket/math pi)
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equals-position assembly)
  (define selection (formula-source-select-one assembly "="))
  (define part-name (caar (visual-selection-paths selection)))
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly part-name))))

;; Shift the complete TeX layout as a rigid unit so all endpoints share the
;; first equation's equals-sign position. The individual matched fragments can
;; still move relative to that stationary anchor.
(define (formula-with-equals-at assembly position)
  (define shift (vec2- position (equals-position assembly)))
  (formula-assembly-visual-with-parts
   assembly
   (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
     (formula-part
      (formula-part-name part)
      (visual-with-position
       (formula-part-formula part)
       (vec2+ (visual-position (formula-part-formula part)) shift))))))

(define (equation source parts)
  (math-tex
   #:id 'equation
   #:font-size 1/2
   #:source-map 'declared
   #:parts parts
   source))

(define (make-demo-scene)
  (define pythagoras
    (equation
     "a^2 + b^2 = c^2"
     (list (source-part 'a-square "a^2")
           (source-part 'plus "+")
           (source-part 'b-square "b^2")
           (source-part 'equals "=")
           (source-part 'c-square "c^2"))))
  (define isolated-b-layout
    (equation
     "b^2 = c^2 - a^2"
     (list (source-part 'b-square "b^2")
           (source-part 'equals "=")
           (source-part 'c-square "c^2")
           (source-part 'minus "-")
           (source-part 'a-square "a^2"))))
  (define reversed-sides-layout
    (equation
     "c^2 - a^2 = b^2"
     (list (source-part 'c-square "c^2")
           (source-part 'minus "-")
           (source-part 'a-square "a^2")
           (source-part 'equals "=")
           (source-part 'b-square "b^2"))))
  (define fixed-equals-position (equals-position pythagoras))
  (define isolated-b
    (formula-with-equals-at isolated-b-layout fixed-equals-position))
  (define reversed-sides
    (formula-with-equals-at reversed-sides-layout fixed-equals-position))
  (define title
    (plain-text
     "Source-addressed formula matching"
     #:id 'title
     #:center (vec2 0 2)
     #:font-size 1/3
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define initial
    (scene-add (scene-add (make-scene) title) pythagoras))
  (define before-isolating
    (scene-wait initial 1))
  ;; Identical source atoms move automatically. The explicit source match says
  ;; that the old `+` is the new `-`; its arc travels below the fixed `=` while
  ;; cross-fading into the changed glyph.
  (define b-isolated
    (scene-play before-isolating
                (transform-matching-strings
                 pythagoras
                 isolated-b
                 #:key-map
                 (list
                  (string-match "+" "-"
                                #:route (formula-arc #:angle (/ pi 2))))
                 #:mismatch-mode 'fade-transform)
                #:duration 2))
  (define before-reversing
    (scene-wait b-isolated 1))
  ;; Every group matches in this second transition, so it is a pure reorder;
  ;; the equals sign remains in its fixed position throughout.
  (define sides-reversed
    (scene-play before-reversing
                (transform-matching-strings isolated-b reversed-sides)
                #:duration 2))
  (scene-wait sides-reversed 1))

(module+ main
  (run-demo "manim-style-formula-matching.rkt" make-demo-scene))
