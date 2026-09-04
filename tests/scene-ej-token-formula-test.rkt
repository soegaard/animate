#lang racket/base

;;;
;;; SCENE-EJ Conservative TeX Atom Source Mapping Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; Token mode maps safely wrappable TeX atoms. Scripts and known command
  ;; arguments stay with their base so every physical tagged fragment remains
  ;; valid TeX. It is deliberately more conservative than a glyph provenance
  ;; map, but it makes ordinary formulas source-addressable without a manual
  ;; #:parts list.
  (define default-mapped
    (math-tex #:id 'default-mapped #:font-size 1/2 "x + y"))
  (check-equal? (formula-source default-mapped) "x + y")
  (check-equal?
   (map formula-source-match-text (formula-find default-mapped "x"))
   '("x"))
  ;; Opting out remains possible for deliberately unsplit/legacy artifacts.
  (check-false
   (formula-source-map
    (math-tex #:id 'unmapped #:source-map 'none "x + y")))
  (define equation
    (math-tex
     #:id 'equation
     #:font-size 1/2
     #:source-map 'tokens
     "x^2 + \\frac{a}{b}"))
  (check-equal? (formula-source equation) "x^2 + \\frac{a}{b}")
  (check-equal?
   (map formula-source-match-name
        (formula-source-map-matches (formula-source-map equation)))
   '(source-token-0 source-token-1 source-token-2))
  (check-equal?
   (map formula-source-match-span
        (formula-source-map-matches (formula-source-map equation)))
   (list (source-span 0 3) (source-span 4 5) (source-span 6 17)))
  (check-equal?
   (map formula-source-match-text (formula-find equation "2"))
   '("x^2"))
  (check-equal?
   (visual-selection-paths (formula-source-select-one equation "+"))
   '((source-token-1)))
  (check-equal?
   (visual-selection-paths
    (formula-source-select equation (source-span 0 5)))
   '((source-token-0) (source-token-1)))

  ;; A wrapped atom can use TeX source unlike its simple source selector. The
  ;; original source coordinate system remains visible through the map.
  (check-equal?
   (map formula-source-match-text (formula-find equation "\\frac{a}{b}"))
   '("\\frac{a}{b}"))
  (define plus-report (formula-explain-selection equation "+"))
  (check-equal? (source-selection-report-selector plus-report) "+")
  (check-equal?
   (map formula-source-match-name (source-selection-report-matches plus-report))
   '(source-token-1))
  (check-equal? (source-selection-report-rejected-spans plus-report) '())
  (define greek
    (math-tex #:id 'greek #:font-size 1/2 #:source-map 'tokens "\\alpha + x"))
  ;; The characters `alpha` are inside one TeX control word and are not a
  ;; source boundary. The full control sequence remains selectable.
  (check-equal? (formula-find greek "alpha") '())
  (check-equal?
   (map formula-source-match-text (formula-find greek "\\alpha"))
   '("\\alpha"))
  (check-true
   (pair? (source-selection-report-diagnostics
           (formula-explain-selection greek "alpha"))))
  (define highlighted
    (formula-color equation (formula-source-select-one equation "2") "gold"))
  (check-equal? (formula-source highlighted) "x^2 + \\frac{a}{b}")

  ;; Token mode owns its atom declarations. Mixing it with manually named
  ;; declared parts would create two flat claims for the same visible leaves.
  (check-exn
   exn:fail?
   (lambda ()
     (math-tex
      #:id 'bad
      #:source-map 'tokens
      #:parts (list (source-part 'x "x"))
      "x")))

  ;; Token atoms feed SCENE-EK directly: no coordinating fragment names are
  ;; needed to preserve x, =, 7, and the relocated 3 across the rewrite.
  (define before
    (math-tex #:id 'rewrite #:font-size 1/2 #:source-map 'tokens "x + 3 = 7"))
  (define after
    (math-tex #:id 'rewrite #:font-size 1/2 #:source-map 'tokens "x = 7 - 3"))
  (define transition
    (scene-play
     (scene-add (make-scene) before)
     (transform-matching-strings
      before after
      #:key-map (list (string-match "+" "-")))
     #:duration 1))
  (check-equal?
   (formula-source
    (scene-state-ref (scene-current-state transition) 'rewrite))
   "x = 7 - 3"))
