#lang racket/base

;;;
;;; Solving an Equation with Fade-Transform
;;;

;; A complete, valid reduction. Formula fragments that change between stages
;; use `fade-transform`, while the equality sign remains at one fixed visual
;; position throughout the derivation.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equals-position assembly)
  (for/first ([part (in-list (formula-assembly-visual-parts assembly))]
              #:when (string=? (formula-visual-source
                                 (formula-part-formula part))
                               "="))
    (visual-position (formula-part-formula part))))

;; Shift a completed TeX layout as a rigid unit so that every stage shares one
;; equals-sign anchor. Its independently rendered formula fragments can then
;; still transform relative to that fixed point.
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
  (define start
    (math-tex
     #:id 'equation
     #:font-size 3/5
     "{{ \\frac{6x}{3} }} = {{ 4 }}"))
  (define simplified-left-layout
    (math-tex
     #:id 'equation
     #:font-size 3/5
     "{{ 2x }} = {{ 4 }}"))
  (define divided-layout
    (math-tex
     #:id 'equation
     #:font-size 3/5
     "{{ \\frac{2x}{2} }} = {{ \\frac{4}{2} }}"))
  (define solution-layout
    (math-tex
     #:id 'equation
     #:font-size 3/5
     "{{ x }} = {{ 2 }}"))
  (define fixed-equals-position (equals-position start))
  (define simplified-left
    (formula-with-equals-at simplified-left-layout fixed-equals-position))
  (define divided
    (formula-with-equals-at divided-layout fixed-equals-position))
  (define solution
    (formula-with-equals-at solution-layout fixed-equals-position))
  (define title
    (plain-text
     "SCENE-BV: Solving an equation"
     #:id 'title
     #:center (vec2 0 11/5)
     #:font-size 3/10
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "Simplify • divide both sides by 2 • simplify"
     #:id 'explanation
     #:center (vec2 0 6/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define note
    (plain-text
     "Fade-transform carries each changing formula part between stages."
     #:id 'note
     #:center (vec2 0 -7/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define initial
    (scene-add
     (scene-add
      (scene-add
       (scene-add (make-scene) title)
       explanation)
      note)
     start))
  (define before-simplifying
    (scene-wait initial 1))
  (define left-simplified
    (scene-play
     before-simplifying
     ;; The fraction reduces to 2x; = and 4 remain exact automatic matches.
     (transform-matching-tex start
                             simplified-left
                             #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define before-dividing
    (scene-wait left-simplified 1))
  (define divided-by-two
    (scene-play
     before-dividing
     ;; Introduce the same division on both sides of the equation.
     (transform-matching-tex simplified-left
                             divided
                             #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define before-finishing
    (scene-wait divided-by-two 1))
  (define solved
    (scene-play
     before-finishing
     ;; Both fractions now reduce to their final values.
     (transform-matching-tex divided
                             solution
                             #:mismatch-mode 'fade-transform)
     #:duration 2))
  (scene-wait solved 1))

(module+ main
  (run-demo "fade-transform-mismatches.rkt" make-demo-scene))
