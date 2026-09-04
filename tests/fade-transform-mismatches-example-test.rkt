#lang racket/base

;; Construction coverage for the fade-transform equation-reduction example.

(require rackunit
         racket/string
         "../main.rkt"
         "../examples/fade-transform-mismatches.rkt")

(define (formula-sources scene time)
  (map (lambda (part)
         (string-trim (formula-visual-source (formula-part-formula part))))
       (formula-assembly-visual-parts
        (scene-visual-at scene 'equation time))))

(define (formula-for-source scene time source)
  (formula-part-formula
   (for/first ([part
                (in-list
                 (formula-assembly-visual-parts
                  (scene-visual-at scene 'equation time)))]
               #:when (string=? (string-trim
                                 (formula-visual-source
                                  (formula-part-formula part)))
                                source))
     part)))

(define (equals-position scene time)
  (visual-position (formula-for-source scene time "=")))

(module+ test
  (define demo (make-demo-scene))
  (check-equal? (formula-sources demo 0)
                '("\\frac{6x}{3}" "=" "4"))
  (check-equal? (formula-sources demo 3)
                '("2x" "=" "4"))
  (check-equal? (formula-sources demo 6)
                '("\\frac{2x}{2}" "=" "\\frac{4}{2}"))
  (check-equal? (formula-sources demo 9)
                '("x" "=" "2"))
  (check-equal? (equals-position demo 3)
                (equals-position demo 0))
  (check-equal? (equals-position demo 6)
                (equals-position demo 0))
  (check-equal? (equals-position demo 9)
                (equals-position demo 0))

  ;; At each simplification midpoint, the before and after fragments occupy
  ;; one shared position: they are a moving fade-transform pair, not two
  ;; independent endpoint fades.
  (define first-fraction (formula-for-source demo 0 "\\frac{6x}{3}"))
  (define first-reduction (formula-for-source demo 3 "2x"))
  (define first-midpoint-source
    (formula-for-source demo 2 "\\frac{6x}{3}"))
  (define first-midpoint-destination
    (formula-for-source demo 2 "2x"))
  (check-equal? (visual-position first-midpoint-source)
                (visual-position first-midpoint-destination))
  (check-equal?
   (visual-position first-midpoint-source)
   (vec2-lerp (visual-position first-fraction)
              (visual-position first-reduction)
              1/2))

  (define second-left-fraction (formula-for-source demo 6 "\\frac{2x}{2}"))
  (define second-reduction (formula-for-source demo 9 "x"))
  (define second-midpoint-source
    (formula-for-source demo 8 "\\frac{2x}{2}"))
  (define second-midpoint-destination
    (formula-for-source demo 8 "x"))
  (check-equal? (visual-position second-midpoint-source)
                (visual-position second-midpoint-destination))
  (check-equal?
   (visual-position second-midpoint-source)
   (vec2-lerp (visual-position second-left-fraction)
              (visual-position second-reduction)
              1/2)))
