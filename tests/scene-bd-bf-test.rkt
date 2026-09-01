#lang racket/base

;;;
;;; SCENE-BD--BF Formula Part Addressing and Matching Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (part name source center)
    (latex-formula-part source #:name name #:center center))

  (define source
    (formula-assembly
     (list (part 'left "x" (vec2 -1 0))
           (part 'plus "+" origin)
           (part 'right "y" (vec2 1 0)))
     #:id 'equation))
  (define destination
    (formula-assembly
     (list (part 'moved-left "x" (vec2 -2 1))
           (part 'plus "+" (vec2 0 1))
           (part 'new-right "z" (vec2 2 1)))
     #:id 'destination))
  (define base (scene-add (make-scene) source))

  ;; Formula-assembly parts now take the same stable paths as group children.
  (check-true (scene-state-has? (scene-current-state base) '(equation left)))
  (check-equal?
   (visual-id (scene-ref base '(equation plus)))
   'plus)
  (define moved
    (scene-play base (move-to '(equation left) (vec2 3 0)) #:duration 2))
  (check-equal?
   (visual-position (scene-visual-at moved '(equation left) 1))
   (vec2 1 0))
  (define removed
    (scene-remove base '(equation right)))
  (check-false (scene-state-has? (scene-current-state removed) '(equation right)))
  (check-equal?
   (formula-assembly-visual-part-names
    (scene-ref removed 'equation))
   '(left plus))

  ;; Explicit correspondence remains available for deliberately chosen moves.
  (define explicit
    (formula-correspondence
     source destination
     (list (formula-part-match 'left 'moved-left)
           (formula-part-match 'plus 'plus))))
  (check-equal? (formula-correspondence-matches explicit)
                (list (formula-part-match 'left 'moved-left)
                      (formula-part-match 'plus 'plus)))

  ;; Automatic matching finds unchanged rendered parts, even if their stable
  ;; local names differ. Changed parts remain unmatched for fade out/in.
  (define automatic
    (formula-correspondence-auto source destination))
  (check-equal? (formula-correspondence-matches automatic)
                (list (formula-part-match 'left 'moved-left)
                      (formula-part-match 'plus 'plus)))
  (check-equal? (formula-correspondence-unmatched-source-names automatic)
                '(right))
  (check-equal? (formula-correspondence-unmatched-destination-names automatic)
                '(new-right))
  (define transformed
    (scene-play base (transform-formula-parts automatic) #:duration 2))
  (check-equal?
   (formula-assembly-visual-part-names (scene-ref transformed 'equation))
   '(moved-left plus new-right)))
