#lang racket/base

;;;
;;; Pure mapped-composition delay plans
;;;

;; A delay plan is independent of source/scheduled order. The scene compiler
;; supplies already ordered target refs plus an optional frozen local-start
;; position context, and this module returns immutable nonnegative offsets.

(require "geometry.rkt"
         "target-sequence.rkt")

(provide delay-plan?
         index-delay
         index-delay?
         index-delay-ratio
         constant-delay
         constant-delay?
         distance-delay
         distance-delay?
         radial-delay
         radial-delay?
         wave-delay
         wave-delay?
         delay-plan-requires-layout?
         resolve-delay-plan)

(struct index-delay-value (ratio) #:transparent)
(struct constant-delay-value (value) #:transparent)
(struct distance-delay-value (point scale) #:transparent)
(struct radial-delay-value (center scale) #:transparent)
(struct wave-delay-value (direction wavelength phase) #:transparent)

(define (delay-plan? value)
  (or (index-delay-value? value)
      (constant-delay-value? value)
      (distance-delay-value? value)
      (radial-delay-value? value)
      (wave-delay-value? value)))

(define index-delay? index-delay-value?)
(define index-delay-ratio index-delay-value-ratio)
(define constant-delay? constant-delay-value?)
(define distance-delay? distance-delay-value?)
(define radial-delay? radial-delay-value?)
(define wave-delay? wave-delay-value?)

(define (vec2-magnitude value)
  (sqrt (+ (* (vec2-x value) (vec2-x value))
           (* (vec2-y value) (vec2-y value)))))

(define (check-nonnegative-finite who label value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who
                           "a nonnegative finite real"
                           label value)))

(define (check-finite-vec2 who label value #:nonzero? [nonzero? #f])
  (unless (and (vec2? value)
               (finite-real? (vec2-x value))
               (finite-real? (vec2-y value)))
    (raise-arguments-error who "a vec2 with finite components" label value))
  (when (and nonzero? (zero? (vec2-magnitude value)))
    (raise-arguments-error who "a nonzero direction vector" label value))
  value)

;; index-delay uses the scheduled index, never source index. This makes it a
;; timing policy while `#:order` remains the separate policy that determines
;; which target receives each scheduled index.
(define (index-delay ratio)
  (check-nonnegative-finite 'index-delay "ratio" ratio)
  (index-delay-value ratio))

;; A constant delay is useful as an explicit lead-in for a mapped group.
(define (constant-delay value)
  (check-nonnegative-finite 'constant-delay "value" value)
  (constant-delay-value value))

(define (distance-delay point scale)
  (check-finite-vec2 'distance-delay "point" point)
  (check-nonnegative-finite 'distance-delay "scale" scale)
  (distance-delay-value point scale))

(define (radial-delay center scale)
  (check-finite-vec2 'radial-delay "center" center)
  (check-nonnegative-finite 'radial-delay "scale" scale)
  (radial-delay-value center scale))

(define (wave-delay direction wavelength phase)
  (check-finite-vec2 'wave-delay "direction" direction #:nonzero? #t)
  (unless (and (finite-real? wavelength) (positive? wavelength))
    (raise-arguments-error 'wave-delay "a positive finite wavelength"
                           "wavelength" wavelength))
  (unless (finite-real? phase)
    (raise-arguments-error 'wave-delay "a finite phase" "phase" phase))
  (wave-delay-value direction wavelength phase))

(define (delay-plan-requires-layout? plan)
  (or (distance-delay-value? plan)
      (radial-delay-value? plan)
      (wave-delay-value? plan)))

;; resolve-delay-plan : delay-plan? immutable-vector? immutable-hash?
;;                       -> immutable-vector?
;; `context` may carry a `positions` hash mapping the exact resolved target-ref
;; values to frozen world-space vec2 positions. Position-driven plans reject a
;; missing position rather than treating a local or unavailable layout as (0,0).
(define (resolve-delay-plan plan references context)
  (unless (delay-plan? plan)
    (raise-argument-error 'resolve-delay-plan "delay-plan?" plan))
  (unless (vector? references)
    (raise-argument-error 'resolve-delay-plan "vector? of target-ref?" references))
  (unless (andmap target-ref? (vector->list references))
    (raise-argument-error 'resolve-delay-plan "vector? of target-ref?" references))
  (unless (hash? context)
    (raise-argument-error 'resolve-delay-plan "immutable hash? as context" context))
  (define (frozen-position reference)
    (define positions (hash-ref context 'positions #f))
    (define position (and (hash? positions) (hash-ref positions reference #f)))
    (unless (vec2? position)
      (raise-arguments-error
       'resolve-delay-plan
       "a frozen local-start 2D position for every target of this delay plan"
       "delay-plan" plan
       "target-path" (target-ref-path reference)
       "target-ref" reference
       "available-position" position))
    position)
  (define raw-offsets
    (cond
      [(index-delay-value? plan)
       (for/vector #:length (vector-length references)
                   ([reference (in-vector references)])
         (* (index-delay-value-ratio plan)
            (target-ref-scheduled-index reference)))]
      [(constant-delay-value? plan)
       (make-vector (vector-length references) (constant-delay-value-value plan))]
      [(distance-delay-value? plan)
       (for/vector #:length (vector-length references)
                   ([reference (in-vector references)])
         (* (distance-delay-value-scale plan)
            (vec2-magnitude
             (vec2- (frozen-position reference)
                    (distance-delay-value-point plan)))))]
      [(radial-delay-value? plan)
       (for/vector #:length (vector-length references)
                   ([reference (in-vector references)])
         (* (radial-delay-value-scale plan)
            (vec2-magnitude
             (vec2- (frozen-position reference)
                    (radial-delay-value-center plan)))))]
      [else
       (define direction (wave-delay-value-direction plan))
       (for/vector #:length (vector-length references)
                   ([reference (in-vector references)])
         (+ (/ (+ (* (vec2-x direction) (vec2-x (frozen-position reference)))
                  (* (vec2-y direction) (vec2-y (frozen-position reference))))
               (wave-delay-value-wavelength plan))
            (wave-delay-value-phase plan)))]))
  (define normalized-offsets
    (if (delay-plan-requires-layout? plan)
        (let ([minimum (apply min (vector->list raw-offsets))])
          (for/vector #:length (vector-length raw-offsets)
                      ([offset (in-vector raw-offsets)])
            (- offset minimum)))
        raw-offsets))
  (unless (andmap (lambda (offset)
                    (and (finite-real? offset) (not (negative? offset))))
                  (vector->list normalized-offsets))
    (raise-arguments-error 'resolve-delay-plan
                           "finite nonnegative delay offsets"
                           "delay-plan" plan
                           "offsets" normalized-offsets))
  (vector->immutable-vector normalized-offsets))
