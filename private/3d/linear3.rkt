#lang racket/base

;;;
;;; Three-Dimensional Linear Maps
;;;

;; Defines pure immutable 3×3 matrices acting on column vectors. Matrix
;; entries use ordinary row-major constructor order, while composition is
;; stated as function composition so the inner map always acts first.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../geometry.rkt"
         "vec3.rkt")

;; Exports
(provide (struct-out linear3)
         identity-linear3
         linear3-compose
         linear3-invert
         linear3-determinant
         linear3-transpose
         linear3-apply-vector
         linear3-normal-transform)


;;;
;;; Data Representation
;;;

;; linear3 represents the matrix
;;
;;     [ m00 m01 m02 ]
;;     [ m10 m11 m12 ]
;;     [ m20 m21 m22 ]
;;
;; acting on column vectors. Constructor arguments follow those rows in order.
(struct linear3 (m00 m01 m02
                 m10 m11 m12
                 m20 m21 m22)
  #:transparent
  #:guard
  (lambda (m00 m01 m02 m10 m11 m12 m20 m21 m22 who)
    (for ([entry (in-list (list m00 m01 m02
                                  m10 m11 m12
                                  m20 m21 m22))])
      (unless (finite-real? entry)
        (raise-argument-error who "nine finite real matrix entries" entry)))
    (values m00 m01 m02 m10 m11 m12 m20 m21 m22)))

;; linear3 stores one finite linear transformation. Matrix multiplication and
;; constructor row ordering are both significant public semantics.


;;;
;;; Construction and Queries
;;;

; identity-linear3 : linear3?
;;   Gives the identity matrix.
(define identity-linear3
  (linear3 1 0 0
           0 1 0
           0 0 1))

; linear3-determinant : linear3? -> finite-real?
;;   Returns map's determinant.
(define (linear3-determinant map)
  (check-linear3 'linear3-determinant map)
  (+ (* (linear3-m00 map)
        (- (* (linear3-m11 map) (linear3-m22 map))
           (* (linear3-m12 map) (linear3-m21 map))))
     (* (- (linear3-m01 map))
        (- (* (linear3-m10 map) (linear3-m22 map))
           (* (linear3-m12 map) (linear3-m20 map))))
     (* (linear3-m02 map)
        (- (* (linear3-m10 map) (linear3-m21 map))
           (* (linear3-m11 map) (linear3-m20 map))))))

; linear3-transpose : linear3? -> linear3?
;;   Returns the transpose of map.
(define (linear3-transpose map)
  (check-linear3 'linear3-transpose map)
  (linear3 (linear3-m00 map) (linear3-m10 map) (linear3-m20 map)
           (linear3-m01 map) (linear3-m11 map) (linear3-m21 map)
           (linear3-m02 map) (linear3-m12 map) (linear3-m22 map)))

; linear3-invert : linear3? -> linear3?
;;   Returns map's inverse, or raises an error when map is singular.
(define (linear3-invert map)
  (check-linear3 'linear3-invert map)
  (define determinant (linear3-determinant map))
  (when (zero? determinant)
    (raise-arguments-error 'linear3-invert
                           "matrix is singular"
                           "map" map))
  (define inverse-determinant (/ 1 determinant))
  (linear3
   (* inverse-determinant
      (- (* (linear3-m11 map) (linear3-m22 map))
         (* (linear3-m12 map) (linear3-m21 map))))
   (* inverse-determinant
      (- (* (linear3-m02 map) (linear3-m21 map))
         (* (linear3-m01 map) (linear3-m22 map))))
   (* inverse-determinant
      (- (* (linear3-m01 map) (linear3-m12 map))
         (* (linear3-m02 map) (linear3-m11 map))))
   (* inverse-determinant
      (- (* (linear3-m12 map) (linear3-m20 map))
         (* (linear3-m10 map) (linear3-m22 map))))
   (* inverse-determinant
      (- (* (linear3-m00 map) (linear3-m22 map))
         (* (linear3-m02 map) (linear3-m20 map))))
   (* inverse-determinant
      (- (* (linear3-m02 map) (linear3-m10 map))
         (* (linear3-m00 map) (linear3-m12 map))))
   (* inverse-determinant
      (- (* (linear3-m10 map) (linear3-m21 map))
         (* (linear3-m11 map) (linear3-m20 map))))
   (* inverse-determinant
      (- (* (linear3-m01 map) (linear3-m20 map))
         (* (linear3-m00 map) (linear3-m21 map))))
   (* inverse-determinant
      (- (* (linear3-m00 map) (linear3-m11 map))
         (* (linear3-m01 map) (linear3-m10 map))))))


;;;
;;; Transformation Operations
;;;

; linear3-compose : linear3? linear3? -> linear3?
;;   Returns outer ∘ inner, so inner acts first on a vector.
(define (linear3-compose outer inner)
  (check-linear3 'linear3-compose outer)
  (check-linear3 'linear3-compose inner)
  (define (entry row column)
    (+ (* (matrix-ref outer row 0) (matrix-ref inner 0 column))
       (* (matrix-ref outer row 1) (matrix-ref inner 1 column))
       (* (matrix-ref outer row 2) (matrix-ref inner 2 column))))
  (linear3 (entry 0 0) (entry 0 1) (entry 0 2)
           (entry 1 0) (entry 1 1) (entry 1 2)
           (entry 2 0) (entry 2 1) (entry 2 2)))

; linear3-apply-vector : linear3? vec3? -> vec3?
;;   Applies map to vector as a column vector.
(define (linear3-apply-vector map vector)
  (check-linear3 'linear3-apply-vector map)
  (unless (vec3? vector)
    (raise-argument-error 'linear3-apply-vector "vec3?" vector))
  (vec3 (+ (* (linear3-m00 map) (vec3-x vector))
           (* (linear3-m01 map) (vec3-y vector))
           (* (linear3-m02 map) (vec3-z vector)))
        (+ (* (linear3-m10 map) (vec3-x vector))
           (* (linear3-m11 map) (vec3-y vector))
           (* (linear3-m12 map) (vec3-z vector)))
        (+ (* (linear3-m20 map) (vec3-x vector))
           (* (linear3-m21 map) (vec3-y vector))
           (* (linear3-m22 map) (vec3-z vector)))))

; linear3-normal-transform : linear3? -> linear3?
;;   Returns inverse-transpose map used to transform surface normals.
(define (linear3-normal-transform map)
  (linear3-transpose (linear3-invert map)))


;;;
;;; Local Helpers
;;;

; matrix-ref : linear3? exact-nonnegative-integer? exact-nonnegative-integer?
;              -> finite-real?
;;   Extracts one validated matrix entry by zero-based row and column.
(define (matrix-ref map row column)
  (case (+ column (* row 3))
    [(0) (linear3-m00 map)] [(1) (linear3-m01 map)] [(2) (linear3-m02 map)]
    [(3) (linear3-m10 map)] [(4) (linear3-m11 map)] [(5) (linear3-m12 map)]
    [(6) (linear3-m20 map)] [(7) (linear3-m21 map)] [(8) (linear3-m22 map)]
    [else (error 'matrix-ref "invalid matrix index: ~e, ~e" row column)]))

; check-linear3 : symbol? any/c -> void?
;;   Raises an argument error unless value is a linear3.
(define (check-linear3 who value)
  (unless (linear3? value)
    (raise-argument-error who "linear3?" value)))
