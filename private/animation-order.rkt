#lang racket/base

;;;
;;; Immutable animation ordering policies
;;;

;; Order values contain only transparent immutable data. In particular,
;; shuffled orders never retain a random generator or depend on global state.

(require racket/list
         "effect-random.rkt")

(provide animation-order?
         forward-order
         forward-order?
         reverse-order
         reverse-order?
         permutation-order
         permutation-order?
         shuffled-order
         shuffled-order?
         resolve-animation-order)

(struct forward-order-value () #:transparent)
(struct reverse-order-value () #:transparent)
(struct permutation-order-value (indices) #:transparent)
(struct shuffled-order-value (seed) #:transparent)

(define (animation-order? value)
  (or (forward-order-value? value)
      (reverse-order-value? value)
      (permutation-order-value? value)
      (shuffled-order-value? value)))

(define forward-order? forward-order-value?)
(define reverse-order? reverse-order-value?)
(define permutation-order? permutation-order-value?)
(define shuffled-order? shuffled-order-value?)

(define (forward-order) (forward-order-value))
(define (reverse-order) (reverse-order-value))

;; permutation-order validates the intrinsic part of a permutation now. Its
;; count-relative requirement (exactly 0 through n-1) is checked on resolution.
(define (permutation-order indices)
  (unless (or (list? indices) (vector? indices))
    (raise-argument-error 'permutation-order "list? or vector?" indices))
  (define copied
    (vector->immutable-vector
     (if (vector? indices) indices (list->vector indices))))
  (unless (andmap exact-nonnegative-integer? (vector->list copied))
    (raise-argument-error
     'permutation-order
     "list/vector of exact nonnegative integers"
     indices))
  (define duplicate
    (find-duplicate (vector->list copied)))
  (when duplicate
    (raise-arguments-error
     'permutation-order
     "a permutation without duplicate indices"
     "duplicate-index" duplicate
     "indices" indices))
  (permutation-order-value copied))

(define (shuffled-order #:seed [seed 0])
  (unless (exact-integer? seed)
    (raise-argument-error 'shuffled-order "exact integer" seed))
  (shuffled-order-value seed))

;; resolve-animation-order : animation-order? exact-nonnegative-integer?
;;                            -> immutable-vector?
(define (resolve-animation-order order count)
  (unless (animation-order? order)
    (raise-argument-error 'resolve-animation-order "animation-order?" order))
  (unless (exact-nonnegative-integer? count)
    (raise-argument-error
     'resolve-animation-order "exact nonnegative integer" count))
  (cond
    [(forward-order-value? order)
     (vector->immutable-vector (list->vector (range count)))]
    [(reverse-order-value? order)
     (vector->immutable-vector (list->vector (reverse (range count))))]
    [(permutation-order-value? order)
     (define indices (permutation-order-value-indices order))
     (unless (= (vector-length indices) count)
       (raise-arguments-error
        'resolve-animation-order
        "a permutation with exactly one index for every target"
        "count" count
        "indices" indices))
     (unless (for/and ([index (in-vector indices)]) (< index count))
       (raise-arguments-error
        'resolve-animation-order
        "a permutation whose indices are in range"
        "count" count
        "indices" indices))
     indices]
    [else
     (deterministic-shuffle count (shuffled-order-value-seed order))]))

(define (deterministic-shuffle count seed)
  (define mutable (list->vector (range count)))
  (let loop ([index (sub1 count)])
    (if (positive? index)
        (let* ([swap-index
                (effect-random-bounded-integer
                 current-effect-random-plan-version seed 'animation-order
                 index 'shuffle-swap (add1 index))]
               [saved (vector-ref mutable index)])
          (vector-set! mutable index (vector-ref mutable swap-index))
          (vector-set! mutable swap-index saved)
          (loop (sub1 index)))
        (vector->immutable-vector mutable))))

(define (find-duplicate values)
  (let loop ([remaining values] [seen (hash)])
    (cond
      [(null? remaining) #f]
      [(hash-has-key? seen (car remaining)) (car remaining)]
      [else (loop (cdr remaining) (hash-set seen (car remaining) #t))])))
