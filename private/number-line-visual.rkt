#lang racket/base

;;;
;;; Number-Line Visuals
;;;

;; Defines immutable horizontal number-line model values. Rendering remains in
;; the Pict adapter through conversion to ordinary semantic path geometry.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "color-style.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide number-line
         number-line-visual?
         number-line-visual-range
         number-line-visual-length
         number-line-visual-stroke
         number-line-visual-stroke-width
         number-line-visual-tick-size
         number-line-visual-tip-length
         number-line-visual-tip-width
         number-line-visual-start-tip?
         number-line-visual-end-tip?
         number-line-unit-length
         number-line-tick-values
         number-line-number->point
         number-line-point->number
         number-line-visual-start
         number-line-visual-end
         number-line-visual->path-visual)


;;;
;;; Data Representation
;;;

(struct number-line-visual
  (identifier
   transform
   opacity
   range
   length
   stroke
   stroke-width
   tick-size
   tip-length
   tip-width
   start-tip?
   end-tip?)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (number-line-visual-identifier visual))

   (define (visual-position visual)
     (affine-transform-translation
      (number-line-visual-transform visual)))

   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error
        'visual-with-position
        "vec2?"
        position))
     (struct-copy
      number-line-visual
      visual
      [transform
       (affine-transform-with-translation
        (number-line-visual-transform visual)
        position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (number-line-visual-transform visual))

   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy number-line-visual visual
                  [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (number-line-visual-opacity visual))

   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "opacity?"
        opacity))
     (struct-copy number-line-visual visual
                  [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width visual)
     (number-line-visual-stroke-width visual))

   (define (visual-with-stroke-width visual stroke-width)
     (unless (stroke-width? stroke-width)
       (raise-argument-error
        'visual-with-stroke-width
        "stroke-width?"
        stroke-width))
     (struct-copy number-line-visual visual
                  [stroke-width stroke-width]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color visual)
     (number-line-visual-stroke visual))
   (define (visual-with-stroke-color visual color)
     (unless (color-spec? color)
       (raise-argument-error 'visual-with-stroke-color "color-spec?" color))
     (struct-copy number-line-visual visual [stroke color]))])

;; number-line-visual represents one horizontal semantic number line.
;;  - identifier    Stable symbol identity.
;;  - transform     Translation, rotation, and positive x/y scale.
;;  - opacity       Global semantic opacity in the interval [0, 1].
;;  - range         Numeric range and regular tick step. It contains zero.
;;  - length        Local shaft length for the complete numeric interval.
;;  - stroke        Stroke and tip-fill color name.
;;  - stroke-width  Cosmetic stroke width in pixels.
;;  - tick-size     Full local length of every regular tick.
;;  - tip-length    Local length of each enabled triangular tip.
;;  - tip-width     Full local width of each enabled triangular tip.
;;  - start-tip?    Whether the minimum endpoint has a tip.
;;  - end-tip?      Whether the maximum endpoint has a tip.
;; Tick ordering follows increasing numeric value.


;;;
;;; Construction
;;;

