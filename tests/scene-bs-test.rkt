#lang racket/base

;;;
;;; SCENE-BS Tagged Formula Tests
;;;

;; Verifies that one complete TeX layout is recovered as independently movable
;; tagged fragments and that formula correspondence retains specialised fragment
;; renderer data through interior timeline samples.

(require (only-in racket/math pi)
         rackunit
         racket/string
         (only-in pict pict?)
         "../main.rkt")

(define (formula-for-source assembly source)
  (formula-part-formula
   (for/first ([part (in-list (formula-assembly-visual-parts assembly))]
               #:when (string=? (string-trim
                                 (formula-visual-source
                                  (formula-part-formula part)))
                                source))
     part)))

(define (source-mapped-equation id source parts)
  (math-tex
   #:id id
   #:font-size 2/5
   #:source-map 'declared
   #:parts parts
   source))

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
    (transform-matching-parts source destination)
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
    (transform-matching-parts
     source
     destination
     #:matches (list (formula-part-match 'plus 'minus)))))

  ;; Source-mapped `math-tex` keeps one complete TeX layout while the author
  ;; selects formula material by its source rather than generated child IDs.
  (define manim-source
    (source-mapped-equation
     'manim-equation
     "a^2 + b^2 = c^2"
     (list (source-part 'a-square "a^2")
           (source-part 'plus "+")
           (source-part 'b-square "b^2")
           (source-part 'equals "=")
           (source-part 'c-square "c^2"))))
  (define manim-destination
    (source-mapped-equation
     'manim-equation
     "b^2 = c^2 - a^2"
     (list (source-part 'b-square "b^2")
           (source-part 'equals "=")
           (source-part 'c-square "c^2")
           (source-part 'minus "-")
           (source-part 'a-square "a^2"))))
  (check-equal?
   (formula-assembly-visual-part-names manim-source)
   '(a-square plus b-square equals c-square))
  (check-equal?
   (map (lambda (part)
          (string-trim (formula-visual-source (formula-part-formula part))))
        (formula-assembly-visual-parts manim-source))
   '("a^2" "+" "b^2" "=" "c^2"))

  (define manim-animated
    (scene-play
     (scene-add (make-scene) manim-source)
     (transform-matching-strings manim-source manim-destination)
     #:duration 2))
  (check-equal?
   (map (lambda (part)
          (string-trim (formula-visual-source (formula-part-formula part))))
        (formula-assembly-visual-parts
         (scene-state-ref (scene-current-state manim-animated)
                          'manim-equation)))
   '("b^2" "=" "c^2" "-" "a^2"))
  (check-true (pict? (scene->pict manim-animated 1)))

  ;; A selected source pair can use an arc without bending every matched term.
  ;; Both cross-fade layers occupy the same curved position at the midpoint.
  (define arced-manim
    (scene-play
     (scene-add (make-scene) manim-source)
     (transform-matching-strings
      manim-source
      manim-destination
      #:key-map
      (list
       (string-match "+" "-" #:route (formula-arc #:angle (/ pi 2)))))
     #:duration 2))
  (define arced-midpoint
    (scene-state-ref (scene-sample arced-manim 1) 'manim-equation))
  (define source-plus
    (formula-part-formula
     (for/first ([part (in-list (formula-assembly-visual-parts manim-source))]
                 #:when (string=? (string-trim
                                   (formula-visual-source
                                    (formula-part-formula part)))
                                  "+"))
       part)))
  (define destination-minus
    (formula-part-formula
     (for/first
         ([part (in-list (formula-assembly-visual-parts manim-destination))]
          #:when (string=? (string-trim
                            (formula-visual-source
                             (formula-part-formula part)))
                           "-"))
       part)))
  (define arced-plus
    (formula-part-formula
     (for/first ([part (in-list (formula-assembly-visual-parts arced-midpoint))]
                 #:when (string=? (string-trim
                                   (formula-visual-source
                                    (formula-part-formula part)))
                                  "+"))
       part)))
  (define arced-minus
    (formula-part-formula
     (for/first ([part (in-list (formula-assembly-visual-parts arced-midpoint))]
                 #:when (string=? (string-trim
                                   (formula-visual-source
                                    (formula-part-formula part)))
                                  "-"))
       part)))
  (check-equal? (visual-position arced-plus)
                (visual-position arced-minus))
  (check-true
   (> (abs
       (- (vec2-y (visual-position arced-plus))
          (vec2-y
           (vec2-lerp (visual-position source-plus)
                      (visual-position destination-minus)
                      1/2))))
      1/1000))

  ;; A global path arc is the concise source-matching form. It affects all matched
  ;; fragments, while unpaired source/destination fragments still fade in place.
  (define globally-arced-manim
    (scene-play
     (scene-add (make-scene) manim-source)
     (transform-matching-strings manim-source manim-destination
                                 #:path-arc (/ pi 2))
     #:duration 2))
  (define globally-arced-midpoint
    (scene-state-ref (scene-sample globally-arced-manim 1) 'manim-equation))
  (define source-a-square (formula-for-source manim-source "a^2"))
  (define destination-a-square (formula-for-source manim-destination "a^2"))
  (define arced-a-square
    (formula-for-source globally-arced-midpoint "a^2"))
  (check-true
   (> (abs
       (- (vec2-y (visual-position arced-a-square))
          (vec2-y
           (vec2-lerp (visual-position source-a-square)
                      (visual-position destination-a-square)
                      1/2))))
      1/1000))

  ;; `fade-transform` pairs unmatched pieces in source/destination order.
  ;; The unmatched + and - therefore share one travelling midpoint instead of
  ;; fading independently at their endpoint positions.
  (define mismatch-fade-transformed
    (scene-play
     (scene-add (make-scene) manim-source)
     (transform-matching-strings manim-source
                                 manim-destination
                                 #:mismatch-mode 'fade-transform)
     #:duration 2))
  (define mismatch-fade-transform-midpoint
    (scene-state-ref (scene-sample mismatch-fade-transformed 1)
                     'manim-equation))
  (define mismatch-fade-transform-plus
    (formula-for-source mismatch-fade-transform-midpoint "+"))
  (define mismatch-fade-transform-minus
    (formula-for-source mismatch-fade-transform-midpoint "-"))
  (check-equal? (visual-position mismatch-fade-transform-plus)
                (visual-position mismatch-fade-transform-minus))
  (check-equal?
   (visual-position mismatch-fade-transform-plus)
   (vec2-lerp (visual-position source-plus)
              (visual-position destination-minus)
              1/2))

  ;; `key-map` permits an explicit changed-term pairing without exposing
  ;; generated fragment names.
  (define mapped-source
    (source-mapped-equation
     'mapped
     "x = x"
     (list (source-part 'left-x (source-span 0 1))
           (source-part 'equals "=")
           (source-part 'right-x (source-span 4 5)))))
  (define mapped-destination
    (source-mapped-equation
     'mapped
     "y = y"
     (list (source-part 'left-y (source-span 0 1))
           (source-part 'equals "=")
           (source-part 'right-y (source-span 4 5)))))
  (check-true
   (transform-formula-parts-request?
    (transform-matching-strings mapped-source
                                mapped-destination
                                #:key-map (list (string-match "x" "y")))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (string-match 'x "y")))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (string-match "+" "-" #:route 'not-a-formula-arc)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-arc #:angle +inf.0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (transform-matching-strings manim-source
                                 manim-destination
                                 #:mismatch-mode 'transform)))

  ;; Ordinary token mapping gives short source atoms without author-supplied
  ;; part names.
  (define inline-group
    (math-tex #:id 'inline-group "x+y"))
  (check-equal?
   (map (lambda (part)
          (formula-visual-source (formula-part-formula part)))
        (formula-assembly-visual-parts inline-group))
   '("x" "+" "y"))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (tagged-formula #:id 'bad
                     (formula-fragment 'same "x")
                     (formula-fragment 'same "y")))))
