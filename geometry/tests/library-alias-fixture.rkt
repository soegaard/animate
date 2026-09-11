#lang racket/base

;; Both identifiers resolve to the same exported binding but have distinct
;; printed names in the DSL datum. Neither spelling may be dropped.
(require "../core.rkt"
         (prefix-in one: "../constructions.rkt")
         (prefix-in two: "../constructions.rkt"))
(provide two-prefixes)
(construction two-prefixes
  (given [A (point -2 0)] [B (point 2 0)] [C (point 1 3)])
  (step [m (one:perpendicular-bisector A B)]
        [n (two:perpendicular-bisector B C)])
  (step [O (intersection m n)])
  (assert (equal-length (segment O A) (segment O B) (segment O C)))
  (result m n O))
