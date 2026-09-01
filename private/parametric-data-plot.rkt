#lang racket/base

;;;
;;; Parametric Curves and Data Plots
;;;

;; Samples ordered parameter domains and ordered point series into immutable
;; path geometry aligned with semantic Cartesian axes.
;;
;; Construction stores only path geometry and style. Procedures and input point
;; collections are not retained by the resulting Visuals.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "axes-visual.rkt"
         "coordinate-series.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out parameter-range)
         sample-parametric-path
         parametric-curve
         data-series-path
         data-plot)


;;;
;;; Parameter Domains
;;;

(struct parameter-range (start end)
  #:transparent
  #:guard
  (lambda (start end who)
    (unless (finite-real? start)
      (raise-argument-error who "finite real?" start))
    (unless (finite-real? end)
      (raise-argument-error who "finite real?" end))
    (define span
      (- end start))
    (unless (and (finite-real? span)
                 (not (zero? span)))
      (raise-arguments-error
       who
       "the ordered parameter span must be a nonzero finite real"
       "start" start
       "end" end
       "span" span))
    (values start end)))

;; parameter-range represents one ordered closed parameter domain.
;;  - start  finite-real?  first sampled parameter value.
;;  - end    finite-real?  last sampled parameter value.
;;
;; Ordering is significant. A decreasing domain samples from the larger start
;; value toward the smaller end value.


;;;
;;; Parametric Sampling
;;;

