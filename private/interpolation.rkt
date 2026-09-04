#lang racket/base

;;;
;;; Semantic Value Interpolation
;;;

;; Defines the small common interpolation protocol used by named scene values.
;; Values deliberately stay renderer-independent: currently finite reals, vec2
;; coordinates, finite complex values, and semantic RGBA colors participate.  New semantic value kinds
;; can be added here without changing scene-state or timeline scheduling.


;;;
;;; Imports and Exports
;;;

(require "color-style.rkt"
         "geometry.rkt")

(provide finite-complex?
         interpolable?
         interpolate-value)


;;;
;;; Protocol
;;;

; interpolable? : any/c -> boolean?
;; Reports whether value is a semantic value supported by interpolate-value.
(define (interpolable? value)
  (or (finite-real? value)
      (finite-complex? value)
      (vec2? value)
      (rgba-color? value)))

; interpolate-value : interpolable? interpolable? finite-real? -> interpolable?
;; Interpolates two semantic values of the same kind over the closed unit
;; interval. Exact endpoints preserve the original semantic values.
(define (interpolate-value from to progress)
  (unless (interpolable? from)
    (raise-argument-error 'interpolate-value "interpolable?" from))
  (unless (interpolable? to)
    (raise-argument-error 'interpolate-value "interpolable?" to))
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'interpolate-value
     "finite real in [0, 1]"
     progress))
  (cond
    [(and (finite-real? from) (finite-real? to))
     (interpolate-endpoints from to progress real-lerp)]
    [(and (finite-complex? from) (finite-complex? to))
     (interpolate-endpoints from to progress complex-lerp)]
    [(and (vec2? from) (vec2? to))
     (interpolate-endpoints from to progress vec2-lerp)]
    [(and (rgba-color? from) (rgba-color? to))
     (interpolate-endpoints from to progress rgba-color-lerp)]
    [else
     (raise-arguments-error
      'interpolate-value
      "the values must have the same interpolable semantic kind"
      "from" from
      "to" to)]))

;; finite-complex? : any/c -> boolean?
;; A complex scene value is finite only when both cartesian components are
;; finite reals. Real numbers are handled by finite-real? before this case.
(define (finite-complex? value)
  (and (number? value)
       (not (real? value))
       (finite-real? (real-part value))
       (finite-real? (imag-part value))))

;; complex-lerp : finite-complex? finite-complex? finite-real? -> complex?
;; Interpolates real and imaginary coordinates independently.
(define (complex-lerp from to progress)
  (make-rectangular
   (real-lerp (real-part from) (real-part to) progress)
   (real-lerp (imag-part from) (imag-part to) progress)))

; interpolate-endpoints : any/c any/c finite-real? procedure? -> any/c
;; Keeps a caller's endpoint representation intact instead of reconstructing it.
(define (interpolate-endpoints from to progress interpolate)
  (cond
    [(zero? progress)
     from]
    [(= progress 1)
     to]
    [else
     (interpolate from to progress)]))
