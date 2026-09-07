#lang racket/base

;; Read-only semantic reports for preview/authoring tools.  They operate on
;; prepared values only and never select, transform, or otherwise mutate a
;; Scene or view.

(require "equilibrium3d.rkt" "flow-map3d.rkt" "linearization3d.rkt"
         "ode-flow3d.rkt" "seed-set3d.rkt")

(provide trajectory-inspection3d equilibrium-inspection3d
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
