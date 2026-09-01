#lang racket/base

;;;
;;; Scatter Plots and Filled Coordinate Areas
;;;

;; Constructs ordered point-marker groups and closed filled areas from existing
;; axes-aligned sampling operations. Returned values contain only immutable
;; semantic Visual data.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "axes-visual.rkt"
         "function-graph.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "parametric-data-plot.rkt"
         "path-geometry.rkt"
         "point-marker-visual.rkt"
         "visual-model.rkt")

;; Exports
(provide scatter-plot
         sample-function-area-path
         function-area
         data-series-area-path
         data-area)


;;;
;;; Scatter Plots
;;;

; scatter-plot : axes-visual?
;                (listof (or/c vec2? false/c))
;                #:id symbol?
;                [#:clip? boolean?]
;                [#:shape point-marker-shape?]
;                [#:size positive-finite-real?]
;                [#:opacity opacity?]
;                [#:fill any/c]
;                [#:stroke any/c]
;                [#:stroke-width nonnegative-finite-real?]
;                -> group-visual?
;;   Creates an ordered group of upright point markers from numeric coordinates.
(define (scatter-plot axes points
                      #:id identifier
                      #:clip? [clip? #t]
                      #:shape [shape 'circle]
                      #:size [size 1/5]
                      #:opacity [opacity 1]
                      #:fill [fill "royalblue"]
                      #:stroke [stroke "black"]
                      #:stroke-width [stroke-width 1])
  (check-scatter-arguments axes
                           points
                           identifier
                           clip?
                           shape
                           size
                           opacity
                           stroke-width)
  (define axes-angle
    (visual-rotation axes))
  (define markers
    (for/list ([point (in-list points)]
               [index (in-naturals)]
               #:when (scatter-point-visible? axes point clip?))
      (point-marker
       #:id (scatter-marker-id identifier index)
       #:center (numeric-coordinate->scatter-local axes point)
       #:rotation (- axes-angle)
       #:shape shape
       #:size size
       #:fill fill
       #:stroke stroke
       #:stroke-width stroke-width)))
  (group markers
         #:id identifier
         #:center (visual-position axes)
         #:rotation axes-angle
         #:opacity opacity))

; scatter-marker-id : symbol? exact-nonnegative-integer? -> symbol?
;;   Derives one deterministic marker identity from the plot identity and index.
(define (scatter-marker-id identifier index)
  (string->symbol
   (format "~a-marker-~a"
           (symbol->string identifier)
           index)))

; scatter-point-visible? : axes-visual? (or/c vec2? false/c) boolean?
;                          -> boolean?
;;   Reports whether one input point should produce a marker.
(define (scatter-point-visible? axes point clip?)
  (and point
       (or (not clip?)
           (and
            (axis-range-contains?
             (axes-visual-x-range axes)
             (vec2-x point))
            (axis-range-contains?
             (axes-visual-y-range axes)
             (vec2-y point))))))

; numeric-coordinate->scatter-local : axes-visual? vec2? -> vec2?
;;   Maps a numeric point to the scatter group's scaled local coordinates.
(define (numeric-coordinate->scatter-local axes point)
  (define axes-scale
    (visual-scale axes))
  (define local
    (axes-coordinates->local-point axes
                                   (vec2-x point)
                                   (vec2-y point)))
  (vec2 (* (vec2-x local) (vec2-x axes-scale))
        (* (vec2-y local) (vec2-y axes-scale))))


;;;
;;; Function Areas
;;;

; sample-function-area-path : axes-visual?
;                             (procedure-arity-includes/c 1)
;                             [#:baseline finite-real?]
;                             [#:x-min (or/c finite-real? false/c)]
;                             [#:x-max (or/c finite-real? false/c)]
;                             [#:sample-count exact-integer-at-least-2?]
;                             [#:clip? boolean?]
;                             [#:max-jump
;                              (or/c nonnegative-finite-real? false/c)]
;                             [#:interpolation curve-interpolation?]
;                             -> path-geometry?
;;   Samples a function and closes every visible run to a horizontal baseline.
(define (sample-function-area-path axes function
                                   #:baseline [baseline 0]
                                   #:x-min [x-min #f]
                                   #:x-max [x-max #f]
                                   #:sample-count [sample-count 201]
                                   #:clip? [clip? #t]
                                   #:max-jump [max-jump #f]
                                   #:interpolation [interpolation 'linear])
  (check-area-baseline 'sample-function-area-path baseline)
  (define graph-path
    (sample-function-path axes
                          function
                          #:x-min x-min
                          #:x-max x-max
                          #:sample-count sample-count
                          #:clip? clip?
                          #:max-jump max-jump
                          #:interpolation interpolation))
  (coordinate-path->area-path axes
                              graph-path
                              baseline
                              clip?))

; function-area : axes-visual?
;                 (procedure-arity-includes/c 1)
;                 #:id symbol?
;                 [#:baseline finite-real?]
;                 [#:x-min (or/c finite-real? false/c)]
;                 [#:x-max (or/c finite-real? false/c)]
;                 [#:sample-count exact-integer-at-least-2?]
;                 [#:clip? boolean?]
;                 [#:max-jump
;                  (or/c nonnegative-finite-real? false/c)]
;                 [#:interpolation curve-interpolation?]
;                 [#:opacity opacity?]
;                 [#:fill any/c]
;                 [#:stroke any/c]
;                 [#:stroke-width nonnegative-finite-real?]
;                 -> path-visual?
;;   Creates a filled path Visual between a sampled function and baseline.
(define (function-area axes function
                       #:id identifier
                       #:baseline [baseline 0]
                       #:x-min [x-min #f]
                       #:x-max [x-max #f]
                       #:sample-count [sample-count 201]
                       #:clip? [clip? #t]
                       #:max-jump [max-jump #f]
                       #:interpolation [interpolation 'linear]
                       #:opacity [opacity 1/2]
                       #:fill [fill "cornflowerblue"]
                       #:stroke [stroke #f]
                       #:stroke-width [stroke-width 0])
  (check-area-style 'function-area
                    identifier
                    opacity
                    stroke-width)
  (define geometry
    (sample-function-area-path
     axes
     function
     #:baseline baseline
     #:x-min x-min
     #:x-max x-max
     #:sample-count sample-count
     #:clip? clip?
     #:max-jump max-jump
     #:interpolation interpolation))
  (coordinate-area-visual axes
                          geometry
                          identifier
                          opacity
                          fill
                          stroke
                          stroke-width))


;;;
;;; Ordered Data Areas
;;;

; data-series-area-path : axes-visual?
;                         (listof (or/c vec2? false/c))
;                         [#:baseline finite-real?]
;                         [#:clip? boolean?]
;                         [#:max-distance
;                          (or/c nonnegative-finite-real? false/c)]
;                         [#:interpolation curve-interpolation?]
;                         -> path-geometry?
;;   Closes every accepted ordered data run to a horizontal baseline.
(define (data-series-area-path axes points
                               #:baseline [baseline 0]
                               #:clip? [clip? #t]
                               #:max-distance [max-distance #f]
                               #:interpolation [interpolation 'linear])
  (check-area-baseline 'data-series-area-path baseline)
  (define data-path
    (data-series-path axes
                      points
                      #:clip? clip?
                      #:max-distance max-distance
                      #:interpolation interpolation))
  (coordinate-path->area-path axes
                              data-path
                              baseline
                              clip?))

; data-area : axes-visual?
;             (listof (or/c vec2? false/c))
;             #:id symbol?
;             [#:baseline finite-real?]
;             [#:clip? boolean?]
;             [#:max-distance
;              (or/c nonnegative-finite-real? false/c)]
;             [#:interpolation curve-interpolation?]
;             [#:opacity opacity?]
;             [#:fill any/c]
;             [#:stroke any/c]
;             [#:stroke-width nonnegative-finite-real?]
;             -> path-visual?
;;   Creates a filled path Visual from ordered data runs and a baseline.
(define (data-area axes points
                   #:id identifier
                   #:baseline [baseline 0]
                   #:clip? [clip? #t]
                   #:max-distance [max-distance #f]
                   #:interpolation [interpolation 'linear]
                   #:opacity [opacity 1/2]
                   #:fill [fill "lightgreen"]
                   #:stroke [stroke #f]
                   #:stroke-width [stroke-width 0])
  (check-area-style 'data-area
                    identifier
                    opacity
                    stroke-width)
  (define geometry
    (data-series-area-path axes
                           points
                           #:baseline baseline
                           #:clip? clip?
                           #:max-distance max-distance
                           #:interpolation interpolation))
  (coordinate-area-visual axes
                          geometry
                          identifier
                          opacity
                          fill
                          stroke
                          stroke-width))


;;;
;;; Area Geometry
;;;

; coordinate-path->area-path : axes-visual? path-geometry? finite-real?
;                              boolean? -> path-geometry?
;;   Closes every open path run to the resolved local baseline.
(define (coordinate-path->area-path axes geometry baseline clip?)
  (define local-baseline-y
    (vec2-y
     (axes-coordinates->local-point
      axes
      (if (eq? (axes-visual-x-scale axes) 'log) 1 0)
      (resolved-area-baseline axes baseline clip?))))
  (path-geometry
   (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
     (path-subpath->area-subpath subpath local-baseline-y))))

; path-subpath->area-subpath : path-subpath? finite-real? -> path-subpath?
;;   Prepends and appends baseline edges around one open graph run.
(define (path-subpath->area-subpath subpath baseline-y)
  (when (path-subpath-closed? subpath)
    (raise-arguments-error
     'coordinate-path->area-path
     "coordinate graph subpaths must be open"
     "subpath" subpath))
  (define graph-start
    (path-subpath-start subpath))
  (define graph-end
    (subpath-final-point subpath))
  (define baseline-start
    (vec2 (vec2-x graph-start)
          baseline-y))
  (define baseline-end
    (vec2 (vec2-x graph-end)
          baseline-y))
  (path-subpath
   baseline-start
   (append
    (list (line-path-segment graph-start))
    (path-subpath-segments subpath)
    (list (line-path-segment baseline-end)))
   #t))

; subpath-final-point : path-subpath? -> vec2?
;;   Returns the final endpoint of a nonempty coordinate graph subpath.
(define (subpath-final-point subpath)
  (define segments
    (path-subpath-segments subpath))
  (if (null? segments)
      (path-subpath-start subpath)
      (path-segment-end-point (car (reverse segments)))))

; path-segment-end-point : path-segment? -> vec2?
;;   Returns the endpoint stored by one supported path segment.
(define (path-segment-end-point segment)
  (cond
    [(line-path-segment? segment)
     (line-path-segment-end segment)]
    [(cubic-bezier-path-segment? segment)
     (cubic-bezier-path-segment-end segment)]
    [else
     (raise-argument-error
      'path-segment-end-point
      "supported path segment"
      segment)]))

; resolved-area-baseline : axes-visual? finite-real? boolean? -> finite-real?
;;   Clamps the baseline to the visible y range when clipping is enabled.
(define (resolved-area-baseline axes baseline clip?)
  (cond
    [(not clip?)
     baseline]
    [else
     (define y-range
       (axes-visual-y-range axes))
     (min (axis-range-maximum y-range)
          (max (axis-range-minimum y-range)
               baseline))]))

; coordinate-area-visual : axes-visual? path-geometry? symbol? opacity?
;                          any/c any/c nonnegative-real? -> path-visual?
;;   Wraps area geometry in a path Visual with an axes-transform snapshot.
(define (coordinate-area-visual axes geometry identifier opacity fill stroke
                                stroke-width)
  (make-path-visual geometry
                    #:id identifier
                    #:center (visual-position axes)
                    #:rotation (visual-rotation axes)
                    #:scale (visual-scale axes)
                    #:opacity opacity
                    #:fill fill
                    #:stroke stroke
                    #:stroke-width stroke-width))


;;;
;;; Validation
;;;

; check-scatter-arguments : any/c any/c any/c any/c any/c any/c any/c any/c
;                           -> void?
;;   Validates scatter construction before any marker values are created.
(define (check-scatter-arguments axes
                                 points
                                 identifier
                                 clip?
                                 shape
                                 size
                                 opacity
                                 stroke-width)
  (unless (axes-visual? axes)
    (raise-argument-error 'scatter-plot "axes-visual?" axes))
  (unless (and (list? points)
               (andmap scatter-point? points))
    (raise-argument-error
     'scatter-plot
     "list of vec2 values and #f gaps"
     points))
  (unless (symbol? identifier)
    (raise-argument-error 'scatter-plot "symbol?" identifier))
  (unless (boolean? clip?)
    (raise-argument-error 'scatter-plot "boolean?" clip?))
  (unless (point-marker-shape? shape)
    (raise-argument-error
     'scatter-plot
     "point-marker-shape?"
     shape))
  (unless (and (finite-real? size)
               (positive? size))
    (raise-argument-error
     'scatter-plot
     "positive finite real?"
     size))
  (unless (opacity? opacity)
    (raise-argument-error 'scatter-plot "opacity?" opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     'scatter-plot
     "nonnegative finite real?"
     stroke-width)))

; scatter-point? : any/c -> boolean?
;;   Reports whether value is one finite numeric coordinate or an omitted point.
(define (scatter-point? value)
  (or (not value)
      (vec2? value)))

; check-area-baseline : symbol? any/c -> void?
;;   Raises an argument error unless baseline is a finite real.
(define (check-area-baseline who baseline)
  (unless (finite-real? baseline)
    (raise-argument-error who "finite-real?" baseline)))

; check-area-style : symbol? any/c any/c any/c -> void?
;;   Validates identity, opacity, and cosmetic stroke width before sampling.
(define (check-area-style who identifier opacity stroke-width)
  (unless (symbol? identifier)
    (raise-argument-error who "symbol?" identifier))
  (unless (opacity? opacity)
    (raise-argument-error who "opacity?" opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     who
     "nonnegative finite real?"
     stroke-width)))
