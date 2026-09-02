#lang racket/base

;;;
;;; Coordinate-System and Calculus Teaching Helpers
;;;

;; High-level static builders over the existing axes and path model.  They do
;; not retain callbacks: a parameter-driven illustration uses derived-visual to
;; reconstruct one of these ordinary values from its sampled parameter.

(require racket/list
         "affine-transform.rkt"
         "annotation-geometry.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide graph-point
         graph-label
         vertical-line-to-graph
         horizontal-line-to-graph
         tangent-line
         secant-line
         secant-slope-group
         area-under-graph
         area-between-curves
         riemann-rectangles)


;;;
;;; Points, Labels, and Projection Lines
;;;

; graph-point : axes-visual? (-> finite-real? finite-real?) finite-real? -> vec2?
;; Evaluates function at x and returns the world point through axes conversion.
(define (graph-point axes function x)
  (check-axes 'graph-point axes)
  (check-function 'graph-point function)
  (check-finite 'graph-point "x" x)
  (axes-coordinates->point axes x (function-value 'graph-point function x)))

; graph-label : axes-visual? function? finite-real? string?
;               #:id symbol? [#:offset vec2?] ... -> text-visual?
;; Places an ordinary text label at one sampled graph point plus world offset.
(define (graph-label axes function x label
                     #:id id
                     #:offset [offset (vec2 1/5 1/5)]
                     #:font-size [font-size 1/4]
                     #:color [color "black"])
  (unless (string? label)
    (raise-argument-error 'graph-label "string?" label))
  (check-symbol 'graph-label id)
  (unless (vec2? offset)
    (raise-argument-error 'graph-label "vec2?" offset))
  (plain-text label #:id id #:center (vec2+ (graph-point axes function x) offset)
              #:font-size font-size #:color color))

; vertical-line-to-graph : axes-visual? function? finite-real?
;                          #:id symbol? [#:baseline finite-real?] ... -> path-visual?
;; Draws the projection from (x, baseline) to the graph point (x, f(x)).
(define (vertical-line-to-graph axes function x
                                #:id id
                                #:baseline [baseline (default-y-baseline axes)]
                                #:opacity [opacity 1]
                                #:stroke [stroke "gray"]
                                #:stroke-width [stroke-width 2])
  (check-axes 'vertical-line-to-graph axes)
  (check-function 'vertical-line-to-graph function)
  (check-finite 'vertical-line-to-graph "x" x)
  (check-finite 'vertical-line-to-graph "baseline" baseline)
  (line (axes-coordinates->point axes x baseline)
        (graph-point axes function x)
        #:id id #:opacity opacity #:stroke stroke #:stroke-width stroke-width))

; horizontal-line-to-graph : axes-visual? function? finite-real?
;                            #:id symbol? [#:baseline finite-real?] ... -> path-visual?
;; Draws the projection from (baseline, f(x)) to the graph point (x, f(x)).
(define (horizontal-line-to-graph axes function x
                                  #:id id
                                  #:baseline [baseline (default-x-baseline axes)]
                                  #:opacity [opacity 1]
                                  #:stroke [stroke "gray"]
                                  #:stroke-width [stroke-width 2])
  (check-axes 'horizontal-line-to-graph axes)
  (check-function 'horizontal-line-to-graph function)
  (check-finite 'horizontal-line-to-graph "x" x)
  (check-finite 'horizontal-line-to-graph "baseline" baseline)
  (define y (function-value 'horizontal-line-to-graph function x))
  (line (axes-coordinates->point axes baseline y)
        (axes-coordinates->point axes x y)
        #:id id #:opacity opacity #:stroke stroke #:stroke-width stroke-width))


;;;
;;; Tangents and Secants
;;;

; tangent-line : axes-visual? function? finite-real?
;                #:id symbol? [#:dx positive-finite-real?]
;                [#:length positive-finite-real?] ... -> path-visual?
;; Estimates a graph tangent by a symmetric numeric difference and displays a
;; finite world-space segment centered at x.
(define (tangent-line axes function x
                      #:id id
                      #:dx [dx 1/100]
                      #:length [length 2]
                      #:opacity [opacity 1]
                      #:stroke [stroke "crimson"]
                      #:stroke-width [stroke-width 3])
  (check-axes 'tangent-line axes)
  (check-function 'tangent-line function)
  (check-finite 'tangent-line "x" x)
  (check-positive 'tangent-line "dx" dx)
  (check-positive 'tangent-line "length" length)
  (define left (graph-point axes function (- x dx)))
  (define right (graph-point axes function (+ x dx)))
  (define center (graph-point axes function x))
  (define direction (unit-vector 'tangent-line left right))
  (line (vec2- center (vec2-scale (/ length 2) direction))
        (vec2+ center (vec2-scale (/ length 2) direction))
        #:id id #:opacity opacity #:stroke stroke #:stroke-width stroke-width))

; secant-line : axes-visual? function? finite-real? finite-real?
;               #:id symbol? ... -> path-visual?
;; Connects the graph points at x and x + dx.
(define (secant-line axes function x dx
                     #:id id
                     #:opacity [opacity 1]
                     #:stroke [stroke "darkorange"]
                     #:stroke-width [stroke-width 3])
  (check-axes 'secant-line axes)
  (check-function 'secant-line function)
  (check-finite 'secant-line "x" x)
  (check-nonzero-finite 'secant-line "dx" dx)
  (line (graph-point axes function x)
        (graph-point axes function (+ x dx))
        #:id id #:opacity opacity #:stroke stroke #:stroke-width stroke-width))

; secant-slope-group : axes-visual? function? finite-real? finite-real?
;                      #:id symbol? ... -> group-visual?
;; Builds a readable secant construction: the two graph points, secant, and
;; dashed Delta-x/Delta-y legs with text labels. This is intentionally a static
;; snapshot; use derived-visual around it when dx is a scene parameter.
(define (secant-slope-group axes function x dx
                            #:id id
                            #:opacity [opacity 1]
                            #:secant-stroke [secant-stroke "darkorange"]
                            #:guide-stroke [guide-stroke "gray"]
                            #:stroke-width [stroke-width 3]
                            #:marker-radius [marker-radius 1/10])
  (check-axes 'secant-slope-group axes)
  (check-function 'secant-slope-group function)
  (check-symbol 'secant-slope-group id)
  (check-finite 'secant-slope-group "x" x)
  (check-nonzero-finite 'secant-slope-group "dx" dx)
  (check-positive 'secant-slope-group "marker-radius" marker-radius)
  (define first (graph-point axes function x))
  (define second (graph-point axes function (+ x dx)))
  (define step (axes-coordinates->point axes (+ x dx) (function-value 'secant-slope-group function x)))
  (define midpoint-x (point-midpoint first step))
  (define midpoint-y (point-midpoint step second))
  (group
   (list
    (line first second #:id (derived-id id "secant") #:opacity opacity
          #:stroke secant-stroke #:stroke-width stroke-width)
    (dashed-line first step #:id (derived-id id "delta-x") #:opacity opacity
                 #:dash-length 1/8 #:gap-length 1/10
                 #:stroke guide-stroke #:stroke-width 2)
    (dashed-line step second #:id (derived-id id "delta-y") #:opacity opacity
                 #:dash-length 1/8 #:gap-length 1/10
                 #:stroke guide-stroke #:stroke-width 2)
    (circle #:id (derived-id id "first-point") #:center first #:radius marker-radius
            #:opacity opacity #:fill secant-stroke #:stroke #f #:stroke-width 0)
    (circle #:id (derived-id id "second-point") #:center second #:radius marker-radius
            #:opacity opacity #:fill secant-stroke #:stroke #f #:stroke-width 0)
    (plain-text "Δx" #:id (derived-id id "delta-x-label")
                #:center (vec2+ midpoint-x (vec2 0 -1/5))
                #:font-size 1/5 #:color guide-stroke #:opacity opacity)
    (plain-text "Δy" #:id (derived-id id "delta-y-label")
                #:center (vec2+ midpoint-y (vec2 1/5 0))
                #:font-size 1/5 #:color guide-stroke #:opacity opacity))
   #:id id))


;;;
;;; Areas and Riemann Rectangles
;;;

; area-under-graph : axes-visual? function?
;                    #:id symbol? ... -> path-visual?
;; Samples a finite function into one closed area between f and a baseline.
(define (area-under-graph axes function
                          #:id id
                          #:x-min [x-min #f]
                          #:x-max [x-max #f]
                          #:baseline [baseline (default-y-baseline axes)]
                          #:sample-count [sample-count 101]
                          #:opacity [opacity 2/5]
                          #:fill [fill "cornflowerblue"]
                          #:stroke [stroke #f]
                          #:stroke-width [stroke-width 0])
  (check-axes 'area-under-graph axes)
  (check-function 'area-under-graph function)
  (check-symbol 'area-under-graph id)
  (check-finite 'area-under-graph "baseline" baseline)
  (define xs (sample-x-values 'area-under-graph axes x-min x-max sample-count))
  (define points
    (for/list ([value (in-list xs)])
      (axes-coordinates->local-point axes value
                                     (function-value 'area-under-graph function value))))
  (define start-base (axes-coordinates->local-point axes (car xs) baseline))
  (define end-base (axes-coordinates->local-point axes (last xs) baseline))
  (axes-local-polygon-visual axes (append points (list end-base start-base))
                             id opacity fill stroke stroke-width))

; area-between-curves : axes-visual? function? function?
;                       #:id symbol? ... -> path-visual?
;; Samples a closed filled band between two finite functions over one interval.
(define (area-between-curves axes first-function second-function
                             #:id id
                             #:x-min [x-min #f]
                             #:x-max [x-max #f]
                             #:sample-count [sample-count 101]
                             #:opacity [opacity 2/5]
                             #:fill [fill "mediumpurple"]
                             #:stroke [stroke #f]
                             #:stroke-width [stroke-width 0])
  (check-axes 'area-between-curves axes)
  (check-function 'area-between-curves first-function)
  (check-function 'area-between-curves second-function)
  (check-symbol 'area-between-curves id)
  (define xs (sample-x-values 'area-between-curves axes x-min x-max sample-count))
  (define first-points
    (for/list ([value (in-list xs)])
      (axes-coordinates->local-point
       axes value (function-value 'area-between-curves first-function value))))
  (define second-points
    (for/list ([value (in-list (reverse xs))])
      (axes-coordinates->local-point
       axes value (function-value 'area-between-curves second-function value))))
  (axes-local-polygon-visual axes (append first-points second-points)
                             id opacity fill stroke stroke-width))

; riemann-rectangles : axes-visual? function?
;                      #:id symbol? [#:count exact-positive-integer?] ... -> path-visual?
;; Creates closed rectangle subpaths using midpoint samples in display-space
;; intervals. On logarithmic axes, the interval spacing remains logarithmic.
(define (riemann-rectangles axes function
                            #:id id
                            #:x-min [x-min #f]
                            #:x-max [x-max #f]
                            #:count [count 8]
                            #:baseline [baseline (default-y-baseline axes)]
                            #:opacity [opacity 2/5]
                            #:fill [fill "seagreen"]
                            #:stroke [stroke "darkgreen"]
                            #:stroke-width [stroke-width 1])
  (check-axes 'riemann-rectangles axes)
  (check-function 'riemann-rectangles function)
  (check-symbol 'riemann-rectangles id)
  (check-finite 'riemann-rectangles "baseline" baseline)
  (unless (and (exact-integer? count) (positive? count))
    (raise-argument-error 'riemann-rectangles "exact positive integer?" count))
  (define xs (sample-x-values 'riemann-rectangles axes x-min x-max (add1 count)))
  (define subpaths
    (for/list ([left-x (in-list xs)] [right-x (in-list (cdr xs))])
      (define middle-x (display-midpoint axes left-x right-x))
      (define top-y (function-value 'riemann-rectangles function middle-x))
      (define bottom-left (axes-coordinates->local-point axes left-x baseline))
      (define bottom-right (axes-coordinates->local-point axes right-x baseline))
      (define top-right (axes-coordinates->local-point axes right-x top-y))
      (define top-left (axes-coordinates->local-point axes left-x top-y))
      (path-subpath bottom-left
                    (list (line-path-segment bottom-right)
                          (line-path-segment top-right)
                          (line-path-segment top-left))
                    #t)))
  (make-path-visual
   (path-geometry subpaths)
   #:id id #:center (visual-position axes)
   #:rotation (visual-rotation axes) #:scale (visual-scale axes)
   #:opacity opacity #:fill fill #:stroke stroke #:stroke-width stroke-width))


;;;
;;; Private Helpers
;;;

(define (sample-x-values who axes requested-minimum requested-maximum count)
  (unless (and (exact-integer? count) (>= count 2))
    (raise-argument-error who "exact integer at least 2" count))
  (define range (axes-visual-x-range axes))
  (define minimum (or requested-minimum (axis-range-minimum range)))
  (define maximum (or requested-maximum (axis-range-maximum range)))
  (check-finite who "x-min" minimum)
  (check-finite who "x-max" maximum)
  (unless (< minimum maximum)
    (raise-arguments-error who "x-min less than x-max" "x-min" minimum "x-max" maximum))
  (for/list ([index (in-range count)])
    (interpolate-x axes minimum maximum (/ index (sub1 count)))))

(define (interpolate-x axes minimum maximum progress)
  (case (axes-visual-x-scale axes)
    [(linear) (+ minimum (* progress (- maximum minimum)))]
    [(log)
     (unless (and (positive? minimum) (positive? maximum))
       (raise-arguments-error
        'sample-x-values "positive bounds for a logarithmic x axis"
        "x-min" minimum "x-max" maximum))
     (define base (axes-visual-x-log-base axes))
     (expt base
           (+ (/ (log minimum) (log base))
              (* progress
                 (- (/ (log maximum) (log base))
                    (/ (log minimum) (log base))))))]
    [else
     (raise-argument-error 'sample-x-values "axis-scale?" (axes-visual-x-scale axes))]))

(define (display-midpoint axes left right)
  (interpolate-x axes left right 1/2))

(define (axes-local-polygon-visual axes points id opacity fill stroke stroke-width)
  (make-path-visual
   (polygon-path points)
   #:id id #:center (visual-position axes)
   #:rotation (visual-rotation axes) #:scale (visual-scale axes)
   #:opacity opacity #:fill fill #:stroke stroke #:stroke-width stroke-width))

(define (default-x-baseline axes)
  (if (eq? (axes-visual-x-scale axes) 'linear)
      0
      (axis-range-minimum (axes-visual-x-range axes))))
(define (default-y-baseline axes)
  (if (eq? (axes-visual-y-scale axes) 'linear)
      0
      (axis-range-minimum (axes-visual-y-range axes))))

(define (function-value who function x)
  (define value
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error who "a graph function that does not raise"
                                   "x" x "exception" (exn-message exception)))])
      (function x)))
  (unless (finite-real? value)
    (raise-arguments-error who "a graph function that returns a finite real"
                           "x" x "result" value))
  value)

(define (unit-vector who start end)
  (define delta (vec2- end start))
  (define length (sqrt (+ (sqr (vec2-x delta)) (sqr (vec2-y delta)))))
  (unless (positive? length)
    (raise-arguments-error who "distinct graph points" "start" start "end" end))
  (vec2-scale (/ 1 length) delta))
(define (point-midpoint a b) (vec2 (/ (+ (vec2-x a) (vec2-x b)) 2) (/ (+ (vec2-y a) (vec2-y b)) 2)))
(define (derived-id base suffix) (string->symbol (format "~a-~a" base suffix)))
(define (sqr value) (* value value))
(define (check-axes who value) (unless (axes-visual? value) (raise-argument-error who "axes-visual?" value)))
(define (check-function who value) (unless (and (procedure? value) (procedure-arity-includes? value 1)) (raise-argument-error who "procedure accepting one argument" value)))
(define (check-symbol who value) (unless (symbol? value) (raise-argument-error who "symbol?" value)))
(define (check-finite who name value) (unless (finite-real? value) (raise-arguments-error who "a finite real" name value)))
(define (check-positive who name value) (unless (and (finite-real? value) (positive? value)) (raise-arguments-error who "a positive finite real" name value)))
(define (check-nonzero-finite who name value) (unless (and (finite-real? value) (not (zero? value))) (raise-arguments-error who "a nonzero finite real" name value)))
