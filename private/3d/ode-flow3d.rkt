#lang racket/base

;;;
;;; Prepared Three-Dimensional ODE Flow
;;;

;; A spatial ODE trajectory is immutable numerical data. Fixed RK4 and
;; adaptive RK45 both retain dense endpoint/derivative segments for binary
;; lookup, so completed preparation is independent of its author field. Both
;; paths use private/ode-state-space rather than a second hand-written vec3
;; integrator.


;;;
;;; Imports and Exports

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "../group-visual.rkt"
         "../ode-flow.rkt"
         "../ode-state-space.rkt"
         "../parameter.rkt"
         "../scene-state.rkt"
         "../visual-model.rkt"
         "curve3d.rkt"
         "marker3d.rkt"
         "plane-basis3d.rkt"
         "point-line-arrow3d.rkt"
         "ray-plane.rkt"
         "seed-set3d.rkt"
         "spatial-dependency.rkt"
         "spatial-group.rkt"
         "spatial-relation.rkt"
         "spatial-relation-context.rkt"
         "spatial-visual.rkt"
         "stroke3d.rkt"
         "bounds3.rkt"
         "tube-style3d.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide ode-field3d
         ode-field3d?
         ode-field3d-procedure
         ode-field3d-arity
         ode-field3d-cache-key
         ode-field3d-autonomous?
         fixed-rk4-solver3d
         fixed-rk4-solver3d?
         fixed-rk4-solver3d-step-size
         adaptive-rk45-solver3d
         adaptive-rk45-solver3d?
         adaptive-rk45-solver3d-settings
         ode-event3d
         ode-event3d?
         ode-event3d-id
         ode-event3d-function
         ode-event3d-direction
         ode-event3d-terminal?
         ode-event3d-value-tolerance
         ode-event3d-time-tolerance
         ode-event3d-maximum-iterations
         ode-event3d-cache-key
         ode-event-hit3d?
         ode-event-hit3d-event-id
         ode-event-hit3d-time
         ode-event-hit3d-position
         ode-event-hit3d-value
         ode-event-hit3d-direction
         ode-event-hit3d-segment-index
         ode-event-hit3d-iterations
         ode-event-hit3d-provenance
         trajectory-termination3d
         trajectory-termination3d?
         trajectory-termination3d-time-limit
         trajectory-termination3d-arc-length-limit
         trajectory-termination3d-bounds
         trajectory-termination3d-minimum-speed
         trajectory-termination3d-maximum-steps
         trajectory-termination3d-events
         trajectory-termination3d-on-field-error
         trajectory-termination-hit3d?
         trajectory-termination-hit3d-reason
         trajectory-termination-hit3d-time
         trajectory-termination-hit3d-position
         trajectory-termination-hit3d-details
         prepared-trajectory3d?
         trajectory-segment3d?
         trajectory-segment3d-t0
         trajectory-segment3d-t1
         trajectory-segment3d-p0
         trajectory-segment3d-p1
         trajectory-segment3d-d0
         trajectory-segment3d-d1
         trajectory-segment3d-arc-length
         trajectory-segment3d-bounds
         ode-trajectory3d?
         ode-trajectory3d-time-range
         ode-trajectory3d-step-size
         ode-trajectory3d-checkpoint-every
         ode-trajectory3d-solver
         ode-trajectory3d-diagnostics
         ode-trajectory3d-event-hits
         ode-trajectory3d-termination
         ode-trajectory3d-diagnostics?
         ode-trajectory3d-diagnostics-solver
         ode-trajectory3d-diagnostics-accepted-steps
         ode-trajectory3d-diagnostics-rejected-steps
         ode-trajectory3d-diagnostics-termination-time
         ode-trajectory3d-diagnostics-termination-reason
         ode-trajectory3d-diagnostics-maximum-error
         ode-trajectory3d-diagnostics-field-evaluations
         ode-trajectory3d-diagnostics-dense-segment-count
         ode-trajectory3d-diagnostics-total-arc-length
         ode-trajectory3d-diagnostics-event-count
         ode-trajectory3d-diagnostics-warnings
         prepare-ode-trajectory3d
         ode-trajectory3d-position
         ode-trajectory3d-derivative
         ode-trajectory3d-speed
         ode-trajectory3d-arc-length-at
         ode-trajectory3d-time-at-arc-length
         ode-trajectory3d-segment-index
         streamline-sample-policy3d
         streamline-sample-policy3d?
         streamline-sample-policy3d-maximum-chord-error
         streamline-sample-policy3d-maximum-turn-angle
         streamline-sample-policy3d-maximum-segment-length
         streamline-sample-policy3d-minimum-segment-length
         prepared-streamline3d?
         prepared-streamline3d-seed
         prepared-streamline3d-direction
         prepared-streamline3d-parameterization
         prepared-streamline3d-trajectory
         prepared-streamline3d-curve-samples
         prepared-streamline3d-diagnostics
         prepared-streamline3d-seed-index
         streamline-diagnostics3d?
         streamline-diagnostics3d-forward
         streamline-diagnostics3d-backward
         streamline-diagnostics3d-field-evaluations
         streamline-diagnostics3d-curve-sample-count
         streamline-diagnostics3d-total-arc-length
         streamline-diagnostics3d-termination-reasons
         streamline-branch-diagnostics3d?
         streamline-branch-diagnostics3d-direction
         streamline-branch-diagnostics3d-time-range
         streamline-branch-diagnostics3d-segment-count
         streamline-branch-diagnostics3d-termination
         prepare-streamline3d
         adaptive-streamline3d
         seed-set3d?
         seed-set3d-kind
         seed-set3d-points
         seed-set3d-count
         seed-set3d-provenance
         seed-set3d-diagnostics
         seed-set3d-cache-key
         explicit-seeds3d
         grid-seeds3d
         plane-seeds3d
         curve-seeds3d
         surface-seeds3d
         sphere-seeds3d
         poisson-seeds3d
         prepared-streamline-set3d?
         prepared-streamline-set3d-seeds
         prepared-streamline-set3d-streamlines
         prepared-streamline-set3d-diagnostics
         prepared-streamline-set3d-spatial-index
         streamline-set-diagnostics3d?
         streamline-set-diagnostics3d-seed-count
         streamline-set-diagnostics3d-accepted-seed-count
         streamline-set-diagnostics3d-rejected-seed-count
         streamline-set-diagnostics3d-termination-reasons
         streamline-set-diagnostics3d-field-evaluations
         streamline-set-diagnostics3d-total-curve-samples
         streamline-set-diagnostics3d-minimum-separation
         streamline-set-diagnostics3d-discarded-short-lines
         streamline-set-diagnostics3d-parallel-mode
         prepare-streamlines3d
         adaptive-streamline-set3d
         poincare-hit3d?
         poincare-hit3d-trajectory-id
         poincare-hit3d-crossing-index
         poincare-hit3d-time
         poincare-hit3d-point
         poincare-hit3d-direction
         poincare-hit3d-source-event
         poincare-section3d
         poincare-hit3d-plane-coordinates
         poincare-hits3d
         prepared-poincare-map3d?
         prepared-poincare-map3d-plane
         prepared-poincare-map3d-seeds
         prepared-poincare-map3d-trajectories
         prepared-poincare-map3d-first-hits
         prepared-poincare-map3d-second-hits
         prepared-poincare-map3d-pairs
         prepared-poincare-map3d-diagnostics
         prepare-poincare-map3d
         vector-field3d
         streamline3d
         streamlines3d
         flow-particle3d
         flow-cloud3d
         prepare-ode3d-frame-samples
         call-with-ode3d-frame-samples
         ode3d-frame-samples-active?)


;;;
;;; Immutable Prepared Trajectories