; number-line : axis-range? [keyword arguments] -> number-line-visual?
;;   Constructs a number line whose semantic origin represents numeric zero.
(define (number-line range
                     #:id identifier
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale-factor 1]
                     #:opacity [opacity 1]
                     #:length [length 10]
                     #:stroke [stroke "black"]
                     #:stroke-width [stroke-width 2]
                     #:tick-size [tick-size 1/5]
                     #:tip-length [tip-length 2/5]
                     #:tip-width [tip-width 3/10]
                     #:start-tip? [start-tip? #f]
                     #:end-tip? [end-tip? #f])
  (unless (axis-range? range)
    (raise-argument-error 'number-line "axis-range?" range))
  (unless (axis-range-contains? range 0)
    (raise-arguments-error
     'number-line
     "the range must contain zero"
     "range" range))
  (unless (symbol? identifier)
    (raise-argument-error 'number-line "symbol?" identifier))
  (unless (vec2? center)
    (raise-argument-error 'number-line "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'number-line "finite-real?" rotation))
  (unless (opacity? opacity)
    (raise-argument-error 'number-line "opacity?" opacity))
  (check-positive-finite-real 'number-line "length" length)
  (unless (or (string? stroke) (rgba-color? stroke))
    (raise-argument-error
     'number-line
     "(or/c string? rgba-color?)"
     stroke))
  (check-nonnegative-finite-real
   'number-line "stroke-width" stroke-width)
  (check-nonnegative-finite-real 'number-line "tick-size" tick-size)
  (check-nonnegative-finite-real 'number-line "tip-length" tip-length)
  (check-nonnegative-finite-real 'number-line "tip-width" tip-width)
  (unless (boolean? start-tip?)
    (raise-argument-error 'number-line "boolean?" start-tip?))
  (unless (boolean? end-tip?)
    (raise-argument-error 'number-line "boolean?" end-tip?))
  (number-line-visual
   identifier
   (make-number-line-transform center rotation scale-factor)
   opacity
   range
   length
   stroke
   stroke-width
   tick-size
   tip-length
   tip-width
   start-tip?
   end-tip?))

; make-number-line-transform : vec2? finite-real? scale-factor?
;                              -> affine-transform?
;;   Constructs the validated transform used by a number-line Visual.
(define (make-number-line-transform center rotation scale-factor)
  (affine-transform-with-scale
   (affine-transform-with-rotation
    (affine-transform-with-translation
     identity-affine-transform
     center)
    rotation)
   (scale-factor->vec2 scale-factor)))


;;;
;;; Numeric Coordinates
;;;

; number-line-unit-length : number-line-visual? -> positive-real?
;;   Returns the local world-unit distance representing one numeric unit.
(define (number-line-unit-length visual)
  (check-number-line 'number-line-unit-length visual)
  (define range
    (number-line-visual-range visual))
  (/ (number-line-visual-length visual)
     (- (axis-range-maximum range)
        (axis-range-minimum range))))

; number-line-tick-values : number-line-visual?
;                           [#:include-zero? boolean?]
;                           -> (listof finite-real?)
;;   Returns increasing regular tick values, optionally including zero.
(define (number-line-tick-values visual #:include-zero? [include-zero? #t])
  (check-number-line 'number-line-tick-values visual)
  (unless (boolean? include-zero?)
    (raise-argument-error
     'number-line-tick-values
     "boolean?"
     include-zero?))
  (define values
    (axis-range-tick-values
     (number-line-visual-range visual)))
  (if include-zero?
      (sort (cons 0 values) <)
      values))

; number-line-number->point : number-line-visual? finite-real? -> vec2?
;;   Maps a numeric value to a point in the containing coordinate system.
(define (number-line-number->point visual number)
  (check-number-line 'number-line-number->point visual)
  (unless (finite-real? number)
    (raise-argument-error
     'number-line-number->point
     "finite-real?"
     number))
  (affine-transform-apply-point
   (number-line-visual-transform visual)
   (vec2 (* number
            (number-line-unit-length visual))
         0)))

; number-line-point->number : number-line-visual? vec2? -> real?
;;   Projects a point onto the transformed number line and returns its value.
(define (number-line-point->number visual point)
  (check-number-line 'number-line-point->number visual)
  (unless (vec2? point)
    (raise-argument-error
     'number-line-point->number
     "vec2?"
     point))
  (define transform
    (number-line-visual-transform visual))
  (define translation
    (affine-transform-translation transform))
  (define angle
    (affine-transform-rotation transform))
  (define scale
    (affine-transform-scale transform))
  (define dx
    (- (vec2-x point)
       (vec2-x translation)))
  (define dy
    (- (vec2-y point)
       (vec2-y translation)))
  (define local-scaled-x
    (+ (* (cos angle) dx)
       (* (sin angle) dy)))
  (define local-x
    (/ local-scaled-x
       (vec2-x scale)))
  (/ local-x
     (number-line-unit-length visual)))

; number-line-visual-start : number-line-visual? -> vec2?
;;   Returns the transformed point at the numeric minimum.
(define (number-line-visual-start visual)
  (check-number-line 'number-line-visual-start visual)
  (number-line-number->point
   visual
   (axis-range-minimum
    (number-line-visual-range visual))))

; number-line-visual-end : number-line-visual? -> vec2?
;;   Returns the transformed point at the numeric maximum.
(define (number-line-visual-end visual)
  (check-number-line 'number-line-visual-end visual)
  (number-line-number->point
   visual
   (axis-range-maximum
    (number-line-visual-range visual))))


;;;
;;; Semantic Path Conversion
;;;

; number-line-visual->path-visual : number-line-visual? -> path-visual?
;;   Converts the number line to ordinary local semantic path geometry.
(define (number-line-visual->path-visual visual)
  (check-number-line 'number-line-visual->path-visual visual)
  (define geometry
    (number-line-path-geometry visual))
  (make-path-visual
   geometry
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (number-line-visual-stroke visual)
   #:stroke (number-line-visual-stroke visual)
   #:stroke-width (number-line-visual-stroke-width visual)))

; number-line-path-geometry : number-line-visual? -> path-geometry?
;;   Builds the ordered shaft, tick, and triangular-tip subpaths.
(define (number-line-path-geometry visual)
  (define unit-length
    (number-line-unit-length visual))
  (define range
    (number-line-visual-range visual))
  (define minimum-x
    (* (axis-range-minimum range) unit-length))
  (define maximum-x
    (* (axis-range-maximum range) unit-length))
  (define half-tick
    (/ (number-line-visual-tick-size visual) 2))
  (define shaft
    (line-subpath (vec2 minimum-x 0)
                  (vec2 maximum-x 0)))
  (define ticks
    (for/list ([value (in-list (number-line-tick-values visual))])
      (define x (* value unit-length))
      (line-subpath (vec2 x (- half-tick))
                    (vec2 x half-tick))))
  (define start-tip
    (if (number-line-visual-start-tip? visual)
        (list
         (tip-subpath minimum-x
                      1
                      (number-line-visual-tip-length visual)
                      (number-line-visual-tip-width visual)))
        '()))
  (define end-tip
    (if (number-line-visual-end-tip? visual)
        (list
         (tip-subpath maximum-x
                      -1
                      (number-line-visual-tip-length visual)
                      (number-line-visual-tip-width visual)))
        '()))
  (path-geometry
   (append (list shaft)
           ticks
           start-tip
           end-tip)))

; line-subpath : vec2? vec2? -> path-subpath?
;;   Constructs one open line subpath.
(define (line-subpath start end)
  (path-subpath start
                (list (line-path-segment end))
                #f))

; tip-subpath : finite-real? (or/c -1 1) nonnegative-real?
;               nonnegative-real? -> path-subpath?
;;   Constructs one closed triangular tip at the given endpoint.
(define (tip-subpath endpoint-x inward-direction tip-length tip-width)
  (define base-x
    (+ endpoint-x
       (* inward-direction tip-length)))
  (define half-width
    (/ tip-width 2))
  (path-subpath
   (vec2 endpoint-x 0)
   (list
    (line-path-segment (vec2 base-x half-width))
    (line-path-segment (vec2 base-x (- half-width))))
   #t))


;;;
;;; Validation
;;;

; check-number-line : symbol? any/c -> void?
;;   Raises an argument error unless value is a number-line Visual.
(define (check-number-line who value)
  (unless (number-line-visual? value)
    (raise-argument-error who "number-line-visual?" value)))

; check-positive-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is positive and finite.
(define (check-positive-finite-real who field value)
  (unless (and (finite-real? value)
               (> value 0))
    (raise-arguments-error
     who
     "expected a positive finite real"
     field value)))

; check-nonnegative-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-nonnegative-finite-real who field value)
  (unless (and (finite-real? value)
               (>= value 0))
    (raise-arguments-error
     who
     "expected a nonnegative finite real"
     field value)))
