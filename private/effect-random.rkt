#lang racket/base

;;;
;;; Keyed deterministic effect randomness
;;;

;; Effect plans must be reproducible without touching Racket's process-global
;; generator. The coordinates below are named rather than positional: adding
;; a new particle property cannot perturb the x/y/rotation plans already
;; published for an effect.

(require racket/format)

(provide current-effect-random-plan-version
         effect-random-u64
         effect-random-unit-real
         effect-random-bounded-integer
         deterministic-effect-real)

(define current-effect-random-plan-version 1)
(define u64-modulus (arithmetic-shift 1 64))
(define u64-mask (sub1 u64-modulus))

(define (u64 value)
  (bitwise-and value u64-mask))

;; SplitMix64's public-domain finalizer. All arithmetic is explicitly reduced
;; to 64 bits, so the result is independent of host word size.
(define (mix-u64 value)
  (define first (u64 (bitwise-xor value (arithmetic-shift value -30))))
  (define second (u64 (* first #xbf58476d1ce4e5b9)))
  (define third (u64 (bitwise-xor second (arithmetic-shift second -27))))
  (define fourth (u64 (* third #x94d049bb133111eb)))
  (u64 (bitwise-xor fourth (arithmetic-shift fourth -31))))

;; A fixed FNV-1a pass converts a semantic key to one word. `~s` is used only
;; for immutable request-plan data (symbols, strings, integers, lists); it is
;; intentionally not applied to procedures or renderer objects.
(define (stable-key-u64 key)
  (define bytes (string->bytes/utf-8 (~s key)))
  (for/fold ([hash #xcbf29ce484222325])
            ([byte (in-bytes bytes)])
    (u64 (* (bitwise-xor hash byte) #x100000001b3))))

(define (check-plan-coordinate who version seed effect-kind item-index property-key)
  (unless (exact-nonnegative-integer? version)
    (raise-argument-error who "exact nonnegative integer as random-plan version" version))
  (unless (exact-integer? seed)
    (raise-argument-error who "exact integer as seed" seed))
  (unless (exact-nonnegative-integer? item-index)
    (raise-argument-error who "exact nonnegative integer as item index" item-index))
  (unless (or (symbol? effect-kind) (string? effect-kind))
    (raise-argument-error who "symbol? or string? as effect kind" effect-kind))
  (unless (or (symbol? property-key) (string? property-key)
              (exact-integer? property-key) (pair? property-key))
    (raise-argument-error who "immutable random property key" property-key)))

;; effect-random-u64 : exact-nonnegative-integer? exact-integer?
;;                     (or/c symbol? string?) exact-nonnegative-integer? any/c
;;                     -> exact-nonnegative-integer?
(define (effect-random-u64 version seed effect-kind item-index property-key)
  (check-plan-coordinate 'effect-random-u64
                         version seed effect-kind item-index property-key)
  (for/fold ([state (mix-u64 (u64 seed))])
            ([coordinate (in-list (list version effect-kind item-index property-key))])
    (mix-u64 (bitwise-xor state (stable-key-u64 coordinate)))))

;; effect-random-unit-real : ... -> exact rational in [0, 1)
(define (effect-random-unit-real version seed effect-kind item-index property-key)
  (/ (effect-random-u64 version seed effect-kind item-index property-key)
     u64-modulus))

;; Rejection sampling avoids the modulo bias that is visible in small palette
;; and Fisher--Yates selections. The retry coordinate remains entirely local
;; to this one named property.
(define (effect-random-bounded-integer version seed effect-kind item-index
                                       property-key bound)
  (unless (exact-positive-integer? bound)
    (raise-argument-error 'effect-random-bounded-integer
                          "exact positive integer" bound))
  (define accepted-limit (- u64-modulus (modulo u64-modulus bound)))
  (let loop ([attempt 0])
    (define candidate
      (effect-random-u64 version seed effect-kind item-index
                         (list property-key 'retry attempt)))
    (if (< candidate accepted-limit)
        (modulo candidate bound)
        (loop (add1 attempt)))))

;; Compatibility for already internal callers. New code should use one of the
;; named APIs above; `salt` is deliberately embedded in a labelled key.
(define (deterministic-effect-real seed index salt)
  (effect-random-unit-real current-effect-random-plan-version
                           seed 'legacy-effect index (list 'legacy-salt salt)))
