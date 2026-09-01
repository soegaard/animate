#lang racket/base

;;;
;;; Arrow Visual Model
;;;

;; Defines immutable semantic arrows with optional tips at either endpoint.
;;
;; Arrow geometry is stored in local mathematical coordinates. This module has
;; no Pict, drawing-context, bitmap, filesystem, process, or browser dependency.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide arrow
         arrow-visual?
         arrow-visual-length
         arrow-visual-stroke
         arrow-visual-stroke-width
         arrow-visual-tip-length
         arrow-visual-tip-width
         arrow-visual-start-tip?
         arrow-visual-end-tip?
         arrow-visual-start
         arrow-visual-end
         arrow-visual-point-at
         arrow-visual-path-geometry
         arrowhead-subpath)


;;;
;;; Data Representation
;;;

(struct arrow-visual
  (id
   transform
   opacity
   local-start
   local-end
   stroke
   stroke-width
   tip-length
   tip-width
   start-tip?
   end-tip?)
  #:transparent
  #:methods gen:visual
  [(define (visual-id arrow)
     (arrow-visual-id arrow))
   (define (visual-position arrow)
     (affine-transform-translation
      (arrow-visual-transform arrow)))
   (define (visual-with-position arrow position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy arrow-visual arrow
                  [transform
                   (affine-transform-with-translation
                    (arrow-visual-transform arrow)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform arrow)
     (arrow-visual-transform arrow))
   (define (visual-with-transform arrow transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy arrow-visual arrow [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity arrow)
     (arrow-visual-opacity arrow))
   (define (visual-with-opacity arrow opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy arrow-visual arrow [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width arrow)
     (arrow-visual-stroke-width arrow))
   (define (visual-with-stroke-width arrow stroke-width)
     (unless (stroke-width? stroke-width)
       (raise-argument-error
        'visual-with-stroke-width
        "nonnegative finite real?"
        stroke-width))
     (struct-copy arrow-visual arrow [stroke-width stroke-width]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color arrow)
     (arrow-visual-stroke arrow))
   (define (visual-with-stroke-color arrow color)
     (unless (color-spec? color)
       (raise-argument-error 'visual-with-stroke-color "color-spec?" color))
     (struct-copy arrow-visual arrow [stroke color]))])

;; arrow-visual represents one styled line segment with optional triangular tips.
;;  - id            symbol?                    stable Visual identity.
;;  - transform     affine-transform?          placement and local deformation.
;;  - opacity       opacity?                   global rendering opacity.
;;  - local-start   vec2?                      shaft start relative to the anchor.
;;  - local-end     vec2?                      shaft end relative to the anchor.
;;  - stroke        any/c                      opaque line and tip style.
;;  - stroke-width  nonnegative finite real?   cosmetic shaft and tip outline width.
;;  - tip-length    positive finite real?      local tip length before scale.
;;  - tip-width     positive finite real?      local tip base width before scale.
;;  - start-tip?    boolean?                   whether the start has a tip.
;;  - end-tip?      boolean?                   whether the end has a tip.
;;
;; The local endpoints are stored in significant start-to-end order. The
;; reference position is their midpoint before optional rotation and scale.


;;;
;;; Construction
;;;

; arrow : vec2? vec2?
;         #:id symbol?
;         [#:rotation finite-real?]
;         [#:scale scale-factor?]
;         [#:opacity opacity?]
;         [#:stroke any/c]
;         [#:stroke-width nonnegative-real?]
;         [#:tip-length positive-real?]
;         [#:tip-width positive-real?]
;         [#:start-tip? boolean?]
;         [#:end-tip? boolean?]
;         -> arrow-visual?
;;   Creates an arrow whose untransformed endpoints are start and end.
(define (arrow start end
               #:id id
               #:rotation [rotation 0]
               #:scale [scale 1]
               #:opacity [opacity 1]
               #:stroke [stroke "black"]
               #:stroke-width [stroke-width 2]
               #:tip-length [tip-length 3/10]
               #:tip-width [tip-width 1/4]
               #:start-tip? [start-tip? #f]
               #:end-tip? [end-tip? #t])
  (unless (vec2? start)
    (raise-argument-error 'arrow "vec2?" start))
  (unless (vec2? end)
    (raise-argument-error 'arrow "vec2?" end))
  (unless (symbol? id)
    (raise-argument-error 'arrow "symbol?" id))
  (unless (finite-real? rotation)
    (raise-argument-error 'arrow "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'arrow
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error 'arrow "finite real in [0, 1]" opacity))
  (check-nonnegative-finite-real 'arrow "stroke-width" stroke-width)
  (check-positive-finite-real 'arrow "tip-length" tip-length)
  (check-positive-finite-real 'arrow "tip-width" tip-width)
  (unless (boolean? start-tip?)
    (raise-argument-error 'arrow "boolean?" start-tip?))
  (unless (boolean? end-tip?)
    (raise-argument-error 'arrow "boolean?" end-tip?))
  (define length
    (point-distance start end))
  (unless (and (finite-real? length)
               (positive? length))
    (raise-arguments-error
     'arrow
     "start and end must be distinct points with a finite distance"
     "start" start
     "end" end
     "distance" length))
  (define center
    (point-midpoint start end))
  (arrow-visual id
                (make-affine-transform #:translation center
                                       #:rotation rotation
                                       #:scale scale)
                opacity
                (vec2- start center)
                (vec2- end center)
                stroke
                stroke-width
                tip-length
                tip-width
                start-tip?
                end-tip?))


;;;
;;; Endpoint Queries
;;;

; arrow-visual-length : arrow-visual? -> positive-real?
;;   Returns the unscaled local shaft length.
(define (arrow-visual-length arrow)
  (check-arrow-visual 'arrow-visual-length arrow)
  (point-distance (arrow-visual-local-start arrow)
                  (arrow-visual-local-end arrow)))

; arrow-visual-start : arrow-visual? -> vec2?
;;   Returns the transformed start point in the containing coordinate system.
(define (arrow-visual-start arrow)
  (check-arrow-visual 'arrow-visual-start arrow)
  (affine-transform-apply-point
   (visual-transform arrow)
   (arrow-visual-local-start arrow)))

; arrow-visual-end : arrow-visual? -> vec2?
;;   Returns the transformed end point in the containing coordinate system.
(define (arrow-visual-end arrow)
  (check-arrow-visual 'arrow-visual-end arrow)
  (affine-transform-apply-point
   (visual-transform arrow)
   (arrow-visual-local-end arrow)))

; arrow-visual-point-at : arrow-visual? unit-real? -> vec2?
;;   Returns the transformed shaft point at progress from start to end.
(define (arrow-visual-point-at arrow progress)
  (check-arrow-visual 'arrow-visual-point-at arrow)
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'arrow-visual-point-at
     "finite real in the closed unit interval"
     progress))
  (affine-transform-apply-point
   (visual-transform arrow)
   (vec2-lerp (arrow-visual-local-start arrow)
              (arrow-visual-local-end arrow)
              progress)))


;;;
;;; Semantic Path Conversion
;;;

; arrow-visual-path-geometry : arrow-visual? -> path-geometry?
;;   Returns local shaft and tip geometry in significant component order.
(define (arrow-visual-path-geometry arrow)
  (check-arrow-visual 'arrow-visual-path-geometry arrow)
  (define local-start
    (arrow-visual-local-start arrow))
  (define local-end
    (arrow-visual-local-end arrow))
  (path-geometry
   (append
    (list (open-line-subpath local-start local-end))
    (if (arrow-visual-start-tip? arrow)
        (list (arrowhead-subpath
               local-start
               local-end
               (arrow-visual-tip-length arrow)
               (arrow-visual-tip-width arrow)))
        '())
    (if (arrow-visual-end-tip? arrow)
        (list (arrowhead-subpath
               local-end
               local-start
               (arrow-visual-tip-length arrow)
               (arrow-visual-tip-width arrow)))
        '()))))

; arrowhead-subpath : vec2? vec2? positive-real? positive-real?
;                     -> path-subpath?
;;   Creates a closed triangular tip at apex pointing away from opposite.
(define (arrowhead-subpath apex opposite tip-length tip-width)
  (unless (vec2? apex)
    (raise-argument-error 'arrowhead-subpath "vec2?" apex))
  (unless (vec2? opposite)
    (raise-argument-error 'arrowhead-subpath "vec2?" opposite))
  (check-positive-finite-real
   'arrowhead-subpath
   "tip-length"
   tip-length)
  (check-positive-finite-real
   'arrowhead-subpath
   "tip-width"
   tip-width)
  (define direction
    (vec2- apex opposite))
  (define direction-length
    (point-distance origin direction))
  (unless (positive? direction-length)
    (raise-arguments-error
     'arrowhead-subpath
     "apex and opposite must be distinct points"
     "apex" apex
     "opposite" opposite))
  (define unit-direction
    (vec2-scale (/ 1 direction-length) direction))
  (define perpendicular
    (vec2 (- (vec2-y unit-direction))
          (vec2-x unit-direction)))
  (define base-center
    (vec2- apex
           (vec2-scale tip-length unit-direction)))
  (define half-width-vector
    (vec2-scale (/ tip-width 2) perpendicular))
  (define base-left
    (vec2+ base-center half-width-vector))
  (define base-right
    (vec2- base-center half-width-vector))
  (path-subpath apex
                (list (line-path-segment base-left)
                      (line-path-segment base-right))
                #t))

; open-line-subpath : vec2? vec2? -> path-subpath?
;;   Creates one open line subpath in start-to-end order.
(define (open-line-subpath start end)
  (path-subpath start
                (list (line-path-segment end))
                #f))


;;;
;;; Geometry Helpers
;;;

; point-midpoint : vec2? vec2? -> vec2?
;;   Returns an overflow-resistant midpoint of two finite points.
(define (point-midpoint start end)
  (vec2 (+ (/ (vec2-x start) 2)
           (/ (vec2-x end) 2))
        (+ (/ (vec2-y start) 2)
           (/ (vec2-y end) 2))))

; point-distance : vec2? vec2? -> nonnegative-real?
;;   Returns a scaled-hypotenuse distance between two finite points.
(define (point-distance start end)
  (define delta-x
    (abs (- (vec2-x end) (vec2-x start))))
  (define delta-y
    (abs (- (vec2-y end) (vec2-y start))))
  (define scale
    (max delta-x delta-y))
  (if (zero? scale)
      0
      (* scale
         (sqrt (+ (sqr (/ delta-x scale))
                  (sqr (/ delta-y scale)))))))

; sqr : finite-real? -> nonnegative-real?
;;   Returns value multiplied by itself.
(define (sqr value)
  (* value value))


;;;
;;; Validation
;;;

; check-arrow-visual : symbol? any/c -> void?
;;   Raises an argument error unless value is an arrow Visual.
(define (check-arrow-visual who value)
  (unless (arrow-visual? value)
    (raise-argument-error who "arrow-visual?" value)))

; check-positive-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is positive and finite.
(define (check-positive-finite-real who field-name value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-arguments-error
     who
     "an arrow dimension must be a positive finite real"
     field-name value)))

; check-nonnegative-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-nonnegative-finite-real who field-name value)
  (unless (and (finite-real? value)
               (not (negative? value)))
    (raise-arguments-error
     who
     "an arrow stroke width must be a nonnegative finite real"
     field-name value)))
