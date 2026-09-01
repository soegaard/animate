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
(require "axes-visual.rkt"
         "coordinate-series.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide sample-function-path
         function-graph)


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
;                        [#:interpolation curve-interpolation?]
;                        -> path-geometry?
;;   Samples a numeric function into axes-local path geometry.
(define (sample-function-path axes function
                              #:x-min [requested-x-min #f]
                              #:x-max [requested-x-max #f]
                              #:sample-count [sample-count 201]
                              #:clip? [clip? #t]
                              #:max-jump [max-jump #f]
                              #:interpolation [interpolation 'linear])
  (check-sampling-arguments 'sample-function-path
                            axes
                            function
                            requested-x-min
                            requested-x-max
                            sample-count
                            clip?
                            max-jump
                            interpolation)
  (define-values (x-min x-max)
    (resolve-sampling-domain axes
                             requested-x-min
                             requested-x-max))
  (define samples
    (sample-function-values function
                            x-min
                            x-max
                            sample-count))
  (coordinate-samples->path
   axes
   samples
   #:clip? clip?
   #:break-between?
   (lambda (start end)
     (and max-jump
          (coordinate-y-distance-exceeds? start end max-jump)))
   #:interpolation interpolation))

; function-graph : axes-visual?
;                  (procedure-arity-includes/c 1)
;                  #:id symbol?
;                  [#:x-min (or/c finite-real? false/c)]
;                  [#:x-max (or/c finite-real? false/c)]
;                  [#:sample-count exact-integer-at-least-2?]
;                  [#:clip? boolean?]
;                  [#:max-jump (or/c nonnegative-finite-real? false/c)]
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

; sample-function-values : (procedure-arity-includes/c 1)
;                          finite-real?
;                          finite-real?
;                          exact-integer-at-least-2?
;                          -> (listof (or/c vec2? false/c))
;;   Samples the closed x interval in increasing order, including both ends.
(define (sample-function-values function x-min x-max sample-count)
  (define last-index
    (sub1 sample-count))
  (for/list ([index (in-range sample-count)])
    (define x
      (cond
        [(zero? index)
         x-min]
        [(= index last-index)
         x-max]
        [else
         (real-lerp x-min
                    x-max
                    (/ index last-index))]))
    (sample-function-value function x)))

; sample-function-value : (procedure-arity-includes/c 1) finite-real?
;                         -> (or/c vec2? false/c)
;;   Converts one function result to a finite sample or an explicit gap.
(define (sample-function-value function x)
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'sample-function-path
             "the sampling procedure raised an exception"
             "x" x
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (function x))
       list)))
  (unless (= (length results) 1)
    (raise-arguments-error
     'sample-function-path
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
      'sample-function-path
      "the sampling procedure must return a real number or #f"
      "x" x
      "result" result)]))


;;;
;;; Validation
;;;

; check-sampling-arguments : symbol? any/c any/c any/c any/c any/c any/c any/c
;                            any/c -> void?
;;   Validates common function-sampling arguments before procedure invocation.
(define (check-sampling-arguments who
                                  axes
                                  function
                                  x-min
                                  x-max
                                  sample-count
                                  clip?
                                  max-jump
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
  (unless (curve-interpolation? interpolation)
    (raise-argument-error
     who
     "curve-interpolation?"
     interpolation)))

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
