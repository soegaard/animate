#lang racket/base

;;;
;;; Spatial Rays and Planes
;;;

;; Defines immutable rays, normalized point-normal planes, and deterministic
;; intersections used later by projection, picking, and clipping. This module
;; remains pure and does not know about any renderer or camera.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../geometry.rkt"
         "bounds3.rkt"
         "vec3.rkt")

;; Exports
(provide ray3
         ray3?
         ray3-origin
         ray3-direction
         plane3
         plane3?
         plane3-point
         plane3-normal
         (struct-out ray3-plane-hit)
         (struct-out ray3-aabb-hit)
         (struct-out ray3-triangle-hit)
         ray3-at
         ray3-intersect-plane
         ray3-intersect-aabb
         ray3-intersect-triangle)


;;;
;;; Data Representation
;;;

(struct ray3 (origin direction)
  #:transparent
  #:guard
  (lambda (origin direction who)
    (unless (vec3? origin)
      (raise-argument-error who "vec3?" origin))
    (unless (vec3? direction)
      (raise-argument-error who "vec3?" direction))
    (when (zero? (vec3-length direction))
      (raise-arguments-error who
                             "ray direction must be nonzero"
                             "direction" direction))
    (values origin direction)))

;; ray3 represents origin + t·direction for finite t at or beyond zero.
;;  - origin     vec3?                     the ray's start point.
;;  - direction  nonzero vec3?             not normalized automatically.

