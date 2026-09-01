#lang racket/base

;;;
;;; Axes Visual Model
;;;

;; Defines immutable semantic Cartesian axes, numeric ranges, tick placement,
;; and coordinate conversion.
;;
;; Axes geometry is stored in local mathematical coordinates. This module has
;; no Pict, drawing-context, bitmap, filesystem, process, or browser dependency.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "color-style.rkt"
         (only-in "arrow-visual.rkt" arrowhead-subpath)
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out axis-range)
         axis-range-contains?
         axis-range-tick-values
         axes
         axes-visual?
         axes-visual-x-range
         axes-visual-y-range
         axes-visual-x-length
         axes-visual-y-length
         axes-visual-stroke
         axes-visual-stroke-width
         axes-visual-tick-size
         axes-visual-tip-length
         axes-visual-tip-width
         axes-visual-x-tip?
         axes-visual-y-tip?
         axes-x-unit-length
         axes-y-unit-length
         axes-coordinates->point
         axes-point->coordinates
         axes-visual-path-geometry)


;;;
;;; Axis Ranges
;;;

(struct axis-range (minimum maximum tick-step)
  #:transparent
  #:guard
  (lambda (minimum maximum tick-step who)
    (unless (finite-real? minimum)
      (raise-argument-error who "finite real?" minimum))
    (unless (finite-real? maximum)
      (raise-argument-error who "finite real?" maximum))
    (unless (< minimum maximum)
      (raise-arguments-error
       who
       "the minimum must be less than the maximum"
       "minimum" minimum
       "maximum" maximum))
    (define span
      (- maximum minimum))
    (unless (and (finite-real? span)
                 (positive? span))
      (raise-arguments-error
       who
       "the range span must be a positive finite real"
       "minimum" minimum
       "maximum" maximum
       "span" span))
    (unless (<= minimum 0 maximum)
      (raise-arguments-error
       who
       "the range must contain zero"
       "minimum" minimum
       "maximum" maximum))
    (unless (and (finite-real? tick-step)
                 (positive? tick-step))
      (raise-argument-error who "positive finite real?" tick-step))
    (values minimum maximum tick-step)))

;; axis-range represents one numeric axis interval and its regular tick step.
;;  - minimum    finite-real?           smallest represented coordinate.
;;  - maximum    finite-real?           largest represented coordinate.
;;  - tick-step  positive finite real?  spacing between tick coordinates.
;;
;; The interval must contain zero. Tick values are ordered from minimum to
;; maximum and exclude zero because the two axes already intersect there.

