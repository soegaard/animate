#lang racket/base

;;;
;;; Exact Dyadic Parameter Coordinates
;;;

(require "surface-provenance3d.rkt")

(provide dyadic-coordinate->real
         dyadic-coordinate-midpoint
         dyadic-coordinate-compare
         uv-key->pair
         make-uv-key)

; dyadic-coordinate->real : dyadic-coordinate? -> exact-rational?
;; Converts only at evaluator boundaries; keys themselves remain exact.
(define (dyadic-coordinate->real value)
  (unless (dyadic-coordinate? value)
    (raise-argument-error 'dyadic-coordinate->real "dyadic-coordinate?" value))
  (/ (dyadic-coordinate-numerator value)
     (expt 2 (dyadic-coordinate-level value))))

(define (dyadic-coordinate-midpoint first second)
  (unless (and (dyadic-coordinate? first) (dyadic-coordinate? second))
    (raise-argument-error 'dyadic-coordinate-midpoint "two dyadic-coordinate values"
                          (list first second)))
  (define level (max (dyadic-coordinate-level first) (dyadic-coordinate-level second)))
  (define first-numerator
    (* (dyadic-coordinate-numerator first)
       (expt 2 (- level (dyadic-coordinate-level first)))))
  (define second-numerator
    (* (dyadic-coordinate-numerator second)
       (expt 2 (- level (dyadic-coordinate-level second)))))
  (dyadic-coordinate (+ first-numerator second-numerator) (add1 level)))

(define (dyadic-coordinate-compare first second)
  (define difference (- (dyadic-coordinate->real first)
                        (dyadic-coordinate->real second)))
  (cond [(negative? difference) -1] [(positive? difference) 1] [else 0]))

(define (uv-key->pair key)
  (unless (uv-key? key)
    (raise-argument-error 'uv-key->pair "uv-key?" key))
  (cons (dyadic-coordinate->real (uv-key-u key))
        (dyadic-coordinate->real (uv-key-v key))))

(define (make-uv-key u-numerator u-level v-numerator v-level)
  (uv-key (dyadic-coordinate u-numerator u-level)
          (dyadic-coordinate v-numerator v-level)))
