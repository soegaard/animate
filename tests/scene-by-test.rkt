#lang racket/base

;; SCENE-BY: dvisvgm glyph formulas match by rendered outline, not complete
;; formula source. The test uses a genuine algebraic rewrite without {{...}}
;; groups or manually declared formula fragments.

(require (only-in pict pict?)
         rackunit
         "../main.rkt"
         "../private/glyph-outline-morph-visual.rkt")

(define (glyph index)
  (string->symbol (format "glyph-~a" index)))

(define (glyph-position scene time name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref
     (scene-visual-at scene 'equation time)
     name))))

(module+ test
  (define source
    (glyph-tex #:id 'equation #:font-size 1/2 "x + 3 = 7"))
  (define destination
    (glyph-tex #:id 'equation #:font-size 1/2 "x = 7 - 3"))
  (check-equal? (formula-assembly-visual-part-names source)
                '(glyph-0 glyph-1 glyph-2 glyph-3 glyph-4))
  (check-equal? (formula-assembly-visual-part-names destination)
                '(glyph-0 glyph-1 glyph-2 glyph-3 glyph-4))
  ;; Every glyph Visual keeps the complete author TeX source. The separate
  ;; dvisvgm outline key nevertheless matches x, 3, =, and 7 automatically.
  (check-false
   (string=?
    (formula-visual-source
     (formula-part-formula (formula-assembly-visual-ref source (glyph 0))))
    (formula-visual-source
     (formula-part-formula
      (formula-assembly-visual-ref destination (glyph 0))))))
  (check-equal?
   (formula-correspondence-matches
    (formula-correspondence-auto source destination))
   (list (formula-part-match (glyph 0) (glyph 0))
         (formula-part-match (glyph 2) (glyph 4))
         (formula-part-match (glyph 3) (glyph 1))
         (formula-part-match (glyph 4) (glyph 2))))

  ;; The glyph-specific wrapper validates glyph-tex assemblies and retains the
  ;; ordinary correspondence options for an intentional plus-to-minus change.
  (check-true
   (transform-formula-parts-request?
    (transform-matching-glyphs
     source
     destination
     #:matches (list (formula-part-match (glyph 1) (glyph 3))))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (transform-matching-glyphs
      (math-tex #:id 'other "{{ x }}")
      destination)))

  ;; SCENE-BZ is opt-in. The explicit + -> - pair has one closed dvisvgm
  ;; contour on each side, so its interior is one outline-morph formula layer
  ;; rather than the historical moving cross-fade pair.
  (define outline-morphed
    (scene-play
     (scene-add (make-scene) source)
     (transform-matching-glyphs
      source
      destination
      #:matches (list (formula-part-match (glyph 1) (glyph 3)))
      #:changed-mode 'morph)
     #:duration 2))
  (define interior-parts
    (formula-assembly-visual-parts
     (scene-visual-at outline-morphed 'equation 1)))
  (check-true
   (for/or ([part (in-list interior-parts)])
     (glyph-outline-morph-visual?
      (formula-part-formula part))))
  (check-false
   (for/or ([part (in-list
                   (formula-assembly-visual-parts
                    (scene-visual-at outline-morphed 'equation 0)))])
     (glyph-outline-morph-visual?
      (formula-part-formula part))))
  (check-true (pict? (scene->pict outline-morphed 1)))

  ;; SCENE-CA extends the same conservative rule to compound closed glyphs.
  ;; Italic a and b both contain an outer contour and a counter, so their
  ;; dvisvgm paths are paired without reversing either contour's traversal.
  (define complex-source
    (glyph-tex #:id 'complex "a"))
  (define complex-destination
    (glyph-tex #:id 'complex "b"))
  (define complex-transition
    (scene-play
     (scene-add (make-scene) complex-source)
     (transform-matching-glyphs
      complex-source
      complex-destination
      #:matches (list (formula-part-match (glyph 0) (glyph 0)))
      #:changed-mode 'morph)
     #:duration 1))
  (check-true
   (for/or ([part (in-list
                   (formula-assembly-visual-parts
                    (scene-visual-at complex-transition 'complex 1/2)))])
     (glyph-outline-morph-visual?
      (formula-part-formula part))))
  (check-true (pict? (scene->pict complex-transition 1/2)))

  ;; One closed contour cannot safely morph into a glyph with a counter.  The
  ;; conservative fallback remains essential when contour topology differs.
  (define incompatible-transition
    (scene-play
     (scene-add (make-scene) complex-source)
     (transform-matching-glyphs
      complex-source
      (glyph-tex #:id 'complex "+")
      #:matches (list (formula-part-match (glyph 0) (glyph 0)))
      #:changed-mode 'morph)
     #:duration 1))
  (check-false
   (for/or ([part (in-list
                   (formula-assembly-visual-parts
                    (scene-visual-at incompatible-transition 'complex 1/2)))])
     (glyph-outline-morph-visual?
      (formula-part-formula part))))

  ;; Anchored rewrites work directly with glyph assemblies. = remains fixed
  ;; even though it has a different generated index at the destination.
  (define animated
    (scene-play
     (scene-add (make-scene) source)
     (rewrite-formula
      source
      destination
      #:anchor (formula-part-match (glyph 3) (glyph 1))
      #:matches (list (formula-part-match (glyph 1) (glyph 3)))
      #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define equals-position
    (glyph-position animated 0 (glyph 3)))
  (define final-equals-position
    (glyph-position animated 2 (glyph 1)))
  (check-= (vec2-x final-equals-position) (vec2-x equals-position) 1e-12)
  (check-= (vec2-y final-equals-position) (vec2-y equals-position) 1e-12)
  (check-true (pict? (scene->pict animated 1))))
