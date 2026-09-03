#lang racket/base

;;;
;;; Affine Transform Model
;;;

;; Defines immutable translation, rotation, and scale data for two-dimensional
;; Visuals, plus general two-dimensional linear and affine maps.
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
         affine-transform-apply-point
         linear2
         linear2?
         linear2-a
         linear2-b
         linear2-c
         linear2-d
         make-linear2
         identity-linear2
         linear2-determinant
         linear2-compose
         linear2-apply-vector
         affine2
         affine2?
         affine2-a
         affine2-b
         affine2-h
         affine2-c
         affine2-d
         affine2-k
         affine2-linear
         affine2-translation
         make-affine2
         identity-affine2
         affine2-with-linear
         affine2-with-translation
         affine2-compose
         affine2-lerp
         affine2-apply-vector
         affine2-apply-point
         affine-transform->affine2)


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
;;; General Linear and Affine Maps

;; linear2 represents the matrix
;;
;;     [ a b ]
;;     [ c d ]
;;
;; acting on column vectors.  All entries are finite, but the matrix may be
;; singular: a continuous animation to a reflection necessarily passes through
;; such a map under entry-wise interpolation.
(struct linear2 (a b c d)
  #:transparent
  #:guard
  (lambda (a b c d who)
    (for ([entry (in-list (list a b c d))])
      (unless (finite-real? entry)
        (raise-argument-error who "four finite real matrix entries" entry)))
    (values a b c d)))

;; make-linear2 : finite-real? finite-real? finite-real? finite-real? -> linear2?
;; Creates the linear map whose matrix is [a b; c d].  Arguments follow
;; ordinary row order, so a matrix literal can be indented naturally:
;;
;;   (linear2 a b
;;            c d)
(define (make-linear2 a b c d)
  (linear2 a b c d))

;; identity-linear2 : linear2?
(define identity-linear2
  (make-linear2 1 0 0 1))