; sample-parametric-path : axes-visual?
;                          (procedure-arity-includes/c 1)
;                          [#:parameter-range parameter-range?]
;                          [#:sample-count exact-integer-at-least-2?]
;                          [#:clip? boolean?]
;                          [#:max-distance
;                           (or/c nonnegative-finite-real? false/c)]
;                          [#:interpolation curve-interpolation?]
;                          -> path-geometry?
;;   Samples a coordinate-valued procedure over one ordered parameter domain.
(define (sample-parametric-path axes function
                                #:parameter-range
                                [domain (parameter-range 0 1)]
                                #:sample-count [sample-count 201]
                                #:clip? [clip? #t]
                                #:max-distance [max-distance #f]
                                #:interpolation [interpolation 'linear])
  (check-parametric-arguments axes
                              function
                              domain
                              sample-count
                              clip?
                              max-distance
                              interpolation)
  (define samples
    (sample-parametric-values function
                              domain
                              sample-count))
  (coordinate-samples->path
   axes
   samples
   #:clip? clip?
   #:break-between? (max-distance-break-predicate max-distance)
   #:interpolation interpolation))

; parametric-curve : axes-visual?
;                    (procedure-arity-includes/c 1)
;                    #:id symbol?
;                    [#:parameter-range parameter-range?]
;                    [#:sample-count exact-integer-at-least-2?]
;                    [#:clip? boolean?]
;                    [#:max-distance
;                     (or/c nonnegative-finite-real? false/c)]
;                    [#:interpolation curve-interpolation?]
;                    [#:opacity opacity?]
;                    [#:stroke any/c]
;                    [#:stroke-width nonnegative-finite-real?]
;                    -> path-visual?
;;   Creates a styled path Visual from one sampled parametric curve.
(define (parametric-curve axes function
                          #:id id
                          #:parameter-range
                          [domain (parameter-range 0 1)]
                          #:sample-count [sample-count 201]
                          #:clip? [clip? #t]
                          #:max-distance [max-distance #f]
                          #:interpolation [interpolation 'linear]
                          #:opacity [opacity 1]
                          #:stroke [stroke "royalblue"]
                          #:stroke-width [stroke-width 3])
  (check-coordinate-path-style 'parametric-curve
                               id
                               opacity
                               stroke-width)
  (define path
    (sample-parametric-path axes
                            function
                            #:parameter-range domain
                            #:sample-count sample-count
                            #:clip? clip?
                            #:max-distance max-distance
                            #:interpolation interpolation))
  (coordinate-path-visual axes
                          path
                          id
                          opacity
                          stroke
                          stroke-width))

; sample-parametric-values : (procedure-arity-includes/c 1)
;                            parameter-range?
;                            exact-integer-at-least-2?
;                            -> (listof (or/c vec2? false/c))
;;   Samples the ordered closed domain, including its exact two endpoints.
(define (sample-parametric-values function domain sample-count)
  (define last-index
    (sub1 sample-count))
  (for/list ([index (in-range sample-count)])
    (define parameter
      (cond
        [(zero? index)
         (parameter-range-start domain)]
        [(= index last-index)
         (parameter-range-end domain)]
        [else
         (real-lerp (parameter-range-start domain)
                    (parameter-range-end domain)
                    (/ index last-index))]))
    (sample-parametric-value function parameter)))

; sample-parametric-value : (procedure-arity-includes/c 1) finite-real?
;                           -> (or/c vec2? false/c)
;;   Converts one procedure result to a coordinate sample or explicit gap.
(define (sample-parametric-value function parameter)
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'sample-parametric-path
             "the sampling procedure raised an exception"
             "parameter" parameter
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (function parameter))
       list)))
  (unless (= (length results) 1)
    (raise-arguments-error
     'sample-parametric-path
     "the sampling procedure must return exactly one value"
     "parameter" parameter
     "result count" (length results)))
  (define result
    (car results))
  (cond
    [(eq? result #f)
     #f]
    [(vec2? result)
     result]
    [else
     (raise-arguments-error
      'sample-parametric-path
      "the sampling procedure must return a vec2 value or #f"
      "parameter" parameter
      "result" result)]))


;;;
;;; Ordered Data Series
;;;

; data-series-path : axes-visual?
;                    (listof (or/c vec2? false/c))
;                    [#:clip? boolean?]
;                    [#:max-distance
;                     (or/c nonnegative-finite-real? false/c)]
;                    [#:interpolation curve-interpolation?]
;                    -> path-geometry?
;;   Converts an ordered coordinate series and explicit gaps to path geometry.
(define (data-series-path axes points
                          #:clip? [clip? #t]
                          #:max-distance [max-distance #f]
                          #:interpolation [interpolation 'linear])
  (check-data-series-arguments axes
                               points
                               clip?
                               max-distance
                               interpolation)
  (coordinate-samples->path
   axes
   points
   #:clip? clip?
   #:break-between? (max-distance-break-predicate max-distance)
   #:interpolation interpolation))

; data-plot : axes-visual?
;             (listof (or/c vec2? false/c))
;             #:id symbol?
;             [#:clip? boolean?]
;             [#:max-distance (or/c nonnegative-finite-real? false/c)]
;             [#:interpolation curve-interpolation?]
;             [#:opacity opacity?]
;             [#:stroke any/c]
;             [#:stroke-width nonnegative-finite-real?]
;             -> path-visual?
;;   Creates a styled path Visual from one ordered coordinate series.
(define (data-plot axes points
                   #:id id
                   #:clip? [clip? #t]
                   #:max-distance [max-distance #f]
                   #:interpolation [interpolation 'linear]
                   #:opacity [opacity 1]
                   #:stroke [stroke "seagreen"]
                   #:stroke-width [stroke-width 3])
  (check-coordinate-path-style 'data-plot
                               id
                               opacity
                               stroke-width)
  (define path
    (data-series-path axes
                      points
                      #:clip? clip?
                      #:max-distance max-distance
                      #:interpolation interpolation))
  (coordinate-path-visual axes
                          path
                          id
                          opacity
                          stroke
                          stroke-width))


;;;
;;; Shared Construction
;;;

; max-distance-break-predicate :
;   (or/c nonnegative-finite-real? false/c)
;   -> (-> vec2? vec2? boolean?)
;;   Returns a predicate that breaks runs beyond the optional distance limit.
(define (max-distance-break-predicate max-distance)
  (lambda (start end)
    (and max-distance
         (coordinate-distance-exceeds? start end max-distance))))

; coordinate-path-visual : axes-visual? path-geometry? symbol? opacity?
;                          any/c nonnegative-finite-real? -> path-visual?
;;   Wraps axes-local geometry in a path Visual with an axes-transform snapshot.
(define (coordinate-path-visual axes path id opacity stroke stroke-width)
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
;;; Validation
;;;

; check-parametric-arguments : any/c any/c any/c any/c any/c any/c any/c
;                              -> void?
;;   Validates parametric sampling arguments before procedure invocation.
(define (check-parametric-arguments axes
                                    function
                                    domain
                                    sample-count
                                    clip?
                                    max-distance
                                    interpolation)
  (unless (axes-visual? axes)
    (raise-argument-error
     'sample-parametric-path
     "axes-visual?"
     axes))
  (unless (and (procedure? function)
               (procedure-arity-includes? function 1))
    (raise-argument-error
     'sample-parametric-path
     "procedure accepting one argument"
     function))
  (unless (parameter-range? domain)
    (raise-argument-error
     'sample-parametric-path
     "parameter-range?"
     domain))
  (check-coordinate-path-options 'sample-parametric-path
                                 sample-count
                                 clip?
                                 max-distance
                                 interpolation))

; check-data-series-arguments : any/c any/c any/c any/c any/c -> void?
;;   Validates ordered point-series arguments before path conversion.
(define (check-data-series-arguments axes
                                     points
                                     clip?
                                     max-distance
                                     interpolation)
  (unless (axes-visual? axes)
    (raise-argument-error 'data-series-path "axes-visual?" axes))
  (unless (and (list? points)
               (andmap data-series-point? points))
    (raise-argument-error
     'data-series-path
     "list of vec2 values and #f gaps"
     points))
  (check-coordinate-path-options 'data-series-path
                                 #f
                                 clip?
                                 max-distance
                                 interpolation))

; check-coordinate-path-options : symbol? (or/c exact-integer? false/c)
;                                 any/c any/c any/c -> void?
;;   Validates sampling count, clipping, distance, and interpolation options.
(define (check-coordinate-path-options who
                                       sample-count
                                       clip?
                                       max-distance
                                       interpolation)
  (when sample-count
    (unless (and (exact-integer? sample-count)
                 (>= sample-count 2))
      (raise-argument-error
       who
       "exact integer greater than or equal to 2"
       sample-count)))
  (unless (boolean? clip?)
    (raise-argument-error who "boolean?" clip?))
  (unless (or (not max-distance)
              (and (finite-real? max-distance)
                   (not (negative? max-distance))))
    (raise-argument-error
     who
     "nonnegative finite real or #f"
     max-distance))
  (unless (curve-interpolation? interpolation)
    (raise-argument-error
     who
     "curve-interpolation?"
     interpolation)))

; check-coordinate-path-style : symbol? any/c any/c any/c -> void?
;;   Validates identity, opacity, and cosmetic stroke width before sampling.
(define (check-coordinate-path-style who id opacity stroke-width)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error
     who
     "finite real in [0, 1]"
     opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     who
     "nonnegative finite real?"
     stroke-width)))

; data-series-point? : any/c -> boolean?
;;   Reports whether value is one finite coordinate or an explicit gap.
(define (data-series-point? value)
  (or (not value)
      (vec2? value)))
