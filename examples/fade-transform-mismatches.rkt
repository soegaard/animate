#lang racket/base

;;;
;;; Solving an Equation with Fade-Transform
;;;

;; A complete, valid reduction. Formula fragments that change between stages
;; use `fade-transform`, while the equality sign remains at one fixed visual
;; position throughout the derivation.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equals-position assembly)
  (define selection (formula-source-select-one assembly "="))
  (define part-name (caar (visual-selection-paths selection)))
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref assembly part-name))))

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

(define (equation source parts)
  (math-tex
   #:id 'equation
   #:font-size 3/5
   #:source-map 'declared
   #:parts parts
   source))

(define (make-demo-scene)
  (define start
    (equation
     "\\frac{6x}{3} = 4"
     (list (source-part 'left "\\frac{6x}{3}")
           (source-part 'equals "=")
           (source-part 'right "4"))))
  (define simplified-left-layout
    (equation
     "2x = 4"
     (list (source-part 'left "2x")
           (source-part 'equals "=")
           (source-part 'right "4"))))
  (define divided-layout
    (equation
     "\\frac{2x}{2} = \\frac{4}{2}"
     (list (source-part 'left "\\frac{2x}{2}")
           (source-part 'equals "=")
           (source-part 'right "\\frac{4}{2}"))))
  (define solution-layout
    (equation
     "x = 2"
     (list (source-part 'left "x")
           (source-part 'equals "=")
           (source-part 'right "2"))))
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
     (transform-matching-strings start
                                 simplified-left
                                 #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define before-dividing
    (scene-wait left-simplified 1))
  (define divided-by-two
    (scene-play
     before-dividing
     ;; Introduce the same division on both sides of the equation.
     (transform-matching-strings simplified-left
                                 divided
                                 #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define before-finishing
    (scene-wait divided-by-two 1))
  (define solved
    (scene-play
     before-finishing
     ;; Both fractions now reduce to their final values.
     (transform-matching-strings divided
                                 solution
                                 #:mismatch-mode 'fade-transform)
     #:duration 2))
  (scene-wait solved 1))

(module+ main
  (run-demo "fade-transform-mismatches.rkt" make-demo-scene))
