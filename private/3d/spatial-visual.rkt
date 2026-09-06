#lang racket/base

;;;
;;; Spatial Visual Protocol
;;;

;; Defines the pure, immutable protocol shared by objects that live inside a
;; view3d.  Spatial objects are intentionally separate from ordinary 2D
;; Visuals: only their enclosing view3d participates in the existing timeline.


;;;
;;; Imports and Exports
;;;

(require racket/generic
         "../geometry.rkt"
         "transform3.rkt"
         "rotation3.rkt"
         "vec3.rkt"
         "bounds3.rkt")

(provide gen:spatial-visual
         spatial-visual?
         spatial-id
         spatial-transform
         spatial-with-transform
         spatial-opacity
         spatial-with-opacity
         spatial-local-bounds
         spatial-opacity?
         spatial-position
         spatial-with-position
         spatial-rotation
         spatial-with-rotation
         spatial-scale
         spatial-with-scale)


;;;
;;; Spatial Protocol
;;;

; spatial-id : spatial-visual? -> symbol?
;;   Returns a stable identity within one spatial container.
;
; spatial-transform : spatial-visual? -> transform3?
;;   Returns the local scale-then-rotate-then-translate transform.
;
; spatial-with-transform : spatial-visual? transform3? -> spatial-visual?
;;   Returns a copy with its complete local transform replaced.
;
; spatial-opacity : spatial-visual? -> spatial-opacity?
;;   Returns the semantic opacity inherited by this object's descendants.
;
; spatial-with-opacity : spatial-visual? spatial-opacity? -> spatial-visual?
;;   Returns a copy with its semantic opacity replaced.
;
; spatial-local-bounds : spatial-visual? -> aabb3?
;;   Returns bounds in this object's untransformed local coordinates.
(define-generics spatial-visual
  (spatial-id spatial-visual)
  (spatial-transform spatial-visual)
  (spatial-with-transform spatial-visual transform)
  (spatial-opacity spatial-visual)
  (spatial-with-opacity spatial-visual opacity)
  (spatial-local-bounds spatial-visual))


;;;
;;; Validation
;;;

; spatial-opacity? : any/c -> boolean?
;;   Reports whether value is a finite opacity in the closed unit interval.
(define (spatial-opacity? value)
  (and (finite-real? value)
       (<= 0 value 1)))

(define (check-spatial-visual who value)
  (unless (spatial-visual? value)
    (raise-argument-error who "spatial-visual?" value)))

(define (check-spatial-transform who value)
  (unless (transform3? value)
    (raise-argument-error who "transform3?" value)))


;;;
;;; Transform Conveniences
;;;

; spatial-position : spatial-visual? -> vec3?
;;   Returns the translation component of an object's local transform.
(define (spatial-position object)
  (check-spatial-visual 'spatial-position object)
  (transform3-translation (spatial-transform object)))

; spatial-with-position : spatial-visual? vec3? -> spatial-visual?
;;   Returns object with its local translation replaced.
(define (spatial-with-position object position)
  (check-spatial-visual 'spatial-with-position object)
  (unless (vec3? position)
    (raise-argument-error 'spatial-with-position "vec3?" position))
  (spatial-with-transform
   object
   (make-transform3
    #:translation position
    #:rotation (transform3-rotation (spatial-transform object))
    #:scale (transform3-scale (spatial-transform object)))))

; spatial-rotation : spatial-visual? -> rotation3?
;;   Returns the rotation component of an object's local transform.
(define (spatial-rotation object)
  (check-spatial-visual 'spatial-rotation object)
  (transform3-rotation (spatial-transform object)))

; spatial-with-rotation : spatial-visual? rotation3? -> spatial-visual?
;;   Returns object with its local rotation replaced.
(define (spatial-with-rotation object rotation)
  (check-spatial-visual 'spatial-with-rotation object)
  (unless (rotation3? rotation)
    (raise-argument-error 'spatial-with-rotation "rotation3?" rotation))
  (spatial-with-transform
   object
   (make-transform3
    #:translation (transform3-translation (spatial-transform object))
    #:rotation rotation
    #:scale (transform3-scale (spatial-transform object)))))

; spatial-scale : spatial-visual? -> vec3?
;;   Returns the scale component of an object's local transform.
(define (spatial-scale object)
  (check-spatial-visual 'spatial-scale object)
  (transform3-scale (spatial-transform object)))

; spatial-with-scale : spatial-visual? vec3? -> spatial-visual?
;;   Returns object with its local scale replaced.
(define (spatial-with-scale object scale)
  (check-spatial-visual 'spatial-with-scale object)
  (unless (and (vec3? scale)
               (not (zero? (vec3-x scale)))
               (not (zero? (vec3-y scale)))
               (not (zero? (vec3-z scale))))
    (raise-argument-error
     'spatial-with-scale
     "vec3 with finite nonzero scale components"
     scale))
  (spatial-with-transform
   object
   (make-transform3
    #:translation (transform3-translation (spatial-transform object))
    #:rotation (transform3-rotation (spatial-transform object))
    #:scale scale)))
