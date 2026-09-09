#lang racket/base

;;;
;;; FX-E0 Immutable Animation Order Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (check-true (animation-order? (forward-order)))
  (check-true (forward-order? (forward-order)))
  (check-true (reverse-order? (reverse-order)))
  (check-equal? (resolve-animation-order (forward-order) 0) '#())
  (check-equal? (resolve-animation-order (forward-order) 4) '#(0 1 2 3))
  (check-equal? (resolve-animation-order (reverse-order) 4) '#(3 2 1 0))

  ;; A permutation's immutable indices can be reused with a matching count and
  ;; rejects every count-relative violation deterministically.
  (define permuted (permutation-order #(2 0 1)))
  (check-true (permutation-order? permuted))
  (check-equal? (resolve-animation-order permuted 3) '#(2 0 1))
  (check-exn exn:fail:contract? (lambda () (resolve-animation-order permuted 2)))
  (check-exn exn:fail:contract? (lambda () (permutation-order '(0 1 1))))
  (check-exn exn:fail:contract?
             (lambda () (resolve-animation-order (permutation-order '(0 1 3)) 3)))

  ;; Shuffles are derived only from their transparent seed and target count.
  (define seed-a (shuffled-order #:seed 17))
  (define seed-b (shuffled-order #:seed 18))
  (check-true (shuffled-order? seed-a))
  (check-equal? seed-a (shuffled-order #:seed 17))
  (check-equal? (resolve-animation-order seed-a 8)
                (resolve-animation-order seed-a 8))
  (check-not-equal? (resolve-animation-order seed-a 8)
                    (resolve-animation-order seed-b 8))
  (check-equal? (sort (vector->list (resolve-animation-order seed-a 8)) <)
                '(0 1 2 3 4 5 6 7))
  (check-exn exn:fail:contract? (lambda () (shuffled-order #:seed 1/2))))
