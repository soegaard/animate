#lang racket/base

;; Read-only semantic reports for preview/authoring tools.  They operate on
;; prepared values only and never select, transform, or otherwise mutate a
;; Scene or view.

(require "../geometry.rkt"
         "equilibrium3d.rkt" "flow-map3d.rkt" "linearization3d.rkt"
         "ode-flow3d.rkt" "seed-set3d.rkt" "vec3.rkt")

(provide trajectory-inspection3d equilibrium-inspection3d
         trajectory-pick-inspection3d
         linearization-inspection3d flow-map-inspection3d)

(define (trajectory-inspection3d trajectory)
  (unless (prepared-trajectory3d? trajectory)
    (raise-argument-error 'trajectory-inspection3d "prepared-trajectory3d?" trajectory))
  (define range (ode-trajectory3d-time-range trajectory))
  (hasheq 'kind 'trajectory
          'time-range range
          'solver (ode-trajectory3d-solver trajectory)
          'diagnostics (ode-trajectory3d-diagnostics trajectory)
          'termination (ode-trajectory3d-termination trajectory)
          'event-hits (ode-trajectory3d-event-hits trajectory)
          'arc-length (ode-trajectory3d-arc-length-at trajectory (cdr range))))

;; A preview can map a screen pick to world space, then ask this retained-data
;; query for an author-facing explanation.  The closest position is evaluated
;; on a declared uniform sample polyline, so its approximation policy is
;; visible in the report rather than disguised as an exact closest point of an
;; arbitrary dense curve.
(define (trajectory-pick-inspection3d trajectory point
                                      #:samples [samples 128]
                                      #:near-event-time [near-event-time #f])
  (unless (prepared-trajectory3d? trajectory)
    (raise-argument-error 'trajectory-pick-inspection3d "prepared-trajectory3d?" trajectory))
  (unless (vec3-finite? point)
    (raise-argument-error 'trajectory-pick-inspection3d "finite vec3?" point))
  (unless (and (exact-integer? samples) (>= samples 2))
    (raise-argument-error 'trajectory-pick-inspection3d "exact integer at least 2 as #:samples" samples))
  (when near-event-time
    (unless (and (finite-real? near-event-time) (>= near-event-time 0))
      (raise-argument-error 'trajectory-pick-inspection3d
                            "#f or nonnegative finite real as #:near-event-time"
                            near-event-time)))
  (define range (ode-trajectory3d-time-range trajectory))
  (define start (car range))
  (define end (cdr range))
  (define time-at
    (lambda (index) (+ start (* (- end start) (/ index (sub1 samples))))))
  (define positions
    (vector->immutable-vector
     (for/vector ([index (in-range samples)])
       (ode-trajectory3d-position trajectory (time-at index)))))
  (define-values (segment-index progress nearest-position distance)
    (for/fold ([best-index 0] [best-progress 0] [best-position (vector-ref positions 0)]
               [best-distance +inf.0])
              ([index (in-range (sub1 samples))])
      (define-values (candidate-progress candidate-position candidate-distance)
        (nearest-on-segment3d point (vector-ref positions index)
                              (vector-ref positions (add1 index))))
      (if (< candidate-distance best-distance)
          (values index candidate-progress candidate-position candidate-distance)
          (values best-index best-progress best-position best-distance))))
  (define time (+ (time-at segment-index)
                  (* progress (- (time-at (add1 segment-index)) (time-at segment-index)))))
  (define nearest-sample-index
    (if (<= progress 1/2) segment-index (add1 segment-index)))
  (define default-event-radius (/ (- end start) (sub1 samples)))
  (define event-radius (or near-event-time default-event-radius))
  (define nearby-event
    (for/fold ([nearest #f]) ([hit (in-vector (ode-trajectory3d-event-hits trajectory))])
      (cond [(> (abs (- (ode-event-hit3d-time hit) time)) event-radius) nearest]
            [(or (not nearest)
                 (< (abs (- (ode-event-hit3d-time hit) time))
                    (abs (- (ode-event-hit3d-time nearest) time)))) hit]
            [else nearest])))
  (hasheq 'kind 'trajectory-pick
          'query-point point
          'sample-count samples
          'nearest-curve-sample
          (hasheq 'index nearest-sample-index
                  'time (time-at nearest-sample-index)
                  'position (vector-ref positions nearest-sample-index))
          'interpolated-time time
          'interpolated-position nearest-position
          'distance distance
          'arc-length-position (ode-trajectory3d-arc-length-at trajectory time)
          'field-derivative (ode-trajectory3d-derivative trajectory time)
          'nearby-event-hit nearby-event))

(define (nearest-on-segment3d point start end)
  (define direction (vec3- end start))
  (define length-squared (vec3-dot direction direction))
  (define progress
    (if (zero? length-squared) 0
        (max 0 (min 1 (/ (vec3-dot (vec3- point start) direction) length-squared)))))
  (define position (vec3+ start (vec3-scale progress direction)))
  (values progress position (vec3-distance point position)))

(define (equilibrium-inspection3d search)
  (unless (equilibrium-search3d? search)
    (raise-argument-error 'equilibrium-inspection3d "equilibrium-search3d?" search))
  (hasheq 'kind 'equilibrium-search
          'seeds (equilibrium-search3d-seeds search)
          'roots (equilibrium-search3d-roots search)
          'seed-results (equilibrium-search3d-seed-results search)
          'diagnostics (equilibrium-search3d-diagnostics search)))

(define (linearization-inspection3d value)
  (unless (linearization3d? value)
    (raise-argument-error 'linearization-inspection3d "linearization3d?" value))
  (hasheq 'kind 'linearization
          'point (linearization3d-point value)
          'jacobian (linearization3d-jacobian value)
          'eigenvalues (linearization3d-eigenvalues value)
          'real-directions (linearization3d-real-directions value)
          'invariant-planes (linearization3d-invariant-planes value)
          'classification (linearization3d-classification value)
          'diagnostics (linearization3d-diagnostics value)))

(define (flow-map-inspection3d map index)
  (unless (prepared-flow-map3d? map)
    (raise-argument-error 'flow-map-inspection3d "prepared-flow-map3d?" map))
  (define endpoint (flow-map3d-ref map index))
  (hasheq 'kind 'flow-map-slot
          'seed-index index
          'source (vector-ref (seed-set3d-points (prepared-flow-map3d-seeds map)) index)
          'endpoint endpoint
          'trajectory (vector-ref (prepared-flow-map3d-trajectories map) index)
          'displacement (flow-map3d-displacement map index)
          'diagnostics (prepared-flow-map3d-diagnostics map)))
