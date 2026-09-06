#lang racket/base

;;;
;;; Deterministic Surface Grids
;;;

;; Defines the fixed rectangular sample topology shared by every Stage-G
;; surface.  A grid records its parameter locations as well as its sampled
;; positions, so triangle identity is independent of camera or frame time.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../geometry.rkt"
         "vec3.rkt")

(provide surface-grid?
         surface-grid-u-values
         surface-grid-v-values
         surface-grid-points
         surface-grid-u-count
         surface-grid-v-count
         surface-grid-ref
         surface-grid-index
         surface-grid-triangles
         make-surface-grid
         surface-grid-from-points)


;;;
;;; Data Representation
;;;

(struct surface-grid-value (u-values v-values points)
  #:transparent)

;; surface-grid-value represents a fixed rectangular surface sample lattice.
;;  - u-values  immutable-vectorof finite-real? increasing parameter values.
;;  - v-values  immutable-vectorof finite-real? increasing parameter values.
;;  - points    immutable-vectorof vec3?, u-major then v-minor.  Its order is
;;              the canonical stable vertex identity used by triangle meshes.

(define surface-grid? surface-grid-value?)
(define surface-grid-u-values surface-grid-value-u-values)
(define surface-grid-v-values surface-grid-value-v-values)
(define surface-grid-points surface-grid-value-points)


;;;
;;; Construction and Lookup
;;;

; make-surface-grid : (finite-real? finite-real? -> vec3?)
;                     #:u-range two-real-range? #:v-range two-real-range?
;                     #:resolution two-exact-integer-resolution? -> surface-grid?
;;   Samples one parameterization at deterministic inclusive rectangular sites.
(define (make-surface-grid procedure
                           #:u-range [u-range (list -1 1)]
                           #:v-range [v-range (list -1 1)]
                           #:resolution [resolution (list 33 33)])
  (unless (procedure? procedure)
    (raise-argument-error 'make-surface-grid "procedure?" procedure))
  (define-values (u-min u-max) (increasing-range 'make-surface-grid u-range))
  (define-values (v-min v-max) (increasing-range 'make-surface-grid v-range))
  (define-values (u-count v-count) (grid-resolution 'make-surface-grid resolution))
  (define u-values (sample-values u-min u-max u-count))
  (define v-values (sample-values v-min v-max v-count))
  (surface-grid-from-points
   u-values v-values
   (for/vector ([u (in-vector u-values)])
     (for/vector ([v (in-vector v-values)])
       (define point (procedure u v))
       (unless (and (vec3? point) (vec3-finite? point))
         (raise-arguments-error
          'make-surface-grid
          "a parameterization producing finite vec3? values"
          "u" u "v" v "result" point))
       point))))

; surface-grid-from-points : vector? vector? vector-of-vector? -> surface-grid?
;;   Freezes already-sampled u-major point rows after complete shape checks.
(define (surface-grid-from-points u-values v-values point-rows)
  (define checked-u (check-values 'surface-grid-from-points "u-values" u-values))
  (define checked-v (check-values 'surface-grid-from-points "v-values" v-values))
  (unless (vector? point-rows)
    (raise-argument-error 'surface-grid-from-points "vector?" point-rows))
  (unless (= (vector-length point-rows) (vector-length checked-u))
    (raise-arguments-error 'surface-grid-from-points
                           "one point row for every u parameter"
                           "u-count" (vector-length checked-u)
                           "row-count" (vector-length point-rows)))
  (define points
    (vector->immutable-vector
     (for*/vector ([row (in-vector point-rows)]
                   [point (in-vector (check-row row (vector-length checked-v)))])
       point)))
  (surface-grid-value checked-u checked-v points))

; surface-grid-u-count : surface-grid? -> exact-positive-integer?
;;   Returns the stable count of u samples.
(define (surface-grid-u-count grid)
  (unless (surface-grid? grid) (raise-argument-error 'surface-grid-u-count "surface-grid?" grid))
  (vector-length (surface-grid-u-values grid)))

; surface-grid-v-count : surface-grid? -> exact-positive-integer?
;;   Returns the stable count of v samples.
(define (surface-grid-v-count grid)
  (unless (surface-grid? grid) (raise-argument-error 'surface-grid-v-count "surface-grid?" grid))
  (vector-length (surface-grid-v-values grid)))

; surface-grid-index : surface-grid? exact-nonnegative-integer?
;                      exact-nonnegative-integer? -> exact-nonnegative-integer?
;;   Converts a lattice coordinate to its u-major stable mesh index.
(define (surface-grid-index grid u-index v-index)
  (check-grid-index 'surface-grid-index grid u-index v-index)
  (+ (* u-index (surface-grid-v-count grid)) v-index))

; surface-grid-ref : surface-grid? exact-nonnegative-integer?
;                    exact-nonnegative-integer? -> vec3?
;;   Looks up one sampled position by lattice coordinates.
(define (surface-grid-ref grid u-index v-index)
  (vector-ref (surface-grid-points grid)
              (surface-grid-index grid u-index v-index)))

; surface-grid-triangles : surface-grid? -> immutable-vector?
;;   Returns two CCW parameter-space triangle indices for every rectangular cell.
(define (surface-grid-triangles grid)
  (unless (surface-grid? grid)
    (raise-argument-error 'surface-grid-triangles "surface-grid?" grid))
  (define u-limit (sub1 (surface-grid-u-count grid)))
  (define v-limit (sub1 (surface-grid-v-count grid)))
  (vector->immutable-vector
   (list->vector
    (apply append
           (for*/list ([u (in-range u-limit)] [v (in-range v-limit)])
             (define lower-left (surface-grid-index grid u v))
             (define lower-right (surface-grid-index grid (add1 u) v))
             (define upper-right (surface-grid-index grid (add1 u) (add1 v)))
             (define upper-left (surface-grid-index grid u (add1 v)))
             (list (vector-immutable lower-left lower-right upper-right)
                   (vector-immutable lower-left upper-right upper-left)))))))


;;;
;;; Validation Helpers
;;;

(define (increasing-range who range)
  (unless (and (list? range) (= (length range) 2)
               (andmap finite-real? range) (< (first range) (second range)))
    (raise-argument-error who "two-element increasing list of finite reals" range))
  (values (first range) (second range)))

(define (grid-resolution who resolution)
  (unless (and (list? resolution) (= (length resolution) 2)
               (andmap (lambda (value) (and (exact-integer? value) (>= value 2)))
                       resolution))
    (raise-argument-error who "two-element list of exact integers at least 2" resolution))
  (values (first resolution) (second resolution)))

(define (sample-values minimum maximum count)
  (vector->immutable-vector
   (for/vector ([index (in-range count)])
     (+ minimum (* (/ index (sub1 count)) (- maximum minimum))))))

(define (check-values who label values)
  (unless (and (vector? values) (>= (vector-length values) 2))
    (raise-arguments-error who "a vector with at least two parameter values"
                           "parameter" label "values" values))
  (define copied
    (vector->immutable-vector
     (for/vector ([value (in-vector values)])
       (unless (finite-real? value)
         (raise-arguments-error who "finite parameter values"
                                "parameter" label "value" value))
       value)))
  (for ([previous (in-vector copied)] [current (in-vector copied 1)])
    (unless (< previous current)
      (raise-arguments-error who "strictly increasing parameter values"
                             "parameter" label "values" values)))
  copied)

(define (check-row row expected-count)
  (unless (and (vector? row) (= (vector-length row) expected-count))
    (raise-arguments-error 'surface-grid-from-points
                           "a point row matching the v parameter count"
                           "row" row "v-count" expected-count))
  (vector->immutable-vector
   (for/vector ([point (in-vector row)])
     (unless (and (vec3? point) (vec3-finite? point))
       (raise-argument-error 'surface-grid-from-points "finite vec3?" point))
     point)))

(define (check-grid-index who grid u-index v-index)
  (unless (surface-grid? grid) (raise-argument-error who "surface-grid?" grid))
  (unless (and (exact-nonnegative-integer? u-index)
               (< u-index (surface-grid-u-count grid)))
    (raise-argument-error who "in-range exact nonnegative u index" u-index))
  (unless (and (exact-nonnegative-integer? v-index)
               (< v-index (surface-grid-v-count grid)))
    (raise-argument-error who "in-range exact nonnegative v index" v-index)))
