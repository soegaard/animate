#lang racket/base

;;;
;;; SCENE-EJ Root-Relative Visual Selection Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; Formula construction knows its own root identity but not the future group
  ;; path an author may place it under.  Leaf paths therefore remain relative.
  (define xs
    (visual-selection
     '(equation)
     '((glyph-2) (glyph-4) (glyph-2))))
  (check-equal? (visual-selection-root xs) '(equation))
  (check-equal? (visual-selection-paths xs) '((glyph-2) (glyph-4)))
  (check-equal? (visual-selection-count xs) 2)
  (check-false (visual-selection-empty? xs))
  (check-equal?
   (visual-selection-absolute-paths xs)
   '((equation glyph-2) (equation glyph-4)))

  ;; Empty paths are valid selections of the root itself; an empty selection
  ;; carries the same root context without manufacturing a fake group Visual.
  (define equation-root (visual-selection '(equation) '(())))
  (define no-leaves (visual-selection '(equation) '()))
  (check-equal? (visual-selection-absolute-paths equation-root) '((equation)))
  (check-true (visual-selection-empty? no-leaves))
  (check-equal? (visual-selection-count no-leaves) 0)

  ;; Set operations use only ordered paths.  They preserve the left argument's
  ;; source order, append new paths deterministically, and never use hashes.
  (define exponents (visual-selection '(equation) '((glyph-4) (glyph-5))))
  (check-equal?
   (visual-selection-paths (visual-selection-union xs exponents))
   '((glyph-2) (glyph-4) (glyph-5)))
  (check-equal?
   (visual-selection-paths (visual-selection-intersection xs exponents))
   '((glyph-4)))
  (check-exn exn:fail?
             (lambda ()
               (visual-selection-union
                xs
                (visual-selection '(other-equation) '((glyph-2))))))

  ;; A component-local selection can be attached to its actual nested scene
  ;; location.  The rebased result is still a selection, not a rendered Visual.
  (define nested-xs (visual-selection-rebase xs '(diagram equation)))
  (check-equal? (visual-selection-root nested-xs) '(diagram equation))
  (check-equal?
   (visual-selection-absolute-paths nested-xs)
   '((diagram equation glyph-2) (diagram equation glyph-4)))
  (check-exn exn:fail?
             (lambda () (visual-selection-rebase xs '(diagram other))))

  ;; Selection paths can be used with the existing immutable scene lookup once
  ;; rebased, including beneath ordinary affine groups.
  (define equation
    (group
     (list (circle #:id 'glyph-2 #:radius 1/8)
           (circle #:id 'glyph-4 #:radius 1/8 #:center (vec2 1 0)))
     #:id 'equation))
  (define diagram
    (group (list equation) #:id 'diagram #:center (vec2 2 1) #:rotation 1/5))
  (define state
    (scene-current-state (scene-add (make-scene) diagram)))
  (for ([path (in-list (visual-selection-absolute-paths nested-xs))])
    (check-true (visual? (scene-state-ref state path)))))
