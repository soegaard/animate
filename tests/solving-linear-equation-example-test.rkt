#lang racket/base

;; End-to-end coverage for the SCENE-BX anchored rewrite example.

(require rackunit
         "../main.rkt"
         "../examples/solving-linear-equation.rkt")

(define (formula-sources scene time)
  (map (lambda (part)
         (formula-visual-source (formula-part-formula part)))
       (formula-assembly-visual-parts
        (scene-visual-at scene 'equation time))))

(define (equals-position scene time)
  (visual-position
   (formula-part-formula
    (for/first ([part (in-list (formula-assembly-visual-parts
                                (scene-visual-at scene 'equation time)))]
                #:when (string=? (formula-visual-source
                                  (formula-part-formula part))
                                 "="))
      part))))

(module+ test
  (define demo (make-demo-scene))
  (define endpoints '(0 5/2 9/2 7 19/2))
  (define fixed-equals (equals-position demo 0))
  (for ([time (in-list endpoints)])
    (define current-equals (equals-position demo time))
    (check-= (vec2-x current-equals) (vec2-x fixed-equals) 1e-12)
    (check-= (vec2-y current-equals) (vec2-y fixed-equals) 1e-12))
  (check-equal? (formula-sources demo 0) '("2x" "+" "1" "=" "5"))
  (check-equal? (formula-sources demo 5/2) '("2x" "=" "5" "-" "1"))
  (check-equal? (formula-sources demo 9/2) '("2x" "=" "4"))
  (check-equal? (formula-sources demo 7)
                '("\\frac{2x}{2}" "=" "\\frac{4}{2}"))
  (check-equal? (formula-sources demo 19/2) '("x" "=" "2")))
