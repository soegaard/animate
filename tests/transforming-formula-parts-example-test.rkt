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

  ;; After the entrance, the source is the Pythagorean equation.
  (check-equal?
   (equation-sources (equation-at 2))
   '("a^2" "+" "b^2" "=" "c^2"))

  ;; The first transition subtracts a squared from both sides.
  (check-equal?
   (equation-sources (equation-at 4))
   '("b^2" "=" "c^2" "-" "a^2"))

  ;; The second transition swaps the sides without changing any term.
  (check-equal?
   (equation-sources (equation-at 6))
   '("c^2" "-" "a^2" "=" "b^2")))
