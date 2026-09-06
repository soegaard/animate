#lang racket/base

;;;
;;; Three-Dimensional Axis-Aligned Bounds
;;;

;; Defines immutable world-coordinate axis-aligned boxes for fitting, culling,
;; and later picking. Empty bounds are explicit and carry no invented point.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine3.rkt"
         "vec3.rkt")

;; Exports
(provide aabb3
         aabb3?
         aabb3-minimum
         aabb3-maximum
         aabb3-empty
         aabb3-empty?
         aabb3-union
         aabb3-from-points
         aabb3-transform
         aabb3-center
         aabb3-size
         aabb3-contains?)


;;;
;;; Data Representation
;;;

(struct aabb3-value (minimum maximum)
  #:transparent)

;; aabb3-value represents an inclusive axis-aligned spatial box.
;;  - minimum  (or/c #f vec3?)  lower corner, or #f together with maximum for empty.
;;  - maximum  (or/c #f vec3?)  upper corner, or #f together with minimum for empty.

(define aabb3? aabb3-value?)
(define aabb3-minimum aabb3-value-minimum)
(define aabb3-maximum aabb3-value-maximum)


;;;
;;; Construction
;;;

; aabb3 : (or/c #f vec3?) (or/c #f vec3?) -> aabb3?
;;   Constructs a validated inclusive box; two #f values denote the empty box.
(define (aabb3 minimum maximum)
  (cond
    [(and (not minimum) (not maximum)) (aabb3-value #f #f)]
    [(and (vec3? minimum) (vec3? maximum))
     (unless (and (<= (vec3-x minimum) (vec3-x maximum))
                  (<= (vec3-y minimum) (vec3-y maximum))
                  (<= (vec3-z minimum) (vec3-z maximum)))
       (raise-arguments-error 'aabb3
                              "minimum must not exceed maximum on any axis"
                              "minimum" minimum
                              "maximum" maximum))
     (aabb3-value minimum maximum)]
    [else
     (raise-arguments-error 'aabb3
                            "both corners must be vec3 values, or both must be #f"
                            "minimum" minimum
                            "maximum" maximum)]))

; aabb3-empty : aabb3?
;;   Gives the spatial box containing no points.
(define aabb3-empty
  (aabb3 #f #f))

; aabb3-empty? : aabb3? -> boolean?
;;   Reports whether bounds contain no points.
(define (aabb3-empty? bounds)
  (check-aabb3 'aabb3-empty? bounds)
  (not (aabb3-minimum bounds)))

; aabb3-from-points : (listof vec3?) -> aabb3?
;;   Returns the least axis-aligned box containing points, or aabb3-empty.
(define (aabb3-from-points points)
  (unless (list? points)
    (raise-argument-error 'aabb3-from-points "list?" points))
  (for ([point (in-list points)])
    (unless (vec3? point)
      (raise-argument-error 'aabb3-from-points "(listof vec3?)" points)))
  (if (null? points)
      aabb3-empty
      (aabb3
       (vec3 (apply min (map vec3-x points))
             (apply min (map vec3-y points))
             (apply min (map vec3-z points)))
       (vec3 (apply max (map vec3-x points))
             (apply max (map vec3-y points))
             (apply max (map vec3-z points))))))


;;;
;;; Bounds Operations
;;;

; aabb3-union : aabb3? aabb3? -> aabb3?
;;   Returns the least axis-aligned box containing first and second.
(define (aabb3-union first second)
  (check-aabb3 'aabb3-union first)
  (check-aabb3 'aabb3-union second)
  (cond [(aabb3-empty? first) second]
        [(aabb3-empty? second) first]
        [else
         (aabb3
          (componentwise-min (aabb3-minimum first) (aabb3-minimum second))
          (componentwise-max (aabb3-maximum first) (aabb3-maximum second)))]))

; aabb3-transform : aabb3? affine3? -> aabb3?
;;   Returns the smallest axis-aligned box containing bounds after map.
(define (aabb3-transform bounds map)
  (check-aabb3 'aabb3-transform bounds)
  (unless (affine3? map)
    (raise-argument-error 'aabb3-transform "affine3?" map))
  (if (aabb3-empty? bounds)
      aabb3-empty
      (aabb3-from-points
       (for/list ([corner (in-list (aabb3-corners bounds))])
         (affine3-apply-point map corner)))))

; aabb3-center : aabb3? -> vec3?
;;   Returns the geometric centre of nonempty bounds.
(define (aabb3-center bounds)
  (check-nonempty-aabb3 'aabb3-center bounds)
  (vec3-scale 1/2
              (vec3+ (aabb3-minimum bounds) (aabb3-maximum bounds))))

; aabb3-size : aabb3? -> vec3?
;;   Returns nonnegative width, height, and depth of nonempty bounds.
(define (aabb3-size bounds)
  (check-nonempty-aabb3 'aabb3-size bounds)
  (vec3- (aabb3-maximum bounds) (aabb3-minimum bounds)))

; aabb3-contains? : aabb3? vec3? -> boolean?
;;   Reports whether point lies in bounds' inclusive volume.
(define (aabb3-contains? bounds point)
  (check-aabb3 'aabb3-contains? bounds)
  (unless (vec3? point)
    (raise-argument-error 'aabb3-contains? "vec3?" point))
  (and (not (aabb3-empty? bounds))
       (<= (vec3-x (aabb3-minimum bounds)) (vec3-x point)
           (vec3-x (aabb3-maximum bounds)))
       (<= (vec3-y (aabb3-minimum bounds)) (vec3-y point)
           (vec3-y (aabb3-maximum bounds)))
       (<= (vec3-z (aabb3-minimum bounds)) (vec3-z point)
           (vec3-z (aabb3-maximum bounds)))))


;;;
;;; Local Helpers
;;;

; aabb3-corners : aabb3? -> (listof vec3?)
;;   Enumerates nonempty bounds' eight corners in deterministic bit order.
(define (aabb3-corners bounds)
  (check-nonempty-aabb3 'aabb3-corners bounds)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (for*/list ([x (in-list (list (vec3-x minimum) (vec3-x maximum)))]
              [y (in-list (list (vec3-y minimum) (vec3-y maximum)))]
              [z (in-list (list (vec3-z minimum) (vec3-z maximum)))])
    (vec3 x y z)))

; componentwise-min : vec3? vec3? -> vec3?
;;   Returns the lower coordinate on every axis.
(define (componentwise-min first second)
  (vec3 (min (vec3-x first) (vec3-x second))
        (min (vec3-y first) (vec3-y second))
        (min (vec3-z first) (vec3-z second))))

; componentwise-max : vec3? vec3? -> vec3?
;;   Returns the upper coordinate on every axis.
(define (componentwise-max first second)
  (vec3 (max (vec3-x first) (vec3-x second))
        (max (vec3-y first) (vec3-y second))
        (max (vec3-z first) (vec3-z second))))

; check-aabb3 : symbol? any/c -> void?
;;   Raises an argument error unless value is an aabb3.
(define (check-aabb3 who value)
  (unless (aabb3? value)
    (raise-argument-error who "aabb3?" value)))

; check-nonempty-aabb3 : symbol? any/c -> void?
;;   Raises an argument error unless value is a nonempty aabb3.
(define (check-nonempty-aabb3 who value)
  (check-aabb3 who value)
  (when (aabb3-empty? value)
    (raise-arguments-error who "bounds must not be empty" "bounds" value)))
