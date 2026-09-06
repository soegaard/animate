#lang racket/base

;;;
;;; Decomposed Three-Dimensional Transforms
;;;

;; Defines author-oriented scale-then-rotate-then-translate transforms. The
;; representation deliberately keeps rotation separate from scale; composing
;; arbitrary nonuniform transforms may introduce shear, so composition returns
;; a general affine3 map rather than silently dropping that information.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../geometry.rkt"
         "affine3.rkt"
         "linear3.rkt"
         "rotation3.rkt"
         "vec3.rkt")

;; Exports
(provide (struct-out transform3)
         make-transform3
         identity-transform3
         transform3->affine3
         transform3-compose
         transform3-apply-point
         transform3-lerp)


;;;
;;; Data Representation
;;;

; nonzero-scale3? : any/c -> boolean?
;;   Reports whether value is a finite three-component scale with no zero axis.
(define (nonzero-scale3? value)
  (and (vec3? value)
       (not (zero? (vec3-x value)))
       (not (zero? (vec3-y value)))
       (not (zero? (vec3-z value)))))

(struct transform3 (translation rotation scale)
  #:transparent
  #:guard
  (lambda (translation rotation scale who)
    (unless (vec3? translation)
      (raise-argument-error who "vec3?" translation))
    (unless (rotation3? rotation)
      (raise-argument-error who "rotation3?" rotation))
    (unless (nonzero-scale3? scale)
      (raise-argument-error
       who
       "vec3 with finite nonzero scale components"
       scale))
    (values translation rotation scale)))

;; transform3 represents one decomposed local-to-world transform.
;;  - translation  vec3?                         final world displacement.
;;  - rotation     rotation3?                    proper rotation after scale.
;;  - scale        vec3? with nonzero components  componentwise local scale.
;; Components act in significant order: scale, then rotate, then translate.


;;;
;;; Construction
;;;

; make-transform3 : [#:translation vec3?] [#:rotation rotation3?]
;                   [#:scale nonzero-scale3?] -> transform3?
;;   Creates a validated scale-then-rotate-then-translate transform.
(define (make-transform3 #:translation [translation origin3]
                         #:rotation [rotation identity-rotation3]
                         #:scale [scale (vec3 1 1 1)])
  (transform3 translation rotation scale))

; identity-transform3 : transform3?
;;   Gives the transform that leaves every spatial point unchanged.
(define identity-transform3
  (make-transform3))


;;;
;;; Transformation Operations
;;;

; transform3->affine3 : transform3? -> affine3?
;;   Converts decomposed scale, rotation, and translation to a full affine map.
(define (transform3->affine3 transform)
  (check-transform3 'transform3->affine3 transform)
  (affine3
   (linear3-compose
    (rotation3->linear3 (transform3-rotation transform))
    (scale->linear3 (transform3-scale transform)))
   (transform3-translation transform)))

; transform3-compose : transform3? transform3? -> affine3?
;;   Returns outer ∘ inner as a full affine map, retaining any induced shear.
(define (transform3-compose outer inner)
  (check-transform3 'transform3-compose outer)
  (check-transform3 'transform3-compose inner)
  (affine3-compose (transform3->affine3 outer)
                   (transform3->affine3 inner)))

; transform3-apply-point : transform3? vec3? -> vec3?
;;   Applies scale, then rotation, then translation to point.
(define (transform3-apply-point transform point)
  (check-transform3 'transform3-apply-point transform)
  (unless (vec3? point)
    (raise-argument-error 'transform3-apply-point "vec3?" point))
  (affine3-apply-point (transform3->affine3 transform) point))

; transform3-lerp : transform3? transform3? unit-real? -> transform3?
;;   Interpolates translation, rotation, and scale with exact endpoints.
(define (transform3-lerp from to progress)
  (check-transform3 'transform3-lerp from)
  (check-transform3 'transform3-lerp to)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'transform3-lerp
                          "finite real in the closed unit interval"
                          progress))
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [else
         (when (scale-interpolation-crosses-zero?
                (transform3-scale from) (transform3-scale to))
           (raise-arguments-error
            'transform3-lerp
            "scale interpolation would pass through zero"
            "from-scale" (transform3-scale from)
            "to-scale" (transform3-scale to)))
         (define scale
           (vec3-lerp (transform3-scale from)
                      (transform3-scale to)
                      progress))
         ;; A decomposed scale cannot pass through zero without becoming
         ;; singular, so reject endpoints that would force such an interior.
         (unless (nonzero-scale3? scale)
           (raise-arguments-error
            'transform3-lerp
            "scale interpolation passes through zero"
            "from-scale" (transform3-scale from)
            "to-scale" (transform3-scale to)
            "progress" progress))
         (transform3
          (vec3-lerp (transform3-translation from)
                     (transform3-translation to)
                     progress)
          (rotation3-slerp (transform3-rotation from)
                           (transform3-rotation to)
                           progress)
          scale)]))


;;;
;;; Local Helpers
;;;

; scale-interpolation-crosses-zero? : vec3? vec3? -> boolean?
;;   Reports whether any corresponding nonzero component has opposite signs.
(define (scale-interpolation-crosses-zero? from to)
  (or (negative? (* (vec3-x from) (vec3-x to)))
      (negative? (* (vec3-y from) (vec3-y to)))
      (negative? (* (vec3-z from) (vec3-z to)))))

; scale->linear3 : nonzero-scale3? -> linear3?
;;   Converts a componentwise scale to its diagonal matrix.
(define (scale->linear3 scale)
  (linear3 (vec3-x scale) 0 0
           0 (vec3-y scale) 0
           0 0 (vec3-z scale)))

; check-transform3 : symbol? any/c -> void?
;;   Raises an argument error unless value is a transform3.
(define (check-transform3 who value)
  (unless (transform3? value)
    (raise-argument-error who "transform3?" value)))
