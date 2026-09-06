#lang racket/base

;;;
;;; Three-Dimensional Vectors
;;;

;; Defines immutable finite three-dimensional points and displacement vectors
;; in Animate's right-handed spatial coordinate system. This pure model module
;; has no rendering, GUI, filesystem, or process dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../geometry.rkt")

;; Exports
(provide (struct-out vec3)
         origin3
         x-axis3
         y-axis3
         z-axis3
         vec3+
         vec3-
         vec3*
         vec3-scale
         vec3-dot
         vec3-cross
         vec3-length
         vec3-distance
         vec3-normalize
         vec3-lerp
         vec3-finite?)


;;;
;;; Data Representation
;;;

(struct vec3 (x y z)
  #:transparent
  #:guard
  (lambda (x y z who)
    (for ([component (in-list (list x y z))])
      (unless (finite-real? component)
        (raise-argument-error who "finite real?" component)))
    (values x y z)))

;; vec3 represents a point or displacement in right-handed world coordinates.
;;  - x  finite-real?  component increasing to the mathematical right.
;;  - y  finite-real?  component increasing upward.
;;  - z  finite-real?  component increasing out of the screen toward a viewer.


;;;
;;; Constants
;;;

; origin3 : vec3?
;;   Gives the origin of spatial world coordinates.
(define origin3
  (vec3 0 0 0))

; x-axis3 : vec3?
;;   Gives the positive x unit displacement.
(define x-axis3
  (vec3 1 0 0))

; y-axis3 : vec3?
;;   Gives the positive y unit displacement.
(define y-axis3
  (vec3 0 1 0))

; z-axis3 : vec3?
;;   Gives the positive z unit displacement, toward a conventional viewer.
(define z-axis3
  (vec3 0 0 1))


;;;
;;; Vector Operations
;;;

; vec3+ : vec3? vec3? -> vec3?
;;   Returns the componentwise sum of first and second.
(define (vec3+ first second)
  (check-vec3 'vec3+ first)
  (check-vec3 'vec3+ second)
  (vec3 (+ (vec3-x first) (vec3-x second))
        (+ (vec3-y first) (vec3-y second))
        (+ (vec3-z first) (vec3-z second))))

; vec3- : vec3? vec3? -> vec3?
;;   Returns the componentwise difference of first and second.
(define (vec3- first second)
  (check-vec3 'vec3- first)
  (check-vec3 'vec3- second)
  (vec3 (- (vec3-x first) (vec3-x second))
        (- (vec3-y first) (vec3-y second))
        (- (vec3-z first) (vec3-z second))))

; vec3* : vec3? vec3? -> vec3?
;;   Returns the componentwise product of first and second.
(define (vec3* first second)
  (check-vec3 'vec3* first)
  (check-vec3 'vec3* second)
  (vec3 (* (vec3-x first) (vec3-x second))
        (* (vec3-y first) (vec3-y second))
        (* (vec3-z first) (vec3-z second))))

; vec3-scale : finite-real? vec3? -> vec3?
;;   Multiplies every component of value by scalar.
(define (vec3-scale scalar value)
  (unless (finite-real? scalar)
    (raise-argument-error 'vec3-scale "finite real?" scalar))
  (check-vec3 'vec3-scale value)
  (vec3 (* scalar (vec3-x value))
        (* scalar (vec3-y value))
        (* scalar (vec3-z value))))

; vec3-dot : vec3? vec3? -> finite-real?
;;   Returns the Euclidean dot product of first and second.
(define (vec3-dot first second)
  (check-vec3 'vec3-dot first)
  (check-vec3 'vec3-dot second)
  (+ (* (vec3-x first) (vec3-x second))
     (* (vec3-y first) (vec3-y second))
     (* (vec3-z first) (vec3-z second))))

; vec3-cross : vec3? vec3? -> vec3?
;;   Returns first × second using Animate's right-handed basis.
(define (vec3-cross first second)
  (check-vec3 'vec3-cross first)
  (check-vec3 'vec3-cross second)
  (vec3 (- (* (vec3-y first) (vec3-z second))
           (* (vec3-z first) (vec3-y second)))
        (- (* (vec3-z first) (vec3-x second))
           (* (vec3-x first) (vec3-z second)))
        (- (* (vec3-x first) (vec3-y second))
           (* (vec3-y first) (vec3-x second)))))

; vec3-length : vec3? -> nonnegative-real?
;;   Returns the Euclidean length of value.
(define (vec3-length value)
  (check-vec3 'vec3-length value)
  (sqrt (vec3-dot value value)))

; vec3-distance : vec3? vec3? -> nonnegative-real?
;;   Returns the Euclidean distance between first and second.
(define (vec3-distance first second)
  (vec3-length (vec3- first second)))

; vec3-normalize : vec3? -> vec3?
;;   Returns an inexact unit vector in value's direction.
(define (vec3-normalize value)
  (check-vec3 'vec3-normalize value)
  (define length (vec3-length value))
  (when (zero? length)
    (raise-arguments-error 'vec3-normalize
                           "cannot normalize the zero vector"
                           "value" value))
  (define inverse-length (/ 1.0 length))
  (vec3-scale inverse-length value))

; vec3-lerp : vec3? vec3? finite-real? -> vec3?
;;   Interpolates componentwise from first to second by progress.
(define (vec3-lerp first second progress)
  (check-vec3 'vec3-lerp first)
  (check-vec3 'vec3-lerp second)
  (unless (finite-real? progress)
    (raise-argument-error 'vec3-lerp "finite real?" progress))
  (vec3 (+ (vec3-x first) (* progress (- (vec3-x second) (vec3-x first))))
        (+ (vec3-y first) (* progress (- (vec3-y second) (vec3-y first))))
        (+ (vec3-z first) (* progress (- (vec3-z second) (vec3-z first))))))

; vec3-finite? : any/c -> boolean?
;;   Reports whether value is a vec3 with finite real components.
(define (vec3-finite? value)
  (and (vec3? value)
       (finite-real? (vec3-x value))
       (finite-real? (vec3-y value))
       (finite-real? (vec3-z value))))


;;;
;;; Validation
;;;

; check-vec3 : symbol? any/c -> void?
;;   Raises an argument error unless value is a vec3.
(define (check-vec3 who value)
  (unless (vec3? value)
    (raise-argument-error who "vec3?" value)))