(struct fixed-ode-trajectory3d
  (field seed start-time end-time step-size checkpoint-every
         forward-checkpoints backward-checkpoints)
  #:transparent)

(struct adaptive-ode-node3d (time position derivative) #:transparent)

(struct ode-trajectory3d-diagnostics-value
  (solver accepted-steps rejected-steps termination-time maximum-error)
  #:transparent)

(struct adaptive-ode-trajectory3d
  (field seed start-time end-time solver nodes diagnostics)
  #:transparent)

;; T-0's public input values distinguish opaque author behaviour from the
;; numerical trajectory that preparation returns.  Only the former retains a
;; procedure; `prepared-trajectory3d-value` below never does.
(struct ode-field3d-value (procedure arity cache-key autonomous?) #:transparent)

(define (ode-field3d procedure #:cache-key [cache-key #f] #:autonomous? [autonomous? #t])
  (check-field3d 'ode-field3d procedure)
  (unless (boolean? autonomous?)
    (raise-argument-error 'ode-field3d "boolean? as #:autonomous?" autonomous?))
  (ode-field3d-value procedure
                     (if (procedure-arity-includes? procedure 4) 4 3)
                     cache-key autonomous?))

(define (ode-field3d? value) (ode-field3d-value? value))
(define (check-ode-field3d who value)
  (unless (ode-field3d? value)
    (raise-argument-error who "ode-field3d?" value)))
(define (ode-field3d-procedure value)
  (check-ode-field3d 'ode-field3d-procedure value)
  (ode-field3d-value-procedure value))
(define (ode-field3d-arity value)
  (check-ode-field3d 'ode-field3d-arity value)
  (ode-field3d-value-arity value))
(define (ode-field3d-cache-key value)
  (check-ode-field3d 'ode-field3d-cache-key value)
  (ode-field3d-value-cache-key value))
(define (ode-field3d-autonomous? value)
  (check-ode-field3d 'ode-field3d-autonomous? value)
  (ode-field3d-value-autonomous? value))

(struct fixed-rk4-solver3d-value (step-size) #:transparent)
(define (fixed-rk4-solver3d #:step-size [step-size 1/20])
  (check-positive 'fixed-rk4-solver3d "step-size" step-size)
  (fixed-rk4-solver3d-value step-size))
(define (fixed-rk4-solver3d? value) (fixed-rk4-solver3d-value? value))
(define (fixed-rk4-solver3d-step-size value)
  (unless (fixed-rk4-solver3d? value)
    (raise-argument-error 'fixed-rk4-solver3d-step-size "fixed-rk4-solver3d?" value))
  (fixed-rk4-solver3d-value-step-size value))

(struct adaptive-rk45-solver3d-value (settings) #:transparent)
(define (adaptive-rk45-solver3d #:relative-tolerance [relative-tolerance 1e-6]
                                #:absolute-tolerance [absolute-tolerance 1e-9]
                                #:initial-step [initial-step 1/20]
                                #:minimum-step [minimum-step 1e-9]
                                #:maximum-step [maximum-step 1]
                                #:maximum-steps [maximum-steps 100000])
  (adaptive-rk45-solver3d-value
   (adaptive-rk45 #:relative-tolerance relative-tolerance
                  #:absolute-tolerance absolute-tolerance
                  #:initial-step initial-step
                  #:minimum-step minimum-step
                  #:maximum-step maximum-step
                  #:maximum-steps maximum-steps)))
(define (adaptive-rk45-solver3d? value) (adaptive-rk45-solver3d-value? value))
(define (adaptive-rk45-solver3d-settings value)
  (unless (adaptive-rk45-solver3d? value)
    (raise-argument-error 'adaptive-rk45-solver3d-settings "adaptive-rk45-solver3d?" value))
  (adaptive-rk45-solver3d-value-settings value))

;; Event descriptors remain author-side values: their procedures run only while
;; a trajectory is prepared.  A completed trajectory retains immutable hit
;; records, never the event procedures themselves.
(struct ode-event3d-value
  (id function arity direction terminal? value-tolerance time-tolerance
      maximum-iterations cache-key)
  #:transparent)

(define (ode-event3d #:id id
                     #:function function
                     #:direction [direction 'any]
                     #:terminal? [terminal? #t]
                     #:value-tolerance [value-tolerance 1e-9]
                     #:time-tolerance [time-tolerance 1e-9]
                     #:maximum-iterations [maximum-iterations 64]
                     #:cache-key [cache-key #f])
  (check-symbol 'ode-event3d id)
  (unless (and (procedure? function)
               (or (procedure-arity-includes? function 1)
                   (procedure-arity-includes? function 2)))
    (raise-argument-error
     'ode-event3d "procedure accepting (point) or (time point) as #:function" function))
  (unless (memq direction '(any increasing decreasing))
    (raise-argument-error 'ode-event3d "'any, 'increasing, or 'decreasing as #:direction"
                          direction))
  (unless (boolean? terminal?)
    (raise-argument-error 'ode-event3d "boolean? as #:terminal?" terminal?))
  (check-positive 'ode-event3d "value-tolerance" value-tolerance)
  (check-positive 'ode-event3d "time-tolerance" time-tolerance)
  (check-positive-integer 'ode-event3d "maximum-iterations" maximum-iterations)
  (ode-event3d-value id function
                      (if (procedure-arity-includes? function 2) 2 1)
                      direction terminal? value-tolerance time-tolerance
                      maximum-iterations cache-key))

(define (ode-event3d? value) (ode-event3d-value? value))
(define (check-ode-event3d who value)
  (unless (ode-event3d? value) (raise-argument-error who "ode-event3d?" value)))
(define (ode-event3d-id value)
  (check-ode-event3d 'ode-event3d-id value) (ode-event3d-value-id value))
(define (ode-event3d-function value)
  (check-ode-event3d 'ode-event3d-function value) (ode-event3d-value-function value))
(define (ode-event3d-direction value)
  (check-ode-event3d 'ode-event3d-direction value) (ode-event3d-value-direction value))
(define (ode-event3d-terminal? value)
  (check-ode-event3d 'ode-event3d-terminal? value) (ode-event3d-value-terminal? value))
(define (ode-event3d-value-tolerance value)
  (check-ode-event3d 'ode-event3d-value-tolerance value)
  (ode-event3d-value-value-tolerance value))
(define (ode-event3d-time-tolerance value)
  (check-ode-event3d 'ode-event3d-time-tolerance value)
  (ode-event3d-value-time-tolerance value))
(define (ode-event3d-maximum-iterations value)
  (check-ode-event3d 'ode-event3d-maximum-iterations value)
  (ode-event3d-value-maximum-iterations value))
(define (ode-event3d-cache-key value)
  (check-ode-event3d 'ode-event3d-cache-key value) (ode-event3d-value-cache-key value))

(struct ode-event-hit3d
  (event-id time position value direction segment-index iterations provenance)
  #:transparent)

;; A termination policy is an immutable plan, separate from both the author
;; field and the prepared result.  Time and arc limits apply independently on
;; either side of the seed time when a requested range straddles zero.
(struct trajectory-termination3d-value
  (time-limit arc-length-limit bounds minimum-speed maximum-steps events on-field-error)
  #:transparent)

(define (trajectory-termination3d #:time-limit [time-limit #f]
                                  #:arc-length-limit [arc-length-limit #f]
                                  #:bounds [bounds #f]
                                  #:minimum-speed [minimum-speed #f]
                                  #:maximum-steps [maximum-steps 100000]
                                  #:events [events '()]
                                  #:on-field-error [on-field-error 'error])
  (check-optional-nonnegative 'trajectory-termination3d "time-limit" time-limit)
  (check-optional-nonnegative 'trajectory-termination3d "arc-length-limit" arc-length-limit)
  (when bounds
    (unless (and (aabb3? bounds) (not (aabb3-empty? bounds)))
      (raise-argument-error 'trajectory-termination3d "nonempty aabb3? or #f as #:bounds"
                            bounds)))
  (check-optional-nonnegative 'trajectory-termination3d "minimum-speed" minimum-speed)
  (check-positive-integer 'trajectory-termination3d "maximum-steps" maximum-steps)
  (check-ode-events3d 'trajectory-termination3d events)
  (unless (memq on-field-error '(error terminate))
    (raise-argument-error 'trajectory-termination3d "'error or 'terminate as #:on-field-error"
                          on-field-error))
  (trajectory-termination3d-value time-limit arc-length-limit bounds minimum-speed
                                  maximum-steps events on-field-error))

(define (trajectory-termination3d? value) (trajectory-termination3d-value? value))
(define (check-trajectory-termination3d who value)
  (unless (trajectory-termination3d? value)
    (raise-argument-error who "trajectory-termination3d?" value)))
(define (trajectory-termination3d-time-limit value)
  (check-trajectory-termination3d 'trajectory-termination3d-time-limit value)
  (trajectory-termination3d-value-time-limit value))
(define (trajectory-termination3d-arc-length-limit value)
  (check-trajectory-termination3d 'trajectory-termination3d-arc-length-limit value)
  (trajectory-termination3d-value-arc-length-limit value))
(define (trajectory-termination3d-bounds value)
  (check-trajectory-termination3d 'trajectory-termination3d-bounds value)
  (trajectory-termination3d-value-bounds value))
(define (trajectory-termination3d-minimum-speed value)
  (check-trajectory-termination3d 'trajectory-termination3d-minimum-speed value)
  (trajectory-termination3d-value-minimum-speed value))
(define (trajectory-termination3d-maximum-steps value)
  (check-trajectory-termination3d 'trajectory-termination3d-maximum-steps value)
  (trajectory-termination3d-value-maximum-steps value))
(define (trajectory-termination3d-events value)
  (check-trajectory-termination3d 'trajectory-termination3d-events value)
  (trajectory-termination3d-value-events value))
(define (trajectory-termination3d-on-field-error value)
  (check-trajectory-termination3d 'trajectory-termination3d-on-field-error value)
  (trajectory-termination3d-value-on-field-error value))

(struct trajectory-termination-hit3d (reason time position details) #:transparent)

(struct prepared-trajectory-node3d (time position derivative) #:transparent)
(struct trajectory-segment3d (t0 t1 p0 p1 d0 d1 arc-length bounds) #:transparent)
(struct prepared-trajectory3d-value
  (time-range solver nodes segments event-hits termination cumulative-arcs diagnostics source-key checkpoint-every)
  #:transparent)
(struct dense-trajectory-diagnostics3d
  (solver field-evaluations accepted-steps rejected-steps termination-time
          termination-reason maximum-error dense-segment-count total-arc-length
          event-count warnings)
  #:transparent)

(define (ode-trajectory3d? value)
  (or (prepared-trajectory3d-value? value)
      (fixed-ode-trajectory3d? value)
      (adaptive-ode-trajectory3d? value)))

(define (prepared-trajectory3d? value)
  (prepared-trajectory3d-value? value))

(define (ode-trajectory3d-time-range trajectory)
  (check-trajectory3d 'ode-trajectory3d-time-range trajectory)
  (cond [(prepared-trajectory3d? trajectory)
         (prepared-trajectory3d-value-time-range trajectory)]
        [(adaptive-ode-trajectory3d? trajectory)
         (cons (adaptive-ode-trajectory3d-start-time trajectory)
               (adaptive-ode-trajectory3d-end-time trajectory))]
        [else
         (cons (fixed-ode-trajectory3d-start-time trajectory)
               (fixed-ode-trajectory3d-end-time trajectory))]))

(define (ode-trajectory3d-step-size trajectory)
  (check-trajectory3d 'ode-trajectory3d-step-size trajectory)
  (cond [(prepared-trajectory3d? trajectory)
         (define solver (prepared-trajectory3d-value-solver trajectory))
         (and (fixed-rk4-solver3d? solver) (fixed-rk4-solver3d-step-size solver))]
        [(fixed-ode-trajectory3d? trajectory)
         (fixed-ode-trajectory3d-step-size trajectory)]
        [else #f]))

(define (ode-trajectory3d-checkpoint-every trajectory)
  (check-trajectory3d 'ode-trajectory3d-checkpoint-every trajectory)
  (cond [(prepared-trajectory3d? trajectory)
         (prepared-trajectory3d-value-checkpoint-every trajectory)]
        [(fixed-ode-trajectory3d? trajectory)
         (fixed-ode-trajectory3d-checkpoint-every trajectory)]
        [else #f]))

(define (ode-trajectory3d-solver trajectory)
  (check-trajectory3d 'ode-trajectory3d-solver trajectory)
  (cond [(prepared-trajectory3d? trajectory)
         (prepared-trajectory3d-value-solver trajectory)]
        [(adaptive-ode-trajectory3d? trajectory)
         (adaptive-ode-trajectory3d-solver trajectory)]
        [else 'fixed-rk4]))

(define (ode-trajectory3d-diagnostics trajectory)
  (check-trajectory3d 'ode-trajectory3d-diagnostics trajectory)
  (cond [(prepared-trajectory3d? trajectory)
         (prepared-trajectory3d-value-diagnostics trajectory)]
        [(adaptive-ode-trajectory3d? trajectory)
         (adaptive-ode-trajectory3d-diagnostics trajectory)]
        [else #f]))

(define (ode-trajectory3d-event-hits trajectory)
  (check-trajectory3d 'ode-trajectory3d-event-hits trajectory)
  (if (prepared-trajectory3d? trajectory)
      (prepared-trajectory3d-value-event-hits trajectory)
      (vector)))

(define (ode-trajectory3d-termination trajectory)
  (check-trajectory3d 'ode-trajectory3d-termination trajectory)
  (if (prepared-trajectory3d? trajectory)
      (prepared-trajectory3d-value-termination trajectory)
      (vector)))

(define (ode-trajectory3d-diagnostics? value)
  (or (ode-trajectory3d-diagnostics-value? value)
      (dense-trajectory-diagnostics3d? value)))
(define (ode-trajectory3d-diagnostics-solver value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-solver value)
      (ode-trajectory3d-diagnostics-value-solver value)))
(define (ode-trajectory3d-diagnostics-accepted-steps value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-accepted-steps value)
      (ode-trajectory3d-diagnostics-value-accepted-steps value)))
(define (ode-trajectory3d-diagnostics-rejected-steps value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-rejected-steps value)
      (ode-trajectory3d-diagnostics-value-rejected-steps value)))
(define (ode-trajectory3d-diagnostics-termination-time value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-termination-time value)
      (ode-trajectory3d-diagnostics-value-termination-time value)))
(define ode-trajectory3d-diagnostics-maximum-error
  (lambda (value)
    (if (dense-trajectory-diagnostics3d? value)
        (dense-trajectory-diagnostics3d-maximum-error value)
        (ode-trajectory3d-diagnostics-value-maximum-error value))))

(define (ode-trajectory3d-diagnostics-termination-reason value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-termination-reason value)
      'time-range))
(define (ode-trajectory3d-diagnostics-field-evaluations value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-field-evaluations value)
      #f))
(define (ode-trajectory3d-diagnostics-dense-segment-count value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-dense-segment-count value)
      #f))
(define (ode-trajectory3d-diagnostics-total-arc-length value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-total-arc-length value)
      #f))
(define (ode-trajectory3d-diagnostics-event-count value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-event-count value)
      #f))
(define (ode-trajectory3d-diagnostics-warnings value)
  (if (dense-trajectory-diagnostics3d? value)
      (dense-trajectory-diagnostics3d-warnings value)
      '()))

; prepare-ode-trajectory3d : procedure? vec3?
;                            #:time-range (cons/c finite-real? finite-real?)
;                            [#:step-size positive-finite-real?]
;                            [#:checkpoint-every positive-exact-integer?]
;                            [#:solver (or/c #f adaptive-rk45?)]
;                            [#:events (listof ode-event3d?)]
;                            [#:termination (or/c #f trajectory-termination3d?)]
;                            -> ode-trajectory3d?
;; Fields accept either (x y z) or (time x y z).  Preparation is the only
;; operation that creates a trajectory; all returned values are immutable and
;; safe to look up in arbitrary order.
(define (prepare-ode-trajectory3d field seed
                                  #:time-range time-range
                                  #:step-size [step-size 1/20]
                                  #:checkpoint-every [checkpoint-every 16]
                                  #:solver [solver #f]
                                  #:events [events '()]
                                  #:termination [termination #f])
  (define normalized-field (normalize-ode-field3d 'prepare-ode-trajectory3d field))
  (check-vec3 'prepare-ode-trajectory3d seed)
  (check-positive 'prepare-ode-trajectory3d "step-size" step-size)
  (check-checkpoint-every 'prepare-ode-trajectory3d checkpoint-every)
  (define normalized-termination
    (cond [(not termination) (trajectory-termination3d)]
          [(trajectory-termination3d? termination) termination]
          [else (raise-argument-error 'prepare-ode-trajectory3d
                                      "#f or trajectory-termination3d? as #:termination"
                                      termination)]))
  (define all-events (append events (trajectory-termination3d-events normalized-termination)))
  (check-ode-events3d 'prepare-ode-trajectory3d all-events)
  (define-values (start-time end-time)
    (check-time-range 'prepare-ode-trajectory3d time-range))
  (define-values (limited-start limited-end start-time-limited? end-time-limited?)
    (termination-time-range3d start-time end-time normalized-termination))
  (prepare-dense-trajectory3d normalized-field seed limited-start limited-end
                              (normalize-solver3d 'prepare-ode-trajectory3d solver step-size)
                              checkpoint-every all-events normalized-termination
                              (cons start-time-limited? end-time-limited?)))

; ode-trajectory3d-position : ode-trajectory3d? finite-real? -> vec3?
;; Every created trajectory resolves this through stored Hermite segments and
;; never invokes the author field.
(define (ode-trajectory3d-position trajectory time)
  (check-trajectory3d 'ode-trajectory3d-position trajectory)
  (check-trajectory3d-time 'ode-trajectory3d-position trajectory time)
  (cond [(prepared-trajectory3d? trajectory)
         (dense-trajectory-position3d trajectory time)]
        [(adaptive-ode-trajectory3d? trajectory)
         (adaptive-trajectory3d-position trajectory time)]
        [else (fixed-trajectory3d-position trajectory time)]))

(define (fixed-trajectory3d-position trajectory time)
  (define-values (direction full-step checkpoint-index suffix-steps remainder)
    (trajectory3d-query-parts trajectory time))
  (define checkpoints
    (if (negative? direction)
        (fixed-ode-trajectory3d-backward-checkpoints trajectory)
        (fixed-ode-trajectory3d-forward-checkpoints trajectory)))
  (define checkpoint (vector-ref checkpoints checkpoint-index))
  (define checkpoint-time
    (* direction checkpoint-index (fixed-ode-trajectory3d-checkpoint-every trajectory)
       (fixed-ode-trajectory3d-step-size trajectory)))
  (define-values (state current-time)
    (for/fold ([point checkpoint] [point-time checkpoint-time])
              ([ignored (in-range suffix-steps)])
      (values (rk4-step3d (fixed-ode-trajectory3d-field trajectory)
                          point-time point full-step)
              (+ point-time full-step))))
  (if (zero? remainder)
      state
      (rk4-step3d (fixed-ode-trajectory3d-field trajectory)
                  current-time state remainder)))

(define (trajectory3d-query-parts trajectory time)
  (define step-size (fixed-ode-trajectory3d-step-size trajectory))
  (define checkpoint-every (fixed-ode-trajectory3d-checkpoint-every trajectory))
  (define direction (if (negative? time) -1 1))
  (define full-step (* direction step-size))
  (define whole-count (whole-step-count time step-size))
  (define checkpoint-index (quotient whole-count checkpoint-every))
  (define checkpoint-step-count (* checkpoint-index checkpoint-every))
  (values direction full-step checkpoint-index
          (- whole-count checkpoint-step-count)
          (- time (* whole-count full-step))))

(define (build-checkpoints3d field seed direction step-size checkpoint-every extent)
  (define full-count (whole-step-count extent step-size))
  (define checkpoint-count (add1 (quotient full-count checkpoint-every)))
  (define full-step (* direction step-size))
  (define (advance point start-time count)
    (for/fold ([state point] [current-time start-time]) ([ignored (in-range count)])
      (values (rk4-step3d field current-time state full-step)
              (+ current-time full-step))))
  (vector->immutable-vector
   (list->vector
    (let loop ([checkpoint-index 0] [state seed] [reversed '()])
      (if (= checkpoint-index checkpoint-count)
          (reverse reversed)
          (let-values ([(next-state ignored-time)
                        (if (= checkpoint-index (sub1 checkpoint-count))
                            (values state (* direction checkpoint-index
                                             checkpoint-every step-size))
                            (advance state
                                     (* direction checkpoint-index
                                        checkpoint-every step-size)
                                     checkpoint-every))])
            (loop (add1 checkpoint-index) next-state (cons state reversed))))))))


;;;
;;; Adaptive RK45

(define (prepare-adaptive-trajectory3d field seed start-time end-time solver)
  (define-values (backward-nodes backward-diagnostics)
    (adaptive-node-series3d field seed 0 start-time solver))
  (define-values (forward-nodes forward-diagnostics)
    (adaptive-node-series3d field seed 0 end-time solver))
  (define nodes (append (reverse (cdr backward-nodes)) forward-nodes))
  (define start (adaptive-ode-node3d-time (car nodes)))
  (define end (adaptive-ode-node3d-time (last nodes)))
  (adaptive-ode-trajectory3d
   field seed start end solver (vector->immutable-vector (list->vector nodes))
   (ode-trajectory3d-diagnostics-value
    'adaptive-rk45
    (+ (ode-trajectory3d-diagnostics-value-accepted-steps backward-diagnostics)
       (ode-trajectory3d-diagnostics-value-accepted-steps forward-diagnostics))
    (+ (ode-trajectory3d-diagnostics-value-rejected-steps backward-diagnostics)
       (ode-trajectory3d-diagnostics-value-rejected-steps forward-diagnostics))
    end
    (max (ode-trajectory3d-diagnostics-value-maximum-error backward-diagnostics)
         (ode-trajectory3d-diagnostics-value-maximum-error forward-diagnostics)))))

(define (adaptive-node-series3d field seed start-time target-time solver)
  (define direction (if (negative? (- target-time start-time)) -1 1))
  (define initial-node
    (adaptive-ode-node3d start-time seed (call-field3d field start-time seed)))
  (cond
    [(= start-time target-time)
     (values (list initial-node)
             (ode-trajectory3d-diagnostics-value 'adaptive-rk45 0 0 start-time 0))]
    [else
     (let loop ([current initial-node]
                [step (* direction (adaptive-rk45-initial-step solver))]
                [reverse-nodes (list initial-node)]
                [accepted 0] [rejected 0] [maximum-error 0])
       (when (>= (+ accepted rejected) (adaptive-rk45-maximum-steps solver))
         (raise-arguments-error
          'prepare-ode-trajectory3d "adaptive solver exceeded maximum-steps"
          "maximum-steps" (adaptive-rk45-maximum-steps solver)
          "last-time" (adaptive-ode-node3d-time current)
          "target-time" target-time))
       (define remaining (- target-time (adaptive-ode-node3d-time current)))
       (define trial-step
         (* direction
            (min (abs remaining) (adaptive-rk45-maximum-step solver)
                 (max (adaptive-rk45-minimum-step solver) (abs step)))))
       (define-values (candidate endpoint-derivative error)
         (ode-state-space-dormand-prince-step
          vec3-ode-state-space
          (lambda (field-time field-point) (call-field3d field field-time field-point))
          (adaptive-ode-node3d-time current)
          (adaptive-ode-node3d-position current)
          trial-step
          (adaptive-rk45-relative-tolerance solver)
          (adaptive-rk45-absolute-tolerance solver)))
       (define next-maximum-error (max maximum-error error))
       (cond
         [(<= error 1)
          (define candidate-node
            (adaptive-ode-node3d (+ (adaptive-ode-node3d-time current) trial-step)
                                 candidate endpoint-derivative))
          (if (= (adaptive-ode-node3d-time candidate-node) target-time)
              (values (reverse (cons candidate-node reverse-nodes))
                      (ode-trajectory3d-diagnostics-value
                       'adaptive-rk45 (add1 accepted) rejected target-time next-maximum-error))
              (loop candidate-node
                    (* direction
                       (adaptive-next-step-magnitude3d solver (abs trial-step) error))
                    (cons candidate-node reverse-nodes)
                    (add1 accepted) rejected next-maximum-error))]
         [else
          (when (<= (abs trial-step) (adaptive-rk45-minimum-step solver))
            (raise-arguments-error
             'prepare-ode-trajectory3d
             "adaptive solver reached minimum-step before satisfying tolerance"
             "minimum-step" (adaptive-rk45-minimum-step solver)
             "error-ratio" error
             "time" (adaptive-ode-node3d-time current)))
          (loop current
                (* direction
                   (adaptive-rejected-step-magnitude3d solver (abs trial-step) error))
                reverse-nodes accepted (add1 rejected) next-maximum-error)]))]))

(define (adaptive-next-step-magnitude3d solver old-step error)
  (min (adaptive-rk45-maximum-step solver)
       (max (adaptive-rk45-minimum-step solver)
            (* old-step
               (min 5 (max 1/5
                           (* 9/10 (if (zero? error) 5
                                      (expt (/ 1 error) 1/5)))))))))

(define (adaptive-rejected-step-magnitude3d solver old-step error)
  (max (adaptive-rk45-minimum-step solver)
       (* old-step (min 1 (max 1/10 (* 9/10 (expt (/ 1 error) 1/5)))))))

(define (adaptive-trajectory3d-position trajectory time)
  (define nodes (adaptive-ode-trajectory3d-nodes trajectory))
  (define count (vector-length nodes))
  (let loop ([index 0])
    (define current (vector-ref nodes index))
    (cond
      [(= time (adaptive-ode-node3d-time current))
       (adaptive-ode-node3d-position current)]
      [(= index (sub1 count)) (adaptive-ode-node3d-position current)]
      [else
       (define next (vector-ref nodes (add1 index)))
       (if (<= (adaptive-ode-node3d-time current) time (adaptive-ode-node3d-time next))
           (interpolate-adaptive-nodes3d current next time)
           (loop (add1 index)))])))

(define (interpolate-adaptive-nodes3d first second time)
  (define start-time (adaptive-ode-node3d-time first))
  (define step (- (adaptive-ode-node3d-time second) start-time))
  (if (zero? step)
      (adaptive-ode-node3d-position first)
      (ode-state-space-hermite-interpolate
       vec3-ode-state-space
       (adaptive-ode-node3d-position first)
       (adaptive-ode-node3d-derivative first)
       (adaptive-ode-node3d-position second)
       (adaptive-ode-node3d-derivative second)
       step (/ (- time start-time) step))))


;;;
;;; T-0 Dense Prepared Representation

;; These helpers are intentionally separate from the legacy internal structs
;; above while the public API transitions.  `prepare-ode-trajectory3d` now
;; always creates this representation; the older structs are no longer made.

(struct dense-series-report3d
  (accepted rejected maximum-error steps stop-reason stop-node stop-details)
  #:transparent)

(struct exn:fail:ode-field3d exn:fail:contract (time point) #:transparent)

(define (normalize-ode-field3d who value)
  (cond [(ode-field3d? value) value]
        [(procedure? value) (ode-field3d value)]
        [else (raise-argument-error who "procedure? or ode-field3d?" value)]))

(define (normalize-solver3d who value step-size)
  (cond [(not value) (fixed-rk4-solver3d #:step-size step-size)]
        [(fixed-rk4-solver3d? value) value]
        [(adaptive-rk45-solver3d? value) value]
        [(adaptive-rk45? value) (adaptive-rk45-solver3d-value value)]
        [else (raise-argument-error
               who "#f, fixed-rk4-solver3d?, adaptive-rk45-solver3d?, or adaptive-rk45?" value)]))

(define (prepare-dense-trajectory3d field seed start-time end-time solver checkpoint-every
                                    events termination time-limited?)
  (define evaluations (box 0))
  (define lower-target (min 0 start-time))
  (define upper-target (max 0 end-time))
  (define-values (backward backward-report)
    (dense-integrate-series3d field seed 0 lower-target solver evaluations termination))
  (define-values (forward forward-report)
    (dense-integrate-series3d field seed 0 upper-target solver evaluations termination))
  (define all-nodes (append (reverse (cdr backward)) forward))
  (define available-start (prepared-trajectory-node3d-time (car all-nodes)))
  (define available-end (prepared-trajectory-node3d-time (last all-nodes)))
  ;; A max-step or field-error policy may leave only a proper prefix of a
  ;; requested branch.  Clamp the requested data range to actual numerical
  ;; data before any dense lookup is attempted.
  (define unclamped-start (max start-time available-start))
  (define unclamped-end (min end-time available-end))
  (define-values (reachable-start reachable-end)
    (if (<= unclamped-start unclamped-end)
        (values unclamped-start unclamped-end)
        (let ([endpoint (if (positive? start-time) available-end available-start)])
          (values endpoint endpoint))))
  ;; Locate roots from the common dense representation.  The event procedure
  ;; is invoked only during preparation, while the field is never invoked for
  ;; root finding or later lookup.
  (define requested-nodes (dense-clip-nodes3d all-nodes reachable-start reachable-end))
  (define requested-segments (dense-make-segments3d requested-nodes))
  (define requested-hits
    (dense-event-hits3d events requested-nodes requested-segments))
  (define-values (actual-start actual-end termination-hits)
    (dense-resolve-termination3d
     reachable-start reachable-end requested-nodes requested-segments requested-hits
     events termination time-limited?
     (dense-series-termination-candidates3d backward-report forward-report)))
  ;; A terminal root is made an actual endpoint node, rather than merely a
  ;; sampled hit inside another segment.  That keeps subsequent lookup and
  ;; arc-length data canonical and frame-order independent.
  (define nodes (dense-clip-nodes3d all-nodes actual-start actual-end))
  (define segments (dense-make-segments3d nodes))
  (define event-hits
    (dense-reindex-event-hits3d
     (filter (lambda (hit)
               (<= actual-start (ode-event-hit3d-time hit) actual-end))
             requested-hits)
     segments))
  (define cumulative (dense-cumulative-arcs3d segments))
  (define total (vector-ref cumulative (sub1 (vector-length cumulative))))
  (define accepted (+ (dense-series-report3d-accepted backward-report)
                      (dense-series-report3d-accepted forward-report)))
  (define rejected (+ (dense-series-report3d-rejected backward-report)
                      (dense-series-report3d-rejected forward-report)))
  (prepared-trajectory3d-value
   (cons actual-start actual-end) solver nodes segments event-hits termination-hits cumulative
   (dense-trajectory-diagnostics3d
    solver (unbox evaluations) accepted rejected
    (if (positive? (vector-length termination-hits))
        (trajectory-termination-hit3d-time (vector-ref termination-hits 0))
        actual-end)
    (if (positive? (vector-length termination-hits))
        (trajectory-termination-hit3d-reason (vector-ref termination-hits 0))
        'time-range)
    (max (dense-series-report3d-maximum-error backward-report)
         (dense-series-report3d-maximum-error forward-report))
    (vector-length segments) total (vector-length event-hits)
    (dense-event-warnings3d event-hits))
   (ode-field3d-cache-key field) checkpoint-every))

(define (dense-initial-report3d reason node details)
  (dense-series-report3d 0 0 0 '() reason node details))

(define (dense-integrate-series3d field seed start-time target-time solver evaluations termination)
  (let/ec return
    (define initial
      (with-handlers
          ([exn:fail:ode-field3d?
            (lambda (exception)
              (if (eq? (trajectory-termination3d-on-field-error termination) 'terminate)
                  (return
                   (values (list (prepared-trajectory-node3d start-time seed origin3))
                           (dense-initial-report3d
                            'field-error
                            (prepared-trajectory-node3d start-time seed origin3)
                            (list 'field-error (exn-message exception)))))
                  (raise exception)))])
        (prepared-trajectory-node3d start-time seed
                                    (call-field3d field start-time seed evaluations))))
    (cond [(= start-time target-time)
           (values (list initial) (dense-initial-report3d 'time-range #f #f))]
          [(fixed-rk4-solver3d? solver)
           (dense-fixed-series3d field initial target-time
                                 (fixed-rk4-solver3d-step-size solver) evaluations termination)]
          [else
           (dense-adaptive-series3d field initial target-time
                                    (adaptive-rk45-solver3d-settings solver)
                                    evaluations termination)])))

(define (dense-fixed-series3d field initial target-time step-size evaluations termination)
  (define direction (if (< target-time (prepared-trajectory-node3d-time initial)) -1 1))
  (let loop ([current initial] [reversed (list initial)] [steps '()])
    (define remaining (- target-time (prepared-trajectory-node3d-time current)))
    (cond
      [(zero? remaining)
       (values (reverse reversed)
               (dense-series-report3d (length steps) 0 0 (reverse steps)
                                      'time-range #f #f))]
      [(>= (length steps) (trajectory-termination3d-maximum-steps termination))
       (values (reverse reversed)
               (dense-series-report3d
                (length steps) 0 0 (reverse steps) 'maximum-steps current
                (list 'maximum-steps (trajectory-termination3d-maximum-steps termination))))]
      [else
       (with-handlers
           ([exn:fail:ode-field3d?
             (lambda (exception)
               (if (eq? (trajectory-termination3d-on-field-error termination) 'terminate)
                   (values (reverse reversed)
                           (dense-series-report3d
                            (length steps) 0 0 (reverse steps) 'field-error current
                            (list 'field-error (exn-message exception))))
                   (raise exception)))])
         (define step (* direction (min step-size (abs remaining))))
         (define next-time (+ (prepared-trajectory-node3d-time current) step))
         (define next-position
           (dense-rk4-step3d field
                              (prepared-trajectory-node3d-time current)
                              (prepared-trajectory-node3d-position current)
                              step evaluations))
         (define next
           (prepared-trajectory-node3d
            next-time next-position
            (call-field3d field next-time next-position evaluations)))
         (loop next (cons next reversed) (cons (abs step) steps)))])))

(define (dense-adaptive-series3d field initial target-time solver evaluations termination)
  (define direction (if (< target-time (prepared-trajectory-node3d-time initial)) -1 1))
  (let loop ([current initial]
             [step (* direction (adaptive-rk45-initial-step solver))]
             [reversed (list initial)] [accepted 0] [rejected 0]
             [maximum-error 0] [steps '()])
    (define maximum-steps
      (min (adaptive-rk45-maximum-steps solver)
           (trajectory-termination3d-maximum-steps termination)))
    (cond
      [(>= (+ accepted rejected) maximum-steps)
       (values (reverse reversed)
               (dense-series-report3d
                accepted rejected maximum-error (reverse steps) 'maximum-steps current
                (list 'maximum-steps maximum-steps)))]
      [else
       (with-handlers
           ([exn:fail:ode-field3d?
             (lambda (exception)
               (if (eq? (trajectory-termination3d-on-field-error termination) 'terminate)
                   (values (reverse reversed)
                           (dense-series-report3d
                            accepted rejected maximum-error (reverse steps) 'field-error current
                            (list 'field-error (exn-message exception))))
                   (raise exception)))])
         (define remaining (- target-time (prepared-trajectory-node3d-time current)))
         (define trial-step
           (* direction
              (min (abs remaining) (adaptive-rk45-maximum-step solver)
                   (max (adaptive-rk45-minimum-step solver) (abs step)))))
         (define-values (candidate endpoint-derivative error)
           (ode-state-space-dormand-prince-step
            vec3-ode-state-space
            (lambda (field-time field-point)
              (call-field3d field field-time field-point evaluations))
            (prepared-trajectory-node3d-time current)
            (prepared-trajectory-node3d-position current)
            trial-step
            (adaptive-rk45-relative-tolerance solver)
            (adaptive-rk45-absolute-tolerance solver)))
         (define next-maximum-error (max maximum-error error))
         (cond
           [(<= error 1)
            (define next
              (prepared-trajectory-node3d
               (+ (prepared-trajectory-node3d-time current) trial-step)
               candidate endpoint-derivative))
            (if (= (prepared-trajectory-node3d-time next) target-time)
                (values (reverse (cons next reversed))
                        (dense-series-report3d
                         (add1 accepted) rejected next-maximum-error
                         (reverse (cons (abs trial-step) steps)) 'time-range #f #f))
                (loop next
                      (* direction (adaptive-next-step-magnitude3d solver (abs trial-step) error))
                      (cons next reversed) (add1 accepted) rejected next-maximum-error
                      (cons (abs trial-step) steps)))]
           [else
            (when (<= (abs trial-step) (adaptive-rk45-minimum-step solver))
              (raise-arguments-error
               'prepare-ode-trajectory3d
               "adaptive solver reached minimum-step before satisfying tolerance"
               "minimum-step" (adaptive-rk45-minimum-step solver)
               "error-ratio" error "time" (prepared-trajectory-node3d-time current)))
            (loop current
                  (* direction (adaptive-rejected-step-magnitude3d solver (abs trial-step) error))
                  reversed accepted (add1 rejected) next-maximum-error steps)]))])))

(define (dense-rk4-step3d field time point step evaluations)
  (ode-state-space-rk4-step
   vec3-ode-state-space
   (lambda (field-time field-point) (call-field3d field field-time field-point evaluations))
   time point step))

(define (dense-clip-nodes3d all-nodes start-time end-time)
  (define all (vector->immutable-vector (list->vector all-nodes)))
  (define all-segments (dense-make-segments3d all))
  (define (node-at time)
    (prepared-trajectory-node3d time
                                (dense-position-from3d all all-segments time)
                                (dense-derivative-from3d all all-segments time)))
  (vector->immutable-vector
   (list->vector
    (append (list (node-at start-time))
            (for/list ([node (in-vector all)]
                       #:when (< start-time (prepared-trajectory-node3d-time node) end-time))
              node)
            (if (= start-time end-time) '() (list (node-at end-time)))))))

;;;
;;; T-1 Event Detection

;; Event tests intentionally use the dense Hermite segment, rather than a
;; linear interpolation of two event values.  Thus the event path follows the
;; same stored numerical trajectory that lookup and rendering use.

(define (check-ode-events3d who events)
  (unless (list? events) (raise-argument-error who "list? as #:events" events))
  (for ([event (in-list events)]) (check-ode-event3d who event))
  (define ids (map ode-event3d-id events))
  (unless (= (length ids) (length (remove-duplicates ids)))
    (raise-arguments-error who "event ids must be distinct" "events" events)))

(define (call-event3d event time point)
  (define value
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'prepare-ode-trajectory3d "a 3D ODE event raised an exception"
             "event-id" (ode-event3d-id event)
             "time" time
             "point" point
             "exception message" (exn-message exception)))])
      (if (= (ode-event3d-value-arity event) 2)
          ((ode-event3d-value-function event) time point)
          ((ode-event3d-value-function event) point))))
  (unless (finite-real? value)
    (raise-arguments-error
     'prepare-ode-trajectory3d "a 3D ODE event must return a finite real"
     "event-id" (ode-event3d-id event) "time" time "point" point "result" value))
  value)

(define (event-sign3d event value)
  (cond [(> value (ode-event3d-value-tolerance event)) 1]
        [(< value (- (ode-event3d-value-tolerance event))) -1]
        [else 0]))

(define (event-direction-from-signs3d lower-sign upper-sign)
  (cond [(and (= lower-sign 0) (= upper-sign 0)) 'any]
        [(or (and (= lower-sign -1) (>= upper-sign 0))
             (and (= lower-sign 0) (= upper-sign 1))) 'increasing]
        [(or (and (= lower-sign 1) (<= upper-sign 0))
             (and (= lower-sign 0) (= upper-sign -1))) 'decreasing]
        [else 'any]))

(define (event-direction-allowed? event physical-direction)
  (or (eq? (ode-event3d-direction event) 'any)
      ;; A sustained tolerance-zero endpoint has no physical crossing
      ;; orientation. It remains observable for an explicitly directional
      ;; event rather than being silently discarded.
      (eq? physical-direction 'any)
      (eq? (ode-event3d-direction event) physical-direction)))

(define (dense-event-hit-at3d event time position value direction segment-index iterations provenance)
  (ode-event-hit3d (ode-event3d-id event) time position value direction
                   segment-index iterations provenance))

(define (dense-event-root3d event segment segment-index lower-value upper-value direction)
  (define lower-time (trajectory-segment3d-t0 segment))
  (define upper-time (trajectory-segment3d-t1 segment))
  (define lower-sign (event-sign3d event lower-value))
  (let loop ([low lower-time] [high upper-time]
             [low-value lower-value] [high-value upper-value]
             [best-time (if (<= (abs lower-value) (abs upper-value)) lower-time upper-time)]
             [best-value (if (<= (abs lower-value) (abs upper-value)) lower-value upper-value)]
             [iteration 0])
    (cond
      [(>= iteration (ode-event3d-value-maximum-iterations event))
       (dense-event-hit-at3d event best-time
                             (dense-segment-position3d segment best-time) best-value direction
                             segment-index iteration 'maximum-iterations)]
      [else
       (define middle (/ (+ low high) 2))
       (define middle-position (dense-segment-position3d segment middle))
       (define middle-value (call-event3d event middle middle-position))
       (define middle-sign (event-sign3d event middle-value))
       (define-values (next-best-time next-best-value)
         (if (< (abs middle-value) (abs best-value))
             (values middle middle-value)
             (values best-time best-value)))
       (cond
         [(zero? middle-sign)
          (dense-event-hit-at3d event middle middle-position middle-value direction
                                segment-index (add1 iteration) 'bisection)]
         [(and (<= (- high low) (ode-event3d-value-time-tolerance event))
               (<= (abs middle-value) (ode-event3d-value-tolerance event)))
          (dense-event-hit-at3d event next-best-time
                                (dense-segment-position3d segment next-best-time)
                                next-best-value direction segment-index
                                (add1 iteration) 'bisection)]
         [(= (event-sign3d event low-value) middle-sign)
          (loop middle high middle-value high-value
                next-best-time next-best-value (add1 iteration))]
         [else
          (loop low middle low-value middle-value
                next-best-time next-best-value (add1 iteration))])])))

(define (dense-event-hits3d events nodes segments)
  (cond
    [(null? events) '()]
    [(zero? (vector-length segments))
     (define node (vector-ref nodes 0))
     (for/list ([event (in-list events)]
                #:do [(define value
                        (call-event3d event
                                      (prepared-trajectory-node3d-time node)
                                      (prepared-trajectory-node3d-position node)))]
                #:when (and (zero? (event-sign3d event value))
                            (event-direction-allowed? event 'any)))
       (dense-event-hit-at3d event
                             (prepared-trajectory-node3d-time node)
                             (prepared-trajectory-node3d-position node)
                             value 'any 0 0 'endpoint))]
    [else
     (append*
      (for/list ([segment (in-vector segments)] [segment-index (in-naturals)])
        (append*
         (for/list ([event (in-list events)])
           (define lower-time (trajectory-segment3d-t0 segment))
           (define upper-time (trajectory-segment3d-t1 segment))
           (define lower-position (trajectory-segment3d-p0 segment))
           (define upper-position (trajectory-segment3d-p1 segment))
           (define lower-value (call-event3d event lower-time lower-position))
           (define upper-value (call-event3d event upper-time upper-position))
           (define lower-sign (event-sign3d event lower-value))
           (define upper-sign (event-sign3d event upper-value))
           (define direction (event-direction-from-signs3d lower-sign upper-sign))
           (define (allowed?) (event-direction-allowed? event direction))
           (cond
             ;; A shared event node belongs to the segment on its left.  This
             ;; reports an endpoint once even when multiple segments meet it.
             [(and (zero? lower-sign) (zero? segment-index))
              (if (allowed?)
                  (list (dense-event-hit-at3d event lower-time lower-position lower-value
                                               direction segment-index 0 'endpoint))
                  '())]
             [(zero? lower-sign) '()]
             [(zero? upper-sign)
              (if (allowed?)
                  (list (dense-event-hit-at3d event upper-time upper-position upper-value
                                               direction segment-index 0 'endpoint))
                  '())]
             [(and (not (= lower-sign upper-sign)) (allowed?))
              (list (dense-event-root3d event segment segment-index
                                         lower-value upper-value direction))]
             [else '()])))))]))

;; `dense-termination-candidate3d` is a private, serializable comparison value.
;; The public result is the smaller `trajectory-termination-hit3d` record.
(struct dense-termination-candidate3d (reason time position details priority)
  #:transparent)

(define (dense-termination-priority reason)
  ;; The first four cases are the published tie order.  A time limit is a
  ;; clipped request boundary, and low-speed is an accepted-node observation,
  ;; so they follow the more geometrically precise exit conditions.
  (case reason
    [(field-error) 0]
    [(terminal-event) 1]
    [(bounds-exit) 2]
    [(arc-length-limit) 3]
    [(minimum-speed) 4]
    [(maximum-steps) 5]
    [(time-limit) 6]
    [else 7]))

(define (make-termination-candidate3d reason time position details)
  (dense-termination-candidate3d reason time position details
                                 (dense-termination-priority reason)))

(define (dense-candidate->hit3d candidate)
  (trajectory-termination-hit3d
   (dense-termination-candidate3d-reason candidate)
   (dense-termination-candidate3d-time candidate)
   (dense-termination-candidate3d-position candidate)
   (dense-termination-candidate3d-details candidate)))

(define (dense-best-termination3d direction candidates)
  (for/fold ([best #f]) ([candidate (in-list candidates)])
    (cond
      [(not best) candidate]
      [(eq? direction 'forward)
       (cond [(< (dense-termination-candidate3d-time candidate)
                 (dense-termination-candidate3d-time best)) candidate]
             [(and (= (dense-termination-candidate3d-time candidate)
                       (dense-termination-candidate3d-time best))
                    (< (dense-termination-candidate3d-priority candidate)
                       (dense-termination-candidate3d-priority best))) candidate]
             [else best])]
      [else
       (cond [(> (dense-termination-candidate3d-time candidate)
                 (dense-termination-candidate3d-time best)) candidate]
             [(and (= (dense-termination-candidate3d-time candidate)
                       (dense-termination-candidate3d-time best))
                    (< (dense-termination-candidate3d-priority candidate)
                       (dense-termination-candidate3d-priority best))) candidate]
             [else best])])))

(define (dense-terminal-event-candidates3d events hits start-time anchor end-time)
  (define terminal-ids
    (for/list ([event (in-list events)] #:when (ode-event3d-terminal? event))
      (ode-event3d-id event)))
  (for/list ([hit (in-list hits)]
             #:when (and (memq (ode-event-hit3d-event-id hit) terminal-ids)
                         (<= start-time (ode-event-hit3d-time hit) end-time)))
    (make-termination-candidate3d
     'terminal-event
     (ode-event-hit3d-time hit)
     (ode-event-hit3d-position hit)
     (list 'event (ode-event-hit3d-event-id hit)
           (ode-event-hit3d-direction hit)
           (ode-event-hit3d-provenance hit)))))

(define (dense-quadratic-roots-in-unit-interval3d a b c)
  ;; Roots of a*u^2 + b*u + c.  They are used only to split a Hermite
  ;; segment at coordinate extrema, so roots at the segment endpoints add no
  ;; information and are discarded.
  (cond
    [(zero? a)
     (if (zero? b)
         '()
         (let ([root (/ (- c) b)])
           (if (< 0 root 1) (list root) '())))]
    [else
     (define discriminant (- (* b b) (* 4 a c)))
     (if (negative? discriminant)
         '()
         (let* ([root-discriminant (sqrt discriminant)]
                [denominator (* 2 a)]
                [first (/ (+ (- b) root-discriminant) denominator)]
                [second (/ (- (- b) root-discriminant) denominator)])
           (remove-duplicates
            (filter (lambda (root) (< 0 root 1)) (list first second)) =)))]))

(define (dense-segment-coordinate-extrema3d segment coordinate)
  ;; Each coordinate of a cubic Hermite segment is itself a cubic.  Splitting
  ;; at all roots of its derivative gives intervals on which every coordinate
  ;; is monotone, so an AABB exit cannot be hidden between two samples.
  (define t0 (trajectory-segment3d-t0 segment))
  (define step (- (trajectory-segment3d-t1 segment) t0))
  (define p0 (coordinate (trajectory-segment3d-p0 segment)))
  (define p1 (coordinate (trajectory-segment3d-p1 segment)))
  (define d0 (coordinate (trajectory-segment3d-d0 segment)))
  (define d1 (coordinate (trajectory-segment3d-d1 segment)))
  (define cubic-a (+ (* 2 p0) (* -2 p1) (* step d0) (* step d1)))
  (define cubic-b (+ (* -3 p0) (* 3 p1) (* -2 step d0) (* -1 step d1)))
  (define cubic-c (* step d0))
  (for/list ([u (in-list (dense-quadratic-roots-in-unit-interval3d
                           (* 3 cubic-a) (* 2 cubic-b) cubic-c))])
    (+ t0 (* u step))))

(define (dense-sampled-times3d segments start-time end-time direction)
  (define times
    (append*
     (for/list ([segment (in-vector segments)])
       (define first (max start-time (trajectory-segment3d-t0 segment)))
       (define last (min end-time (trajectory-segment3d-t1 segment)))
       (if (> first last)
           '()
           (sort
            (append (list first last)
                    (filter (lambda (time) (< first time last))
                            (append (dense-segment-coordinate-extrema3d segment vec3-x)
                                    (dense-segment-coordinate-extrema3d segment vec3-y)
                                    (dense-segment-coordinate-extrema3d segment vec3-z))))
            <)))))
  (define unique (remove-duplicates (sort times <) =))
  (if (eq? direction 'forward) unique (reverse unique)))

(define (dense-bounds-normal3d bounds point)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (define faces
    (list (cons (abs (- (vec3-x point) (vec3-x minimum))) (vec3 -1 0 0))
          (cons (abs (- (vec3-x point) (vec3-x maximum))) (vec3 1 0 0))
          (cons (abs (- (vec3-y point) (vec3-y minimum))) (vec3 0 -1 0))
          (cons (abs (- (vec3-y point) (vec3-y maximum))) (vec3 0 1 0))
          (cons (abs (- (vec3-z point) (vec3-z minimum))) (vec3 0 0 -1))
          (cons (abs (- (vec3-z point) (vec3-z maximum))) (vec3 0 0 1))))
  (cdr (for/fold ([best (car faces)]) ([face (in-list (cdr faces))])
         (if (< (car face) (car best)) face best))))

(define (dense-bounds-face-normal-at3d bounds point)
  ;; An accepted node can land exactly on a face.  Preserve that exact time
  ;; instead of needlessly replacing it by a nearby bisection result; it also
  ;; makes the documented terminal-event/bounds tie order observable.
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (cond [(= (vec3-x point) (vec3-x minimum)) (vec3 -1 0 0)]
        [(= (vec3-x point) (vec3-x maximum)) (vec3 1 0 0)]
        [(= (vec3-y point) (vec3-y minimum)) (vec3 0 -1 0)]
        [(= (vec3-y point) (vec3-y maximum)) (vec3 0 1 0)]
        [(= (vec3-z point) (vec3-z minimum)) (vec3 0 0 -1)]
        [(= (vec3-z point) (vec3-z maximum)) (vec3 0 0 1)]
        [else #f]))

(define (dense-bounds-face-point3d bounds point normal)
  ;; Preserve the dense state on the two tangential axes, while representing
  ;; the hit exactly on the reported AABB face.  This avoids a one-ulp
  ;; "outside" endpoint after bisection.
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (define (clamp coordinate lower upper)
    (max lower (min upper coordinate)))
  (define x (clamp (vec3-x point) (vec3-x minimum) (vec3-x maximum)))
  (define y (clamp (vec3-y point) (vec3-y minimum) (vec3-y maximum)))
  (define z (clamp (vec3-z point) (vec3-z minimum) (vec3-z maximum)))
  (cond [(positive? (vec3-x normal)) (vec3 (vec3-x maximum) y z)]
        [(negative? (vec3-x normal)) (vec3 (vec3-x minimum) y z)]
        [(positive? (vec3-y normal)) (vec3 x (vec3-y maximum) z)]
        [(negative? (vec3-y normal)) (vec3 x (vec3-y minimum) z)]
        [(positive? (vec3-z normal)) (vec3 x y (vec3-z maximum))]
        [else (vec3 x y (vec3-z minimum))]))

(define (dense-bounds-exit-between3d bounds segment inside-time outside-time)
  (let loop ([inside-time inside-time] [outside-time outside-time] [iterations 0])
    (if (= iterations 48)
        (let* ([dense-point (dense-segment-position3d segment outside-time)]
               [normal (dense-bounds-normal3d bounds dense-point)]
               [point (dense-bounds-face-point3d bounds dense-point normal)])
          (make-termination-candidate3d
           'bounds-exit outside-time point
           (list 'face-normal normal 'dense-bisection)))
        (let* ([middle (/ (+ inside-time outside-time) 2)]
               [point (dense-segment-position3d segment middle)])
          (if (aabb3-contains? bounds point)
              (loop middle outside-time (add1 iterations))
              (loop inside-time middle (add1 iterations)))))))

(define (dense-bounds-exit3d bounds segments start-time end-time direction)
  (and bounds
       (let* ([times (dense-sampled-times3d segments start-time end-time direction)]
              [first-time (and (pair? times) (car times))])
         (cond
           [(not first-time) #f]
           [(not (aabb3-contains? bounds
                                  (dense-segment-position3d
                                   (vector-ref segments
                                               (dense-segment-index-for-time3d segments first-time))
                                   first-time)))
            (define position
              (dense-segment-position3d
               (vector-ref segments (dense-segment-index-for-time3d segments first-time))
               first-time))
            (make-termination-candidate3d
             'bounds-exit first-time position
             (list 'initially-outside 'face-normal (dense-bounds-normal3d bounds position)))]
           [else
            (let loop ([previous-time first-time] [rest (cdr times)])
              (cond [(null? rest) #f]
                    [else
                     (define next-time (car rest))
                     (define segment
                       (vector-ref segments
                                   (dense-segment-index-for-time3d
                                    segments (min previous-time next-time))))
                     (define previous-position
                       (dense-segment-position3d segment previous-time))
                     (define next-position (dense-segment-position3d segment next-time))
                     (if (aabb3-contains? bounds next-position)
                         (loop next-time (cdr rest))
                         (let ([normal (dense-bounds-face-normal-at3d bounds previous-position)])
                           (if normal
                               (make-termination-candidate3d
                                'bounds-exit previous-time previous-position
                                (list 'face-normal normal 'accepted-node))
                               (dense-bounds-exit-between3d
                                bounds segment previous-time next-time))))]))]))))

(define (dense-arc-at3d segments cumulative time)
  (if (zero? (vector-length segments))
      0
      (let ([index (dense-segment-index-for-time3d segments time)])
        (+ (vector-ref cumulative index)
           (dense-segment-arc-length-to3d (vector-ref segments index) time)))))

(define (dense-arc-limit3d limit segments cumulative anchor target direction)
  (if (not limit)
      #f
      (let ([total (abs (- (dense-arc-at3d segments cumulative target)
                           (dense-arc-at3d segments cumulative anchor)))])
        (if (<= total limit)
            #f
            (let loop ([near anchor] [far target] [iterations 48])
              (if (zero? iterations)
                  (make-termination-candidate3d
                   'arc-length-limit far (dense-position-from3d #f segments far)
                   (list 'arc-length limit 'dense-bisection))
                  (let* ([middle (/ (+ near far) 2)]
                         [length (abs (- (dense-arc-at3d segments cumulative middle)
                                         (dense-arc-at3d segments cumulative anchor)))])
                    (if (> length limit)
                        (loop near middle (sub1 iterations))
                        (loop middle far (sub1 iterations))))))))))

(define (dense-low-speed3d minimum-speed nodes segments anchor target direction)
  (and minimum-speed
       (let* ([node-times
               (for/list ([node (in-vector nodes)]
                          #:when (<= (min anchor target)
                                     (prepared-trajectory-node3d-time node)
                                     (max anchor target)))
                 (prepared-trajectory-node3d-time node))]
              [midpoint-times
               (for/list ([segment (in-vector segments)]
                          #:do [(define middle
                                   (/ (+ (trajectory-segment3d-t0 segment)
                                         (trajectory-segment3d-t1 segment)) 2))]
                          #:when (<= (min anchor target) middle (max anchor target)))
                 middle)]
              [times (sort (remove-duplicates (append (list anchor) node-times midpoint-times) =)
                           <)])
         (for/first ([time (in-list (if (eq? direction 'forward) times (reverse times)))]
                   #:do [(define derivative (dense-derivative-from3d nodes segments time))]
                   #:when (<= (vec3-length derivative) minimum-speed))
         (make-termination-candidate3d
          'minimum-speed time (dense-position-from3d nodes segments time)
          (list 'speed (vec3-length derivative) 'threshold minimum-speed
                'accepted-node-or-midpoint))))))

(define (dense-series-termination-candidates3d backward-report forward-report)
  (for/list ([report (in-list (list backward-report forward-report))]
             #:when (and (dense-series-report3d-stop-node report)
                         (not (eq? (dense-series-report3d-stop-reason report) 'time-range)))
             #:do [(define node (dense-series-report3d-stop-node report))])
    (make-termination-candidate3d
     (dense-series-report3d-stop-reason report)
     (prepared-trajectory-node3d-time node)
     (prepared-trajectory-node3d-position node)
     (dense-series-report3d-stop-details report))))

(define (dense-resolve-termination3d start-time end-time nodes segments hits events
                                     termination time-limited? series-candidates)
  ;; `anchor` is the seed time when it lies in the requested interval, and the
  ;; closest requested endpoint otherwise. This makes branch-wise termination
  ;; well-defined for both ordinary forward paths and two-sided trajectories.
  (define anchor (min end-time (max start-time 0)))
  (define cumulative (dense-cumulative-arcs3d segments))
  (define event-candidates
    (dense-terminal-event-candidates3d events hits start-time anchor end-time))
  (define (forward-candidates)
    (append
     (filter (lambda (candidate) (<= anchor (dense-termination-candidate3d-time candidate) end-time))
             event-candidates)
     (filter (lambda (candidate) (<= anchor (dense-termination-candidate3d-time candidate) end-time))
             series-candidates)
     (let ([candidate (dense-bounds-exit3d (trajectory-termination3d-bounds termination)
                                            segments anchor end-time 'forward)])
       (if candidate (list candidate) '()))
     (let ([candidate (dense-arc-limit3d (trajectory-termination3d-arc-length-limit termination)
                                          segments cumulative anchor end-time 'forward)])
       (if candidate (list candidate) '()))
     (let ([candidate (dense-low-speed3d (trajectory-termination3d-minimum-speed termination)
                                          nodes segments anchor end-time 'forward)])
       (if candidate (list candidate) '()))
     (if (cdr time-limited?)
         (list (make-termination-candidate3d
                'time-limit end-time (dense-position-from3d nodes segments end-time)
                (list 'time-limit (trajectory-termination3d-time-limit termination))))
         '())))
  (define (backward-candidates)
    (append
     (filter (lambda (candidate) (<= start-time (dense-termination-candidate3d-time candidate) anchor))
             event-candidates)
     (filter (lambda (candidate) (<= start-time (dense-termination-candidate3d-time candidate) anchor))
             series-candidates)
     (let ([candidate (dense-bounds-exit3d (trajectory-termination3d-bounds termination)
                                            segments start-time anchor 'backward)])
       (if candidate (list candidate) '()))
     (let ([candidate (dense-arc-limit3d (trajectory-termination3d-arc-length-limit termination)
                                          segments cumulative anchor start-time 'backward)])
       (if candidate (list candidate) '()))
     (let ([candidate (dense-low-speed3d (trajectory-termination3d-minimum-speed termination)
                                          nodes segments anchor start-time 'backward)])
       (if candidate (list candidate) '()))
     (if (car time-limited?)
         (list (make-termination-candidate3d
                'time-limit start-time (dense-position-from3d nodes segments start-time)
                (list 'time-limit (trajectory-termination3d-time-limit termination))))
         '())))
  (define forward (and (< anchor end-time)
                       (dense-best-termination3d 'forward (forward-candidates))))
  (define backward (and (< start-time anchor)
                        (dense-best-termination3d 'backward (backward-candidates))))
  (define actual-start (if backward (dense-termination-candidate3d-time backward) start-time))
  (define actual-end (if forward (dense-termination-candidate3d-time forward) end-time))
  ;; A requested interval that lies entirely beyond a time budget collapses
  ;; to the boundary itself.  Neither integration branch has positive length
  ;; in that case, but the policy must still be inspectable as the reason for
  ;; the returned singleton trajectory.
  (define degenerate-time-limit
    (and (= start-time end-time)
         (or (car time-limited?) (cdr time-limited?))
         (make-termination-candidate3d
          'time-limit start-time (dense-position-from3d nodes segments start-time)
          (list 'time-limit (trajectory-termination3d-time-limit termination)))))
  (define hit-list
    (sort (filter values (list backward forward degenerate-time-limit))
          < #:key dense-termination-candidate3d-time))
  (values actual-start actual-end
          (vector->immutable-vector
           (list->vector (map dense-candidate->hit3d hit-list)))) )

(define (dense-reindex-event-hits3d hits segments)
  (vector->immutable-vector
   (list->vector
    (for/list ([hit (in-list hits)])
      (struct-copy ode-event-hit3d hit
                   [segment-index
                    (if (zero? (vector-length segments))
                        0
                        (dense-segment-index-for-time3d
                         segments (ode-event-hit3d-time hit)))])))))

(define (dense-event-warnings3d hits)
  (for/list ([hit (in-vector hits)]
             #:when (eq? (ode-event-hit3d-provenance hit) 'maximum-iterations))
    (list 'event-maximum-iterations
          (ode-event-hit3d-event-id hit)
          (ode-event-hit3d-time hit))))

(define (dense-make-segments3d nodes)
  (vector->immutable-vector
   (list->vector
    (for/list ([index (in-range (max 0 (sub1 (vector-length nodes))))])
      (define first (vector-ref nodes index))
      (define second (vector-ref nodes (add1 index)))
      (define segment
        (trajectory-segment3d
         (prepared-trajectory-node3d-time first) (prepared-trajectory-node3d-time second)
         (prepared-trajectory-node3d-position first) (prepared-trajectory-node3d-position second)
         (prepared-trajectory-node3d-derivative first) (prepared-trajectory-node3d-derivative second)
         0 (dense-segment-bounds3d (prepared-trajectory-node3d-position first)
                                    (prepared-trajectory-node3d-position second))))
      (struct-copy trajectory-segment3d segment
                   [arc-length (dense-segment-arc-length-to3d segment
                                                               (trajectory-segment3d-t1 segment))])))))

(define (dense-cumulative-arcs3d segments)
  (vector->immutable-vector
   (list->vector
    (let loop ([index 0] [total 0] [reversed (list 0)])
      (if (= index (vector-length segments))
          (reverse reversed)
          (let ([next (+ total (trajectory-segment3d-arc-length
                                (vector-ref segments index)))])
            (loop (add1 index) next (cons next reversed))))))))

(define (dense-trajectory-position3d trajectory time)
  (dense-position-from3d (prepared-trajectory3d-value-nodes trajectory)
                         (prepared-trajectory3d-value-segments trajectory) time))

(define (dense-trajectory-derivative3d trajectory time)
  (dense-derivative-from3d (prepared-trajectory3d-value-nodes trajectory)
                           (prepared-trajectory3d-value-segments trajectory) time))

(define (dense-position-from3d nodes segments time)
  (if (zero? (vector-length segments))
      (prepared-trajectory-node3d-position (vector-ref nodes 0))
      (dense-segment-position3d
       (vector-ref segments (dense-segment-index-for-time3d segments time)) time)))

(define (dense-derivative-from3d nodes segments time)
  (if (zero? (vector-length segments))
      (prepared-trajectory-node3d-derivative (vector-ref nodes 0))
      (dense-segment-derivative3d
       (vector-ref segments (dense-segment-index-for-time3d segments time)) time)))

(define (dense-segment-index-for-time3d segments time)
  (let loop ([low 0] [high (sub1 (vector-length segments))])
    (if (= low high)
        low
        (let* ([middle (quotient (+ low high 1) 2)]
               [segment (vector-ref segments middle)])
          (if (<= (trajectory-segment3d-t0 segment) time)
              (loop middle high)
              (loop low (sub1 middle)))))))

(define (dense-segment-progress3d segment time)
  (define duration (- (trajectory-segment3d-t1 segment) (trajectory-segment3d-t0 segment)))
  (if (zero? duration) 0 (/ (- time (trajectory-segment3d-t0 segment)) duration)))

(define (dense-segment-position3d segment time)
  (define s (dense-segment-progress3d segment time))
  (define h (- (trajectory-segment3d-t1 segment) (trajectory-segment3d-t0 segment)))
  (define s2 (* s s))
  (define s3 (* s2 s))
  (vec3+ (vec3+ (vec3-scale (+ (* 2 s3) (* -3 s2) 1) (trajectory-segment3d-p0 segment))
               (vec3-scale (* h (+ s3 (* -2 s2) s)) (trajectory-segment3d-d0 segment)))
         (vec3+ (vec3-scale (+ (* -2 s3) (* 3 s2)) (trajectory-segment3d-p1 segment))
                (vec3-scale (* h (+ s3 (- s2))) (trajectory-segment3d-d1 segment)))))

(define (dense-segment-derivative3d segment time)
  (define s (dense-segment-progress3d segment time))
  (define h (- (trajectory-segment3d-t1 segment) (trajectory-segment3d-t0 segment)))
  (if (zero? h)
      (trajectory-segment3d-d0 segment)
      (let ([s2 (* s s)])
        (vec3+ (vec3+ (vec3-scale (/ (+ (* 6 s2) (* -6 s)) h)
                                      (trajectory-segment3d-p0 segment))
                     (vec3-scale (+ (* 3 s2) (* -4 s) 1) (trajectory-segment3d-d0 segment)))
               (vec3+ (vec3-scale (/ (+ (* -6 s2) (* 6 s)) h)
                                      (trajectory-segment3d-p1 segment))
                      (vec3-scale (+ (* 3 s2) (* -2 s)) (trajectory-segment3d-d1 segment)))))))

(define (dense-segment-arc-length-to3d segment time)
  (define target (max (trajectory-segment3d-t0 segment)
                      (min time (trajectory-segment3d-t1 segment))))
  (let loop ([index 1] [previous (trajectory-segment3d-p0 segment)] [total 0])
    (if (> index 8)
        total
        (let ([next (dense-segment-position3d
                     segment
                     (+ (trajectory-segment3d-t0 segment)
                        (* (/ index 8) (- target (trajectory-segment3d-t0 segment)))) )])
          (loop (add1 index) next (+ total (vec3-distance previous next)))))))

(define (dense-segment-bounds3d first second)
  (cons (vec3 (min (vec3-x first) (vec3-x second))
              (min (vec3-y first) (vec3-y second))
              (min (vec3-z first) (vec3-z second)))
        (vec3 (max (vec3-x first) (vec3-x second))
              (max (vec3-y first) (vec3-y second))
              (max (vec3-z first) (vec3-z second)))))

(define (ode-trajectory3d-segment-index trajectory time)
  (check-trajectory3d 'ode-trajectory3d-segment-index trajectory)
  (check-trajectory3d-time 'ode-trajectory3d-segment-index trajectory time)
  (cond [(prepared-trajectory3d? trajectory)
         (define segments (prepared-trajectory3d-value-segments trajectory))
         (if (zero? (vector-length segments)) 0
             (dense-segment-index-for-time3d segments time))]
        [else
         (raise-arguments-error 'ode-trajectory3d-segment-index
                                "legacy trajectory has no immutable dense segments"
                                "trajectory" trajectory)]))

(define (ode-trajectory3d-derivative trajectory time)
  (check-trajectory3d 'ode-trajectory3d-derivative trajectory)
  (check-trajectory3d-time 'ode-trajectory3d-derivative trajectory time)
  (cond [(prepared-trajectory3d? trajectory)
         (dense-trajectory-derivative3d trajectory time)]
        [else
         (call-trajectory-field3d trajectory time
                                  (ode-trajectory3d-position trajectory time))]))

(define (ode-trajectory3d-speed trajectory time)
  (vec3-length (ode-trajectory3d-derivative trajectory time)))

(define (ode-trajectory3d-arc-length-at trajectory time)
  (check-trajectory3d 'ode-trajectory3d-arc-length-at trajectory)
  (check-trajectory3d-time 'ode-trajectory3d-arc-length-at trajectory time)
  (unless (prepared-trajectory3d? trajectory)
    (raise-arguments-error 'ode-trajectory3d-arc-length-at
                           "legacy trajectory has no immutable arc-length table"
                           "trajectory" trajectory))
  (define segments (prepared-trajectory3d-value-segments trajectory))
  (if (zero? (vector-length segments))
      0
      (let ([index (dense-segment-index-for-time3d segments time)])
        (+ (vector-ref (prepared-trajectory3d-value-cumulative-arcs trajectory) index)
           (dense-segment-arc-length-to3d (vector-ref segments index) time)))))

(define (ode-trajectory3d-time-at-arc-length trajectory arc-length)
  (check-trajectory3d 'ode-trajectory3d-time-at-arc-length trajectory)
  (unless (prepared-trajectory3d? trajectory)
    (raise-arguments-error 'ode-trajectory3d-time-at-arc-length
                           "legacy trajectory has no immutable arc-length table"
                           "trajectory" trajectory))
  (define total
    (dense-trajectory-diagnostics3d-total-arc-length
     (prepared-trajectory3d-value-diagnostics trajectory)))
  (unless (and (finite-real? arc-length) (<= 0 arc-length total))
    (raise-argument-error 'ode-trajectory3d-time-at-arc-length
                          "arc length within the prepared trajectory" arc-length))
  (define segments (prepared-trajectory3d-value-segments trajectory))
  (if (zero? (vector-length segments))
      (car (ode-trajectory3d-time-range trajectory))
      (let* ([cumulative (prepared-trajectory3d-value-cumulative-arcs trajectory)]
             [index (dense-segment-index-for-arc-length3d cumulative arc-length)]
             [segment (vector-ref segments index)]
             [local (- arc-length (vector-ref cumulative index))])
        (dense-segment-time-at-arc-length3d segment local))))

(define (dense-segment-index-for-arc-length3d cumulative arc-length)
  (let loop ([low 0] [high (- (vector-length cumulative) 2)])
    (if (= low high)
        low
        (let ([middle (quotient (+ low high 1) 2)])
          (if (<= (vector-ref cumulative middle) arc-length)
              (loop middle high)
              (loop low (sub1 middle)))))))

(define (dense-segment-time-at-arc-length3d segment target)
  (cond [(zero? (trajectory-segment3d-arc-length segment))
         (trajectory-segment3d-t0 segment)]
        [else
         (let loop ([low (trajectory-segment3d-t0 segment)]
                    [high (trajectory-segment3d-t1 segment)] [iterations 36])
           (if (zero? iterations)
               (/ (+ low high) 2)
               (let ([middle (/ (+ low high) 2)])
                 (if (< (dense-segment-arc-length-to3d segment middle) target)
                     (loop middle high (sub1 iterations))
                     (loop low middle (sub1 iterations))))))]))


;;;
;;; Static Curves and Vector Fields

(define (legacy-streamline3d field seed
                      #:id id
                      #:direction [direction 'both]
                      #:step-size [step-size 1/20]
                      #:steps [steps 120]
                      #:style [style (stroke3d #:color "royalblue" #:width 2)]
                      #:opacity [opacity 1])
  (check-field3d 'legacy-streamline3d field)
  (check-vec3 'legacy-streamline3d seed)
  (check-symbol 'legacy-streamline3d id)
  (check-direction 'legacy-streamline3d direction)
  (check-positive 'legacy-streamline3d "step-size" step-size)
  (check-positive-integer 'legacy-streamline3d "steps" steps)
  (define trajectory
    (prepare-ode-trajectory3d field seed
                              #:time-range (cons (* -1 steps step-size)
                                                  (* steps step-size))
                              #:step-size step-size))
  (define (at index) (ode-trajectory3d-position trajectory (* index step-size)))
  (polyline3d
   (case direction
     [(forward) (for/list ([index (in-range 0 (add1 steps))]) (at index))]
     [(backward) (for/list ([index (in-range steps -1 -1)]) (at (- index)))]
     [else (append (for/list ([index (in-range steps 0 -1)]) (at (- index)))
                   (for/list ([index (in-range 0 (add1 steps))]) (at index)))])
   #:id id #:style style #:opacity opacity))

(define (legacy-streamlines3d field seeds
                       #:id id
                       #:direction [direction 'both]
                       #:step-size [step-size 1/20]
                       #:steps [steps 120]
                       #:style [style (stroke3d #:color "royalblue" #:width 2)]
                       #:opacity [opacity 1])
  (check-field3d 'legacy-streamlines3d field)
  (unless (list? seeds) (raise-argument-error 'legacy-streamlines3d "list?" seeds))
  (for ([seed (in-list seeds)]) (check-vec3 'legacy-streamlines3d seed))
  (check-symbol 'legacy-streamlines3d id)
  (group3d
   (for/list ([seed (in-list seeds)] [index (in-naturals)])
     (legacy-streamline3d field seed #:id (child-id3d id index)
                   #:direction direction #:step-size step-size #:steps steps
                   #:style style #:opacity opacity))
   #:id id))

;; T-3 keeps the numerical trajectory separate from its visual sampling.  The
;; former is dense immutable data; the latter is a deterministic world-space
;; polyline that never changes with camera distance or pixel scale.
(struct streamline-sample-policy3d-value
  (maximum-chord-error maximum-turn-angle maximum-segment-length minimum-segment-length)
  #:transparent)

(define (streamline-sample-policy3d #:maximum-chord-error [maximum-chord-error 1/100]
                                    #:maximum-turn-angle [maximum-turn-angle (/ (acos -1) 12)]
                                    #:maximum-segment-length [maximum-segment-length 1/4]
                                    #:minimum-segment-length [minimum-segment-length 1/2000])
  (check-optional-nonnegative 'streamline-sample-policy3d
                              "maximum-chord-error" maximum-chord-error)
  (unless (and (finite-real? maximum-turn-angle)
               (<= 0 maximum-turn-angle (acos -1)))
    (raise-arguments-error 'streamline-sample-policy3d
                           "turn angle in the closed interval [0, pi]"
                           "maximum-turn-angle" maximum-turn-angle))
  (check-positive 'streamline-sample-policy3d
                  "maximum-segment-length" maximum-segment-length)
  (check-positive 'streamline-sample-policy3d
                  "minimum-segment-length" minimum-segment-length)
  (when (> minimum-segment-length maximum-segment-length)
    (raise-arguments-error 'streamline-sample-policy3d
                           "minimum segment length no greater than maximum segment length"
                           "minimum-segment-length" minimum-segment-length
                           "maximum-segment-length" maximum-segment-length))
  (streamline-sample-policy3d-value maximum-chord-error maximum-turn-angle
                                    maximum-segment-length minimum-segment-length))

(define streamline-sample-policy3d? streamline-sample-policy3d-value?)
(define (check-streamline-sample-policy3d who value)
  (unless (streamline-sample-policy3d? value)
    (raise-argument-error who "streamline-sample-policy3d?" value)))
(define (streamline-sample-policy3d-maximum-chord-error value)
  (check-streamline-sample-policy3d 'streamline-sample-policy3d-maximum-chord-error value)
  (streamline-sample-policy3d-value-maximum-chord-error value))
(define (streamline-sample-policy3d-maximum-turn-angle value)
  (check-streamline-sample-policy3d 'streamline-sample-policy3d-maximum-turn-angle value)
  (streamline-sample-policy3d-value-maximum-turn-angle value))
(define (streamline-sample-policy3d-maximum-segment-length value)
  (check-streamline-sample-policy3d 'streamline-sample-policy3d-maximum-segment-length value)
  (streamline-sample-policy3d-value-maximum-segment-length value))
(define (streamline-sample-policy3d-minimum-segment-length value)
  (check-streamline-sample-policy3d 'streamline-sample-policy3d-minimum-segment-length value)
  (streamline-sample-policy3d-value-minimum-segment-length value))

;; Branch data is intentionally a small immutable summary. It reveals the
;; two sides of a bidirectional integration without retaining an author field
;; or mutable solver state.
(struct streamline-branch-diagnostics3d
  (direction time-range segment-count termination)
  #:transparent)
(struct streamline-diagnostics3d
  (forward backward field-evaluations curve-sample-count total-arc-length
           termination-reasons seed-index)
  #:transparent)
(struct prepared-streamline3d-value
  (seed direction parameterization trajectory curve-samples diagnostics)
  #:transparent)

(define prepared-streamline3d? prepared-streamline3d-value?)
(define (check-prepared-streamline3d who value)
  (unless (prepared-streamline3d? value)
    (raise-argument-error who "prepared-streamline3d?" value)))
(define (prepared-streamline3d-seed value)
  (check-prepared-streamline3d 'prepared-streamline3d-seed value)
  (prepared-streamline3d-value-seed value))
(define (prepared-streamline3d-direction value)
  (check-prepared-streamline3d 'prepared-streamline3d-direction value)
  (prepared-streamline3d-value-direction value))
(define (prepared-streamline3d-parameterization value)
  (check-prepared-streamline3d 'prepared-streamline3d-parameterization value)
  (prepared-streamline3d-value-parameterization value))
(define (prepared-streamline3d-trajectory value)
  (check-prepared-streamline3d 'prepared-streamline3d-trajectory value)
  (prepared-streamline3d-value-trajectory value))
(define (prepared-streamline3d-curve-samples value)
  (check-prepared-streamline3d 'prepared-streamline3d-curve-samples value)
  (prepared-streamline3d-value-curve-samples value))
(define (prepared-streamline3d-diagnostics value)
  (check-prepared-streamline3d 'prepared-streamline3d-diagnostics value)
  (prepared-streamline3d-value-diagnostics value))
(define (prepared-streamline3d-seed-index value)
  (streamline-diagnostics3d-seed-index (prepared-streamline3d-diagnostics value)))

(define (check-streamline-parameterization who value)
  (unless (memq value '(time arc-length))
    (raise-argument-error who "'time or 'arc-length" value)))

(define (normalize-streamline-termination3d who termination)
  (cond [(not termination) (trajectory-termination3d #:time-limit 8)]
        [(trajectory-termination3d? termination) termination]
        [else (raise-argument-error who "#f or trajectory-termination3d?" termination)]))

(define (arc-length-streamline-termination3d termination)
  ;; A normalized field has no direction at an equilibrium.  Make that an
  ;; explicit zero-speed endpoint unless the author supplied a stricter or
  ;; looser threshold already.
  (if (trajectory-termination3d-minimum-speed termination)
      termination
      (trajectory-termination3d
       #:time-limit (trajectory-termination3d-time-limit termination)
       #:arc-length-limit (trajectory-termination3d-arc-length-limit termination)
       #:bounds (trajectory-termination3d-bounds termination)
       #:minimum-speed 0
       #:maximum-steps (trajectory-termination3d-maximum-steps termination)
       #:events (trajectory-termination3d-events termination)
       #:on-field-error (trajectory-termination3d-on-field-error termination))))

(define (streamline-horizon3d termination)
  ;; A supplied policy without a time budget may stop on bounds, an arc budget,
  ;; an event, or speed. Eight parameter units are the deterministic finite
  ;; safety horizon if none of those does.
  (or (trajectory-termination3d-time-limit termination) 8))

(define (streamline-field3d who field parameterization)
  (define normalized (normalize-ode-field3d who field))
  (case parameterization
    [(time) normalized]
    [else
     (unless (ode-field3d-autonomous? normalized)
       (raise-arguments-error who "arc-length streamlines require an autonomous field"
                              "field" field))
     (ode-field3d
      (lambda (x y z)
        (define derivative (call-field3d normalized 0 (vec3 x y z)))
        (define speed (vec3-length derivative))
        (if (zero? speed) origin3 (vec3-scale (/ 1 speed) derivative)))
      #:cache-key (list 'arc-length-streamline (ode-field3d-cache-key normalized)))]))

(define (streamline-turn-angle3d first second)
  (define first-length (vec3-length first))
  (define second-length (vec3-length second))
  (if (or (zero? first-length) (zero? second-length))
      0
      (acos (max -1 (min 1 (/ (vec3-dot first second)
                               (* first-length second-length)))))))

(define (streamline-segment-samples3d trajectory policy first-time last-time)
  (define first-position (ode-trajectory3d-position trajectory first-time))
  (define last-position (ode-trajectory3d-position trajectory last-time))
  (let loop ([left-time first-time] [left-position first-position]
             [right-time last-time] [right-position last-position] [depth 0])
    (define chord-length (vec3-distance left-position right-position))
    (define middle-time (/ (+ left-time right-time) 2))
    (define middle-position (ode-trajectory3d-position trajectory middle-time))
    (define chord-error (vec3-distance middle-position
                                     (vec3-lerp left-position right-position 1/2)))
    (define turn-angle
      (streamline-turn-angle3d
       (ode-trajectory3d-derivative trajectory left-time)
       (ode-trajectory3d-derivative trajectory right-time)))
    (define subdivide?
      (and (< depth 48)
           (> chord-length (streamline-sample-policy3d-minimum-segment-length policy))
           (or (> chord-length (streamline-sample-policy3d-maximum-segment-length policy))
               (> chord-error (streamline-sample-policy3d-maximum-chord-error policy))
               (> turn-angle (streamline-sample-policy3d-maximum-turn-angle policy)))))
    (if (not subdivide?)
        (list left-position right-position)
        (append (drop-right (loop left-time left-position middle-time middle-position (add1 depth)) 1)
                (loop middle-time middle-position right-time right-position (add1 depth))))))

(define (streamline-resample3d trajectory policy)
  (define segments (prepared-trajectory3d-value-segments trajectory))
  (if (zero? (vector-length segments))
      (vector->immutable-vector
       (vector (ode-trajectory3d-position trajectory
                                          (car (ode-trajectory3d-time-range trajectory)))))
      (let ([samples
             (for/fold ([samples '()]) ([segment (in-vector segments)])
               (define next
                 (streamline-segment-samples3d trajectory policy
                                              (trajectory-segment3d-t0 segment)
                                              (trajectory-segment3d-t1 segment)))
               (if (null? samples) next (append samples (cdr next))))])
        (define distinct
          (for/fold ([reversed '()]) ([point (in-list samples)])
            (if (and (pair? reversed) (equal? point (car reversed)))
                reversed
                (cons point reversed))))
        (vector->immutable-vector (list->vector (reverse distinct))))))

(define (streamline-sample-length3d samples)
  (for/fold ([total 0]) ([index (in-range 1 (vector-length samples))])
    (+ total (vec3-distance (vector-ref samples (sub1 index))
                            (vector-ref samples index)))))

(define (streamline-branch-diagnostics3d-for trajectory direction)
  (define range (ode-trajectory3d-time-range trajectory))
  (define branch-range
    (case direction
      [(forward) (cons 0 (cdr range))]
      [else (cons (car range) 0)]))
  (define segments (prepared-trajectory3d-value-segments trajectory))
  (define segment-count
    (for/sum ([segment (in-vector segments)])
      (if (case direction
            [(forward) (>= (trajectory-segment3d-t0 segment) 0)]
            [else (<= (trajectory-segment3d-t1 segment) 0)])
          1 0)))
  (define termination
    (for/first ([hit (in-vector (ode-trajectory3d-termination trajectory))]
                #:when (case direction
                         [(forward) (>= (trajectory-termination-hit3d-time hit) 0)]
                         [else (<= (trajectory-termination-hit3d-time hit) 0)]))
      hit))
  (streamline-branch-diagnostics3d direction branch-range segment-count termination))

(define (prepare-streamline3d field seed
                              #:direction [direction 'forward]
                              #:parameterization [parameterization 'time]
                              #:solver [solver (adaptive-rk45-solver3d)]
                              #:termination [termination #f]
                              #:sample-policy [sample-policy (streamline-sample-policy3d)])
  (check-vec3 'prepare-streamline3d seed)
  (check-direction 'prepare-streamline3d direction)
  (check-streamline-parameterization 'prepare-streamline3d parameterization)
  (check-streamline-sample-policy3d 'prepare-streamline3d sample-policy)
  (define normalized-termination
    (normalize-streamline-termination3d 'prepare-streamline3d termination))
  (define effective-termination
    (if (eq? parameterization 'arc-length)
        (arc-length-streamline-termination3d normalized-termination)
        normalized-termination))
  (define horizon (streamline-horizon3d effective-termination))
  ;; Ask for a little more than an explicit time budget, so the trajectory
  ;; layer records that budget as the selected stopping policy rather than
  ;; treating an exactly equal request endpoint as ordinary completion.
  (define requested-horizon
    (if (trajectory-termination3d-time-limit effective-termination)
        (+ horizon (max 1 (/ horizon 2)))
        horizon))
  (define time-range
    (case direction
      [(forward) (cons 0 requested-horizon)]
      [(backward) (cons (- requested-horizon) 0)]
      [else (cons (- requested-horizon) requested-horizon)]))
  (define trajectory
    (prepare-ode-trajectory3d
     (streamline-field3d 'prepare-streamline3d field parameterization)
     seed #:time-range time-range #:solver solver #:termination effective-termination))
  (define samples (streamline-resample3d trajectory sample-policy))
  (define seed-index
    (or (for/first ([point (in-vector samples)] [index (in-naturals)]
                    #:when (equal? point seed)) index)
        0))
  (define trajectory-diagnostics (ode-trajectory3d-diagnostics trajectory))
  (define termination-hits (ode-trajectory3d-termination trajectory))
  (define diagnostics
    (streamline-diagnostics3d
     (and (memq direction '(forward both))
          (streamline-branch-diagnostics3d-for trajectory 'forward))
     (and (memq direction '(backward both))
          (streamline-branch-diagnostics3d-for trajectory 'backward))
     (ode-trajectory3d-diagnostics-field-evaluations trajectory-diagnostics)
     (vector-length samples)
     (streamline-sample-length3d samples)
     (for/list ([hit (in-vector termination-hits)])
       (trajectory-termination-hit3d-reason hit))
     seed-index))
  (prepared-streamline3d-value seed direction parameterization trajectory samples diagnostics))

(define (adaptive-streamline3d prepared
                               #:id id
                               #:style [style (stroke3d #:color "royalblue" #:width 2)]
                               #:opacity [opacity 1])
  (check-prepared-streamline3d 'adaptive-streamline3d prepared)
  (check-symbol 'adaptive-streamline3d id)
  (unless (or (stroke3d? style) (tube-style3d? style))
    (raise-argument-error 'adaptive-streamline3d
                          "stroke3d? or tube-style3d? as #:style" style))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'adaptive-streamline3d "finite real in [0, 1]" opacity))
  (define samples (prepared-streamline3d-curve-samples prepared))
  (if (< (vector-length samples) 2)
      (group3d '() #:id id)
      (polyline3d (vector->list samples) #:id id #:style style #:opacity opacity)))

;; T-3's set layer retains a seed value, accepted immutable paths, and a
;; deterministic spatial hash separately from its eventual curve Visuals.
;; The hash is only an acceleration structure for separation tests: values are
;; inserted and queried in canonical seed/segment order, never enumerated.
(struct streamline-index-segment3d (start end owner) #:transparent)
(struct streamline-spatial-index3d
  (cell-size cells segment-count)
  #:transparent)
(struct streamline-set-diagnostics3d
  (seed-count accepted-seed-count rejected-seed-count termination-reasons
              field-evaluations total-curve-samples minimum-separation
              discarded-short-lines parallel-mode)
  #:transparent)
(struct prepared-streamline-set3d-value
  (seeds streamlines diagnostics spatial-index)
  #:transparent)

(define prepared-streamline-set3d? prepared-streamline-set3d-value?)
(define (check-prepared-streamline-set3d who value)
  (unless (prepared-streamline-set3d? value)
    (raise-argument-error who "prepared-streamline-set3d?" value)))
(define (prepared-streamline-set3d-seeds value)
  (check-prepared-streamline-set3d 'prepared-streamline-set3d-seeds value)
  (prepared-streamline-set3d-value-seeds value))
(define (prepared-streamline-set3d-streamlines value)
  (check-prepared-streamline-set3d 'prepared-streamline-set3d-streamlines value)
  (prepared-streamline-set3d-value-streamlines value))
(define (prepared-streamline-set3d-diagnostics value)
  (check-prepared-streamline-set3d 'prepared-streamline-set3d-diagnostics value)
  (prepared-streamline-set3d-value-diagnostics value))
(define (prepared-streamline-set3d-spatial-index value)
  (check-prepared-streamline-set3d 'prepared-streamline-set3d-spatial-index value)
  (prepared-streamline-set3d-value-spatial-index value))

(define (check-streamline-set-separation who separation)
  (unless (or (not separation)
              (and (finite-real? separation) (positive? separation)))
    (raise-argument-error who "#f or positive finite separation" separation)))

(define (streamline-spatial-index3d-empty separation)
  (streamline-spatial-index3d separation (hash) 0))

(define (streamline-index-cell3d index point)
  (define cell-size (streamline-spatial-index3d-cell-size index))
  (define (coordinate value)
    (inexact->exact (floor (/ value cell-size))))
  (vector (coordinate (vec3-x point))
          (coordinate (vec3-y point))
          (coordinate (vec3-z point))))

(define (streamline-index-cells-between3d index first last)
  (define first-cell (streamline-index-cell3d index first))
  (define last-cell (streamline-index-cell3d index last))
  (for*/list ([x (in-range (min (vector-ref first-cell 0) (vector-ref last-cell 0))
                             (add1 (max (vector-ref first-cell 0) (vector-ref last-cell 0))))]
              [y (in-range (min (vector-ref first-cell 1) (vector-ref last-cell 1))
                             (add1 (max (vector-ref first-cell 1) (vector-ref last-cell 1))))]
              [z (in-range (min (vector-ref first-cell 2) (vector-ref last-cell 2))
                             (add1 (max (vector-ref first-cell 2) (vector-ref last-cell 2))))])
    (vector x y z)))

(define (streamline-spatial-index3d-add index samples owner)
  (for/fold ([cells (streamline-spatial-index3d-cells index)]
             [segment-count (streamline-spatial-index3d-segment-count index)])
            ([sample-index (in-range 1 (vector-length samples))])
    (define segment
      (streamline-index-segment3d (vector-ref samples (sub1 sample-index))
                                  (vector-ref samples sample-index) owner))
    (values
     (for/fold ([next-cells cells])
               ([cell (in-list (streamline-index-cells-between3d
                                index
                                (streamline-index-segment3d-start segment)
                                (streamline-index-segment3d-end segment)))])
       (hash-set next-cells cell (cons segment (hash-ref next-cells cell '()))))
     (add1 segment-count))))

(define (streamline-spatial-index3d-add-streamline index line owner)
  (define samples (prepared-streamline3d-curve-samples line))
  (define-values (cells segment-count)
    (streamline-spatial-index3d-add index samples owner))
  (streamline-spatial-index3d (streamline-spatial-index3d-cell-size index)
                              cells segment-count))

(define (point-segment-distance3d point start end)
  (define delta (vec3- end start))
  (define magnitude-squared (vec3-dot delta delta))
  (if (zero? magnitude-squared)
      (vec3-distance point start)
      (let* ([raw-progress (/ (vec3-dot (vec3- point start) delta)
                              magnitude-squared)]
             [progress (max 0 (min 1 raw-progress))])
        (vec3-distance point (vec3-lerp start end progress)))))

(define (streamline-spatial-index3d-nearest-distance index point)
  (if (zero? (streamline-spatial-index3d-segment-count index))
      +inf.0
      (let ([cell (streamline-index-cell3d index point)])
        (for*/fold ([nearest +inf.0])
                   ([x (in-range (- (vector-ref cell 0) 1)
                                 (+ (vector-ref cell 0) 2))]
                    [y (in-range (- (vector-ref cell 1) 1)
                                 (+ (vector-ref cell 1) 2))]
                    [z (in-range (- (vector-ref cell 2) 1)
                                 (+ (vector-ref cell 2) 2))]
                    [segment (in-list
                              (hash-ref (streamline-spatial-index3d-cells index)
                                        (vector x y z) '()))])
          (min nearest
               (point-segment-distance3d point
                                         (streamline-index-segment3d-start segment)
                                         (streamline-index-segment3d-end segment)))))))

(define (termination-with-streamline-separation3d termination index separation)
  (define separation-event
    (ode-event3d
     #:id 'streamline-separation
     #:function
     (lambda (point)
       (define distance (streamline-spatial-index3d-nearest-distance index point))
       ;; The event protocol requires a finite scalar.  An empty nearby-cell
       ;; query proves only that the candidate is farther than the policy
       ;; radius, so a fixed positive value is the exact information needed.
       (if (finite-real? distance) (- distance separation) separation))))
  (trajectory-termination3d
   #:time-limit (trajectory-termination3d-time-limit termination)
   #:arc-length-limit (trajectory-termination3d-arc-length-limit termination)
   #:bounds (trajectory-termination3d-bounds termination)
   #:minimum-speed (trajectory-termination3d-minimum-speed termination)
   #:maximum-steps (trajectory-termination3d-maximum-steps termination)
   #:events (append (trajectory-termination3d-events termination)
                    (list separation-event))
   #:on-field-error (trajectory-termination3d-on-field-error termination)))

(define (streamline-set-termination-reasons3d lines)
  (apply append
         (for/list ([line (in-list lines)])
           (streamline-diagnostics3d-termination-reasons
            (prepared-streamline3d-diagnostics line)))))

;; prepare-streamlines3d : ode-field/procedure seed-set3d? ...
;;                         -> prepared-streamline-set3d?
;; Independent sets retain canonical seed order even when `#:parallel?` says
;; they may be scheduled in parallel by a future prepared-work executor.  This
;; pure implementation deliberately does not run arbitrary author procedures
;; concurrently.  Separation is intentionally ordered because each accepted
;; line becomes an event boundary for later candidates.
(define (prepare-streamlines3d field seeds
                               #:direction [direction 'forward]
                               #:parameterization [parameterization 'time]
                               #:solver [solver (adaptive-rk45-solver3d)]
                               #:termination [termination #f]
                               #:sample-policy [sample-policy (streamline-sample-policy3d)]
                               #:separation [separation #f]
                               #:parallel? [parallel? #t])
  (define normalized-field (normalize-ode-field3d 'prepare-streamlines3d field))
  (unless (seed-set3d? seeds)
    (raise-argument-error 'prepare-streamlines3d "seed-set3d?" seeds))
  (check-direction 'prepare-streamlines3d direction)
  (check-streamline-parameterization 'prepare-streamlines3d parameterization)
  (check-streamline-sample-policy3d 'prepare-streamlines3d sample-policy)
  (check-streamline-set-separation 'prepare-streamlines3d separation)
  (unless (boolean? parallel?)
    (raise-argument-error 'prepare-streamlines3d "boolean? as #:parallel?" parallel?))
  (define effective-termination
    (normalize-streamline-termination3d 'prepare-streamlines3d termination))
  (define seed-points (seed-set3d-points seeds))
  (define initial-index
    (and separation (streamline-spatial-index3d-empty separation)))
  (define-values (accepted rejected discarded index)
    (for/fold ([accepted '()] [rejected 0] [discarded 0] [index initial-index])
              ([seed (in-vector seed-points)] [seed-index (in-naturals)])
      (cond
        [(and separation
              (< (streamline-spatial-index3d-nearest-distance index seed) separation))
         (values accepted (add1 rejected) discarded index)]
        [else
         (define candidate-termination
           (if (and separation
                    (positive? (streamline-spatial-index3d-segment-count index)))
               (termination-with-streamline-separation3d effective-termination
                                                        index separation)
               effective-termination))
         (define line
           (prepare-streamline3d
            normalized-field seed #:direction direction #:parameterization parameterization
            #:solver solver #:termination candidate-termination
            #:sample-policy sample-policy))
         (if (< (vector-length (prepared-streamline3d-curve-samples line)) 2)
             (values accepted (add1 rejected) (add1 discarded) index)
             (values (append accepted (list line)) rejected discarded
                     (if separation
                         (streamline-spatial-index3d-add-streamline index line seed-index)
                         index)))])))
  (define diagnostics
    (streamline-set-diagnostics3d
     (vector-length seed-points) (length accepted) rejected
     (streamline-set-termination-reasons3d accepted)
     (for/sum ([line (in-list accepted)])
       (streamline-diagnostics3d-field-evaluations
        (prepared-streamline3d-diagnostics line)))
     (for/sum ([line (in-list accepted)])
       (streamline-diagnostics3d-curve-sample-count
        (prepared-streamline3d-diagnostics line)))
     separation discarded
     (cond [separation 'ordered-separation]
           [parallel? 'independent]
           [else 'serial])))
  (prepared-streamline-set3d-value
   seeds (vector->immutable-vector (list->vector accepted)) diagnostics index))

(define (adaptive-streamline-set3d prepared
                                   #:id id
                                   #:style [style (stroke3d #:color "royalblue" #:width 2)]
                                   #:opacity [opacity 1])
  (check-prepared-streamline-set3d 'adaptive-streamline-set3d prepared)
  (check-symbol 'adaptive-streamline-set3d id)
  (group3d
   (for/list ([line (in-vector (prepared-streamline-set3d-streamlines prepared))]
              [index (in-naturals)])
     (adaptive-streamline3d line #:id (child-id3d id index)
                            #:style style #:opacity opacity))
   #:id id))

;; A Poincare hit is immutable extracted data.  It keeps the dense event-hit
;; record that located the crossing but not the plane event procedure itself.
(struct poincare-hit3d
  (trajectory-id crossing-index time point direction source-event)
  #:transparent)

(define (check-poincare-direction3d who value)
  (unless (memq value '(any positive negative))
    (raise-argument-error who "'any, 'positive, or 'negative" value)))

(define (check-poincare-tangent-policy3d who value)
  (unless (memq value '(ignore include))
    (raise-argument-error who "'ignore or 'include" value)))

(define (check-poincare-tolerance3d who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite tolerance" name value)))

(define (poincare-direction3d event-direction)
  (case event-direction
    [(increasing) 'positive]
    [(decreasing) 'negative]
    [else 'tangent]))

(define (poincare-direction-allowed? requested actual tangent-policy)
  (cond [(eq? actual 'tangent) (eq? tangent-policy 'include)]
        [(eq? requested 'any) #t]
        [else (eq? requested actual)]))

(define (poincare-section3d trajectory plane
                            #:trajectory-id [trajectory-id 'trajectory]
                            #:direction [direction 'any]
                            #:tolerance [tolerance 1e-8]
                            #:deduplicate-time [deduplicate-time tolerance]
                            #:tangent-policy [tangent-policy 'ignore])
  (unless (prepared-trajectory3d? trajectory)
    (raise-argument-error 'poincare-section3d "prepared-trajectory3d?" trajectory))
  (unless (plane3? plane)
    (raise-argument-error 'poincare-section3d "plane3?" plane))
  (check-symbol 'poincare-section3d trajectory-id)
  (check-poincare-direction3d 'poincare-section3d direction)
  (check-poincare-tolerance3d 'poincare-section3d "tolerance" tolerance)
  (check-poincare-tolerance3d 'poincare-section3d "deduplicate-time" deduplicate-time)
  (check-poincare-tangent-policy3d 'poincare-section3d tangent-policy)
  (define plane-event
    (ode-event3d
     #:id 'poincare-plane
     #:function
     (lambda (point)
       (vec3-dot (vec3- point (plane3-point plane)) (plane3-normal plane)))
     #:value-tolerance tolerance #:time-tolerance deduplicate-time))
  ;; Reuse the T1 dense root evaluator.  It reads only retained nodes and
  ;; Hermite segments; calling this query cannot invoke the author field.
  (define raw-hits
    (dense-event-hits3d
     (list plane-event)
     (prepared-trajectory3d-value-nodes trajectory)
     (prepared-trajectory3d-value-segments trajectory)))
  ;; Keep the accepted hit list in physical-time order while explicitly
  ;; suppressing roots shared by neighbouring dense segments.
  (define accepted-hits
    (let loop ([remaining raw-hits] [last-time #f] [reversed '()])
      (cond [(null? remaining) (reverse reversed)]
            [else
             (define hit (car remaining))
             (define actual-direction (poincare-direction3d (ode-event-hit3d-direction hit)))
             (define duplicate?
               (and last-time
                    (<= (abs (- (ode-event-hit3d-time hit) last-time)) deduplicate-time)))
             (if (or duplicate?
                     (not (poincare-direction-allowed? direction actual-direction tangent-policy)))
                 (loop (cdr remaining) last-time reversed)
                 (loop (cdr remaining) (ode-event-hit3d-time hit) (cons hit reversed)))])))
  (vector->immutable-vector
   (list->vector
    (for/list ([hit (in-list accepted-hits)] [index (in-naturals)])
      (poincare-hit3d trajectory-id index (ode-event-hit3d-time hit)
                      (ode-event-hit3d-position hit)
                      (poincare-direction3d (ode-event-hit3d-direction hit)) hit)))))

(define (poincare-hit3d-plane-coordinates hit plane)
  (unless (poincare-hit3d? hit)
    (raise-argument-error 'poincare-hit3d-plane-coordinates "poincare-hit3d?" hit))
  (unless (plane3? plane)
    (raise-argument-error 'poincare-hit3d-plane-coordinates "plane3?" plane))
  (plane-basis3d-project (plane3d-basis plane) (poincare-hit3d-point hit)))

(define (poincare-hits3d hits
                         #:id id
                         #:style [style (point-style3d #:size 9 #:color "gold")])
  (unless (or (list? hits) (vector? hits))
    (raise-argument-error 'poincare-hits3d "list or vector of poincare-hit3d? values" hits))
  (define normalized-hits (if (vector? hits) (vector->list hits) hits))
  (for ([hit (in-list normalized-hits)])
    (unless (poincare-hit3d? hit)
      (raise-argument-error 'poincare-hits3d "list or vector of poincare-hit3d? values" hits)))
  (check-symbol 'poincare-hits3d id)
  (unless (point-style3d? style)
    (raise-argument-error 'poincare-hits3d "point-style3d? as #:style" style))
  (group3d
   (for/list ([hit (in-list normalized-hits)] [index (in-naturals)])
     (point3d (poincare-hit3d-point hit) #:id (child-id3d id index) #:style style))
   #:id id))

;; A return map has no implied global domain: each accepted seed retains its
;; first/second crossing independently, and a missing crossing stays #f in the
;; same canonical vector slot rather than being silently removed.
(struct prepared-poincare-map3d
  (plane seeds trajectories first-hits second-hits pairs diagnostics)
  #:transparent)

(define (prepare-poincare-map3d field plane seeds
                                #:direction [direction 'any]
                                #:tolerance [tolerance 1e-8]
                                #:deduplicate-time [deduplicate-time tolerance]
                                #:tangent-policy [tangent-policy 'ignore]
                                #:streamline-direction [streamline-direction 'forward]
                                #:parameterization [parameterization 'time]
                                #:solver [solver (adaptive-rk45-solver3d)]
                                #:termination [termination #f]
                                #:sample-policy [sample-policy (streamline-sample-policy3d)]
                                #:separation [separation #f]
                                #:parallel? [parallel? #t])
  (unless (plane3? plane)
    (raise-argument-error 'prepare-poincare-map3d "plane3?" plane))
  (unless (seed-set3d? seeds)
    (raise-argument-error 'prepare-poincare-map3d "seed-set3d?" seeds))
  (check-poincare-direction3d 'prepare-poincare-map3d direction)
  (check-poincare-tolerance3d 'prepare-poincare-map3d "tolerance" tolerance)
  (check-poincare-tolerance3d 'prepare-poincare-map3d "deduplicate-time" deduplicate-time)
  (check-poincare-tangent-policy3d 'prepare-poincare-map3d tangent-policy)
  (check-direction 'prepare-poincare-map3d streamline-direction)
  (check-streamline-parameterization 'prepare-poincare-map3d parameterization)
  (check-streamline-sample-policy3d 'prepare-poincare-map3d sample-policy)
  (check-streamline-set-separation 'prepare-poincare-map3d separation)
  (unless (boolean? parallel?)
    (raise-argument-error 'prepare-poincare-map3d "boolean? as #:parallel?" parallel?))
  ;; A return-map record needs one slot for every declared seed, including an
  ;; equilibrium or otherwise short trajectory with no first return.  Ordered
  ;; separation intentionally drops seeds, so it is not a coherent map domain.
  (when separation
    (raise-arguments-error 'prepare-poincare-map3d
                           "Poincare maps retain every declared seed; use #:separation #f"
                           "separation" separation))
  (define lines
    (for/list ([seed (in-vector (seed-set3d-points seeds))])
      (prepare-streamline3d
       field seed #:direction streamline-direction #:parameterization parameterization
       #:solver solver #:termination termination #:sample-policy sample-policy)))
  (define trajectories
    (vector->immutable-vector
     (list->vector
      (for/list ([line (in-list lines)])
        (prepared-streamline3d-trajectory line)))))
  (define hit-vectors
    (for/list ([trajectory (in-vector trajectories)] [index (in-naturals)])
      (poincare-section3d
       trajectory plane #:trajectory-id (string->symbol (format "seed-~a" index))
       #:direction direction #:tolerance tolerance #:deduplicate-time deduplicate-time
       #:tangent-policy tangent-policy)))
  (define first-hits
    (vector->immutable-vector
     (list->vector
      (for/list ([hits (in-list hit-vectors)])
        (and (positive? (vector-length hits)) (vector-ref hits 0))))))
  (define second-hits
    (vector->immutable-vector
     (list->vector
      (for/list ([hits (in-list hit-vectors)])
        (and (> (vector-length hits) 1) (vector-ref hits 1))))))
  (define pairs
    (vector->immutable-vector
     (list->vector
      (for/list ([first (in-vector first-hits)] [second (in-vector second-hits)])
        (and first second (cons first second))))))
  (prepared-poincare-map3d
   plane seeds trajectories first-hits second-hits pairs
   (hasheq 'accepted-seed-count (vector-length trajectories)
           'missing-first-hits
           (for/sum ([hit (in-vector first-hits)]) (if hit 0 1))
           'missing-second-hits
           (for/sum ([hit (in-vector second-hits)]) (if hit 0 1))
           'complete-pairs
           (for/sum ([pair (in-vector pairs)]) (if pair 1 0))
           'parallel-mode (if parallel? 'independent 'serial)
           'field-evaluations
           (for/sum ([line (in-list lines)])
             (streamline-diagnostics3d-field-evaluations
              (prepared-streamline3d-diagnostics line))))))

;; The old static spelling now routes through immutable preparation.  Its
;; familiar step and count keywords select a fixed solver and finite horizon.
(define (streamline3d field seed
                      #:id id
                      #:direction [direction 'both]
                      #:step-size [step-size 1/20]
                      #:steps [steps 120]
                      #:style [style (stroke3d #:color "royalblue" #:width 2)]
                      #:opacity [opacity 1])
  (check-positive 'streamline3d "step-size" step-size)
  (check-positive-integer 'streamline3d "steps" steps)
  (adaptive-streamline3d
   (prepare-streamline3d
    field seed #:direction direction
    #:solver (fixed-rk4-solver3d #:step-size step-size)
    #:termination (trajectory-termination3d #:time-limit (* steps step-size)))
   #:id id #:style style #:opacity opacity))

(define (streamlines3d field seeds
                       #:id id
                       #:direction [direction 'both]
                       #:step-size [step-size 1/20]
                       #:steps [steps 120]
                       #:style [style (stroke3d #:color "royalblue" #:width 2)]
                       #:opacity [opacity 1])
  (check-field3d 'streamlines3d field)
  (unless (list? seeds) (raise-argument-error 'streamlines3d "list?" seeds))
  (for ([seed (in-list seeds)]) (check-vec3 'streamlines3d seed))
  (check-symbol 'streamlines3d id)
  (group3d
   (for/list ([seed (in-list seeds)] [index (in-naturals)])
     (streamline3d field seed #:id (child-id3d id index)
                   #:direction direction #:step-size step-size #:steps steps
                   #:style style #:opacity opacity))
   #:id id))

; vector-field3d : procedure? ... -> group3d?
;; Samples one explicit, deterministic rectangular grid.  `#:seed-order`
;; controls child order (one of 'xyz, 'xzy, 'yxz, 'yzx, 'zxy, or 'zyx), so
;; equal input fields produce equal spatial trees independently of hashing.
(define (vector-field3d field
                        #:id id
                        #:x-range [x-range '(-2 2)]
                        #:y-range [y-range '(-2 2)]
                        #:z-range [z-range '(-2 2)]
                        #:x-count [x-count 5]
                        #:y-count [y-count 5]
                        #:z-count [z-count 5]
                        #:normalize? [normalize? #f]
                        #:length-range [length-range #f]
                        #:color-by-magnitude? [color-by-magnitude? #f]
                        #:seed-order [seed-order 'xyz]
                        #:scale [scale 1/4]
                        #:shaft-style [shaft-style (stroke3d #:color "royalblue" #:width 2)]
                        #:tip-style [tip-style (arrow-style3d #:color "royalblue")]
                        #:opacity [opacity 1])
  (check-field3d 'vector-field3d field)
  (check-symbol 'vector-field3d id)
  (for ([range (in-list (list x-range y-range z-range))]
        [name (in-list '(x-range y-range z-range))])
    (check-range 'vector-field3d name range))
  (for ([count (in-list (list x-count y-count z-count))]
        [name (in-list '(x-count y-count z-count))])
    (check-positive-integer 'vector-field3d (symbol->string name) count))
  (unless (boolean? normalize?)
    (raise-argument-error 'vector-field3d "boolean?" normalize?))
  (unless (boolean? color-by-magnitude?)
    (raise-argument-error 'vector-field3d "boolean?" color-by-magnitude?))
  (check-seed-order 'vector-field3d seed-order)
  (define checked-length-range
    (normalize-length-range 'vector-field3d length-range))
  (check-positive 'vector-field3d "scale" scale)
  (unless (stroke3d? shaft-style)
    (raise-argument-error 'vector-field3d "stroke3d? as #:shaft-style" shaft-style))
  (unless (arrow-style3d? tip-style)
    (raise-argument-error 'vector-field3d "arrow-style3d? as #:tip-style" tip-style))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'vector-field3d "finite real in [0, 1]" opacity))
  (define seeds
    (sort-seeds3d
     (for*/list ([x (in-list (sample-range x-range x-count))]
                 [y (in-list (sample-range y-range y-count))]
                 [z (in-list (sample-range z-range z-count))])
       (vec3 x y z))
     seed-order))
  (define nonzero
    (for/list ([seed (in-list seeds)]
               #:do [(define derivative (call-field3d field 0 seed))]
               #:when (positive? (vec3-length derivative)))
      (cons seed derivative)))
  (define magnitudes (map (lambda (entry) (vec3-length (cdr entry))) nonzero))
  (define minimum-magnitude (if (null? magnitudes) 0 (apply min magnitudes)))
  (define maximum-magnitude (if (null? magnitudes) 0 (apply max magnitudes)))
  (define (magnitude-progress magnitude)
    (if (= minimum-magnitude maximum-magnitude) 1/2
        (/ (- magnitude minimum-magnitude)
           (- maximum-magnitude minimum-magnitude))))
  (define (display-length magnitude)
    (cond
      [checked-length-range
       (+ (car checked-length-range)
          (* (magnitude-progress magnitude)
             (- (cdr checked-length-range) (car checked-length-range))))]
      [normalize? scale]
      [else (* scale magnitude)]))
  (define (display-color magnitude)
    (if color-by-magnitude?
        (rgba-color-lerp (color-spec->rgba-color "deepskyblue")
                         (color-spec->rgba-color "tomato")
                         (magnitude-progress magnitude))
        #f))
  (group3d
   (for/list ([entry (in-list nonzero)] [index (in-naturals)]
              #:do [(define seed (car entry))
                    (define derivative (cdr entry))
                    (define magnitude (vec3-length derivative))
                    (define length (display-length magnitude))]
              #:when (positive? length))
     (define direction (vec3-normalize derivative))
     (define color (display-color magnitude))
     (arrow3d seed (vec3+ seed (vec3-scale length direction))
              #:id (child-id3d id index)
              #:shaft-style (if color (stroke3d-with-color shaft-style color) shaft-style)
              #:tip-style (if color (arrow-style3d-with-color tip-style color) tip-style)
              #:opacity opacity))
   #:id id))


;;;
;;; Parameter-Driven Spatial Particles

;; Metadata is intentionally the explicit spatial-relation cache key.  This
;; lets the renderer's preparation pass discover raw semantic particles without
;; resolving their arbitrary author procedures in its worker threads.
(struct ode-flow-particle3d-metadata (trajectory phase-id tangent-length) #:transparent)
(struct ode3d-frame-sample (position derivative) #:transparent)

(define (flow-particle3d trajectory phase
                         #:id id
                         #:style [style (point-style3d #:size 10 #:color "tomato")]
                         #:opacity [opacity 1]
                         #:tangent-length [tangent-length #f]
                         #:tangent-shaft-style
                         [tangent-shaft-style (stroke3d #:color "darkorange" #:width 2)]
                         #:tangent-tip-style
                         [tangent-tip-style (arrow-style3d #:color "darkorange")])
  (check-trajectory3d 'flow-particle3d trajectory)
  (check-symbol 'flow-particle3d id)
  (unless (point-style3d? style)
    (raise-argument-error 'flow-particle3d "point-style3d? as #:style" style))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'flow-particle3d "finite real in [0, 1]" opacity))
  (when tangent-length (check-positive 'flow-particle3d "tangent-length" tangent-length))
  (when tangent-length
    (unless (stroke3d? tangent-shaft-style)
      (raise-argument-error 'flow-particle3d "stroke3d? as #:tangent-shaft-style"
                            tangent-shaft-style))
    (unless (arrow-style3d? tangent-tip-style)
      (raise-argument-error 'flow-particle3d "arrow-style3d? as #:tangent-tip-style"
                            tangent-tip-style)))
  (define phase-id (parameter-target-id phase 'flow-particle3d))
  (define metadata (ode-flow-particle3d-metadata trajectory phase-id tangent-length))
  (define template-time (car (ode-trajectory3d-time-range trajectory)))
  (define (make-particle time)
    (define sample (ode3d-frame-sample-ref metadata time))
    (define position
      (if sample (ode3d-frame-sample-position sample)
          (ode-trajectory3d-position trajectory time)))
    (cond
      [(not tangent-length)
       (point3d position #:id id #:style style #:opacity opacity)]
      [else
       (define derivative
         (or (and sample (ode3d-frame-sample-derivative sample))
             (ode-trajectory3d-derivative trajectory time)))
       (define has-tangent? (positive? (vec3-length derivative)))
       (define direction
         ;; `arrow3d` deliberately rejects a degenerate segment.  Retain the
         ;; stable relation shape at an equilibrium, but make that placeholder
         ;; invisible instead of falsely depicting an arbitrary +x tangent.
         (if has-tangent? (vec3-normalize derivative) x-axis3))
       (group3d
        (list (point3d position #:id 'marker #:style style #:opacity opacity)
              (arrow3d position
                       (vec3+ position (vec3-scale tangent-length direction))
                       #:id 'tangent
                       #:shaft-style tangent-shaft-style
                       #:tip-style tangent-tip-style
                       #:opacity (if has-tangent? opacity 0)))
        #:id id)]))
  (spatial-relation
   (make-particle template-time)
   #:depends-on (list (spatial-value-dependency phase-id))
   #:cache-key metadata
   (lambda (context ignored-template)
     (define time (spatial-relation-context-value-ref context phase-id))
     (unless (finite-real? time)
       (raise-arguments-error
        'flow-particle3d "the phase parameter must hold a finite real ODE time"
        "phase-id" phase-id "value" time))
     (make-particle time))))

; flow-cloud3d : (listof ode-trajectory3d?) parameter #:id symbol? ... -> group3d?
;; A cloud shares a time parameter while retaining one stable relation ID per
;; prepared seed.  Its children are ordinary flow-particle3d relations, so the
;; same preparation pass handles both a one-particle and a cloud rendering.
(define (flow-cloud3d trajectories phase
                      #:id id
                      #:style [style (point-style3d #:size 10 #:color "tomato")]
                      #:opacity [opacity 1])
  (unless (list? trajectories)
    (raise-argument-error 'flow-cloud3d "list?" trajectories))
  (for ([trajectory (in-list trajectories)])
    (check-trajectory3d 'flow-cloud3d trajectory))
  (check-symbol 'flow-cloud3d id)
  (group3d
   (for/list ([trajectory (in-list trajectories)] [index (in-naturals)])
     (flow-particle3d trajectory phase #:id (child-id3d id index)
                      #:style style #:opacity opacity))
   #:id id))


;;;
;;; Batch Frame Preparation

;; Like the established 2D flow preparation, these dynamic samples are built
;; before parallel PNG workers are launched.  Dense prepared trajectories read
;; only their frozen segment table here; no later render phase invokes the
;; author's field.
(define current-ode3d-frame-samples (make-parameter #f))

;; Avoids duplicate direct-frame preparation when a parallel PNG or isolated
;; preview worker has already installed its immutable sample table.
(define (ode3d-frame-samples-active?)
  (and (current-ode3d-frame-samples) #t))

(define (call-with-ode3d-frame-samples samples thunk)
  (unless (hash? samples)
    (raise-argument-error 'call-with-ode3d-frame-samples "hash?" samples))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-ode3d-frame-samples "procedure accepting zero arguments" thunk))
  (parameterize ([current-ode3d-frame-samples samples]) (thunk)))

(define (prepare-ode3d-frame-samples states)
  (unless (and (list? states) (andmap scene-state? states))
    (raise-argument-error 'prepare-ode3d-frame-samples "list of scene-state? values" states))
  (define times-by-metadata (make-hasheq))
  (for ([state (in-list states)])
    (for ([metadata
           (in-list
            (append-map flow-particle3d-metadata-in-visual
                        (scene-state-visuals-in-drawing-order state)))])
      (define time
        (scene-state-value-ref state (ode-flow-particle3d-metadata-phase-id metadata)))
      (unless (finite-real? time)
        (raise-arguments-error
         'prepare-ode3d-frame-samples
         "a prepared spatial flow particle phase must hold a finite real ODE time"
         "phase-id" (ode-flow-particle3d-metadata-phase-id metadata)
         "value" time))
      (define time-set (hash-ref times-by-metadata metadata #f))
      (unless time-set
        (set! time-set (make-hash))
        (hash-set! times-by-metadata metadata time-set))
      (hash-set! time-set time #t)))
  (for/fold ([samples (hasheq)]) ([(metadata time-set) (in-hash times-by-metadata)])
    (hash-set samples metadata
              (for/fold ([positions (hash)]) ([time (in-hash-keys time-set)])
                (define trajectory (ode-flow-particle3d-metadata-trajectory metadata))
                (define position (ode-trajectory3d-position trajectory time))
                (define derivative
                  (and (ode-flow-particle3d-metadata-tangent-length metadata)
                       (ode-trajectory3d-derivative trajectory time)))
                (hash-set positions time (ode3d-frame-sample position derivative))))))

(define (ode3d-frame-sample-ref metadata time)
  (define all-samples (current-ode3d-frame-samples))
  (and all-samples
       (let ([particle-samples (hash-ref all-samples metadata #f)])
         (and particle-samples
              (hash-ref particle-samples time #f)))))

(define (flow-particle3d-metadata-in-visual visual)
  (cond
    [(view3d? visual)
     (append-map flow-particle3d-metadata-in-spatial (view3d-children visual))]
    [(group-visual? visual)
     (append-map flow-particle3d-metadata-in-visual (group-visual-children visual))]
    [else '()]))

(define (flow-particle3d-metadata-in-spatial spatial)
  (append
   (if (and (spatial-relation? spatial)
            (ode-flow-particle3d-metadata?
             (spatial-relation-cache-key spatial)))
       (list (spatial-relation-cache-key spatial))
       '())
   (if (spatial-container? spatial)
       (append-map flow-particle3d-metadata-in-spatial
                   (map spatial-child-visual (spatial-child-entries spatial)))
       '())))


;;;
;;; Local Numerical and Validation Helpers

(define (rk4-step3d field time point step)
  (ode-state-space-rk4-step
   vec3-ode-state-space
   (lambda (field-time field-point) (call-field3d field field-time field-point))
   time point step))

(define (call-trajectory-field3d trajectory time position)
  (if (prepared-trajectory3d? trajectory)
      (ode-trajectory3d-derivative trajectory time)
      (call-field3d
       (if (adaptive-ode-trajectory3d? trajectory)
           (adaptive-ode-trajectory3d-field trajectory)
           (fixed-ode-trajectory3d-field trajectory))
       time position)))

(define (call-field3d field time point [evaluation-count #f])
  (when evaluation-count
    (set-box! evaluation-count (add1 (unbox evaluation-count))))
  (define procedure
    (if (ode-field3d? field) (ode-field3d-procedure field) field))
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-ode-field3d-error
             time point
             (format "the 3D ODE field raised an exception: ~a"
                     (exn-message exception))))])
      (call-with-values
       (lambda ()
         (if (procedure-arity-includes? procedure 4)
             (procedure time (vec3-x point) (vec3-y point) (vec3-z point))
             (procedure (vec3-x point) (vec3-y point) (vec3-z point))))
       list)))
  (unless (= (length results) 1)
    (raise-ode-field3d-error
     time point
     (format "the 3D ODE field must return exactly one vec3; result count: ~a"
             (length results))))
  (define value (car results))
  (unless (vec3-finite? value)
    (raise-ode-field3d-error
     time point
     (format "the 3D ODE field must return a finite vec3; result: ~e" value)))
  value)

(define (raise-ode-field3d-error time point message)
  (raise
   (exn:fail:ode-field3d
    (format "prepare-ode-trajectory3d: ~a\n  time: ~e\n  point: ~e"
            message time point)
    (current-continuation-marks) time point)))

(define (whole-step-count time step-size)
  (inexact->exact (floor (/ (abs time) step-size))))

(define (check-trajectory3d who trajectory)
  (unless (ode-trajectory3d? trajectory)
    (raise-argument-error who "ode-trajectory3d?" trajectory)))

(define (check-trajectory3d-time who trajectory time)
  (unless (finite-real? time) (raise-argument-error who "finite real?" time))
  (define range (ode-trajectory3d-time-range trajectory))
  (unless (<= (car range) time (cdr range))
    (raise-arguments-error who "time within the prepared trajectory range"
                           "time" time "time-range" range)))

(define (check-field3d who field)
  (unless (or (ode-field3d? field)
              (and (procedure? field)
                   (or (procedure-arity-includes? field 3)
                       (procedure-arity-includes? field 4))))
    (raise-argument-error who
                          "ode-field3d? or procedure accepting (x y z) or (time x y z)" field)))

(define (check-vec3 who value)
  (unless (vec3-finite? value) (raise-argument-error who "finite vec3?" value)))

(define (check-positive who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real" name value)))

(define (check-optional-nonnegative who name value)
  (when value
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error who "#f or nonnegative finite real" name value))))

(define (termination-time-range3d start-time end-time termination)
  (define limit (trajectory-termination3d-time-limit termination))
  (if (not limit)
      (values start-time end-time #f #f)
      (let ([limited-start (max (- limit) (min limit start-time))]
            [limited-end (max (- limit) (min limit end-time))])
        (values limited-start limited-end
                (not (= limited-start start-time))
                (not (= limited-end end-time))))))

(define (check-positive-integer who name value)
  (unless (exact-positive-integer? value)
    (raise-arguments-error who "positive exact integer" name value)))

(define (check-checkpoint-every who value)
  (check-positive-integer who "checkpoint-every" value))

(define (check-time-range who value)
  (unless (and (pair? value) (finite-real? (car value)) (finite-real? (cdr value)))
    (raise-argument-error who "pair of finite real times" value))
  (unless (<= (car value) (cdr value))
    (raise-arguments-error who "a nondecreasing time range" "time-range" value))
  (values (car value) (cdr value)))

(define (check-symbol who value)
  (unless (symbol? value) (raise-argument-error who "symbol?" value)))

(define (check-direction who value)
  (unless (memq value '(forward backward both))
    (raise-argument-error who "'forward, 'backward, or 'both" value)))

(define (check-range who name value)
  (unless (and (list? value) (= (length value) 2)
               (finite-real? (first value)) (finite-real? (second value))
               (<= (first value) (second value)))
    (raise-arguments-error who "two nondecreasing finite endpoints" name value)))

(define (normalize-length-range who value)
  (cond
    [(not value) #f]
    [(and (pair? value) (finite-real? (car value))
          (finite-real? (cdr value)) (<= 0 (car value) (cdr value)))
     value]
    [(and (list? value) (= (length value) 2)
          (finite-real? (first value)) (finite-real? (second value))
          (<= 0 (first value) (second value)))
     (cons (first value) (second value))]
    [else
     (raise-arguments-error who
                            "#f, a two-element list, or a pair of nonnegative increasing lengths"
                            "length-range" value)]))

(define (check-seed-order who value)
  (unless (memq value '(xyz xzy yxz yzx zxy zyx))
    (raise-argument-error who "one of 'xyz, 'xzy, 'yxz, 'yzx, 'zxy, or 'zyx" value)))

(define (sample-range range count)
  (define first-value (first range))
  (define last-value (second range))
  (if (= count 1)
      (list (/ (+ first-value last-value) 2))
      (for/list ([index (in-range count)])
        (+ first-value (* index (/ (- last-value first-value) (sub1 count)))))))

(define (sort-seeds3d seeds order)
  (define axes
    (case order
      [(xyz) '(x y z)] [(xzy) '(x z y)] [(yxz) '(y x z)]
      [(yzx) '(y z x)] [(zxy) '(z x y)] [else '(z y x)]))
  (define (component point axis)
    (case axis [(x) (vec3-x point)] [(y) (vec3-y point)] [else (vec3-z point)]))
  (define (less? first second remaining)
    (cond [(null? remaining) #f]
          [(< (component first (car remaining)) (component second (car remaining))) #t]
          [(> (component first (car remaining)) (component second (car remaining))) #f]
          [else (less? first second (cdr remaining))]))
  (sort seeds (lambda (first second) (less? first second axes))))

(define (child-id3d root index)
  (string->symbol (format "~a-~a" root index)))
