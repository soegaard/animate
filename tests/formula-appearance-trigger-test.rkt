#lang racket/base

;;;
;;; Changed Formula-Part Appearance Deadlines
;;;

(require (only-in racket/math pi)
         rackunit
         "../main.rkt"
         "../private/formula-part-transition.rkt")

(define (part name source center)
  (formula-part
   name
   (latex-formula source #:id name #:center center #:font-size 1/2)))

(define (part-with-source parts source)
  (for/first ([part (in-list parts)]
              #:when (string=? (formula-visual-source (formula-part-formula part))
                               source))
    part))

(module+ test
  ;; The + moves on a semicircle exactly as it would without the trigger. Its
  ;; visual replacement alone uses the short [3/8, 1/2] interval, ending when
  ;; that unchanged path crosses the = part's x-coordinate.
  (define source
    (formula-assembly
     (list (part 'plus "+" (vec2 -1 0))
           (part 'equals "=" origin))
     #:id 'equation))
  (define destination
    (formula-assembly
     (list (part 'minus "-" (vec2 1 0))
           (part 'equals "=" origin))
     #:id 'equation))
  (define plan
    (make-formula-transition-plan
     source
     (formula-correspondence
      source destination
      (list (formula-part-match 'plus 'minus)
            (formula-part-match 'equals 'equals)))
     #:part-paths
     (list (formula-part-path 'plus 'minus (formula-arc #:angle pi)))
     #:appearance-triggers
     (list (formula-part-appearance-trigger 'plus 'minus 'equals 1/8))))

  (define before-change
    (formula-transition-plan-sample-parts plan 3/8))
  (check-equal?
   (visual-opacity (formula-part-formula (part-with-source before-change "+")))
   1)
  (check-equal?
   (visual-opacity (formula-part-formula (part-with-source before-change "-")))
   0)

  (define during-change
    (formula-transition-plan-sample-parts plan 7/16))
  (check-= (visual-opacity
            (formula-part-formula (part-with-source during-change "+")))
           1/2
           1e-8)
  (check-= (visual-opacity
            (formula-part-formula (part-with-source during-change "-")))
           1/2
           1e-8)

  (define complete-change
    (formula-transition-plan-sample-parts plan 1/2))
  (define minus
    (formula-part-formula (part-with-source complete-change "-")))
  (define equals
    (formula-part-formula (part-with-source complete-change "=")))
  (check-equal? (visual-opacity minus) 1)
  (check-= (vec2-x (visual-position minus))
           (vec2-x (visual-position equals))
           1e-8))