;; linear2-determinant : linear2? -> finite-real?
(define (linear2-determinant map)
  (check-linear2 'linear2-determinant map)
  (- (* (linear2-a map) (linear2-d map))
     (* (linear2-b map) (linear2-c map))))

;; linear2-compose : linear2? linear2? -> linear2?
;; Returns outer ∘ inner, so the inner map acts first.
(define (linear2-compose outer inner)
  (check-linear2 'linear2-compose outer)
  (check-linear2 'linear2-compose inner)
  (make-linear2
   (+ (* (linear2-a outer) (linear2-a inner))
      (* (linear2-b outer) (linear2-c inner)))
   (+ (* (linear2-a outer) (linear2-b inner))
      (* (linear2-b outer) (linear2-d inner)))
   (+ (* (linear2-c outer) (linear2-a inner))
      (* (linear2-d outer) (linear2-c inner)))
   (+ (* (linear2-c outer) (linear2-b inner))
      (* (linear2-d outer) (linear2-d inner)))))

;; linear2-apply-vector : linear2? vec2? -> vec2?
(define (linear2-apply-vector map vector)
  (check-linear2 'linear2-apply-vector map)
  (unless (vec2? vector)
    (raise-argument-error 'linear2-apply-vector "vec2?" vector))
  (vec2 (+ (* (linear2-a map) (vec2-x vector))
           (* (linear2-b map) (vec2-y vector)))
        (+ (* (linear2-c map) (vec2-x vector))
           (* (linear2-d map) (vec2-y vector)))))

;; affine2 represents a general linear map followed by translation.  It is
;; intentionally separate from affine-transform: the latter remains the stable
;; decomposed translation/rotation/positive-scale public protocol.
;;
;; The constructor also follows ordinary augmented-row order:
;;
;;   (affine2 a b h
;;            c d k)
;;
;; represents x' = a*x + b*y + h and y' = c*x + d*y + k.
(struct affine2 (a b h c d k)
  #:transparent
  #:guard
  (lambda (a b h c d k who)
    (for ([entry (in-list (list a b h c d k))])
      (unless (finite-real? entry)
        (raise-argument-error who "six finite real affine-map entries" entry)))
    (values a b h c d k)))

;; affine2-linear : affine2? -> linear2?
;; Extracts the matrix portion in the same row order as linear2.
(define (affine2-linear map)
  (check-affine2 'affine2-linear map)
  (linear2 (affine2-a map) (affine2-b map)
           (affine2-c map) (affine2-d map)))

;; affine2-translation : affine2? -> vec2?
;; Extracts the translation column (h, k).
(define (affine2-translation map)
  (check-affine2 'affine2-translation map)
  (vec2 (affine2-h map) (affine2-k map)))

;; make-affine2 : [#:linear linear2?] [#:translation vec2?] -> affine2?
(define (make-affine2 #:linear [linear identity-linear2]
                      #:translation [translation origin])
  (unless (linear2? linear)
    (raise-argument-error 'make-affine2 "linear2?" linear))
  (unless (vec2? translation)
    (raise-argument-error 'make-affine2 "vec2?" translation))
  (affine2 (linear2-a linear)
           (linear2-b linear)
           (vec2-x translation)
           (linear2-c linear)
           (linear2-d linear)
           (vec2-y translation)))

;; identity-affine2 : affine2?
(define identity-affine2
  (make-affine2))

;; affine2-with-linear : affine2? linear2? -> affine2?
(define (affine2-with-linear map linear)
  (check-affine2 'affine2-with-linear map)
  (unless (linear2? linear)
    (raise-argument-error 'affine2-with-linear "linear2?" linear))
  (affine2 (linear2-a linear)
           (linear2-b linear)
           (affine2-h map)
           (linear2-c linear)
           (linear2-d linear)
           (affine2-k map)))

;; affine2-with-translation : affine2? vec2? -> affine2?
(define (affine2-with-translation map translation)
  (check-affine2 'affine2-with-translation map)
  (unless (vec2? translation)
    (raise-argument-error 'affine2-with-translation "vec2?" translation))
  (affine2 (affine2-a map)
           (affine2-b map)
           (vec2-x translation)
           (affine2-c map)
           (affine2-d map)
           (vec2-y translation)))

;; affine2-compose : affine2? affine2? -> affine2?
;; Returns outer ∘ inner, so the inner map acts first.
(define (affine2-compose outer inner)
  (check-affine2 'affine2-compose outer)
  (check-affine2 'affine2-compose inner)
  (make-affine2
   #:linear
   (linear2-compose (affine2-linear outer)
                    (affine2-linear inner))
   #:translation
   (vec2+
    (linear2-apply-vector (affine2-linear outer)
                          (affine2-translation inner))
    (affine2-translation outer))))

;; affine2-lerp : affine2? affine2? unit-real? -> affine2?
;; Interpolates matrix entries and translations. Singular interior maps are
;; valid and render deterministically; callers needing invertibility must
;; choose endpoints/interpolation accordingly.
(define (affine2-lerp from to progress)
  (check-affine2 'affine2-lerp from)
  (check-affine2 'affine2-lerp to)
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error 'affine2-lerp
                          "finite real in the closed unit interval"
                          progress))
  (define from-linear (affine2-linear from))
  (define to-linear (affine2-linear to))
  (make-affine2
   #:linear
   (make-linear2
    (real-lerp (linear2-a from-linear) (linear2-a to-linear) progress)
    (real-lerp (linear2-b from-linear) (linear2-b to-linear) progress)
    (real-lerp (linear2-c from-linear) (linear2-c to-linear) progress)
    (real-lerp (linear2-d from-linear) (linear2-d to-linear) progress))
   #:translation
   (vec2-lerp (affine2-translation from)
              (affine2-translation to)
              progress)))

;; affine2-apply-vector : affine2? vec2? -> vec2?
(define (affine2-apply-vector map vector)
  (check-affine2 'affine2-apply-vector map)
  (linear2-apply-vector (affine2-linear map) vector))

;; affine2-apply-point : affine2? vec2? -> vec2?
(define (affine2-apply-point map point)
  (check-affine2 'affine2-apply-point map)
  (unless (vec2? point)
    (raise-argument-error 'affine2-apply-point "vec2?" point))
  (vec2+ (affine2-translation map)
         (affine2-apply-vector map point)))

;; affine-transform->affine2 : affine-transform? -> affine2?
;; Converts the established scale-then-rotate-then-translate representation to
;; its exact matrix form.
(define (affine-transform->affine2 transform)
  (check-affine-transform 'affine-transform->affine2 transform)
  (define scale (affine-transform-scale transform))
  (define angle (affine-transform-rotation transform))
  (define cosine (cos angle))
  (define sine (sin angle))
  (make-affine2
   #:linear
   (make-linear2 (* cosine (vec2-x scale))
                 (* (- sine) (vec2-y scale))
                 (* sine (vec2-x scale))
                 (* cosine (vec2-y scale)))
   #:translation (affine-transform-translation transform)))


;;;
;;; Validation
;;;

; check-affine-transform : symbol? any/c -> void?
;;   Raises an argument error unless value is an affine transform.
(define (check-affine-transform who value)
  (unless (affine-transform? value)
    (raise-argument-error who "affine-transform?" value)))

(define (check-linear2 who value)
  (unless (linear2? value)
    (raise-argument-error who "linear2?" value)))

(define (check-affine2 who value)
  (unless (affine2? value)
    (raise-argument-error who "affine2?" value)))
