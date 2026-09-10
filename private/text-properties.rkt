#lang racket/base

;; Shared, renderer-independent vocabulary for concrete and semantic text.

(require "geometry.rkt")

(provide text-font-family?
         text-font-style?
         text-font-weight?
         text-line-alignment?
         text-horizontal-alignment?
         text-vertical-alignment?
         text-font-size?
         text-line-spacing?)

(define (text-font-family? value)
  (and (memq value '(default decorative roman script swiss modern symbol system)) #t))

(define (text-font-style? value)
  (and (memq value '(normal italic slant)) #t))

(define (text-font-weight? value)
  (and (memq value '(normal bold light)) #t))

(define (text-horizontal-alignment? value)
  (and (memq value '(left center right)) #t))

;; A paragraph's alignment for individual lines has the same portable domain
;; as an x-axis text anchor, but remains a separately named predicate so style
;; validation and documentation cannot accidentally conflate the two.
(define (text-line-alignment? value)
  (text-horizontal-alignment? value))

(define (text-vertical-alignment? value)
  (and (memq value '(top center baseline bottom)) #t))

(define (text-font-size? value)
  (and (finite-real? value) (positive? value)))

(define (text-line-spacing? value)
  (text-font-size? value))
