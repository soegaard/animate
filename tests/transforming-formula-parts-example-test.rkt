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

  ; equation-part-position : formula-assembly-visual? symbol? -> vec2?
  ;;   Returns the local position of one named rendered formula part.
  (define (equation-part-position equation name)
    (visual-position
     (formula-part-formula
      (formula-assembly-visual-ref equation name))))

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

  ;; Subtracting a squared keeps b squared, the equality sign, and c squared
  ;; fixed; only a squared crosses the equality and plus changes to minus.
  (for ([name (in-list '(b-square equals c-square))])
    (check-equal?
     (equation-part-position (equation-at 3) name)
     (equation-part-position (equation-at 5) name)))

  ;; The second transition swaps the sides without changing any term.
  (check-equal?
   (equation-sources (equation-at 8))
   '("c^2" "-" "a^2" "=" "b^2")))
