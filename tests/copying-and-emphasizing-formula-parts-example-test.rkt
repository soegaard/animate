#lang racket/base

;; Construction coverage for the source-preserving algebra example.

(require rackunit
         "../main.rkt"
         "../examples/copying-and-emphasizing-formula-parts.rkt")

(define (formula-at scene time)
  (scene-visual-at scene 'equation time))

(define (formula-sources scene time)
  (map (lambda (part)
         (formula-visual-source (formula-part-formula part)))
       (formula-assembly-visual-parts (formula-at scene time))))

(define (equals-position scene time)
  (visual-position
   (formula-part-formula
    (for/first ([part (in-list (formula-assembly-visual-parts
                                (formula-at scene time)))]
                #:when (string=? (formula-visual-source
                                  (formula-part-formula part))
                                 "="))
      part))))

(module+ test
  (define demo (make-demo-scene))
  (check-equal? (formula-sources demo 0) '("x" "=" "2"))
  (check-equal? (formula-sources demo 7) '("x" "+" "x" "=" "2" "+" "x"))
  (check-equal? (equals-position demo 0) (equals-position demo 7))
  ;; The operation midpoint contains the ordinary transformed source x and
  ;; two independently travelling copies.
  (check-equal?
   (length (filter (lambda (source) (string=? source "x"))
                   (formula-sources demo 6)))
   3)
  ;; Temporary attention overlays disappear at their clip boundaries.
  (check-equal? (scene-state-count (scene-sample demo 13/4)) 6)
  (check-equal? (scene-state-count (scene-sample demo 9/2)) 6))
