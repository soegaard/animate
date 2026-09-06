#lang racket/base

;;;
;;; Spatial Projection Values
;;;

;; Defines immutable lens values and pure camera-local projection arithmetic.
;; A camera owns near/far distances; projections deliberately receive viewport
;; aspect at use time so the same camera can serve several view3d rectangles.


;;;
;;; Imports and Exports
;;;

(require (only-in racket/math pi)
         "../geometry.rkt"
         "vec3.rkt")

(provide (struct-out perspective-projection3d)
         (struct-out orthographic-projection3d)
         projection3d?
         projection3d-project-view
         projection3d-half-height
         projection3d-half-width)


;;;
;;; Projection Values
;;;

(struct perspective-projection3d (vertical-field-of-view)
  #:transparent
  #:guard
  (lambda (vertical-field-of-view who)
    (unless (and (finite-real? vertical-field-of-view)
                 (positive? vertical-field-of-view)
                 (< vertical-field-of-view pi))
      (raise-argument-error
       who
       "finite field of view strictly between 0 and pi"
       vertical-field-of-view))
    (values vertical-field-of-view)))

;; perspective-projection3d represents one vertical perspective lens.
;;  - vertical-field-of-view  finite-real?  full vertical angle in radians.

(struct orthographic-projection3d (vertical-size)
  #:transparent
  #:guard
  (lambda (vertical-size who)
    (unless (and (finite-real? vertical-size) (positive? vertical-size))
      (raise-argument-error who "positive finite real?" vertical-size))
    (values vertical-size)))

;; orthographic-projection3d represents one parallel vertical viewport size.
;;  - vertical-size  positive finite real?  visible world units from bottom to top.

; projection3d? : any/c -> boolean?
;;   Reports whether value is a supported spatial projection value.
(define (projection3d? value)
  (or (perspective-projection3d? value)
      (orthographic-projection3d? value)))


;;;
;;; View-Local Arithmetic
;;;

; projection3d-half-height : projection3d? positive-real? -> positive-real?
;;   Returns the local y extent at one positive forward depth.
(define (projection3d-half-height projection depth)
  (check-projection 'projection3d-half-height projection)
  (check-positive-depth 'projection3d-half-height depth)
  (cond [(perspective-projection3d? projection)
         (* depth
            (tan (/ (perspective-projection3d-vertical-field-of-view projection)
                    2)))]
        [else
         (/ (orthographic-projection3d-vertical-size projection) 2)]))

; projection3d-half-width : projection3d? positive-real? positive-real?
;;   Returns the local x extent at one positive forward depth and viewport aspect.
(define (projection3d-half-width projection depth aspect)
  (check-aspect 'projection3d-half-width aspect)
  (* aspect (projection3d-half-height projection depth)))

; projection3d-project-view : projection3d? vec3? positive-real? -> vec2?
;;   Projects a camera-local point with negative z (positive forward depth) to
;; normalized viewport coordinates: centre is (0,0), edges are ±1.
(define (projection3d-project-view projection view-point aspect)
  (check-projection 'projection3d-project-view projection)
  (unless (vec3? view-point)
    (raise-argument-error 'projection3d-project-view "vec3?" view-point))
  (check-aspect 'projection3d-project-view aspect)
  (define depth (- (vec3-z view-point)))
  (check-positive-depth 'projection3d-project-view depth)
  (define half-height (projection3d-half-height projection depth))
  (define half-width (* aspect half-height))
  (vec2 (/ (vec3-x view-point) half-width)
        (/ (vec3-y view-point) half-height)))


;;;
;;; Validation
;;;

(define (check-projection who value)
  (unless (projection3d? value)
    (raise-argument-error who "projection3d?" value)))

(define (check-positive-depth who value)
  (unless (and (finite-real? value) (positive? value))
    (raise-argument-error who "positive finite forward depth" value)))

(define (check-aspect who value)
  (unless (and (finite-real? value) (positive? value))
    (raise-argument-error who "positive finite viewport aspect" value)))
