#lang racket/base

;;;
;;; Deterministic Traced Paths
;;;

;; A trace is reconstructed from an explicit scalar scene parameter and a pure
;; position function.  It never accumulates prior rendered frames: sampling the
;; scene at time t always resamples the same interval [t0,t].

(require "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "parameter.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide traced-path)


;;;
;;; Public Construction
;;;

; traced-path : (or/c symbol? scene-parameter?)
;               (-> derived-context? finite-real? vec2?)
;               #:id symbol?
;               [#:start-time finite-real?]
;               [#:sample-count exact-integer-at-least-2?]
;               [#:trail-length (or/c false/c nonnegative-finite-real?)]
;               [#:dissipate? boolean?]
;               [#:minimum-opacity opacity?]
;               [#:opacity opacity?]
;               [#:stroke any/c]
;               [#:stroke-width nonnegative-finite-real?]
;               -> derived-visual?
;;   Reconstructs a deterministic locus from start-time through phase's value.
(define (traced-path phase position
                     #:id id
                     #:start-time [start-time 0]
                     #:sample-count [sample-count 121]
                     #:trail-length [trail-length #f]
                     #:dissipate? [dissipate? #f]
                     #:minimum-opacity [minimum-opacity 0]
                     #:opacity [opacity 1]
                     #:stroke [stroke "crimson"]
                     #:stroke-width [stroke-width 3])
  (define phase-id
    (parameter-target-id phase 'traced-path))
  (unless (and (procedure? position)
               (procedure-arity-includes? position 2))
    (raise-argument-error
     'traced-path
     "procedure accepting derived-context? and finite-real? time arguments"
     position))
  (unless (symbol? id)
    (raise-argument-error 'traced-path "symbol?" id))
  (check-finite 'traced-path "start-time" start-time)
  (unless (and (exact-integer? sample-count) (>= sample-count 2))
    (raise-argument-error 'traced-path "exact integer at least 2" sample-count))
  (unless (or (not trail-length)
              (and (finite-real? trail-length) (>= trail-length 0)))
    (raise-argument-error
     'traced-path
     "#f or nonnegative finite real"
     trail-length))
  (unless (boolean? dissipate?)
    (raise-argument-error 'traced-path "boolean?" dissipate?))
  (check-opacity 'traced-path "minimum-opacity" minimum-opacity)
  (check-opacity 'traced-path "opacity" opacity)
  (check-nonnegative 'traced-path "stroke-width" stroke-width)
  (define (sample-points context)
    (define current-time
      (derived-context-value-ref context phase-id))
    (unless (finite-real? current-time)
      (raise-arguments-error
       'traced-path
       "the phase parameter must hold a finite real time at every sampled frame"
       "phase-id" phase-id
       "value" current-time))
    (define interval-end current-time)
    (define interval-start
      (if trail-length
          (max start-time (- interval-end trail-length))
          start-time))
    (cond
      [(<= interval-end interval-start)
       '()]
      [else
       (for/list ([index (in-range sample-count)])
         (define time
           (real-lerp interval-start interval-end
                      (/ index (sub1 sample-count))))
         (define point (position context time))
         (unless (vec2? point)
           (raise-arguments-error
            'traced-path
            "the position procedure must return a vec2"
            "phase-id" phase-id
            "time" time
            "result" point))
         point)]))
  (define (make-solid points)
    (points->path-visual points id opacity stroke stroke-width))
  (define (make-dissipating points)
    (group
     (for/list ([start (in-list points)]
                [end (in-list (if (null? points) '() (cdr points)))]
                [index (in-naturals)])
       (define progress
         (/ (add1 index) (sub1 sample-count)))
       (points->path-visual
        (list start end)
        (string->symbol (format "trace-segment-~a" index))
        (* opacity (real-lerp minimum-opacity 1 progress))
        stroke stroke-width))
     #:id id))
  ;; The template is intentionally harmless. Scene-aware resolution replaces
  ;; it with the exact path/group for the currently sampled scalar state.
  (derived-visual
   (if dissipate?
       (group '() #:id id)
       (make-solid '()))
   (lambda (context _template)
     (define points (sample-points context))
     (if dissipate?
         (make-dissipating points)
         (make-solid points)))))


;;;
;;; Path Conversion
;;;

; points->path-visual : (listof vec2?) symbol? opacity? any/c
;                       nonnegative-finite-real? -> path-visual?
;; Centers nonempty geometry at its semantic reference point, matching line and
;; polygon constructors. An empty trace is a valid invisible path at origin.
(define (points->path-visual points id opacity stroke stroke-width)
  (cond
    [(null? points)
     (make-path-visual empty-path-geometry
                       #:id id #:opacity opacity #:fill #f
                       #:stroke stroke #:stroke-width stroke-width)]
    [else
     (define geometry (polyline-path points))
     (define center (path-geometry-center geometry))
     (make-path-visual
      (path-geometry-translate geometry (vec2-scale -1 center))
      #:id id #:center center #:opacity opacity #:fill #f
      #:stroke stroke #:stroke-width stroke-width)]))


;;;
;;; Validation
;;;

(define (check-finite who field value)
  (unless (finite-real? value)
    (raise-arguments-error who "a finite real value" field value)))

(define (check-nonnegative who field value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who "a nonnegative finite real value" field value)))

(define (check-opacity who field value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-arguments-error who "a finite real in [0, 1]" field value)))
