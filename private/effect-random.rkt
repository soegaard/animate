#lang racket/base

;;;
;;; Deterministic Effect Randomness
;;;

;; A deliberately small, pure pseudo-random source for visual-effect plans.
;; The public effects that use it retain their generated values, so sampling a
;; frame never consumes global random state or depends on earlier samples.

(provide deterministic-effect-real)

(define effect-random-modulus 2147483648)
(define effect-random-multiplier 1103515245)
(define effect-random-increment 12345)

; deterministic-effect-real : exact-integer? exact-nonnegative-integer?
;                             exact-integer? -> unit-real?
;; Produces one reproducible pseudo-random value from independent plan
;; coordinates. `index` and `salt` make the call order irrelevant.
(define (deterministic-effect-real seed index salt)
  (define state
    (modulo (+ seed (* 1103515245 index) (* 12345 salt))
            effect-random-modulus))
  (/ (modulo (+ (* effect-random-multiplier state)
                effect-random-increment)
             effect-random-modulus)
     effect-random-modulus))