(struct plane3-value (point normal)
  #:transparent)

;; plane3-value represents all p with dot(p - point, normal) = 0.
;;  - point   vec3?             one point lying in the plane.
;;  - normal  normalized vec3?  orientation, stored in inexact unit form.

(define plane3? plane3-value?)
(define plane3-point plane3-value-point)
(define plane3-normal plane3-value-normal)

(struct ray3-plane-hit (point distance)
  #:transparent
  #:guard
  (lambda (point distance who)
    (unless (vec3? point)
      (raise-argument-error who "vec3?" point))
    (unless (and (finite-real? distance) (>= distance 0))
      (raise-argument-error who "nonnegative finite real?" distance))
    (values point distance)))

;; ray3-plane-hit represents a forward ray/plane intersection.
;;  - point     vec3?              intersection point.
;;  - distance  nonnegative-real?  ray parameter t at that point.

(struct ray3-aabb-hit (entry exit)
  #:transparent
  #:guard
  (lambda (entry exit who)
    (unless (and (finite-real? entry) (>= entry 0))
      (raise-argument-error who "nonnegative finite real?" entry))
    (unless (and (finite-real? exit) (>= exit entry))
      (raise-argument-error who "finite real at least entry" exit))
    (values entry exit)))

;; ray3-aabb-hit represents the closed ray-parameter interval inside a box.
;;  - entry  nonnegative-real?  first point of the ray inside the box.
;;  - exit   nonnegative-real?  final point of the ray inside the box.

;; ray3-triangle-hit records one exact, forward, double-sided triangle hit.
;; `barycentric` is a vec3 of weights for the first, second, and third input
;; vertices respectively.  `normal` follows the declared vertex winding.
(struct ray3-triangle-hit (point distance barycentric normal)
  #:transparent
  #:guard
  (lambda (point distance barycentric normal who)
    (unless (vec3? point)
      (raise-argument-error who "vec3? point" point))
    (unless (and (finite-real? distance) (>= distance 0))
      (raise-argument-error who "nonnegative finite real? distance" distance))
    (unless (vec3? barycentric)
      (raise-argument-error who "vec3? barycentric" barycentric))
    (unless (vec3? normal)
      (raise-argument-error who "vec3? normal" normal))
    (values point distance barycentric normal)))


;;;
;;; Construction
;;;

; plane3 : vec3? vec3? -> plane3?
;;   Constructs a plane through point with a normalized nonzero normal.
(define (plane3 point normal)
  (unless (vec3? point)
    (raise-argument-error 'plane3 "vec3?" point))
  (unless (vec3? normal)
    (raise-argument-error 'plane3 "vec3?" normal))
  (when (zero? (vec3-length normal))
    (raise-arguments-error 'plane3
                           "plane normal must be nonzero"
                           "normal" normal))
  (plane3-value point (vec3-normalize normal)))


;;;
;;; Intersection Operations
;;;

; ray3-at : ray3? finite-real? -> vec3?
;;   Returns the point at parameter t along ray; t may be negative for algebraic use.
(define (ray3-at ray distance)
  (unless (ray3? ray)
    (raise-argument-error 'ray3-at "ray3?" ray))
  (unless (finite-real? distance)
    (raise-argument-error 'ray3-at "finite real?" distance))
  (vec3+ (ray3-origin ray)
         (vec3-scale distance (ray3-direction ray))))

; ray3-intersect-plane : ray3? plane3? -> (or/c #f ray3-plane-hit?)
;;   Returns the nearest forward intersection, or #f for parallel/behind planes.
(define (ray3-intersect-plane ray plane)
  (unless (ray3? ray)
    (raise-argument-error 'ray3-intersect-plane "ray3?" ray))
  (unless (plane3? plane)
    (raise-argument-error 'ray3-intersect-plane "plane3?" plane))
  (define denominator (vec3-dot (plane3-normal plane) (ray3-direction ray)))
  (if (zero? denominator)
      #f
      (let ([distance
             (/ (vec3-dot (plane3-normal plane)
                           (vec3- (plane3-point plane) (ray3-origin ray)))
                denominator)])
        (and (>= distance 0)
             (ray3-plane-hit (ray3-at ray distance) distance)))))

; ray3-intersect-aabb : ray3? aabb3? -> (or/c #f ray3-aabb-hit?)
;;   Returns the forward entry and exit parameters for bounds, or #f if absent.
(define (ray3-intersect-aabb ray bounds)
  (unless (ray3? ray)
    (raise-argument-error 'ray3-intersect-aabb "ray3?" ray))
  (unless (aabb3? bounds)
    (raise-argument-error 'ray3-intersect-aabb "aabb3?" bounds))
  (cond
    [(aabb3-empty? bounds) #f]
    [else
     (define-values (minimum-parameter maximum-parameter)
       (for/fold ([minimum-parameter -inf.0]
                  [maximum-parameter +inf.0])
                 ([origin-coordinate
                   (in-list (list (vec3-x (ray3-origin ray))
                                  (vec3-y (ray3-origin ray))
                                  (vec3-z (ray3-origin ray))))]
                  [direction-coordinate
                   (in-list (list (vec3-x (ray3-direction ray))
                                  (vec3-y (ray3-direction ray))
                                  (vec3-z (ray3-direction ray))))]
                  [minimum-coordinate
                   (in-list (list (vec3-x (aabb3-minimum bounds))
                                  (vec3-y (aabb3-minimum bounds))
                                  (vec3-z (aabb3-minimum bounds))))]
                  [maximum-coordinate
                   (in-list (list (vec3-x (aabb3-maximum bounds))
                                  (vec3-y (aabb3-maximum bounds))
                                  (vec3-z (aabb3-maximum bounds))))])
         (cond
           [(zero? direction-coordinate)
            (if (<= minimum-coordinate origin-coordinate maximum-coordinate)
                (values minimum-parameter maximum-parameter)
                (values +inf.0 -inf.0))]
           [else
            (define first (/ (- minimum-coordinate origin-coordinate)
                             direction-coordinate))
            (define second (/ (- maximum-coordinate origin-coordinate)
                              direction-coordinate))
            (values (max minimum-parameter (min first second))
                    (min maximum-parameter (max first second)))])))
     (and (<= minimum-parameter maximum-parameter)
          (>= maximum-parameter 0)
          (ray3-aabb-hit (max 0 minimum-parameter) maximum-parameter))]))

; ray3-intersect-triangle : ray3? vec3? vec3? vec3?
;                           -> (or/c #f ray3-triangle-hit?)
;; Möller--Trumbore intersection with a fixed numerical tolerance.  Picking is
;; deliberately double-sided: culling controls a camera render, while an
;; inspector must report the authored triangle a user pointed at.
(define (ray3-intersect-triangle ray first second third)
  (unless (ray3? ray)
    (raise-argument-error 'ray3-intersect-triangle "ray3?" ray))
  (for ([point (in-list (list first second third))])
    (unless (vec3? point)
      (raise-argument-error 'ray3-intersect-triangle "three vec3? vertices" point)))
  (define edge-one (vec3- second first))
  (define edge-two (vec3- third first))
  (define normal (vec3-cross edge-one edge-two))
  (cond
    [(<= (vec3-length normal) 1e-12) #f]
    [else
     (define cross-direction-edge-two
       (vec3-cross (ray3-direction ray) edge-two))
     (define determinant (vec3-dot edge-one cross-direction-edge-two))
     (if (<= (abs determinant) 1e-12)
         #f
         (let* ([inverse-determinant (/ 1 determinant)]
                [origin-offset (vec3- (ray3-origin ray) first)]
                [second-weight
                 (* inverse-determinant
                    (vec3-dot origin-offset cross-direction-edge-two))])
           (if (or (< second-weight -1e-10) (> second-weight (+ 1 1e-10)))
               #f
               (let* ([cross-offset-edge-one
                       (vec3-cross origin-offset edge-one)]
                      [third-weight
                       (* inverse-determinant
                          (vec3-dot (ray3-direction ray) cross-offset-edge-one))]
                      [distance
                       (* inverse-determinant
                          (vec3-dot edge-two cross-offset-edge-one))]
                      [first-weight (- 1 second-weight third-weight)])
                 (and (>= third-weight -1e-10)
                      (>= first-weight -1e-10)
                      (>= distance 0)
                      (ray3-triangle-hit
                       (ray3-at ray distance)
                       distance
                       (vec3 (max 0 first-weight)
                             (max 0 second-weight)
                             (max 0 third-weight))
                       (vec3-normalize normal)))))))]))
