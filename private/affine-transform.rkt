#lang racket/base

;;;
;;; Affine Transform Model
;;;

;; Defines immutable translation, rotation, and scale data for two-dimensional
;; Visuals.
;;
;; Transform components are applied in the fixed order scale, rotate, then
;; translate. This module contains only pure mathematical operations.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "geometry.rkt")

;; Exports
(provide affine-transform?
         affine-transform-translation
         affine-transform-rotation
         affine-transform-scale
         make-affine-transform
         identity-affine-transform
         scale-factor?
         scale-factor->vec2
         affine-transform-with-translation
         affine-transform-with-rotation
         affine-transform-with-scale
         affine-transform-lerp
         affine-transform-apply-vector
         affine-transform-apply-point)


;;;
;;; Scale Values
;;;

; scale-factor? : any/c -> boolean?
;;   Reports whether value is a positive finite uniform or two-dimensional scale.
(define (scale-factor? value)
  (or (and (finite-real? value)
           (positive? value))
      (and (vec2? value)
           (positive? (vec2-x value))
           (positive? (vec2-y value)))))

; scale-factor->vec2 : (or/c positive-real? vec2?) -> vec2?
;;   Converts a uniform or two-dimensional scale factor to a vec2.
(define (scale-factor->vec2 value)
  (unless (scale-factor? value)
    (raise-argument-error
     'scale-factor->vec2
     "positive finite real or vec2 with positive components"
     value))
  (if (vec2? value)
      value
      (vec2 value value)))


;;;
;;; Data Representation
;;;

(struct affine-transform (translation rotation scale)
  #:transparent
  #:guard
  (lambda (translation rotation scale who)
    (unless (vec2? translation)
      (raise-argument-error who "vec2?" translation))
    (unless (finite-real? rotation)
      (raise-argument-error who "finite real?" rotation))
    (unless (scale-factor? scale)
      (raise-argument-error
       who
       "positive finite real or vec2 with positive components"
       scale))
    (values translation rotation (scale-factor->vec2 scale))))

;; affine-transform represents one decomposed affine transform.
;;  - translation  vec2?                       containing-system position.
;;  - rotation     finite-real?                counter-clockwise radians.
;;  - scale        vec2? with positive fields  local x and y scale factors.
;;
;; Components are applied to local geometry in this significant order:
;; scale, then rotate, then translate. Shear is not represented in SCENE-C.


;;;
;;; Construction
;;;

; make-affine-transform : [#:translation vec2?]
;                         [#:rotation finite-real?]
;                         [#:scale (or/c positive-real? vec2?)]
;                         -> affine-transform?
;;   Creates a validated decomposed affine transform.
(define (make-affine-transform #:translation [translation origin]
                               #:rotation [rotation 0]
                               #:scale [scale 1])
  (affine-transform translation rotation scale))

; identity-affine-transform : affine-transform?
;;   Gives the transform that leaves every point unchanged.
(define identity-affine-transform
  (make-affine-transform))


;;;
;;; Immutable Updates
;;;

; affine-transform-with-translation : affine-transform? vec2?
;                                     -> affine-transform?
;;   Returns transform with its translation replaced.
(define (affine-transform-with-translation transform translation)
  (check-affine-transform 'affine-transform-with-translation transform)
  (unless (vec2? translation)
    (raise-argument-error
     'affine-transform-with-translation
     "vec2?"
     translation))
  (struct-copy affine-transform transform [translation translation]))

; affine-transform-with-rotation : affine-transform? finite-real?
;                                  -> affine-transform?
;;   Returns transform with its rotation replaced.
(define (affine-transform-with-rotation transform rotation)
  (check-affine-transform 'affine-transform-with-rotation transform)
  (unless (finite-real? rotation)
    (raise-argument-error
     'affine-transform-with-rotation
     "finite real?"
     rotation))
  (struct-copy affine-transform transform [rotation rotation]))

; affine-transform-with-scale : affine-transform?
;                               (or/c positive-real? vec2?)
;                               -> affine-transform?
;;   Returns transform with its local scale replaced.
(define (affine-transform-with-scale transform scale)
  (check-affine-transform 'affine-transform-with-scale transform)
  (unless (scale-factor? scale)
    (raise-argument-error
     'affine-transform-with-scale
     "positive finite real or vec2 with positive components"
     scale))
  (struct-copy affine-transform transform
               [scale (scale-factor->vec2 scale)]))


;;;
;;; Interpolation and Application
;;;

; affine-transform-lerp : affine-transform? affine-transform? unit-real?
;                         -> affine-transform?
;;   Interpolates corresponding transform components within the unit interval.
(define (affine-transform-lerp from to progress)
  (check-affine-transform 'affine-transform-lerp from)
  (check-affine-transform 'affine-transform-lerp to)
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'affine-transform-lerp
     "finite real in the closed unit interval"
     progress))
  (make-affine-transform
   #:translation
   (vec2-lerp (affine-transform-translation from)
              (affine-transform-translation to)
              progress)
   #:rotation
   (real-lerp (affine-transform-rotation from)
              (affine-transform-rotation to)
              progress)
   #:scale
   (vec2-lerp (affine-transform-scale from)
              (affine-transform-scale to)
              progress)))

; affine-transform-apply-vector : affine-transform? vec2? -> vec2?
;;   Applies transform's scale and rotation to a displacement vector.
(define (affine-transform-apply-vector transform vector)
  (check-affine-transform 'affine-transform-apply-vector transform)
  (unless (vec2? vector)
    (raise-argument-error
     'affine-transform-apply-vector
     "vec2?"
     vector))
  (define scale
    (affine-transform-scale transform))
  (define scaled
    (vec2* scale vector))
  (define angle
    (affine-transform-rotation transform))
  (define cosine
    (cos angle))
  (define sine
    (sin angle))
  (vec2 (- (* cosine (vec2-x scaled))
           (* sine (vec2-y scaled)))
        (+ (* sine (vec2-x scaled))
           (* cosine (vec2-y scaled)))))

; affine-transform-apply-point : affine-transform? vec2? -> vec2?
;;   Applies transform's scale, rotation, and translation to a point.
(define (affine-transform-apply-point transform point)
  (check-affine-transform 'affine-transform-apply-point transform)
  (unless (vec2? point)
    (raise-argument-error 'affine-transform-apply-point "vec2?" point))
  (vec2+ (affine-transform-translation transform)
         (affine-transform-apply-vector transform point)))


;;;
;;; Validation
;;;

; check-affine-transform : symbol? any/c -> void?
;;   Raises an argument error unless value is an affine transform.
(define (check-affine-transform who value)
  (unless (affine-transform? value)
    (raise-argument-error who "affine-transform?" value)))
