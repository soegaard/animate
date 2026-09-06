#lang racket/base

;;;
;;; Three-Dimensional Rotations
;;;

;; Defines proper spatial rotations as normalized, sign-canonical quaternions.
;; Raw quaternion construction remains private so every public rotation has one
;; stable representation and composes without accumulating non-unit scale.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/math pi)
         "../geometry.rkt"
         "linear3.rkt"
         "vec3.rkt")

;; Exports
(provide rotation3?
         rotation3-components
         identity-rotation3
         axis-angle
         rotation3-from-to
         rotation3-look-at
         rotation3-compose
         rotation3-invert
         rotation3-apply
         rotation3->linear3
         rotation3-slerp)


;;;
;;; Data Representation
;;;

(struct rotation3-value (w x y z)
  #:transparent)

;; rotation3-value stores a normalized quaternion in scalar-first order.
;;  - w  finite-real?  scalar component.
;;  - x  finite-real?  coefficient of the rightward unit axis.
;;  - y  finite-real?  coefficient of the upward unit axis.
;;  - z  finite-real?  coefficient of the outward unit axis.
;; The stored sign is canonical: the first nonzero component is positive.

(define rotation3? rotation3-value?)


;;;
;;; Construction
;;;

; rotation3-components : rotation3? -> (vectorof finite-real?)
;;   Returns a debugging snapshot of the scalar-first normalized quaternion.
(define (rotation3-components rotation)
  (check-rotation3 'rotation3-components rotation)
  (vector-immutable (rotation3-value-w rotation)
                    (rotation3-value-x rotation)
                    (rotation3-value-y rotation)
                    (rotation3-value-z rotation)))

; identity-rotation3 : rotation3?
;;   Gives the identity spatial rotation.
(define identity-rotation3
  (rotation3-value 1 0 0 0))

; axis-angle : vec3? finite-real? -> rotation3?
;;   Returns the right-handed rotation through angle around nonzero axis.
(define (axis-angle axis angle)
  (unless (vec3? axis)
    (raise-argument-error 'axis-angle "vec3?" axis))
  (unless (finite-real? angle)
    (raise-argument-error 'axis-angle "finite real?" angle))
  (define unit-axis (vec3-normalize axis))
  (define half-angle (/ angle 2))
  (define sine (sin half-angle))
  (make-rotation3 (cos half-angle)
                  (* sine (vec3-x unit-axis))
                  (* sine (vec3-y unit-axis))
                  (* sine (vec3-z unit-axis))))

; rotation3-from-to : vec3? vec3? -> rotation3?
;;   Returns the shortest rotation sending from-direction to to-direction.
(define (rotation3-from-to from-direction to-direction)
  (unless (vec3? from-direction)
    (raise-argument-error 'rotation3-from-to "vec3?" from-direction))
  (unless (vec3? to-direction)
    (raise-argument-error 'rotation3-from-to "vec3?" to-direction))
  (define from (vec3-normalize from-direction))
  (define to (vec3-normalize to-direction))
  (define cosine (clamp-unit (vec3-dot from to)))
  (cond
    [(>= cosine (- 1 1e-12)) identity-rotation3]
    [(<= cosine (+ -1 1e-12))
     (axis-angle (perpendicular-axis from) pi)]
    [else
     (define cross (vec3-cross from to))
     (make-rotation3 (+ 1 cosine)
                     (vec3-x cross)
                     (vec3-y cross)
                     (vec3-z cross))]))

; rotation3-look-at : vec3? [#:up vec3?] -> rotation3?
;;   Maps local +z to forward while keeping local +y as close to up as possible.
(define (rotation3-look-at forward #:up [up y-axis3])
  (unless (vec3? forward)
    (raise-argument-error 'rotation3-look-at "vec3?" forward))
  (unless (vec3? up)
    (raise-argument-error 'rotation3-look-at "vec3?" up))
  (define unit-forward (vec3-normalize forward))
  (define right-candidate (vec3-cross up unit-forward))
  (when (zero? (vec3-length right-candidate))
    (raise-arguments-error 'rotation3-look-at
                           "up must not be parallel to forward"
                           "forward" forward
                           "up" up))
  (define right (vec3-normalize right-candidate))
  (define corrected-up (vec3-cross unit-forward right))
  (rotation3-from-column-matrix
   right corrected-up unit-forward))


;;;
;;; Rotation Operations
;;;

; rotation3-compose : rotation3? rotation3? -> rotation3?
;;   Returns outer ∘ inner, so inner rotates a vector first.
(define (rotation3-compose outer inner)
  (check-rotation3 'rotation3-compose outer)
  (check-rotation3 'rotation3-compose inner)
  (define ow (rotation3-value-w outer))
  (define ox (rotation3-value-x outer))
  (define oy (rotation3-value-y outer))
  (define oz (rotation3-value-z outer))
  (define iw (rotation3-value-w inner))
  (define ix (rotation3-value-x inner))
  (define iy (rotation3-value-y inner))
  (define iz (rotation3-value-z inner))
  (make-rotation3
   (- (* ow iw) (* ox ix) (* oy iy) (* oz iz))
   (+ (* ow ix) (* ox iw) (* oy iz) (- (* oz iy)))
   (+ (* ow iy) (- (* ox iz)) (* oy iw) (* oz ix))
   (+ (* ow iz) (* ox iy) (- (* oy ix)) (* oz iw))))

; rotation3-invert : rotation3? -> rotation3?
;;   Returns the inverse rotation.
(define (rotation3-invert rotation)
  (check-rotation3 'rotation3-invert rotation)
  (make-rotation3 (rotation3-value-w rotation)
                  (- (rotation3-value-x rotation))
                  (- (rotation3-value-y rotation))
                  (- (rotation3-value-z rotation))))

; rotation3-apply : rotation3? vec3? -> vec3?
;;   Applies rotation to vector.
(define (rotation3-apply rotation vector)
  (check-rotation3 'rotation3-apply rotation)
  (unless (vec3? vector)
    (raise-argument-error 'rotation3-apply "vec3?" vector))
  (linear3-apply-vector (rotation3->linear3 rotation) vector))

; rotation3->linear3 : rotation3? -> linear3?
;;   Converts rotation to its corresponding proper orthogonal matrix.
(define (rotation3->linear3 rotation)
  (check-rotation3 'rotation3->linear3 rotation)
  (define w (rotation3-value-w rotation))
  (define x (rotation3-value-x rotation))
  (define y (rotation3-value-y rotation))
  (define z (rotation3-value-z rotation))
  (linear3
   (- 1 (* 2 (+ (* y y) (* z z))))
   (* 2 (- (* x y) (* z w)))
   (* 2 (+ (* x z) (* y w)))
   (* 2 (+ (* x y) (* z w)))
   (- 1 (* 2 (+ (* x x) (* z z))))
   (* 2 (- (* y z) (* x w)))
   (* 2 (- (* x z) (* y w)))
   (* 2 (+ (* y z) (* x w)))
   (- 1 (* 2 (+ (* x x) (* y y))))))

; rotation3-slerp : rotation3? rotation3? unit-real? -> rotation3?
;;   Interpolates along the shortest rotational path with exact endpoints.
(define (rotation3-slerp from to progress)
  (check-rotation3 'rotation3-slerp from)
  (check-rotation3 'rotation3-slerp to)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'rotation3-slerp
                          "finite real in the closed unit interval"
                          progress))
  (cond
    [(zero? progress) from]
    [(= progress 1) to]
    [else
     (define raw-dot (rotation3-dot from to))
     ;; q and -q represent one rotation. Negate only the interpolation target
     ;; when required so the arc is never longer than pi.
     (define sign (if (negative? raw-dot) -1 1))
     (define cosine (* sign raw-dot))
     (define target-w (* sign (rotation3-value-w to)))
     (define target-x (* sign (rotation3-value-x to)))
     (define target-y (* sign (rotation3-value-y to)))
     (define target-z (* sign (rotation3-value-z to)))
     (if (> cosine 0.9995)
         (make-rotation3
          (+ (rotation3-value-w from)
             (* progress (- target-w (rotation3-value-w from))))
          (+ (rotation3-value-x from)
             (* progress (- target-x (rotation3-value-x from))))
          (+ (rotation3-value-y from)
             (* progress (- target-y (rotation3-value-y from))))
          (+ (rotation3-value-z from)
             (* progress (- target-z (rotation3-value-z from)))))
         (let* ([angle (acos (clamp-unit cosine))]
                [sine (sin angle)]
                [from-weight (/ (sin (* (- 1 progress) angle)) sine)]
                [to-weight (/ (sin (* progress angle)) sine)])
           (make-rotation3
            (+ (* from-weight (rotation3-value-w from))
               (* to-weight target-w))
            (+ (* from-weight (rotation3-value-x from))
               (* to-weight target-x))
            (+ (* from-weight (rotation3-value-y from))
               (* to-weight target-y))
            (+ (* from-weight (rotation3-value-z from))
               (* to-weight target-z)))))]))


;;;
;;; Quaternion Helpers
;;;

; make-rotation3 : finite-real? finite-real? finite-real? finite-real?
;                  -> rotation3?
;;   Normalizes and sign-canonicalizes one internal quaternion.
(define (make-rotation3 w x y z)
  (for ([component (in-list (list w x y z))])
    (unless (finite-real? component)
      (raise-argument-error 'make-rotation3 "finite real quaternion component" component)))
  (define magnitude (sqrt (+ (* w w) (* x x) (* y y) (* z z))))
  (when (zero? magnitude)
    (raise-arguments-error 'make-rotation3
                           "quaternion must have nonzero length"
                           "components" (list w x y z)))
  (define normalized-w (/ w magnitude))
  (define normalized-x (/ x magnitude))
  (define normalized-y (/ y magnitude))
  (define normalized-z (/ z magnitude))
  (define sign
    (canonical-quaternion-sign normalized-w normalized-x normalized-y normalized-z))
  (rotation3-value (* sign normalized-w)
                   (* sign normalized-x)
                   (* sign normalized-y)
                   (* sign normalized-z)))

; canonical-quaternion-sign : finite-real? finite-real? finite-real? finite-real?
;                             -> (or/c 1 -1)
;;   Chooses the representative whose first nonzero component is positive.
(define (canonical-quaternion-sign w x y z)
  (cond [(not (zero? w)) (if (negative? w) -1 1)]
        [(not (zero? x)) (if (negative? x) -1 1)]
        [(not (zero? y)) (if (negative? y) -1 1)]
        [else (if (negative? z) -1 1)]))

; rotation3-dot : rotation3? rotation3? -> finite-real?
;;   Returns the four-dimensional quaternion dot product.
(define (rotation3-dot first second)
  (+ (* (rotation3-value-w first) (rotation3-value-w second))
     (* (rotation3-value-x first) (rotation3-value-x second))
     (* (rotation3-value-y first) (rotation3-value-y second))
     (* (rotation3-value-z first) (rotation3-value-z second))))

; clamp-unit : finite-real? -> finite-real?
;;   Clamps rounding noise to the closed cosine interval.
(define (clamp-unit value)
  (min 1 (max -1 value)))

; perpendicular-axis : vec3? -> vec3?
;;   Returns a deterministic nonzero axis perpendicular to unit-direction.
(define (perpendicular-axis unit-direction)
  (define candidate
    (cond [(and (<= (abs (vec3-x unit-direction)) (abs (vec3-y unit-direction)))
                (<= (abs (vec3-x unit-direction)) (abs (vec3-z unit-direction))))
           x-axis3]
          [(<= (abs (vec3-y unit-direction)) (abs (vec3-z unit-direction)))
           y-axis3]
          [else z-axis3]))
  (vec3-normalize (vec3-cross unit-direction candidate)))

; rotation3-from-column-matrix : vec3? vec3? vec3? -> rotation3?
;;   Converts the right, up, and forward columns of an orthonormal matrix.
(define (rotation3-from-column-matrix right up forward)
  (define m00 (vec3-x right))
  (define m01 (vec3-x up))
  (define m02 (vec3-x forward))
  (define m10 (vec3-y right))
  (define m11 (vec3-y up))
  (define m12 (vec3-y forward))
  (define m20 (vec3-z right))
  (define m21 (vec3-z up))
  (define m22 (vec3-z forward))
  (define trace (+ m00 m11 m22))
  (cond
    [(positive? trace)
     (define scale (* 2 (sqrt (+ trace 1))))
     (make-rotation3 (/ scale 4)
                     (/ (- m21 m12) scale)
                     (/ (- m02 m20) scale)
                     (/ (- m10 m01) scale))]
    [(and (> m00 m11) (> m00 m22))
     (define scale (* 2 (sqrt (+ 1 m00 (- m11) (- m22)))))
     (make-rotation3 (/ (- m21 m12) scale)
                     (/ scale 4)
                     (/ (+ m01 m10) scale)
                     (/ (+ m02 m20) scale))]
    [(> m11 m22)
     (define scale (* 2 (sqrt (+ 1 m11 (- m00) (- m22)))))
     (make-rotation3 (/ (- m02 m20) scale)
                     (/ (+ m01 m10) scale)
                     (/ scale 4)
                     (/ (+ m12 m21) scale))]
    [else
     (define scale (* 2 (sqrt (+ 1 m22 (- m00) (- m11)))))
     (make-rotation3 (/ (- m10 m01) scale)
                     (/ (+ m02 m20) scale)
                     (/ (+ m12 m21) scale)
                     (/ scale 4))]))

; check-rotation3 : symbol? any/c -> void?
;;   Raises an argument error unless value is a rotation3.
(define (check-rotation3 who value)
  (unless (rotation3? value)
    (raise-argument-error who "rotation3?" value)))
