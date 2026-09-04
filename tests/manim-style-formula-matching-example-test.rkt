#lang racket/base

;; Construction coverage for the source-addressed formula-matching demo.

(require rackunit
         racket/string
         "../main.rkt"
         "../examples/manim-style-formula-matching.rkt")

(define (formula-sources scene time)
  (map (lambda (part)
         (string-trim (formula-visual-source (formula-part-formula part))))
       (formula-assembly-visual-parts
        (scene-visual-at scene 'equation time))))

(define (equals-position scene time)
  (for/first ([part
               (in-list
                (formula-assembly-visual-parts
                 (scene-visual-at scene 'equation time)))]
              #:when (string=? (string-trim
                                 (formula-visual-source
                                  (formula-part-formula part)))
                               "="))
    (visual-position (formula-part-formula part))))

(module+ test
  (define demo (make-demo-scene))
  (check-equal?
   (formula-sources demo 0)
   '("a^2" "+" "b^2" "=" "c^2"))
  (check-equal?
   (formula-sources demo 3)
   '("b^2" "=" "c^2" "-" "a^2"))
  (check-equal?
   (formula-sources demo 6)
   '("c^2" "-" "a^2" "=" "b^2"))
  (check-equal? (equals-position demo 3)
                (equals-position demo 0))
  (check-equal? (equals-position demo 6)
                (equals-position demo 0)))
