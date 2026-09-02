#lang racket/base

;;;
;;; SCENE-BS Tagged Formula Tests
;;;

;; Verifies that one complete TeX layout is recovered as independently movable
;; tagged fragments and that formula correspondence retains specialised fragment
;; renderer data through interior timeline samples.

(require rackunit
         (only-in pict pict?)
         "../main.rkt")

(module+ test
  (define source
    (tagged-formula
     #:id 'equation
     #:font-size 2/5
     (formula-fragment 'a-square "a^2")
     (formula-fragment 'plus "+")
     (formula-fragment 'b-square "b^2")
     (formula-fragment 'equals "=")
     (formula-fragment 'c-square "c^2")))

  (define destination
    (tagged-formula
     #:id 'rearranged
     #:font-size 2/5
     (formula-fragment 'b-square "b^2")
     (formula-fragment 'equals "=")
     (formula-fragment 'c-square "c^2")
     (formula-fragment 'minus "-")
     (formula-fragment 'a-square "a^2")))

  (check-equal?
   (formula-assembly-visual-part-names source)
   '(a-square plus b-square equals c-square))
  (check-true
   (andmap tagged-formula-fragment-visual?
           (map formula-part-formula
                (formula-assembly-visual-parts source))))

  ;; The full TeX layout determines distinct local centers. In particular, the
  ;; terms are no longer manually positioned formula snippets.
  (check-true
   (< (vec2-x
       (visual-position
        (formula-part-formula
         (formula-assembly-visual-ref source 'a-square))))
      (vec2-x
       (visual-position
        (formula-part-formula
         (formula-assembly-visual-ref source 'c-square))))))

  (define animated
    (scene-play
     (scene-add (make-scene) source)
     (transform-matching-formula source destination)
     #:duration 2))

  (define midpoint
    (scene-state-ref (scene-sample animated 1) 'equation))
  (check-equal?
   (formula-assembly-visual-part-names midpoint)
   '(__formula-transition-0
     __formula-transition-1
     __formula-transition-2
     __formula-transition-3
     __formula-transition-4
     __formula-transition-5))
  (check-true
   (andmap tagged-formula-fragment-visual?
           (map formula-part-formula
                (formula-assembly-visual-parts midpoint))))

  ;; Tagged fragments remain ordinary nested Visual targets. The specialised
  ;; SVG renderer data survives an immutable nested movement update.
  (define nested-moved
    (scene-play
     (scene-add (make-scene) source)
     (move-to '(equation a-square) (vec2 -4 1))
     #:duration 1))
  (define moved-fragment
    (scene-state-ref (scene-current-state nested-moved)
                     '(equation a-square)))
  (check-equal? (visual-position moved-fragment) (vec2 -4.0 1.0))
  (check-true (tagged-formula-fragment-visual? moved-fragment))

  ;; The specialised renderer is in the normal default renderer list.
  (check-true (pict? (scene->pict animated 1)))

  ;; Explicit correspondence remains available for a changed fragment. It has
  ;; priority over automatic exact-source matches, while still cross-fading the
  ;; two different pieces.
  (check-true
   (transform-formula-parts-request?
    (transform-matching-formula
     source
     destination
     #:matches (list (formula-part-match 'plus 'minus)))))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (tagged-formula #:id 'bad
                     (formula-fragment 'same "x")
                     (formula-fragment 'same "y")))))