; axis-range-contains? : axis-range? any/c -> boolean?
;;   Reports whether value is a finite coordinate in range's closed interval.
(define (axis-range-contains? range value)
  (unless (axis-range? range)
    (raise-argument-error 'axis-range-contains? "axis-range?" range))
  (and (finite-real? value)
       (<= (axis-range-minimum range)
           value
           (axis-range-maximum range))))

; axis-range-tick-values : axis-range? -> (listof finite-real?)
;;   Returns ordered nonzero integer multiples of the range's tick step.
(define (axis-range-tick-values range)
  (unless (axis-range? range)
    (raise-argument-error 'axis-range-tick-values "axis-range?" range))
  (define step
    (axis-range-tick-step range))
  (define minimum-index
    (tick-index-quotient range
                         (axis-range-minimum range)))
  (define maximum-index
    (tick-index-quotient range
                         (axis-range-maximum range)))
  (define first-index
    (integer-ceiling
     (- minimum-index
        (tick-index-tolerance minimum-index))))
  (define last-index
    (integer-floor
     (+ maximum-index
        (tick-index-tolerance maximum-index))))
  (for/list ([index (in-range first-index (add1 last-index))]
             #:unless (zero? index))
    (* index step)))


;;;
;;; Axes Data Representation
;;;

(struct axes-visual
  (id
   transform
   opacity
   x-range
   y-range
   x-length
   y-length
   stroke
   stroke-width
   tick-size
   tip-length
   tip-width
   x-tip?
   y-tip?)
  #:transparent
  #:methods gen:visual
  [(define (visual-id axes)
     (axes-visual-id axes))
   (define (visual-position axes)
     (affine-transform-translation
      (axes-visual-transform axes)))
   (define (visual-with-position axes position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy axes-visual axes
                  [transform
                   (affine-transform-with-translation
                    (axes-visual-transform axes)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform axes)
     (axes-visual-transform axes))
   (define (visual-with-transform axes transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy axes-visual axes [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity axes)
     (axes-visual-opacity axes))
   (define (visual-with-opacity axes opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy axes-visual axes [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width axes)
     (axes-visual-stroke-width axes))
   (define (visual-with-stroke-width axes stroke-width)
     (unless (stroke-width? stroke-width)
       (raise-argument-error
        'visual-with-stroke-width
        "nonnegative finite real?"
        stroke-width))
     (struct-copy axes-visual axes [stroke-width stroke-width]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color axes)
     (axes-visual-stroke axes))
   (define (visual-with-stroke-color axes color)
     (unless (color-spec? color)
       (raise-argument-error 'visual-with-stroke-color "color-spec?" color))
     (struct-copy axes-visual axes [stroke color]))])

;; axes-visual represents one two-dimensional Cartesian coordinate system.
;;  - id            symbol?                    stable Visual identity.
;;  - transform     affine-transform?          placement and local deformation.
;;  - opacity       opacity?                   global rendering opacity.
;;  - x-range       axis-range?                significant horizontal interval.
;;  - y-range       axis-range?                significant vertical interval.
;;  - x-length      positive finite real?      local width of the x interval.
;;  - y-length      positive finite real?      local height of the y interval.
;;  - stroke        any/c                      opaque axis and tick style.
;;  - stroke-width  nonnegative finite real?   cosmetic line and outline width.
;;  - tick-size     nonnegative finite real?   local full tick length.
;;  - tip-length    positive finite real?      local maximum-end tip length.
;;  - tip-width     positive finite real?      local maximum-end tip base width.
;;  - x-tip?        boolean?                   whether the maximum x endpoint has a tip.
;;  - y-tip?        boolean?                   whether the maximum y endpoint has a tip.
;;
;; The ranges and their tick values have significant numeric order. Numeric
;; coordinate (0, 0) is the Visual reference position before affine deformation.


;;;
;;; Construction
;;;

; axes : #:id symbol?
;        [#:center vec2?]
;        [#:rotation finite-real?]
;        [#:scale scale-factor?]
;        [#:opacity opacity?]
;        [#:x-range axis-range?]
;        [#:y-range axis-range?]
;        [#:x-length positive-real?]
;        [#:y-length positive-real?]
;        [#:stroke any/c]
;        [#:stroke-width nonnegative-real?]
;        [#:tick-size nonnegative-real?]
;        [#:tip-length positive-real?]
;        [#:tip-width positive-real?]
;        [#:x-tip? boolean?]
;        [#:y-tip? boolean?]
;        -> axes-visual?
;;   Creates semantic Cartesian axes with regular ticks and optional tips.
(define (axes #:id id
              #:center [center origin]
              #:rotation [rotation 0]
              #:scale [scale 1]
              #:opacity [opacity 1]
              #:x-range [x-range (axis-range -6 6 1)]
              #:y-range [y-range (axis-range -3 3 1)]
              #:x-length [x-length 12]
              #:y-length [y-length 6]
              #:stroke [stroke "black"]
              #:stroke-width [stroke-width 2]
              #:tick-size [tick-size 3/20]
              #:tip-length [tip-length 3/10]
              #:tip-width [tip-width 1/4]
              #:x-tip? [x-tip? #t]
              #:y-tip? [y-tip? #t])
  (unless (symbol? id)
    (raise-argument-error 'axes "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'axes "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'axes "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'axes
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error 'axes "finite real in [0, 1]" opacity))
  (unless (axis-range? x-range)
    (raise-argument-error 'axes "axis-range?" x-range))
  (unless (axis-range? y-range)
    (raise-argument-error 'axes "axis-range?" y-range))
  (check-positive-finite-real 'axes "x-length" x-length)
  (check-positive-finite-real 'axes "y-length" y-length)
  (check-axis-unit-length 'axes "x-unit-length" x-range x-length)
  (check-axis-unit-length 'axes "y-unit-length" y-range y-length)
  (check-nonnegative-finite-real 'axes "stroke-width" stroke-width)
  (check-nonnegative-finite-real 'axes "tick-size" tick-size)
  (check-positive-finite-real 'axes "tip-length" tip-length)
  (check-positive-finite-real 'axes "tip-width" tip-width)
  (unless (boolean? x-tip?)
    (raise-argument-error 'axes "boolean?" x-tip?))
  (unless (boolean? y-tip?)
    (raise-argument-error 'axes "boolean?" y-tip?))
  (axes-visual id
               (make-affine-transform #:translation center
                                      #:rotation rotation
                                      #:scale scale)
               opacity
               x-range
               y-range
               x-length
               y-length
               stroke
               stroke-width
               tick-size
               tip-length
               tip-width
               x-tip?
               y-tip?))


;;;
;;; Coordinate Conversion
;;;

; axes-x-unit-length : axes-visual? -> positive-real?
;;   Returns the unscaled local length representing one x coordinate unit.
(define (axes-x-unit-length axes)
  (check-axes-visual 'axes-x-unit-length axes)
  (/ (axes-visual-x-length axes)
     (axis-range-span (axes-visual-x-range axes))))

; axes-y-unit-length : axes-visual? -> positive-real?
;;   Returns the unscaled local length representing one y coordinate unit.
(define (axes-y-unit-length axes)
  (check-axes-visual 'axes-y-unit-length axes)
  (/ (axes-visual-y-length axes)
     (axis-range-span (axes-visual-y-range axes))))

; axes-coordinates->point : axes-visual? finite-real? finite-real? -> vec2?
;;   Converts numeric x and y coordinates to the containing coordinate system.
(define (axes-coordinates->point axes x y)
  (check-axes-visual 'axes-coordinates->point axes)
  (unless (finite-real? x)
    (raise-argument-error 'axes-coordinates->point "finite real?" x))
  (unless (finite-real? y)
    (raise-argument-error 'axes-coordinates->point "finite real?" y))
  (affine-transform-apply-point
   (visual-transform axes)
   (vec2 (* x (axes-x-unit-length axes))
         (* y (axes-y-unit-length axes)))))

; axes-point->coordinates : axes-visual? vec2? -> vec2?
;;   Converts a containing-system point to numeric axis coordinates.
(define (axes-point->coordinates axes point)
  (check-axes-visual 'axes-point->coordinates axes)
  (unless (vec2? point)
    (raise-argument-error 'axes-point->coordinates "vec2?" point))
  (define local-point
    (affine-transform-unapply-point
     (visual-transform axes)
     point))
  (vec2 (/ (vec2-x local-point)
           (axes-x-unit-length axes))
        (/ (vec2-y local-point)
           (axes-y-unit-length axes))))


;;;
;;; Semantic Path Conversion
;;;

; axes-visual-path-geometry : axes-visual? -> path-geometry?
;;   Returns local shafts, ticks, and maximum-end tips in drawing order.
(define (axes-visual-path-geometry axes)
  (check-axes-visual 'axes-visual-path-geometry axes)
  (define x-start
    (axes-local-point axes
                      (axis-range-minimum
                       (axes-visual-x-range axes))
                      0))
  (define x-end
    (axes-local-point axes
                      (axis-range-maximum
                       (axes-visual-x-range axes))
                      0))
  (define y-start
    (axes-local-point axes
                      0
                      (axis-range-minimum
                       (axes-visual-y-range axes))))
  (define y-end
    (axes-local-point axes
                      0
                      (axis-range-maximum
                       (axes-visual-y-range axes))))
  (path-geometry
   (append
    (list (open-line-subpath x-start x-end)
          (open-line-subpath y-start y-end))
    (x-tick-subpaths axes)
    (y-tick-subpaths axes)
    (if (axes-visual-x-tip? axes)
        (list (arrowhead-subpath
               x-end
               x-start
               (axes-visual-tip-length axes)
               (axes-visual-tip-width axes)))
        '())
    (if (axes-visual-y-tip? axes)
        (list (arrowhead-subpath
               y-end
               y-start
               (axes-visual-tip-length axes)
               (axes-visual-tip-width axes)))
        '()))))

; axes-local-point : axes-visual? finite-real? finite-real? -> vec2?
;;   Converts numeric coordinates to local geometric coordinates.
(define (axes-local-point axes x y)
  (vec2 (* x (axes-x-unit-length axes))
        (* y (axes-y-unit-length axes))))

; x-tick-subpaths : axes-visual? -> (listof path-subpath?)
;;   Returns vertical x-axis tick segments in increasing coordinate order.
(define (x-tick-subpaths axes)
  (define half-tick-size
    (/ (axes-visual-tick-size axes) 2))
  (if (zero? half-tick-size)
      '()
      (for/list ([value
                  (in-list
                   (axis-range-tick-values
                    (axes-visual-x-range axes)))])
        (define center
          (axes-local-point axes value 0))
        (open-line-subpath
         (vec2+ center (vec2 0 (- half-tick-size)))
         (vec2+ center (vec2 0 half-tick-size))))))

; y-tick-subpaths : axes-visual? -> (listof path-subpath?)
;;   Returns horizontal y-axis tick segments in increasing coordinate order.
(define (y-tick-subpaths axes)
  (define half-tick-size
    (/ (axes-visual-tick-size axes) 2))
  (if (zero? half-tick-size)
      '()
      (for/list ([value
                  (in-list
                   (axis-range-tick-values
                    (axes-visual-y-range axes)))])
        (define center
          (axes-local-point axes 0 value))
        (open-line-subpath
         (vec2+ center (vec2 (- half-tick-size) 0))
         (vec2+ center (vec2 half-tick-size 0))))))

; open-line-subpath : vec2? vec2? -> path-subpath?
;;   Creates one open line subpath in start-to-end order.
(define (open-line-subpath start end)
  (path-subpath start
                (list (line-path-segment end))
                #f))


;;;
;;; Inverse Transform Helpers
;;;

; affine-transform-unapply-point : affine-transform? vec2? -> vec2?
;;   Removes translation, rotation, and scale from one containing-system point.
(define (affine-transform-unapply-point transform point)
  (define translated
    (vec2- point
           (affine-transform-translation transform)))
  (define angle
    (affine-transform-rotation transform))
  (define cosine
    (cos angle))
  (define sine
    (sin angle))
  (define unrotated
    (vec2 (+ (* cosine (vec2-x translated))
             (* sine (vec2-y translated)))
          (+ (* (- sine) (vec2-x translated))
             (* cosine (vec2-y translated)))))
  (define scale
    (affine-transform-scale transform))
  (vec2 (/ (vec2-x unrotated) (vec2-x scale))
        (/ (vec2-y unrotated) (vec2-y scale))))


;;;
;;; Numeric Helpers
;;;

; axis-range-span : axis-range? -> positive-real?
;;   Returns the validated finite distance from minimum to maximum.
(define (axis-range-span range)
  (- (axis-range-maximum range)
     (axis-range-minimum range)))

; tick-index-relative-tolerance : positive-real?
;;   Gives the fixed relative tolerance for inexact range endpoint indexes.
(define tick-index-relative-tolerance
  1e-12)

; tick-index-quotient : axis-range? finite-real? -> finite-real?
;;   Converts one range endpoint to a finite multiple of the tick step.
(define (tick-index-quotient range endpoint)
  (define quotient
    (/ endpoint (axis-range-tick-step range)))
  (unless (finite-real? quotient)
    (raise-arguments-error
     'axis-range-tick-values
     "the range bounds and tick step must produce finite tick indexes"
     "range" range
     "endpoint" endpoint
     "tick index" quotient))
  quotient)

; tick-index-tolerance : finite-real? -> nonnegative-real?
;;   Returns zero for exact indexes and a small relative inexact tolerance.
(define (tick-index-tolerance index)
  (if (exact? index)
      0
      (* tick-index-relative-tolerance
         (max 1.0 (abs index)))))

; integer-ceiling : finite-real? -> exact-integer?
;;   Returns the exact integer ceiling of a finite real.
(define (integer-ceiling value)
  (integer-value->exact (ceiling value)))

; integer-floor : finite-real? -> exact-integer?
;;   Returns the exact integer floor of a finite real.
(define (integer-floor value)
  (integer-value->exact (floor value)))

; integer-value->exact : integer? -> exact-integer?
;;   Converts an exact or inexact integer value to an exact integer.
(define (integer-value->exact value)
  (if (exact? value)
      value
      (inexact->exact value)))


;;;
;;; Validation
;;;

; check-axes-visual : symbol? any/c -> void?
;;   Raises an argument error unless value is an axes Visual.
(define (check-axes-visual who value)
  (unless (axes-visual? value)
    (raise-argument-error who "axes-visual?" value)))

; check-positive-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is positive and finite.
(define (check-positive-finite-real who field-name value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-arguments-error
     who
     "an axes dimension must be a positive finite real"
     field-name value)))

; check-axis-unit-length : symbol? string? axis-range? positive-real?
;                          -> void?
;;   Raises an argument error unless the range-to-length scale is finite.
(define (check-axis-unit-length who field-name range length)
  (define unit-length
    (/ length (axis-range-span range)))
  (unless (and (finite-real? unit-length)
               (positive? unit-length))
    (raise-arguments-error
     who
     "an axes unit length must be a positive finite real"
     field-name unit-length
     "range" range
     "length" length)))

; check-nonnegative-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-nonnegative-finite-real who field-name value)
  (unless (and (finite-real? value)
               (not (negative? value)))
    (raise-arguments-error
     who
     "an axes size or stroke width must be a nonnegative finite real"
     field-name value)))
