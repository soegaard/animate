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

  ;; Named semantic parts resolve at the mapped node's local start. The
  ;; template receives target-ref metadata rather than a hidden arity-selected
  ;; target/index pair.
  (define seen '())
  (define revealed
    (reveal-formula-parts
     equation
     '(x equals two)
     (lambda (reference)
       (set! seen
             (append seen
                     (list (list (target-ref-path reference)
                                 (target-ref-source-index reference)
                                 (target-ref-scheduled-index reference)))))
       (move-to (target-ref-path reference)
                (vec2 (target-ref-source-index reference) 1)))
     #:order 'reverse #:lag-ratio 1/5))
  (check-false (lagged-start-animation-request? revealed))
  (check-equal? seen '())
  (define animated
    (scene-play (scene-add (make-scene) equation) revealed #:duration 2))
  (check-equal?
   seen
   '(((equation two) 2 0) ((equation equals) 1 1) ((equation x) 0 2)))
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
     (lambda (reference)
       (set! selected-seen (cons (target-ref-selection-data reference)
                                 selected-seen))
       (indicate (target-ref-path reference)))))
  (define selected-scene
    (scene-play (scene-add (make-scene) equation) selected #:duration 1))
  ;; Every leaf in a source selection is a mapped target, and each retains its
  ;; originating semantic selection data.
  (check-equal? selected-seen (list source-selection source-selection))

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
