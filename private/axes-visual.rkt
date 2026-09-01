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
         axis-scale?
         axes
         axes-visual?
         axes-visual-x-range
         axes-visual-y-range
         axes-visual-x-scale
         axes-visual-y-scale
         axes-visual-x-log-base
         axes-visual-y-log-base
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
         axes-coordinates->local-point
         axes-coordinates->point
         axes-point->coordinates
         axes-x-tick-values
         axes-y-tick-values
         axes-x-interpolate-coordinate
         axes-y-interpolate-coordinate
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
    (unless (and (finite-real? tick-step)
                 (positive? tick-step))
      (raise-argument-error who "positive finite real?" tick-step))
    (values minimum maximum tick-step)))

;; axis-range represents one numeric axis interval and its regular tick step.
;;  - minimum    finite-real?           smallest represented coordinate.
;;  - maximum    finite-real?           largest represented coordinate.
;;  - tick-step  positive finite real?  spacing between tick coordinates.
;;
;; Tick values are ordered from minimum to maximum and exclude zero because
;; ordinary Cartesian axes already intersect there. The axes constructor checks
;; the zero-containing invariant only for a linear axis, allowing this shared
;; range representation to describe the strictly-positive range of a log axis.

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

; axis-scale? : any/c -> boolean?
;; Reports whether value names a supported coordinate scale.
(define (axis-scale? value)
  (and (symbol? value)
       (memq value '(linear log))
       #t))


;;;
;;; Axes Data Representation
;;;

(struct axes-visual
  (id
   transform
   opacity
   x-range
   y-range
   x-scale
   y-scale
   x-log-base
   y-log-base
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
;;  - x-scale       axis-scale?                horizontal numeric scale.
;;  - y-scale       axis-scale?                vertical numeric scale.
;;  - x-log-base    positive-real?             logarithm base when x-scale is log.
;;  - y-log-base    positive-real?             logarithm base when y-scale is log.
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
;        [#:x-scale axis-scale?]
;        [#:y-scale axis-scale?]
;        [#:x-log-base positive-real?]
;        [#:y-log-base positive-real?]
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
              #:x-scale [x-scale 'linear]
              #:y-scale [y-scale 'linear]
              #:x-log-base [x-log-base 10]
              #:y-log-base [y-log-base 10]
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
  (check-axis-scale 'axes "x-scale" x-scale)
  (check-axis-scale 'axes "y-scale" y-scale)
  (check-log-base 'axes "x-log-base" x-log-base)
  (check-log-base 'axes "y-log-base" y-log-base)
  (check-axis-range-for-scale 'axes "x-range" x-range x-scale)
  (check-axis-range-for-scale 'axes "y-range" y-range y-scale)
  (check-positive-finite-real 'axes "x-length" x-length)
  (check-positive-finite-real 'axes "y-length" y-length)
  (check-axis-unit-length 'axes "x-unit-length" x-range x-scale x-log-base x-length)
  (check-axis-unit-length 'axes "y-unit-length" y-range y-scale y-log-base y-length)
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
               x-scale
               y-scale
               x-log-base
               y-log-base
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
;;   Returns the unscaled local length representing one x display-space unit.
(define (axes-x-unit-length axes)
  (check-axes-visual 'axes-x-unit-length axes)
  (axis-unit-length (axes-visual-x-range axes)
                    (axes-visual-x-scale axes)
                    (axes-visual-x-log-base axes)
                    (axes-visual-x-length axes)))

; axes-y-unit-length : axes-visual? -> positive-real?
;;   Returns the unscaled local length representing one y display-space unit.
(define (axes-y-unit-length axes)
  (check-axes-visual 'axes-y-unit-length axes)
  (axis-unit-length (axes-visual-y-range axes)
                    (axes-visual-y-scale axes)
                    (axes-visual-y-log-base axes)
                    (axes-visual-y-length axes)))

; axes-coordinates->local-point : axes-visual? finite-real? finite-real? -> vec2?
;; Converts numeric x/y coordinates to untransformed axes-local geometry.
(define (axes-coordinates->local-point axes x y)
  (check-axes-visual 'axes-coordinates->local-point axes)
  (unless (finite-real? x)
    (raise-argument-error 'axes-coordinates->local-point "finite real?" x))
  (unless (finite-real? y)
    (raise-argument-error 'axes-coordinates->local-point "finite real?" y))
  (axes-local-point axes x y))

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
   (axes-coordinates->local-point axes x y)))

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
  (vec2 (axis-display-coordinate->numeric
         (/ (vec2-x local-point)
            (axes-x-unit-length axes))
         (axes-visual-x-scale axes)
         (axes-visual-x-log-base axes))
        (axis-display-coordinate->numeric
         (/ (vec2-y local-point)
            (axes-y-unit-length axes))
         (axes-visual-y-scale axes)
         (axes-visual-y-log-base axes))))

; axes-x-tick-values : axes-visual? -> (listof finite-real?)
;; Returns the deterministic major tick coordinates for the horizontal scale.
(define (axes-x-tick-values axes)
  (check-axes-visual 'axes-x-tick-values axes)
  (axis-tick-values (axes-visual-x-range axes)
                    (axes-visual-x-scale axes)
                    (axes-visual-x-log-base axes)))

; axes-y-tick-values : axes-visual? -> (listof finite-real?)
;; Returns the deterministic major tick coordinates for the vertical scale.
(define (axes-y-tick-values axes)
  (check-axes-visual 'axes-y-tick-values axes)
  (axis-tick-values (axes-visual-y-range axes)
                    (axes-visual-y-scale axes)
                    (axes-visual-y-log-base axes)))

; axes-x-interpolate-coordinate : axes-visual? finite-real? -> finite-real?
;; Interpolates a horizontal numeric coordinate uniformly in display space.
(define (axes-x-interpolate-coordinate axes progress)
  (check-axes-visual 'axes-x-interpolate-coordinate axes)
  (check-axis-interpolation-progress 'axes-x-interpolate-coordinate progress)
  (axis-interpolate-coordinate (axes-visual-x-range axes)
                               (axes-visual-x-scale axes)
                               (axes-visual-x-log-base axes)
                               progress))

; axes-y-interpolate-coordinate : axes-visual? finite-real? -> finite-real?
;; Interpolates a vertical numeric coordinate uniformly in display space.
(define (axes-y-interpolate-coordinate axes progress)
  (check-axes-visual 'axes-y-interpolate-coordinate axes)
  (check-axis-interpolation-progress 'axes-y-interpolate-coordinate progress)
  (axis-interpolate-coordinate (axes-visual-y-range axes)
                               (axes-visual-y-scale axes)
                               (axes-visual-y-log-base axes)
                               progress))


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
                      (axis-reference-coordinate
                       (axes-visual-y-range axes)
                       (axes-visual-y-scale axes))))
  (define x-end
    (axes-local-point axes
                      (axis-range-maximum
                       (axes-visual-x-range axes))
                      (axis-reference-coordinate
                       (axes-visual-y-range axes)
                       (axes-visual-y-scale axes))))
  (define y-start
    (axes-local-point axes
                      (axis-reference-coordinate
                       (axes-visual-x-range axes)
                       (axes-visual-x-scale axes))
                      (axis-range-minimum
                       (axes-visual-y-range axes))))
  (define y-end
    (axes-local-point axes
                      (axis-reference-coordinate
                       (axes-visual-x-range axes)
                       (axes-visual-x-scale axes))
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
  (vec2 (* (axis-numeric->display-coordinate
            x
            (axes-visual-x-scale axes)
            (axes-visual-x-log-base axes))
           (axes-x-unit-length axes))
        (* (axis-numeric->display-coordinate
            y
            (axes-visual-y-scale axes)
            (axes-visual-y-log-base axes))
           (axes-y-unit-length axes))))

; x-tick-subpaths : axes-visual? -> (listof path-subpath?)
;;   Returns vertical x-axis tick segments in increasing coordinate order.
(define (x-tick-subpaths axes)
  (define half-tick-size
    (/ (axes-visual-tick-size axes) 2))
  (if (zero? half-tick-size)
      '()
      (for/list ([value
                  (in-list
                   (axes-x-tick-values axes))])
        (define center
          (axes-local-point axes value
                            (axis-reference-coordinate
                             (axes-visual-y-range axes)
                             (axes-visual-y-scale axes))))
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
                   (axes-y-tick-values axes))])
        (define center
          (axes-local-point axes
                            (axis-reference-coordinate
                             (axes-visual-x-range axes)
                             (axes-visual-x-scale axes))
                            value))
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
;;   Returns the validated finite numeric distance from minimum to maximum.
(define (axis-range-span range)
  (- (axis-range-maximum range)
     (axis-range-minimum range)))

; axis-unit-length : axis-range? axis-scale? positive-real? positive-real?
;;   -> positive-real?
;; Returns one local length per display-space unit.
(define (axis-unit-length range scale base length)
  (/ length (axis-display-range-span range scale base)))

; axis-display-range-span : axis-range? axis-scale? positive-real? -> positive-real?
;; Returns the finite positive span after linear or logarithmic conversion.
(define (axis-display-range-span range scale base)
  (- (axis-numeric->display-coordinate (axis-range-maximum range) scale base)
     (axis-numeric->display-coordinate (axis-range-minimum range) scale base)))

; axis-numeric->display-coordinate : finite-real? axis-scale? positive-real?
;;                                    -> finite-real?
(define (axis-numeric->display-coordinate value scale base)
  (case scale
    [(linear) value]
    [(log)
     (unless (positive? value)
       (raise-argument-error
        'axes-coordinates->local-point
        "positive finite real for a logarithmic axis"
        value))
     (/ (log value) (log base))]
    [else
     (raise-argument-error 'axis-numeric->display-coordinate "axis-scale?" scale)]))

; axis-display-coordinate->numeric : finite-real? axis-scale? positive-real?
;;                                    -> finite-real?
(define (axis-display-coordinate->numeric value scale base)
  (case scale
    [(linear) value]
    [(log) (expt base value)]
    [else
     (raise-argument-error 'axis-display-coordinate->numeric "axis-scale?" scale)]))

; axis-tick-values : axis-range? axis-scale? positive-real? -> (listof finite-real?)
;; Returns linear multiples or powers of base at tick-step exponent intervals.
(define (axis-tick-values range scale base)
  (case scale
    [(linear) (axis-range-tick-values range)]
    [(log)
     (define step (axis-range-tick-step range))
     (define minimum-index
       (tick-index-quotient-for-log range
                                    (axis-range-minimum range)
                                    base))
     (define maximum-index
       (tick-index-quotient-for-log range
                                    (axis-range-maximum range)
                                    base))
     (define first-index
       (integer-ceiling
        (- (/ minimum-index step)
           (tick-index-tolerance (/ minimum-index step)))))
     (define last-index
       (integer-floor
        (+ (/ maximum-index step)
           (tick-index-tolerance (/ maximum-index step)))))
     (for/list ([index (in-range first-index (add1 last-index))])
       (axis-display-coordinate->numeric (* index step) 'log base))]
    [else
     (raise-argument-error 'axis-tick-values "axis-scale?" scale)]))

; axis-interpolate-coordinate : axis-range? axis-scale? positive-real?
;;                               finite-real? -> finite-real?
;; Interpolates numeric values after converting through the selected scale.
(define (axis-interpolate-coordinate range scale base progress)
  (axis-display-coordinate->numeric
   (real-lerp (axis-numeric->display-coordinate (axis-range-minimum range)
                                                scale
                                                base)
              (axis-numeric->display-coordinate (axis-range-maximum range)
                                                scale
                                                base)
              progress)
   scale
   base))

; tick-index-quotient-for-log : axis-range? positive-real? positive-real?
;;                               -> finite-real?
(define (tick-index-quotient-for-log range endpoint base)
  (define quotient
    (/ (log endpoint) (log base)))
  (unless (finite-real? quotient)
    (raise-arguments-error
     'axes-x-tick-values
     "the logarithmic range and base must produce finite tick indexes"
     "range" range
     "log base" base
     "tick index" quotient))
  quotient)

; axis-reference-coordinate : axis-range? axis-scale? -> finite-real?
;; Selects the Cartesian zero or visible log-scale unit as the shaft crossing.
(define (axis-reference-coordinate range scale)
  (case scale
    [(linear) 0]
    [(log)
     (cond [(axis-range-contains? range 1) 1]
           [(positive? (axis-range-minimum range))
            (axis-range-minimum range)]
           [else (axis-range-maximum range)])]
    [else
     (raise-argument-error 'axis-reference-coordinate "axis-scale?" scale)]))

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

; check-axis-unit-length : symbol? string? axis-range? axis-scale? positive-real?
;                          positive-real? -> void?
;;   Raises an argument error unless the range-to-length scale is finite.
(define (check-axis-unit-length who field-name range scale base length)
  (define unit-length
    (axis-unit-length range scale base length))
  (unless (and (finite-real? unit-length)
               (positive? unit-length))
    (raise-arguments-error
     who
     "an axes unit length must be a positive finite real"
     field-name unit-length
     "range" range
     "length" length)))

; check-axis-scale : symbol? string? any/c -> void?
(define (check-axis-scale who field-name value)
  (unless (axis-scale? value)
    (raise-arguments-error who "an axis scale must be 'linear or 'log"
                           field-name value)))

; check-log-base : symbol? string? any/c -> void?
(define (check-log-base who field-name value)
  (unless (and (finite-real? value)
               (> value 1))
    (raise-arguments-error who
                           "a logarithmic base must be finite and greater than one"
                           field-name value)))

; check-axis-range-for-scale : symbol? string? axis-range? axis-scale? -> void?
;; Preserves historical zero-containing ranges for linear axes while permitting
;; strictly-positive intervals for logarithmic axes.
(define (check-axis-range-for-scale who field-name range scale)
  (case scale
    [(linear)
     (unless (axis-range-contains? range 0)
       (raise-arguments-error who
                              "a linear axis range must contain zero"
                              field-name range))]
    [(log)
     (unless (positive? (axis-range-minimum range))
       (raise-arguments-error who
                              "a logarithmic axis range must be strictly positive"
                              field-name range))]
    [else
     (raise-argument-error who "axis-scale?" scale)]))

; check-axis-interpolation-progress : symbol? any/c -> void?
(define (check-axis-interpolation-progress who value)
  (unless (and (finite-real? value)
               (<= 0 value 1))
    (raise-argument-error who "finite real in [0, 1]" value)))

; check-nonnegative-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-nonnegative-finite-real who field-name value)
  (unless (and (finite-real? value)
               (not (negative? value)))
    (raise-arguments-error
     who
     "an axes size or stroke width must be a nonnegative finite real"
     field-name value)))
