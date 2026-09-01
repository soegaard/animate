#lang racket/base

;;;
;;; Derived Function Graphs
;;;

;; Defines a plotting convenience over SCENE-AW derived Visuals. The graph's
;; field is sampled afresh from each immutable scene state; no mutable updater,
;; callback cache, or renderer state is stored in the resulting Visual.

(require "axes-visual.rkt"
         "derived-visual.rkt"
         "function-graph.rkt")

(provide derived-function-graph)

; derived-function-graph : axes-visual?
;                          (procedure-arity-includes/c 2)
;                          #:id symbol?
;                          [#:x-min (or/c finite-real? false/c)]
;                          [#:x-max (or/c finite-real? false/c)]
;                          [#:sample-count exact-integer-at-least-2?]
;                          [#:clip? boolean?]
;                          [#:max-jump (or/c nonnegative-finite-real? false/c)]
;                          [#:detect-discontinuities? boolean?]
;                          [#:interpolation curve-interpolation?]
;                          [#:opacity opacity?]
;                          [#:stroke any/c]
;                          [#:stroke-width nonnegative-finite-real?]
;                          -> derived-visual?
;; Creates one function graph whose field receives sampled scene context and x.
(define (derived-function-graph axes field
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
  (unless (and (procedure? field)
               (procedure-arity-includes? field 2))
    (raise-argument-error
     'derived-function-graph
     "procedure accepting derived-context? and numeric x arguments"
     field))
  ;; Running the ordinary constructor once supplies an immutable path Visual
  ;; template with the intended ID, axes transform, and style. Its harmless
  ;; zero graph is never exposed by scene-aware lookup: resolution always
  ;; reconstructs geometry from the exact sampled context.
  (define (make-graph function)
    (function-graph axes
                    function
                    #:id id
                    #:x-min x-min
                    #:x-max x-max
                    #:sample-count sample-count
                    #:clip? clip?
                    #:max-jump max-jump
                    #:detect-discontinuities? detect-discontinuities?
                    #:interpolation interpolation
                    #:opacity opacity
                    #:stroke stroke
                    #:stroke-width stroke-width))
  (derived-visual
   (make-graph (lambda (_x) 0))
   (lambda (context _template)
     (make-graph
      (lambda (x)
        (field context x))))))
