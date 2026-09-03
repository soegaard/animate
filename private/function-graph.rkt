#lang racket/base

;;;
;;; Sampled Function Graphs
;;;

;; Samples one-variable numeric procedures into immutable path geometry aligned
;; with semantic Cartesian axes.
;;
;; Sampling happens when a graph is constructed. The resulting model stores
;; only path geometry, never the sampling procedure or renderer state.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "axes-visual.rkt"
         "coordinate-series.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide sample-function-path
         function-graph
         sample-adaptive-function-path
         adaptive-function-graph)


;;;
;;; Public Construction
;;;

; sample-function-path : axes-visual?
;                        (procedure-arity-includes/c 1)
;                        [#:x-min (or/c finite-real? false/c)]
;                        [#:x-max (or/c finite-real? false/c)]
;                        [#:sample-count exact-integer-at-least-2?]
;                        [#:clip? boolean?]
;                        [#:max-jump (or/c nonnegative-finite-real? false/c)]
;                        [#:detect-discontinuities? boolean?]
;                        [#:interpolation curve-interpolation?]
;                        -> path-geometry?
;;   Samples a numeric function into axes-local path geometry.
(define (sample-function-path axes function
                              #:x-min [requested-x-min #f]
                              #:x-max [requested-x-max #f]
                              #:sample-count [sample-count 201]
                              #:clip? [clip? #t]
                              #:max-jump [max-jump #f]
                              #:detect-discontinuities?
                              [detect-discontinuities? #f]
                              #:interpolation [interpolation 'linear])
  (check-sampling-arguments 'sample-function-path
                            axes
                            function
                            requested-x-min
                            requested-x-max
                            sample-count
                            clip?
                            max-jump
                            detect-discontinuities?
                            interpolation)
  (define-values (x-min x-max)
    (resolve-sampling-domain axes
                             requested-x-min
                             requested-x-max))
  (define samples
    (sample-function-values axes
                            function
                            x-min
                            x-max
                            sample-count))
  (coordinate-samples->path
   axes
   samples
   #:clip? clip?
   #:break-between?
   (lambda (start end)
     (or (and max-jump
              (coordinate-y-distance-exceeds? start end max-jump))
         (and detect-discontinuities?
              (coordinate-pair-crosses-hidden-asymptote? axes start end))))
   #:interpolation interpolation))

; function-graph : axes-visual?
;                  (procedure-arity-includes/c 1)
;                  #:id symbol?
;                  [#:x-min (or/c finite-real? false/c)]
;                  [#:x-max (or/c finite-real? false/c)]
;                  [#:sample-count exact-integer-at-least-2?]
;                  [#:clip? boolean?]
;                  [#:max-jump (or/c nonnegative-finite-real? false/c)]
;                  [#:detect-discontinuities? boolean?]
;                  [#:interpolation curve-interpolation?]
;                  [#:opacity opacity?]
;                  [#:stroke any/c]
;                  [#:stroke-width nonnegative-finite-real?]
;                  -> path-visual?
;;   Creates a path Visual aligned with a sampled snapshot of axes.
(define (function-graph axes function
                        #:id id
                        #:x-min [x-min #f]
                        #:x-max [x-max #f]
                        #:sample-count [sample-count 201]
                        #:clip? [clip? #t]
                        #:max-jump [max-jump #f]
                        #:detect-discontinuities?
                        [detect-discontinuities? #f]
                        #:interpolation [interpolation 'linear]
                        #:opacity [opacity 1]
                        #:stroke [stroke "royalblue"]
                        #:stroke-width [stroke-width 3])
  (unless (symbol? id)
    (raise-argument-error 'function-graph "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error
     'function-graph
     "finite real in [0, 1]"
     opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     'function-graph
     "nonnegative finite real?"
     stroke-width))
  (define path
    (sample-function-path axes
                          function
                          #:x-min x-min
                          #:x-max x-max
                          #:sample-count sample-count
                          #:clip? clip?
                          #:max-jump max-jump
                          #:detect-discontinuities?
                          detect-discontinuities?
                          #:interpolation interpolation))
  (make-path-visual path
                    #:id id
                    #:center (visual-position axes)
                    #:rotation (visual-rotation axes)
                    #:scale (visual-scale axes)
                    #:opacity opacity
                    #:fill #f
                    #:stroke stroke
                    #:stroke-width stroke-width))


;;;
;;; Adaptive Public Construction
;;;

; sample-adaptive-function-path : axes-visual?
;                                 (procedure-arity-includes/c 1)
;                                 [#:x-min (or/c finite-real? false/c)]
;                                 [#:x-max (or/c finite-real? false/c)]
;                                 [#:initial-sample-count exact-integer-at-least-2?]
;                                 [#:max-deviation nonnegative-finite-real?]
;                                 [#:max-depth exact-nonnegative-integer?]
;                                 [#:clip? boolean?]
;                                 [#:max-jump (or/c nonnegative-finite-real? false/c)]
;                                 [#:detect-discontinuities? boolean?]
;                                 [#:excluded-intervals (listof numeric-interval-spec?)]
;                                 [#:interpolation curve-interpolation?]
;                                 -> path-geometry?
;; Samples a function with deterministic quarter/midpoint/three-quarter probes
;; in axes-local geometry. Explicit exclusions and detected poles become path
;; breaks.
(define (sample-adaptive-function-path axes function
                                       #:x-min [requested-x-min #f]
                                       #:x-max [requested-x-max #f]
                                       #:initial-sample-count
                                       [initial-sample-count 17]
                                       #:max-deviation [max-deviation 1/100]
                                       #:max-depth [max-depth 12]
                                       #:clip? [clip? #t]
                                       #:max-jump [max-jump #f]
                                       #:detect-discontinuities?
                                       [detect-discontinuities? #t]
                                       #:excluded-intervals
                                       [excluded-intervals '()]
                                       #:interpolation [interpolation 'linear])
  (check-adaptive-sampling-arguments
   'sample-adaptive-function-path
   axes function requested-x-min requested-x-max initial-sample-count
   max-deviation max-depth clip? max-jump detect-discontinuities?
   excluded-intervals interpolation)
  (define-values (x-min x-max)
    (resolve-sampling-domain axes requested-x-min requested-x-max))
  (define excluded
    (normalize-excluded-intervals excluded-intervals))
  (define active-intervals
    (subtract-excluded-intervals x-min x-max excluded))
  (define samples
    (adaptive-function-samples axes function active-intervals
                               initial-sample-count max-deviation max-depth
                               max-jump detect-discontinuities?))
  (coordinate-samples->path
   axes samples #:clip? clip? #:interpolation interpolation))

; adaptive-function-graph : axes-visual?
;                           (procedure-arity-includes/c 1)
;                           #:id symbol? ... -> path-visual?
;; Wraps adaptive path geometry in the same immutable axes transform snapshot
;; used by function-graph.
(define (adaptive-function-graph axes function
                                 #:id id
                                 #:x-min [x-min #f]
                                 #:x-max [x-max #f]
                                 #:initial-sample-count
                                 [initial-sample-count 17]
                                 #:max-deviation [max-deviation 1/100]
                                 #:max-depth [max-depth 12]
                                 #:clip? [clip? #t]
                                 #:max-jump [max-jump #f]
                                 #:detect-discontinuities?
                                 [detect-discontinuities? #t]
                                 #:excluded-intervals
                                 [excluded-intervals '()]
                                 #:interpolation [interpolation 'linear]
                                 #:opacity [opacity 1]
                                 #:stroke [stroke "royalblue"]
                                 #:stroke-width [stroke-width 3])
  (unless (symbol? id)
    (raise-argument-error 'adaptive-function-graph "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error
     'adaptive-function-graph
     "finite real in [0, 1]"
     opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     'adaptive-function-graph
     "nonnegative finite real?"
     stroke-width))
  (define path
    (sample-adaptive-function-path
     axes function
     #:x-min x-min #:x-max x-max
     #:initial-sample-count initial-sample-count
     #:max-deviation max-deviation #:max-depth max-depth
     #:clip? clip? #:max-jump max-jump
     #:detect-discontinuities? detect-discontinuities?
     #:excluded-intervals excluded-intervals
     #:interpolation interpolation))
  (make-path-visual path
                    #:id id
                    #:center (visual-position axes)
                    #:rotation (visual-rotation axes)
                    #:scale (visual-scale axes)
                    #:opacity opacity
                    #:fill #f
                    #:stroke stroke
                    #:stroke-width stroke-width))


;;;
;;; Sampling
;;;

; sample-function-values : axes-visual? (procedure-arity-includes/c 1)
;                          finite-real?
;                          finite-real?
;                          exact-integer-at-least-2?
;                          -> (listof (or/c vec2? false/c))
;;   Samples the closed x interval in increasing order, including both ends.
(define (sample-function-values axes function x-min x-max sample-count)
  (define last-index
    (sub1 sample-count))
  (for/list ([index (in-range sample-count)])
    (define x
      (sampling-domain-value axes x-min x-max (/ index last-index)))
    (sample-function-value function x)))

; sampling-domain-value : axes-visual? finite-real? finite-real? finite-real?
;                         -> finite-real?
;; Returns one point uniformly spaced in the x display coordinate.  Keeping this
;; shared lets adaptive sampling use the same log-axis semantics as fixed grids.
(define (sampling-domain-value axes x-min x-max progress)
  (cond
    [(zero? progress) x-min]
    [(= progress 1) x-max]
    [(eq? (axes-visual-x-scale axes) 'log)
     (logarithmic-domain-value axes x-min x-max progress)]
    [else
     (real-lerp x-min x-max progress)]))

; logarithmic-domain-value : axes-visual? positive-real? positive-real?
;                            finite-real? -> finite-real?
;; Interpolates requested function-graph bounds uniformly in log display space.
(define (logarithmic-domain-value axes x-min x-max progress)
  (define base (axes-visual-x-log-base axes))
  (expt base
        (real-lerp (/ (log x-min) (log base))
                   (/ (log x-max) (log base))
                   progress)))

; sample-function-value : (procedure-arity-includes/c 1) finite-real?
;                         -> (or/c vec2? false/c)
;;   Converts one function result to a finite sample or an explicit gap.
(define (sample-function-value function x
                               #:who [who 'sample-function-path]
                               #:divide-by-zero-gap?
                               [divide-by-zero-gap? #f])
  (define results
    (with-handlers
        ([(lambda (exception)
            (and divide-by-zero-gap?
                 (exn:fail:contract:divide-by-zero? exception)))
          (lambda (_exception) (list #f))]
         [exn:fail?
          (lambda (exception)
            (raise-arguments-error
             who
             "the sampling procedure raised an exception"
             "x" x
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (function x))
       list)))
  (unless (= (length results) 1)
    (raise-arguments-error
     who
     "the sampling procedure must return exactly one value"
     "x" x
     "result count" (length results)))
  (define result
    (car results))
  (cond
    [(eq? result #f)
     #f]
    [(finite-real? result)
     (vec2 x result)]
    [(real? result)
     #f]
    [else
     (raise-arguments-error
      who
      "the sampling procedure must return a real number or #f"
      "x" x
      "result" result)]))


;;;
;;; Adaptive Sampling
;;;

;; An adaptive-segment is one accepted numeric-coordinate chord. A #f in the
;; segment stream records a mandatory gap; later conversion merges only truly
;; adjacent chords into a path run.
(struct adaptive-segment (start end)
  #:transparent)

;; An excluded-interval records a closed numeric interval which must remain a
;; gap. The endpoint values may still become the visible ends of neighbouring
;; branches; no segment can cross the interval's interior.
(struct excluded-interval (minimum maximum)
  #:transparent)

; adaptive-function-samples : axes-visual? procedure?
;                             (listof (list finite-real? finite-real?)) ...
;                             -> (listof (or/c vec2? false/c))
;; Builds a deterministic series of finite samples and explicit gaps. Function
;; results are cached by exact x value, so shared adaptive boundaries are never
;; evaluated twice.
(define (adaptive-function-samples axes function active-intervals
                                   initial-sample-count max-deviation max-depth
                                   max-jump detect-discontinuities?)
  (define sample-cache (make-hash))
  (define (sample-at x)
    (hash-ref!
     sample-cache x
     (lambda ()
       (sample-function-value function x
                              #:who 'sample-adaptive-function-path
                              #:divide-by-zero-gap? #t))))
  (define (break-between? start end)
    (or (and max-jump
             (coordinate-y-distance-exceeds? start end max-jump))
        (and detect-discontinuities?
             (coordinate-pair-crosses-hidden-asymptote? axes start end))))
  (define (chord-deviation start probe end progress)
    ;; Every probe lies at a display-space fraction of its chord. Comparing its
    ;; local point to the matching fraction of the chord measures the rendered
    ;; axes-local flatness directly. Quarter probes catch a crest or trough
    ;; which happens to leave the interval midpoint nearly chord-collinear.
    (define start-local
      (axes-coordinates->local-point axes (vec2-x start) (vec2-y start)))
    (define probe-local
      (axes-coordinates->local-point axes (vec2-x probe) (vec2-y probe)))
    (define end-local
      (axes-coordinates->local-point axes (vec2-x end) (vec2-y end)))
    (vec2-distance probe-local
                   (vec2-lerp start-local end-local progress)))
  (define (breaks-among? samples)
    (for/or ([start (in-list samples)]
             [end (in-list (cdr samples))])
      (break-between? start end)))
  (define (must-refine? start quarter middle three-quarters end)
    (define samples (list start quarter middle three-quarters end))
    (or (not start)
        (not quarter)
        (not middle)
        (not three-quarters)
        (not end)
        (breaks-among? samples)
        (> (max (chord-deviation start quarter end 1/4)
                (chord-deviation start middle end 1/2)
                (chord-deviation start three-quarters end 3/4))
           max-deviation)))
  (define (sample-interval x-start start x-end end depth)
    (define x-quarter
      (sampling-domain-value axes x-start x-end 1/4))
    (define x-middle
      (sampling-domain-value axes x-start x-end 1/2))
    (define x-three-quarters
      (sampling-domain-value axes x-start x-end 3/4))
    (define quarter (sample-at x-quarter))
    (define middle (sample-at x-middle))
    (define three-quarters (sample-at x-three-quarters))
    (define needs-refinement?
      (must-refine? start quarter middle three-quarters end))
    (cond
      [(and needs-refinement? (< depth max-depth))
       (append (sample-interval x-start start x-middle middle (add1 depth))
               (sample-interval x-middle middle x-end end (add1 depth)))]
      [(or (not start)
           (not quarter)
           (not middle)
           (not three-quarters)
           (not end)
           (breaks-among? (list start quarter middle three-quarters end)))
       (list #f)]
      [else
       (list (adaptive-segment start end))]))
  (define segment-stream
    (append*
     (for/list ([interval (in-list active-intervals)])
       (define x-min (car interval))
       (define x-max (cadr interval))
       (define xs
         (for/list ([index (in-range initial-sample-count)])
           (sampling-domain-value axes x-min x-max
                                  (/ index (sub1 initial-sample-count)))))
       (append
        (for/fold ([segments '()])
                  ([x-start (in-list xs)] [x-end (in-list (cdr xs))])
          (append segments
                  (sample-interval x-start (sample-at x-start)
                                   x-end (sample-at x-end) 0)))
        (list #f)))))
  (adaptive-segments->samples segment-stream))

; adaptive-segments->samples : (listof (or/c adaptive-segment? false/c))
;                              -> (listof (or/c vec2? false/c))
;; Joins contiguous accepted chords and retains explicit breaks between runs.
(define (adaptive-segments->samples segment-stream)
  (define reversed-runs
    (let loop ([remaining segment-stream]
               [current-reversed '()]
               [runs '()])
      (cond
        [(null? remaining)
         (flush-adaptive-run current-reversed runs)]
        [(not (car remaining))
         (loop (cdr remaining) '()
               (flush-adaptive-run current-reversed runs))]
        [else
         (define segment (car remaining))
         (define start (adaptive-segment-start segment))
         (define end (adaptive-segment-end segment))
         (cond
           [(null? current-reversed)
            (loop (cdr remaining) (list end start) runs)]
           [(equal? (car current-reversed) start)
            (loop (cdr remaining) (cons end current-reversed) runs)]
           [else
           (loop (cdr remaining) (list end start)
                  (flush-adaptive-run current-reversed runs))])])))
  (define runs (reverse reversed-runs))
  (cond
    [(null? runs) '()]
    [else
     (append*
      (for/list ([run (in-list runs)] [index (in-naturals)])
        (append run (if (= index (sub1 (length runs))) '() (list #f)))))]))

; flush-adaptive-run : (listof vec2?) (listof (listof vec2?))
;                      -> (listof (listof vec2?))
;; Ignores insignificant point-only runs, just like coordinate-series paths.
(define (flush-adaptive-run reversed-points runs)
  (if (>= (length reversed-points) 2)
      (cons (reverse reversed-points) runs)
      runs))

; vec2-distance : vec2? vec2? -> nonnegative-finite-real?
;; Returns a stable Euclidean distance for the local midpoint flatness test.
(define (vec2-distance first second)
  (define dx (abs (- (vec2-x second) (vec2-x first))))
  (define dy (abs (- (vec2-y second) (vec2-y first))))
  (define scale (max dx dy))
  (if (zero? scale)
      0
      (* scale
         (sqrt (+ (sqr (/ dx scale))
                  (sqr (/ dy scale)))))))

(define (sqr value)
  (* value value))

; normalize-excluded-intervals : (listof numeric-interval-spec?)
;                                -> (listof excluded-interval?)
;; Converts flexible pair/list input to sorted, merged intervals.
(define (normalize-excluded-intervals interval-specifications)
  (define raw-intervals
    (for/list ([specification (in-list interval-specifications)])
      (define-values (minimum maximum)
        (numeric-interval-specification-values specification))
      (excluded-interval minimum maximum)))
  (define sorted
    (sort raw-intervals < #:key excluded-interval-minimum))
  (reverse
   (for/fold ([merged-reversed '()]) ([current (in-list sorted)])
     (cond
       [(null? merged-reversed)
        (list current)]
       [else
        (define previous (car merged-reversed))
        (if (<= (excluded-interval-minimum current)
                (excluded-interval-maximum previous))
            (cons (excluded-interval
                   (excluded-interval-minimum previous)
                   (max (excluded-interval-maximum previous)
                        (excluded-interval-maximum current)))
                  (cdr merged-reversed))
            (cons current merged-reversed))]))))

; subtract-excluded-intervals : finite-real? finite-real?
;                               (listof excluded-interval?)
;                               -> (listof (list finite-real? finite-real?))
;; Splits one requested domain at excluded intervals. It leaves only positive
;; spans, in increasing order, and preserves boundary values for clipping.
(define (subtract-excluded-intervals x-min x-max excluded)
  (define-values (reversed-pieces final-start)
    (for/fold ([pieces '()] [current-start x-min])
              ([current (in-list excluded)])
      (define start (excluded-interval-minimum current))
      (define end (excluded-interval-maximum current))
      (cond
        [(<= end current-start)
         (values pieces current-start)]
        [(>= start x-max)
         (values pieces current-start)]
        [else
         (define before-end (min start x-max))
         (values (if (< current-start before-end)
                     (cons (list current-start before-end) pieces)
                     pieces)
                 (max current-start end))])))
  (reverse
   (if (< final-start x-max)
       (cons (list final-start x-max) reversed-pieces)
       reversed-pieces)))


;;;
;;; Validation
;;;

; check-adaptive-sampling-arguments : symbol? any/c any/c any/c any/c any/c
;                                      any/c any/c any/c any/c any/c any/c
;                                      -> void?
;; Validates adaptive controls before any callback invocation.
(define (check-adaptive-sampling-arguments who
                                           axes function x-min x-max
                                           initial-sample-count max-deviation
                                           max-depth clip? max-jump
                                           detect-discontinuities?
                                           excluded-intervals interpolation)
  (check-sampling-arguments who axes function x-min x-max
                            initial-sample-count clip? max-jump
                            detect-discontinuities? interpolation)
  (unless (and (finite-real? max-deviation)
               (not (negative? max-deviation)))
    (raise-argument-error who "nonnegative finite real?" max-deviation))
  (unless (and (exact-integer? max-depth)
               (not (negative? max-depth)))
    (raise-argument-error who "exact nonnegative integer?" max-depth))
  (unless (list? excluded-intervals)
    (raise-argument-error who "list of increasing numeric interval pairs"
                          excluded-intervals))
  (for ([specification (in-list excluded-intervals)])
    (define-values (minimum maximum)
      (numeric-interval-specification-values specification))
    (unless (< minimum maximum)
      (raise-arguments-error
       who
       "each excluded interval must have an increasing finite range"
       "interval" specification))))

; numeric-interval-specification-values : any/c -> (values finite-real? finite-real?)
;; Accepts either the concise (cons minimum maximum) spelling or a two-element
;; list. Both are convenient in quoted Racket data and keep exclusions free of
;; a public wrapper structure.
(define (numeric-interval-specification-values specification)
  (cond
    [(and (pair? specification)
          (finite-real? (car specification))
          (finite-real? (cdr specification)))
     (values (car specification) (cdr specification))]
    [(and (list? specification)
          (= (length specification) 2)
          (finite-real? (car specification))
          (finite-real? (cadr specification)))
     (values (car specification) (cadr specification))]
    [else
     (raise-argument-error
      'sample-adaptive-function-path
      "numeric interval as (cons minimum maximum) or (list minimum maximum)"
      specification)]))

; check-sampling-arguments : symbol? any/c any/c any/c any/c any/c any/c any/c
;                            any/c any/c -> void?
;;   Validates common function-sampling arguments before procedure invocation.
(define (check-sampling-arguments who
                                  axes
                                  function
                                  x-min
                                  x-max
                                  sample-count
                                  clip?
                                  max-jump
                                  detect-discontinuities?
                                  interpolation)
  (unless (axes-visual? axes)
    (raise-argument-error who "axes-visual?" axes))
  (unless (and (procedure? function)
               (procedure-arity-includes? function 1))
    (raise-argument-error
     who
     "procedure accepting one argument"
     function))
  (unless (or (not x-min)
              (finite-real? x-min))
    (raise-argument-error who "finite real or #f" x-min))
  (unless (or (not x-max)
              (finite-real? x-max))
    (raise-argument-error who "finite real or #f" x-max))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 2))
    (raise-argument-error
     who
     "exact integer greater than or equal to 2"
     sample-count))
  (unless (boolean? clip?)
    (raise-argument-error who "boolean?" clip?))
  (unless (or (not max-jump)
              (and (finite-real? max-jump)
                   (not (negative? max-jump))))
    (raise-argument-error
     who
     "nonnegative finite real or #f"
     max-jump))
  (unless (boolean? detect-discontinuities?)
    (raise-argument-error who "boolean?" detect-discontinuities?))
  (unless (curve-interpolation? interpolation)
    (raise-argument-error
     who
     "curve-interpolation?"
     interpolation)))

; coordinate-pair-crosses-hidden-asymptote? : axes-visual? vec2? vec2? -> boolean?
;; Identifies the characteristic adjacent samples of a vertical asymptote: both
;; endpoints lie beyond opposite sides of the visible numeric y interval. This
;; avoids connecting clipped branches through the plotting window while leaving
;; ordinary steep or discontinuous in-range data under caller control.
(define (coordinate-pair-crosses-hidden-asymptote? axes start end)
  (define y-range (axes-visual-y-range axes))
  (define start-y (vec2-y start))
  (define end-y (vec2-y end))
  (or (and (< start-y (axis-range-minimum y-range))
           (> end-y (axis-range-maximum y-range)))
      (and (> start-y (axis-range-maximum y-range))
           (< end-y (axis-range-minimum y-range)))))

; resolve-sampling-domain : axes-visual?
;                           (or/c finite-real? false/c)
;                           (or/c finite-real? false/c)
;                           -> (values finite-real? finite-real?)
;;   Resolves omitted bounds from axes and validates a finite positive span.
(define (resolve-sampling-domain axes requested-x-min requested-x-max)
  (define x-range
    (axes-visual-x-range axes))
  (define x-min
    (or requested-x-min
        (axis-range-minimum x-range)))
  (define x-max
    (or requested-x-max
        (axis-range-maximum x-range)))
  (unless (< x-min x-max)
    (raise-arguments-error
     'sample-function-path
     "the sampling minimum must be less than the sampling maximum"
     "x-min" x-min
     "x-max" x-max))
  (when (and (eq? (axes-visual-x-scale axes) 'log)
             (not (positive? x-min)))
    (raise-arguments-error
     'sample-function-path
     "the sampling interval for a logarithmic x axis must be strictly positive"
     "x-min" x-min
     "x-max" x-max))
  (define span
    (- x-max x-min))
  (unless (and (finite-real? span)
               (positive? span))
    (raise-arguments-error
     'sample-function-path
     "the sampling span must be a positive finite real"
     "x-min" x-min
     "x-max" x-max
     "span" span))
  (values x-min x-max))
