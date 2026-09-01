#lang racket/base

;;;
;;; Transforming Formula Parts Example Regression Tests
;;;

;; Checks the two mathematically motivated equation endpoints in the example.


;;;
;;; Imports
;;;

(require rackunit
         "../examples/transforming-formula-parts.rkt"
         "../main.rkt")


(module+ test
  ; demo : scene?
  ;;   Gives the canonical two-step equation transformation.
  (define demo
    (make-demo-scene))

  ; equation-at : nonnegative-real? -> formula-assembly-visual?
  ;;   Returns the stable equation assembly at one clip endpoint.
  (define (equation-at time)
    (scene-state-ref (scene-sample demo time) 'equation))

  ; equation-sources : formula-assembly-visual? -> (listof string?)
  ;;   Reports formula source strings in their visible left-to-right order.
  (define (equation-sources equation)
    (for/list ([part (in-list (formula-assembly-visual-parts equation))])
      (formula-visual-source (formula-part-formula part))))

  ;; The source equation holds for one second before the first transition.
  (check-equal?
   (equation-sources (equation-at 2))
   '("a^2" "+" "b^2" "=" "c^2"))
  (check-equal?
   (equation-sources (equation-at 3))
   '("a^2" "+" "b^2" "=" "c^2"))

  ;; The rearranged equation likewise holds before its side swap.
  (check-equal?
   (equation-sources (equation-at 5))
   '("b^2" "=" "c^2" "-" "a^2"))
  (check-equal?
   (equation-sources (equation-at 6))
   '("b^2" "=" "c^2" "-" "a^2"))

  ;; The second transition swaps the sides without changing any term.
  (check-equal?
   (equation-sources (equation-at 8))
   '("c^2" "-" "a^2" "=" "b^2")))
