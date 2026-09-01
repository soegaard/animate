#lang racket/base

;;;
;;; Geometry
;;;

;; Defines finite two-dimensional coordinates and interpolation operations.
;;
;; This module contains only immutable mathematical values and pure functions.


;;;
;;; Imports and Exports
;;;

;; Exports
(provide (struct-out vec2)
         finite-real?
         origin
         vec2+
         vec2-
         real-lerp
         vec2-scale
         vec2*
         vec2-lerp)


;;;
;;; Data Representation
;;;

(struct vec2 (x y)
  #:transparent
  #:guard
  (lambda (x y who)
    (unless (finite-real? x)
      (raise-argument-error who "finite real?" x))
    (unless (finite-real? y)
      (raise-argument-error who "finite real?" y))
    (values x y)))

;; vec2 represents a point or displacement in mathematical world coordinates.
;;  - x  finite-real?  horizontal component.
;;  - y  finite-real?  vertical component.


;;;
;;; Predicates
;;;

; finite-real? : any/c -> boolean?
;;   Reports whether value is a finite real number.
(define (finite-real? value)
  (and (real? value)
       (rational? value)))


;;;
;;; Constants
;;;

; origin : vec2?
;;   Gives the origin of world coordinates.
(define origin
  (vec2 0 0))


;;;
;;; Scalar Interpolation
;;;

; real-lerp : finite-real? finite-real? finite-real? -> finite-real?
;;   Interpolates linearly from from to to by progress.
(define (real-lerp from to progress)
  (unless (finite-real? from)
    (raise-argument-error 'real-lerp "finite real?" from))
  (unless (finite-real? to)
    (raise-argument-error 'real-lerp "finite real?" to))
  (unless (finite-real? progress)
    (raise-argument-error 'real-lerp "finite real?" progress))
  (+ from (* progress (- to from))))


;;;
;;; Vector Operations
;;;

; vec2+ : vec2? vec2? -> vec2?
;;   Returns the componentwise sum of a and b.
(define (vec2+ a b)
  (check-vec2 'vec2+ a)
  (check-vec2 'vec2+ b)
  (vec2 (+ (vec2-x a) (vec2-x b))
        (+ (vec2-y a) (vec2-y b))))

; vec2- : vec2? vec2? -> vec2?
;;   Returns the componentwise difference of a and b.
(define (vec2- a b)
  (check-vec2 'vec2- a)
  (check-vec2 'vec2- b)
  (vec2 (- (vec2-x a) (vec2-x b))
        (- (vec2-y a) (vec2-y b))))

; vec2-scale : finite-real? vec2? -> vec2?
;;   Scales value by scalar.
(define (vec2-scale scalar value)
  (unless (finite-real? scalar)
    (raise-argument-error 'vec2-scale "finite real?" scalar))
  (check-vec2 'vec2-scale value)
  (vec2 (* scalar (vec2-x value))
        (* scalar (vec2-y value))))

; vec2* : vec2? vec2? -> vec2?
;;   Returns the componentwise product of a and b.
(define (vec2* a b)
  (check-vec2 'vec2* a)
  (check-vec2 'vec2* b)
  (vec2 (* (vec2-x a) (vec2-x b))
        (* (vec2-y a) (vec2-y b))))

; vec2-lerp : vec2? vec2? finite-real? -> vec2?
;;   Interpolates linearly from from to to by progress.
(define (vec2-lerp from to progress)
  (check-vec2 'vec2-lerp from)
  (check-vec2 'vec2-lerp to)
  (unless (finite-real? progress)
    (raise-argument-error 'vec2-lerp "finite real?" progress))
  (vec2 (real-lerp (vec2-x from) (vec2-x to) progress)
        (real-lerp (vec2-y from) (vec2-y to) progress)))


;;;
;;; Validation
;;;

; check-vec2 : symbol? any/c -> void?
;;   Raises an argument error unless value is a vec2.
(define (check-vec2 who value)
  (unless (vec2? value)
    (raise-argument-error who "vec2?" value)))
