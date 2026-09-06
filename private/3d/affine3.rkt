#lang racket/base

;;;
;;; Three-Dimensional Affine Maps
;;;

;; Defines immutable general linear-plus-translation maps. These values retain
;; shear and reflections exactly, unlike the author-oriented decomposed
;; transform3 representation.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../geometry.rkt"
         "linear3.rkt"
         "vec3.rkt")

;; Exports
(provide affine3
         affine3?
         affine3-linear
         affine3-translation
         identity-affine3
         affine3-compose
         affine3-invert
         affine3-apply-point
         affine3-apply-vector
         affine3-normal-transform
         affine3-lerp)


;;;
;;; Data Representation
;;;

(struct affine3-value (linear translation)
  #:transparent)

;; affine3-value represents a full affine map applied to a point as
;; linear(point) + translation. The linear component can contain scale, shear,
;; rotation, reflection, or a singular map; translation is a world displacement.

(define affine3? affine3-value?)
(define affine3-linear affine3-value-linear)
(define affine3-translation affine3-value-translation)


;;;
;;; Construction and Queries
;;;

; affine3 : linear3? vec3? -> affine3?
;;   Constructs a validated full affine map from its linear and translation parts.
(define (affine3 linear translation)
  (unless (linear3? linear)
    (raise-argument-error 'affine3 "linear3?" linear))
  (unless (vec3? translation)
    (raise-argument-error 'affine3 "vec3?" translation))
  (affine3-value linear translation))

; identity-affine3 : affine3?
;;   Gives the affine map that leaves every point unchanged.
(define identity-affine3
  (affine3 identity-linear3 origin3))


;;;
;;; Transformation Operations
;;;

; affine3-compose : affine3? affine3? -> affine3?
;;   Returns outer ∘ inner, so inner acts first.
(define (affine3-compose outer inner)
  (check-affine3 'affine3-compose outer)
  (check-affine3 'affine3-compose inner)
  (affine3
   (linear3-compose (affine3-linear outer) (affine3-linear inner))
   (vec3+
    (linear3-apply-vector (affine3-linear outer)
                          (affine3-translation inner))
    (affine3-translation outer))))

; affine3-invert : affine3? -> affine3?
;;   Returns the inverse affine map, or raises an error for a singular linear part.
(define (affine3-invert map)
  (check-affine3 'affine3-invert map)
  (define inverse-linear (linear3-invert (affine3-linear map)))
  (affine3 inverse-linear
           (vec3-scale -1
                       (linear3-apply-vector inverse-linear
                                             (affine3-translation map)))))

; affine3-apply-point : affine3? vec3? -> vec3?
;;   Applies map's linear component and translation to point.
(define (affine3-apply-point map point)
  (check-affine3 'affine3-apply-point map)
  (unless (vec3? point)
    (raise-argument-error 'affine3-apply-point "vec3?" point))
  (vec3+ (linear3-apply-vector (affine3-linear map) point)
         (affine3-translation map)))

; affine3-apply-vector : affine3? vec3? -> vec3?
;;   Applies only map's linear component to displacement vector.
(define (affine3-apply-vector map vector)
  (check-affine3 'affine3-apply-vector map)
  (linear3-apply-vector (affine3-linear map) vector))

; affine3-normal-transform : affine3? -> linear3?
;;   Returns the inverse-transpose of map's linear component for normal vectors.
(define (affine3-normal-transform map)
  (check-affine3 'affine3-normal-transform map)
  (linear3-normal-transform (affine3-linear map)))

; affine3-lerp : affine3? affine3? unit-real? -> affine3?
;;   Interpolates matrix entries and translation, preserving exact endpoints.
(define (affine3-lerp from to progress)
  (check-affine3 'affine3-lerp from)
  (check-affine3 'affine3-lerp to)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'affine3-lerp
                          "finite real in the closed unit interval"
                          progress))
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [else
         (affine3 (linear3-lerp (affine3-linear from)
                                (affine3-linear to)
                                progress)
                  (vec3-lerp (affine3-translation from)
                             (affine3-translation to)
                             progress))]))


;;;
;;; Local Helpers
;;;

; linear3-lerp : linear3? linear3? unit-real? -> linear3?
;;   Interpolates corresponding matrix entries for affine-map animation.
(define (linear3-lerp from to progress)
  (linear3
   (lerp-entry linear3-m00 from to progress)
   (lerp-entry linear3-m01 from to progress)
   (lerp-entry linear3-m02 from to progress)
   (lerp-entry linear3-m10 from to progress)
   (lerp-entry linear3-m11 from to progress)
   (lerp-entry linear3-m12 from to progress)
   (lerp-entry linear3-m20 from to progress)
   (lerp-entry linear3-m21 from to progress)
   (lerp-entry linear3-m22 from to progress)))

; lerp-entry : (linear3? -> finite-real?) linear3? linear3? finite-real?
;              -> finite-real?
;;   Interpolates one named matrix entry.
(define (lerp-entry accessor from to progress)
  (+ (accessor from) (* progress (- (accessor to) (accessor from)))))

; check-affine3 : symbol? any/c -> void?
;;   Raises an argument error unless value is an affine3.
(define (check-affine3 who value)
  (unless (affine3? value)
    (raise-argument-error who "affine3?" value)))
