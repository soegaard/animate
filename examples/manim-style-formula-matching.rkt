#lang racket/base

;;;
;;; Manim-Style Formula Matching
;;;

;; `math-tex` retains one TeX layout per endpoint. Its `{{ ... }}` groups make
;; the intended matchable pieces visible in source without naming every part.

(require (only-in racket/math pi)
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equals-position assembly)
  (for/first ([part (in-list (formula-assembly-visual-parts assembly))]
              #:when (string=? (formula-visual-source
                                 (formula-part-formula part))
                               "="))
    (visual-position (formula-part-formula part))))

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

(define (make-demo-scene)
  (define pythagoras
    (math-tex
     #:id 'equation
     #:font-size 1/2
     "{{ a^2 }} + {{ b^2 }} = {{ c^2 }}"))
  (define isolated-b-layout
    (math-tex
     #:id 'equation
     #:font-size 1/2
     "{{ b^2 }} = {{ c^2 }} - {{ a^2 }}"))
  (define reversed-sides-layout
    (math-tex
     #:id 'equation
     #:font-size 1/2
     "{{ c^2 }} - {{ a^2 }} = {{ b^2 }}"))
  (define fixed-equals-position (equals-position pythagoras))
  (define isolated-b
    (formula-with-equals-at isolated-b-layout fixed-equals-position))
  (define reversed-sides
    (formula-with-equals-at reversed-sides-layout fixed-equals-position))
  (define title
    (plain-text
     "Manim-style {{...}} formula matching"
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
  ;; Identical grouped source strings move automatically. `key-map` says that
  ;; the old `+` is the new `-`; its explicit arc travels below the fixed `=`
  ;; while cross-fading into the changed glyph.
  (define b-isolated
    (scene-play before-isolating
                (transform-matching-tex pythagoras
                                        isolated-b
                                        #:key-map (hash "+" "-")
                                        #:path-map
                                        (hash (cons "+" "-")
                                              (formula-arc #:angle (/ pi 2))))
                #:duration 2))
  (define before-reversing
    (scene-wait b-isolated 1))
  ;; Every group matches in this second transition, so it is a pure reorder;
  ;; the equals sign remains in its fixed position throughout.
  (define sides-reversed
    (scene-play before-reversing
                (transform-matching-tex isolated-b reversed-sides)
                #:duration 2))
  (scene-wait sides-reversed 1))

(module+ main
  (run-demo "manim-style-formula-matching.rkt" make-demo-scene))
