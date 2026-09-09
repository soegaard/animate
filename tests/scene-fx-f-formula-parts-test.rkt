#lang racket/base

;;;
;;; FX-F5 Semantic Formula-Part Composition Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define equation
    (formula-assembly
     (list (formula-part 'x (latex-formula "x" #:id 'x #:center (vec2 -1 0)))
           (formula-part 'equals (latex-formula "=" #:id 'equals #:center origin))
           (formula-part 'two (latex-formula "2" #:id 'two #:center (vec2 1 0))))
     #:id 'equation))

  ;; Named semantic parts are resolved before mapping. The factory still runs
  ;; in original source order and receives the ordinary stable visual paths.
  (define seen '())
  (define revealed
    (reveal-formula-parts
     equation
     '(x equals two)
     (lambda (target source-index)
       (set! seen (append seen (list (list target source-index))))
       (move-to target (vec2 source-index 1)))
     #:order 'reverse #:lag-ratio 1/5))
  (check-true (lagged-start-animation-request? revealed))
  (check-equal?
   seen
   '(((equation x) 0) ((equation equals) 1) ((equation two) 2)))
  (define animated
    (scene-play (scene-add (make-scene) equation) revealed #:duration 2))
  (check-equal? (visual-position (scene-visual-at animated '(equation x) 2))
                (vec2 0 1))
  (check-equal? (visual-position (scene-visual-at animated '(equation equals) 2))
                (vec2 1 1))
  (check-equal? (visual-position (scene-visual-at animated '(equation two) 2))
                (vec2 2 1))

  ;; Root-relative source selections are already semantic formula targets. A
  ;; caller can map an attention-style factory over those without reducing them
  ;; to fragile glyph indexes.
  (define source-selection
    (visual-selection '(equation) '((x) (two))))
  (define selected-seen '())
  (define selected
    (reveal-formula-parts
     equation
     (list source-selection)
     (lambda (target)
       (set! selected-seen (cons target selected-seen))
       (indicate target))))
  (check-true (lagged-start-animation-request? selected))
  (check-equal? selected-seen (list source-selection))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (reveal-formula-parts equation '() (lambda (_target) (indicate 'x)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (reveal-formula-parts
      equation
      (list (visual-selection '(other) '((x))))
      (lambda (_target) (indicate 'x)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (reveal-formula-parts (circle #:id 'not-formula #:radius 1)
                           '(x)
                           (lambda (_target) (indicate 'x))))))
