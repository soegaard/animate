#lang racket/base

;;;
;;; SCENE-EJ Declared Source-Mapped Formula Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; The declared source map partitions the original TeX source into the
  ;; existing tagged-formula pipeline. Only author-declared spans are exposed
  ;; as source matches; deterministic source-gap fragments retain all other
  ;; visible material and preserve the exact rendered formula.
  (define equation
    (math-tex
     #:id 'equation
     #:font-size 1/2
     #:source-map 'declared
     #:parts
     (list (source-part 'unknown "x")
           (source-part 'equals "="))
     "2x + 1 = 5"))
  (check-equal? (formula-source equation) "2x + 1 = 5")
  (check-true (formula-source-map? (formula-source-map equation)))
  (check-equal?
   (formula-assembly-visual-part-names equation)
   '(source-gap-0 unknown source-gap-1 equals source-gap-2))
  (check-equal?
   (map formula-source-match-name
        (formula-source-map-matches (formula-source-map equation)))
   '(unknown equals))
  (check-equal?
   (map formula-source-match-span
        (formula-source-map-matches (formula-source-map equation)))
   (list (source-span 1 2) (source-span 7 8)))
  (check-equal?
   (map formula-source-match-text
        (formula-source-map-matches (formula-source-map equation)))
   '("x" "="))

  (check-equal?
   (map formula-source-match-name (formula-find equation "x"))
   '(unknown))
  (check-equal?
   (formula-find equation "2")
   '())
  (check-equal?
   (visual-selection-root (formula-source-select-one equation "x"))
   '(equation))
  (check-equal?
   (visual-selection-paths (formula-source-select-one equation "x"))
   '((unknown)))
  (check-equal?
   (visual-selection-paths
    (formula-source-select equation #px"x|="))
   '((unknown) (equals)))
  ;; Declared source selections already work with immutable part styling. The
  ;; source map remains valid because styling retains the same part tree.
  (define highlighted
    (formula-color equation (formula-source-select-one equation "x") "gold"))
  (check-equal? (formula-source highlighted) "2x + 1 = 5")
  (check-equal?
   (map formula-source-match-name (formula-find highlighted "x"))
   '(unknown))
  (check-equal?
   (visual-fill-color
    (formula-part-formula
     (formula-assembly-visual-ref highlighted 'unknown)))
   "gold")
  ;; Read-only attention accepts several selected leaves without constructing a
  ;; fake formula group. The temporary overlay is present only inside the clip.
  (define emphasized
    (scene-play
     (scene-add (make-scene) equation)
     (circumscribe (formula-source-select equation #px"x|=")
                   #:padding 1/10)
     #:duration 1))
  (check-equal? (scene-state-count (scene-sample emphasized 1/2)) 2)
  (check-equal? (scene-state-count (scene-current-state emphasized)) 1)
  (check-true
   (focus-on-request?
    (focus-on (formula-source-select equation #px"x|="))))
  (check-exn exn:fail?
             (lambda ()
               (show-passing-flash (formula-source-select equation "x"))))
  (check-exn exn:fail?
             (lambda () (formula-source-select equation "2")))
  (check-exn exn:fail?
             (lambda () (formula-source-select-one equation #px"x|=")))

  ;; Whitespace-only gaps are absorbed into neighboring visible fragments so
  ;; the SVG pipeline is never asked to crop an empty group.
  (define tightly-declared
    (math-tex
     #:id 'tight
     #:font-size 1/2
     #:source-map 'declared
     #:parts
     (list (source-part 'x "x")
           (source-part 'plus "+")
           (source-part 'y "y"))
     "x + y"))
  (check-equal?
   (formula-assembly-visual-part-names tightly-declared)
   '(x plus y))
  (check-equal?
   (formula-visual-source
    (formula-part-formula
     (formula-assembly-visual-ref tightly-declared 'x)))
   "x ")

  ;; These errors are raised before LaTeX runs. Declared names are stable,
  ;; singular, and non-overlapping; complex nesting waits for a future
  ;; selection-tree representation.
  (check-exn
   exn:fail?
   (lambda ()
     (math-tex
      #:id 'repeated
      #:source-map 'declared
      #:parts (list (source-part 'x "x"))
      "x + x")))
  (check-exn
   exn:fail?
   (lambda ()
     (math-tex
      #:id 'overlap
      #:source-map 'declared
      #:parts (list (source-part 'left "x+")
                    (source-part 'plus "+"))
      "x+y")))
  (check-exn
   exn:fail?
   (lambda ()
     (math-tex
      #:id 'split-control
      #:source-map 'declared
      #:parts (list (source-part 'broken "alpha"))
      "\\alpha + x"))))
