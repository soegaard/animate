#lang racket/base

;;;
;;; Deterministic ODE Flow and Streamlines
;;;

;; Integrates a two-dimensional autonomous or time-dependent field with
;; fixed-step RK4. Direct numerical queries remain history-free, while prepared
;; trajectories retain immutable canonical checkpoints so animation rendering
;; does not recompute a seed-to-time prefix for every frame.


;;;
;;; Imports and Exports

(require racket/list
         "axes-visual.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "ode-state-space.rkt"
         "parameter.rkt"
         "path-geometry.rkt"
         "point-marker-visual.rkt"
         "scene-state.rkt"
         "visual-model.rkt")

(provide ode-flow-position
         adaptive-rk45
         adaptive-rk45?
         adaptive-rk45-relative-tolerance
         adaptive-rk45-absolute-tolerance
         adaptive-rk45-initial-step
         adaptive-rk45-minimum-step
         adaptive-rk45-maximum-step
         adaptive-rk45-maximum-steps
         ode-event
         ode-event?
         ode-event-function
         ode-event-direction
         ode-event-name
         ode-trajectory?
         ode-trajectory-time-range
         ode-trajectory-step-size
         ode-trajectory-checkpoint-every
         ode-trajectory-solver
         ode-trajectory-diagnostics
         ode-trajectory-diagnostics?
         ode-trajectory-diagnostics-solver
         ode-trajectory-diagnostics-accepted-steps
         ode-trajectory-diagnostics-rejected-steps
         ode-trajectory-diagnostics-termination-time
         ode-trajectory-diagnostics-termination-reason
         ode-trajectory-diagnostics-maximum-error
         prepare-ode-trajectory
         ode-trajectory-position
         streamline-points
         streamline
         streamlines
         flow-particle
         prepare-ode-frame-samples
         call-with-ode-frame-samples
         ode-frame-samples-active?)


;;;
;;; Public Numerical API

;; ode-flow-position : field vec2? finite-real? #:step-size positive-finite-real?
;;                     -> vec2?
;; Returns the fixed-step fourth-order Runge--Kutta solution from time zero.
(define (ode-flow-position field seed time #:step-size [step-size 1/20])
  (check-field 'ode-flow-position field)
  (check-vec2 'ode-flow-position seed)
  (check-finite 'ode-flow-position "time" time)
  (check-positive 'ode-flow-position "step-size" step-size)
  (cond
    [(zero? time) seed]
    [else
     (define direction (if (positive? time) 1 -1))
     (define full-step (* direction step-size))
     (define whole-count (inexact->exact (floor (/ (abs time) step-size))))
     (define-values (state current-time)
       (for/fold ([point seed] [current-time 0])
                 ([ignored (in-range whole-count)])
         (values (rk4-step field current-time point full-step)
                 (+ current-time full-step))))
     (define remainder (- time (* whole-count full-step)))
     (if (zero? remainder)
         state
         (rk4-step field current-time state remainder))]))


;;;
;;; Prepared Fixed-Step Trajectories

;; ode-trajectory-value stores canonical fixed-RK4 checkpoints for one initial
;; value problem. The forward and backward vectors hold positions at step
;; indices 0, checkpoint-every, 2*checkpoint-every, ... from time zero. They
;; are immutable after construction, so lookup is independent of query order
;; and safe to share among renderer workers. The field may accept either
;; `(x y)` for an autonomous system or `(time x y)` for a non-autonomous one.
(struct ode-trajectory-value
  (field seed start-time end-time step-size checkpoint-every
         forward-checkpoints backward-checkpoints)
  #:transparent)

;; `adaptive-rk45` is immutable solver configuration. The solver uses the
;; Dormand--Prince embedded 5(4) pair with deterministic accept/reject rules.
(struct adaptive-rk45-value
  (relative-tolerance absolute-tolerance initial-step minimum-step maximum-step
                      maximum-steps)
  #:transparent)

;; adaptive-rk45 : [#:relative-tolerance positive-finite-real?]
;;                  [#:absolute-tolerance positive-finite-real?]
;;                  [#:initial-step positive-finite-real?]
;;                  [#:minimum-step positive-finite-real?]
;;                  [#:maximum-step positive-finite-real?]
;;                  [#:maximum-steps positive-exact-integer?]
;;                  -> adaptive-rk45?
(define (adaptive-rk45 #:relative-tolerance [relative-tolerance 1e-6]
                       #:absolute-tolerance [absolute-tolerance 1e-8]
                       #:initial-step [initial-step 1/10]
                       #:minimum-step [minimum-step 1e-8]
                       #:maximum-step [maximum-step 1]
                       #:maximum-steps [maximum-steps 100000])
  (check-positive 'adaptive-rk45 "relative-tolerance" relative-tolerance)
  (check-positive 'adaptive-rk45 "absolute-tolerance" absolute-tolerance)
  (check-positive 'adaptive-rk45 "initial-step" initial-step)
  (check-positive 'adaptive-rk45 "minimum-step" minimum-step)
  (check-positive 'adaptive-rk45 "maximum-step" maximum-step)
  (check-steps 'adaptive-rk45 maximum-steps)
  (unless (<= minimum-step initial-step maximum-step)
    (raise-arguments-error
     'adaptive-rk45
     "minimum-step <= initial-step <= maximum-step is required"
     "minimum-step" minimum-step
     "initial-step" initial-step
     "maximum-step" maximum-step))
  (adaptive-rk45-value relative-tolerance absolute-tolerance initial-step
                        minimum-step maximum-step maximum-steps))

(define (adaptive-rk45? value)
  (adaptive-rk45-value? value))
(define (adaptive-rk45-relative-tolerance value)
  (adaptive-rk45-value-relative-tolerance value))
(define (adaptive-rk45-absolute-tolerance value)
  (adaptive-rk45-value-absolute-tolerance value))
(define (adaptive-rk45-initial-step value)
  (adaptive-rk45-value-initial-step value))
(define (adaptive-rk45-minimum-step value)
  (adaptive-rk45-value-minimum-step value))
(define (adaptive-rk45-maximum-step value)
  (adaptive-rk45-value-maximum-step value))
(define (adaptive-rk45-maximum-steps value)
  (adaptive-rk45-value-maximum-steps value))

;; An event supplies a scalar whose sign crossing ends adaptive integration.
;; It accepts either `(x y)` or `(time x y)`, exactly like an ODE field.
(struct ode-event-value (function direction name)
  #:transparent)

(define (ode-event function #:direction [direction 'any] #:name [name 'event])
  (check-field 'ode-event function)
  (unless (memq direction '(any increasing decreasing))
    (raise-argument-error 'ode-event "'any, 'increasing, or 'decreasing"
                          direction))
  (unless (symbol? name)
    (raise-argument-error 'ode-event "symbol?" name))
  (ode-event-value function direction name))

(define (ode-event? value) (ode-event-value? value))
(define (ode-event-function value) (ode-event-value-function value))
(define (ode-event-direction value) (ode-event-value-direction value))
(define (ode-event-name value) (ode-event-value-name value))

;; Adaptive nodes retain endpoint derivatives so arbitrary-time lookup can use
;; deterministic cubic Hermite dense output without reinvoking the field.
(struct adaptive-ode-node (time position derivative)
  #:transparent)

(struct ode-trajectory-diagnostics-value
  (solver accepted-steps rejected-steps termination-time termination-reason
          maximum-error)
  #:transparent)

(define (ode-trajectory-diagnostics? value)
  (ode-trajectory-diagnostics-value? value))
(define (ode-trajectory-diagnostics-solver value)
  (ode-trajectory-diagnostics-value-solver value))
(define (ode-trajectory-diagnostics-accepted-steps value)
  (ode-trajectory-diagnostics-value-accepted-steps value))
(define (ode-trajectory-diagnostics-rejected-steps value)
  (ode-trajectory-diagnostics-value-rejected-steps value))
(define (ode-trajectory-diagnostics-termination-time value)
  (ode-trajectory-diagnostics-value-termination-time value))
(define (ode-trajectory-diagnostics-termination-reason value)
  (ode-trajectory-diagnostics-value-termination-reason value))
(define (ode-trajectory-diagnostics-maximum-error value)
  (ode-trajectory-diagnostics-value-maximum-error value))

(struct adaptive-ode-trajectory-value
  (field seed start-time end-time solver nodes diagnostics)
  #:transparent)

;; ode-trajectory? : any/c -> boolean?
(define (ode-trajectory? value)
  (or (ode-trajectory-value? value)
      (adaptive-ode-trajectory-value? value)))

;; ode-trajectory-time-range : ode-trajectory? -> pair?
;; Returns the closed supported range as (cons start-time end-time).
(define (ode-trajectory-time-range trajectory)
  (check-trajectory 'ode-trajectory-time-range trajectory)
  (if (adaptive-ode-trajectory-value? trajectory)
      (cons (adaptive-ode-trajectory-value-start-time trajectory)
            (adaptive-ode-trajectory-value-end-time trajectory))
      (cons (ode-trajectory-value-start-time trajectory)
            (ode-trajectory-value-end-time trajectory))))

;; ode-trajectory-step-size : ode-trajectory? -> positive-finite-real?
(define (ode-trajectory-step-size trajectory)
  (check-trajectory 'ode-trajectory-step-size trajectory)
  (if (adaptive-ode-trajectory-value? trajectory)
      #f
      (ode-trajectory-value-step-size trajectory)))

;; ode-trajectory-checkpoint-every : ode-trajectory? -> positive-exact-integer?
(define (ode-trajectory-checkpoint-every trajectory)
  (check-trajectory 'ode-trajectory-checkpoint-every trajectory)
  (if (adaptive-ode-trajectory-value? trajectory)
      #f
      (ode-trajectory-value-checkpoint-every trajectory)))

;; ode-trajectory-solver : ode-trajectory? -> (or/c 'fixed-rk4 adaptive-rk45?)
(define (ode-trajectory-solver trajectory)
  (check-trajectory 'ode-trajectory-solver trajectory)
  (if (adaptive-ode-trajectory-value? trajectory)
      (adaptive-ode-trajectory-value-solver trajectory)
      'fixed-rk4))

;; ode-trajectory-diagnostics : ode-trajectory? -> (or/c false/c ...)
;; Fixed RK4 keeps its established checkpoint representation and returns #f.
(define (ode-trajectory-diagnostics trajectory)
  (check-trajectory 'ode-trajectory-diagnostics trajectory)
  (and (adaptive-ode-trajectory-value? trajectory)
       (adaptive-ode-trajectory-value-diagnostics trajectory)))

;; prepare-ode-trajectory : field vec2? #:time-range (cons/c finite-real? finite-real?)
;;                          #:step-size positive-finite-real?
;;                          #:checkpoint-every positive-exact-integer?
;;                          -> ode-trajectory?
;; Prepares a bounded, immutable fixed-RK4 trajectory. Checkpoints are reached
;; only by the same canonical full steps that ode-flow-position would take from
;; the seed, preserving its numerical semantics while avoiding repeated prefix
;; integration for later queries.
(define (prepare-ode-trajectory field seed
                                #:time-range time-range
                                #:step-size [step-size 1/20]
                                #:checkpoint-every [checkpoint-every 16]
                                #:solver [solver #f]
                                #:event [event #f])
  (check-field 'prepare-ode-trajectory field)
  (check-vec2 'prepare-ode-trajectory seed)
  (check-positive 'prepare-ode-trajectory "step-size" step-size)
  (check-checkpoint-every 'prepare-ode-trajectory checkpoint-every)
  (define-values (start-time end-time)
    (check-time-range 'prepare-ode-trajectory time-range))
  (check-solver 'prepare-ode-trajectory solver)
  (check-event 'prepare-ode-trajectory event)
  (if solver
      (prepare-adaptive-trajectory field seed start-time end-time solver event)
      (begin
        (when event
          (raise-arguments-error
           'prepare-ode-trajectory
           "#:event requires an adaptive solver"
           "event" event))
        (ode-trajectory-value
         field seed start-time end-time step-size checkpoint-every
         (build-checkpoints field seed 1 step-size checkpoint-every
                            (max 0 end-time))
         (build-checkpoints field seed -1 step-size checkpoint-every
                            (max 0 (- start-time)))))))

;; ode-trajectory-position : ode-trajectory? finite-real? -> vec2?
;; Looks up one time in a prepared trajectory. The selected checkpoint is always
;; between time zero and the query; integration never reverses direction from a
;; later point. At most checkpoint-every - 1 full steps plus one remainder step
;; are needed after the constant-time checkpoint lookup.
(define (ode-trajectory-position trajectory time)
  (check-trajectory 'ode-trajectory-position trajectory)
  (check-trajectory-time 'ode-trajectory-position trajectory time)
  (if (adaptive-ode-trajectory-value? trajectory)
      (adaptive-trajectory-position trajectory time)
      (fixed-trajectory-position trajectory time)))

(define (fixed-trajectory-position trajectory time)
  (define field (ode-trajectory-value-field trajectory))
  (define-values (direction full-step checkpoint-index suffix-steps remainder)
    (trajectory-query-parts trajectory time))
  (define checkpoints
    (if (negative? direction)
        (ode-trajectory-value-backward-checkpoints trajectory)
        (ode-trajectory-value-forward-checkpoints trajectory)))
  (define checkpoint
    (vector-ref checkpoints checkpoint-index))
  (define checkpoint-time
    (* direction checkpoint-index
       (ode-trajectory-value-checkpoint-every trajectory)
       (ode-trajectory-value-step-size trajectory)))
  (define-values (state current-time)
    (for/fold ([point checkpoint] [current-time checkpoint-time])
              ([ignored (in-range suffix-steps)])
      (values (rk4-step field current-time point full-step)
              (+ current-time full-step))))
  (if (zero? remainder)
      state
      (rk4-step field current-time state remainder)))

;; trajectory-query-parts : ode-trajectory? finite-real?
;;                           -> (values -1-or-1 finite-real?
;;                                      exact-nonnegative-integer?
;;                                      exact-nonnegative-integer? finite-real?)
;; Decomposes a time exactly as ode-flow-position does: a direction, canonical
;; full step, checkpoint index, number of full steps after that checkpoint, and
;; the final (possibly zero) remainder step.
(define (trajectory-query-parts trajectory time)
  (define step-size (ode-trajectory-value-step-size trajectory))
  (define checkpoint-every
    (ode-trajectory-value-checkpoint-every trajectory))
  (define direction (if (negative? time) -1 1))
  (define full-step (* direction step-size))
  (define whole-count (whole-step-count time step-size))
  (define checkpoint-index (quotient whole-count checkpoint-every))
  (define checkpoint-step-count (* checkpoint-index checkpoint-every))
  (values direction
          full-step
          checkpoint-index
          (- whole-count checkpoint-step-count)
          (- time (* whole-count full-step))))

;; build-checkpoints : field vec2? -1-or-1 positive-finite-real?
;;                     positive-exact-integer? nonnegative-finite-real?
;;                     -> immutable-vectorof-vec2?
;; Builds every canonical stride checkpoint through the supplied nonnegative
;; time extent. The loop never accumulates a time coordinate, only integer step
;; counts, so inexact step values cannot move a checkpoint boundary.
(define (build-checkpoints field seed direction step-size checkpoint-every extent)
  (define full-count (whole-step-count extent step-size))
  (define checkpoint-count
    (add1 (quotient full-count checkpoint-every)))
  (define full-step (* direction step-size))
  (define (advance point start-time count)
    (for/fold ([state point] [current-time start-time])
              ([ignored (in-range count)])
      (values (rk4-step field current-time state full-step)
              (+ current-time full-step))))
  (define checkpoints
    (let loop ([checkpoint-index 0] [state seed] [reversed '()])
      (if (= checkpoint-index checkpoint-count)
          (reverse reversed)
          (let-values ([(next-state _next-time)
                        (if (= checkpoint-index (sub1 checkpoint-count))
                            (values state
                                    (* direction checkpoint-index
                                       checkpoint-every step-size))
                            (advance state
                                     (* direction checkpoint-index
                                        checkpoint-every step-size)
                                     checkpoint-every))])
            (loop (add1 checkpoint-index)
                  next-state
                  (cons state reversed))))))
  (vector->immutable-vector (list->vector checkpoints)))

;; whole-step-count : finite-real? positive-finite-real? -> exact-nonnegative-integer?
;; Mirrors ode-flow-position's canonical full-step decision exactly.
(define (whole-step-count time step-size)
  (inexact->exact (floor (/ (abs time) step-size))))


;;;
;;; Prepared Adaptive RK45 Trajectories

;; An adaptive trajectory stores accepted endpoint nodes in increasing time
;; order. Queries interpolate only stored values; unlike a direct fixed query,
;; they never run the author field after construction.

(define (prepare-adaptive-trajectory field seed start-time end-time solver event)
  (define-values (backward-nodes backward-diagnostics)
    (adaptive-node-series field seed 0 start-time solver event))
  (define-values (forward-nodes forward-diagnostics)
    (adaptive-node-series field seed 0 end-time solver event))
  ;; Backward integration visits 0, negative times, ...; reverse all but the
  ;; shared seed before joining it with forward nodes to obtain increasing time.
  (define nodes
    (append (reverse (cdr backward-nodes)) forward-nodes))
  (define start
    (adaptive-ode-node-time (car nodes)))
  (define end
    (adaptive-ode-node-time (last nodes)))
  (define termination
    (cond
      [(not (eq? (ode-trajectory-diagnostics-value-termination-reason
                  backward-diagnostics)
                 'time-range))
       backward-diagnostics]
      [(not (eq? (ode-trajectory-diagnostics-value-termination-reason
                  forward-diagnostics)
                 'time-range))
       forward-diagnostics]
      [else forward-diagnostics]))
  (adaptive-ode-trajectory-value
   field seed start end solver (vector->immutable-vector (list->vector nodes))
   (ode-trajectory-diagnostics-value
    'adaptive-rk45
    (+ (ode-trajectory-diagnostics-value-accepted-steps backward-diagnostics)
       (ode-trajectory-diagnostics-value-accepted-steps forward-diagnostics))
    (+ (ode-trajectory-diagnostics-value-rejected-steps backward-diagnostics)
       (ode-trajectory-diagnostics-value-rejected-steps forward-diagnostics))
    (ode-trajectory-diagnostics-value-termination-time termination)
    (ode-trajectory-diagnostics-value-termination-reason termination)
    (max (ode-trajectory-diagnostics-value-maximum-error backward-diagnostics)
         (ode-trajectory-diagnostics-value-maximum-error forward-diagnostics)))))

;; Integrates from `start-time` to `target-time`. The final node either reaches
;; the requested boundary or an event root located by dense interpolation.
(define (adaptive-node-series field seed start-time target-time solver event)
  (define direction
    (if (negative? (- target-time start-time)) -1 1))
  (define initial-derivative
    (call-field field start-time seed))
  (define initial-node
    (adaptive-ode-node start-time seed initial-derivative))
  (cond
    [(= start-time target-time)
     (values (list initial-node)
             (ode-trajectory-diagnostics-value
              'adaptive-rk45 0 0 start-time 'time-range 0))]
    [else
     (let loop ([current initial-node]
                [step (* direction (adaptive-rk45-value-initial-step solver))]
                [reverse-nodes (list initial-node)]
                [accepted 0]
                [rejected 0]
                [maximum-error 0])
       (when (>= (+ accepted rejected)
                 (adaptive-rk45-value-maximum-steps solver))
         (raise-arguments-error
          'prepare-ode-trajectory
          "adaptive solver exceeded maximum-steps"
          "maximum-steps" (adaptive-rk45-value-maximum-steps solver)
          "last-time" (adaptive-ode-node-time current)
          "target-time" target-time))
       (define remaining
         (- target-time (adaptive-ode-node-time current)))
       (define trial-step
         (* direction
            (min (abs remaining)
                 (adaptive-rk45-value-maximum-step solver)
                 (max (adaptive-rk45-value-minimum-step solver)
                      (abs step)))))
       (define-values (candidate endpoint-derivative error)
         (dormand-prince-step field
                              (adaptive-ode-node-time current)
                              (adaptive-ode-node-position current)
                              trial-step solver))
       (define next-maximum-error
         (max maximum-error error))
       (cond
         [(<= error 1)
          (define candidate-node
            (adaptive-ode-node (+ (adaptive-ode-node-time current) trial-step)
                               candidate endpoint-derivative))
          (define event-node
            (and event
                 (event-crossing-node field event current candidate-node)))
          (if event-node
              (values (reverse (cons event-node reverse-nodes))
                      (ode-trajectory-diagnostics-value
                       'adaptive-rk45 (add1 accepted) rejected
                       (adaptive-ode-node-time event-node)
                       (ode-event-value-name event)
                       next-maximum-error))
              (if (= (adaptive-ode-node-time candidate-node) target-time)
                  (values (reverse (cons candidate-node reverse-nodes))
                          (ode-trajectory-diagnostics-value
                           'adaptive-rk45 (add1 accepted) rejected target-time
                           'time-range next-maximum-error))
                  (loop candidate-node
                        (* direction
                           (adaptive-next-step-magnitude solver
                                                         (abs trial-step) error))
                        (cons candidate-node reverse-nodes)
                        (add1 accepted) rejected next-maximum-error)))]
         [else
          (when (<= (abs trial-step)
                    (adaptive-rk45-value-minimum-step solver))
            (raise-arguments-error
             'prepare-ode-trajectory
             "adaptive solver reached minimum-step before satisfying tolerance"
             "minimum-step" (adaptive-rk45-value-minimum-step solver)
             "error-ratio" error
             "time" (adaptive-ode-node-time current)))
          (loop current
                (* direction
                   (adaptive-rejected-step-magnitude solver
                                                     (abs trial-step) error))
                reverse-nodes accepted (add1 rejected) next-maximum-error)]))]))

;; Dormand--Prince 5(4), returned as the 5th-order endpoint, its derivative,
;; and a deterministic norm-relative embedded error.  The arithmetic lives in
;; ode-state-space.rkt, shared with the spatial vec3 implementation.
(define (dormand-prince-step field time point step solver)
  (ode-state-space-dormand-prince-step
   vec2-ode-state-space
   (lambda (field-time field-point) (call-field field field-time field-point))
   time point step
   (adaptive-rk45-value-relative-tolerance solver)
   (adaptive-rk45-value-absolute-tolerance solver)))

(define (weighted-sum terms)
  (ode-state-space-weighted-sum vec2-ode-state-space terms))

(define (embedded-error-ratio previous fifth fourth solver)
  (ode-state-space-embedded-error-ratio
   vec2-ode-state-space previous fifth fourth
   (adaptive-rk45-value-relative-tolerance solver)
   (adaptive-rk45-value-absolute-tolerance solver)))

(define (adaptive-next-step-magnitude solver old-step error)
  (min (adaptive-rk45-value-maximum-step solver)
       (max (adaptive-rk45-value-minimum-step solver)
            (* old-step
               (min 5
                    (max 1/5
                         (* 9/10
                            (if (zero? error)
                                5
                                (expt (/ 1 error) 1/5)))))))))

(define (adaptive-rejected-step-magnitude solver old-step error)
  (max (adaptive-rk45-value-minimum-step solver)
       (* old-step
          (min 1
               (max 1/10 (* 9/10 (expt (/ 1 error) 1/5)))))))

(define (event-crossing-node field event first second)
  (define first-value
    (call-event event (adaptive-ode-node-time first)
                (adaptive-ode-node-position first)))
  (define second-value
    (call-event event (adaptive-ode-node-time second)
                (adaptive-ode-node-position second)))
  (and (event-crosses? (ode-event-value-direction event)
                       first-value second-value)
       (locate-event-node field event first second first-value second-value)))

(define (event-crosses? direction first second)
  (case direction
    [(increasing) (and (< first 0) (>= second 0))]
    [(decreasing) (and (> first 0) (<= second 0))]
    [else (or (and (< first 0) (>= second 0))
              (and (> first 0) (<= second 0)))]))

;; Forty bisections make the deterministic dense event position much more
;; precise than the default adaptive tolerance without requiring another field
;; integration. The endpoint derivative is sampled once for later dense lookup.
(define (locate-event-node field event first second first-value second-value)
  (define-values (low-time low-value high-time high-value)
    (if (zero? first-value)
        (values (adaptive-ode-node-time first) first-value
                (adaptive-ode-node-time first) first-value)
        (values (adaptive-ode-node-time first) first-value
                (adaptive-ode-node-time second) second-value)))
  (define root-time
    (if (= low-time high-time)
        low-time
        (let loop ([low low-time] [low-value low-value]
                   [high high-time] [high-value high-value]
                   [remaining 40])
          (if (zero? remaining)
              (/ (+ low high) 2)
              (let* ([middle (/ (+ low high) 2)]
                     [position (interpolate-adaptive-nodes first second middle)]
                     [middle-value (call-event event middle position)])
                (if (or (zero? middle-value)
                        (event-crosses? (ode-event-value-direction event)
                                        low-value middle-value))
                    (loop low low-value middle middle-value (sub1 remaining))
                    (loop middle middle-value high high-value
                          (sub1 remaining))))))))
  (define root-position
    (interpolate-adaptive-nodes first second root-time))
  (adaptive-ode-node root-time root-position
                     (call-field field root-time root-position)))

(define (adaptive-trajectory-position trajectory time)
  (define nodes
    (adaptive-ode-trajectory-value-nodes trajectory))
  (define count (vector-length nodes))
  (let loop ([index 0])
    (define current (vector-ref nodes index))
    (cond
      [(= time (adaptive-ode-node-time current))
       (adaptive-ode-node-position current)]
      [(= index (sub1 count))
       (adaptive-ode-node-position current)]
      [else
       (define next (vector-ref nodes (add1 index)))
       (if (<= (adaptive-ode-node-time current) time
               (adaptive-ode-node-time next))
           (interpolate-adaptive-nodes current next time)
           (loop (add1 index)))])))

(define (interpolate-adaptive-nodes first second time)
  (define start-time (adaptive-ode-node-time first))
  (define step (- (adaptive-ode-node-time second) start-time))
  (cond
    [(zero? step) (adaptive-ode-node-position first)]
    [else
     (ode-state-space-hermite-interpolate
      vec2-ode-state-space
      (adaptive-ode-node-position first)
      (adaptive-ode-node-derivative first)
      (adaptive-ode-node-position second)
      (adaptive-ode-node-derivative second)
      step
      (/ (- time start-time) step))]))

;; streamline-points : field vec2? #:direction flow-direction?
;;                     #:step-size positive-finite-real? #:steps positive-integer?
;;                     -> (listof vec2?)
;; Produces a stable collection of coordinate-space ODE samples. `both` has one
;; shared seed point in the middle and never duplicates it.
(define (streamline-points field seed
                           #:direction [direction 'both]
                           #:step-size [step-size 1/20]
                           #:steps [steps 120])
  (check-field 'streamline-points field)
  (check-vec2 'streamline-points seed)
  (check-direction 'streamline-points direction)
  (check-positive 'streamline-points "step-size" step-size)
  (check-steps 'streamline-points steps)
  (define (at index)
    (ode-flow-position field seed (* index step-size) #:step-size step-size))
  (case direction
    [(forward)
     (for/list ([index (in-range 0 (add1 steps))])
       (at index))]
    [(backward)
     (for/list ([index (in-range steps -1 -1)])
       (at (- index)))]
    [(both)
     (append
      (for/list ([index (in-range steps 0 -1)])
        (at (- index)))
      (for/list ([index (in-range 0 (add1 steps))])
        (at index)))]))


;;;
;;; Streamline Visuals

;; streamline : axes-visual? field vec2? #:id symbol? ... -> path-visual?
;; Converts fixed numeric-coordinate samples through the supplied axes.
(define (streamline axes field seed
                    #:id id
                    #:direction [direction 'both]
                    #:step-size [step-size 1/20]
                    #:steps [steps 120]
                    #:opacity [opacity 1]
                    #:stroke [stroke "royalblue"]
                    #:stroke-width [stroke-width 2])
  (check-axes 'streamline axes)
  (unless (symbol? id)
    (raise-argument-error 'streamline "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error 'streamline "opacity?" opacity))
  (check-nonnegative 'streamline "stroke-width" stroke-width)
  (define coordinates
    (streamline-points field seed
                       #:direction direction
                       #:step-size step-size
                       #:steps steps))
  (make-world-path-visual
   (map (lambda (point)
          (axes-coordinates->point axes (vec2-x point) (vec2-y point)))
        coordinates)
   id opacity stroke stroke-width))

;; streamlines : axes-visual? field (listof vec2?) #:id symbol? ...
;;               -> group-visual?
;; Builds an ordinary group whose child IDs are deterministic `id-N` symbols.
(define (streamlines axes field seeds
                    #:id id
                    #:direction [direction 'both]
                    #:step-size [step-size 1/20]
                    #:steps [steps 120]
                    #:opacity [opacity 1]
                    #:stroke [stroke "royalblue"]
                    #:stroke-width [stroke-width 2])
  (check-axes 'streamlines axes)
  (check-field 'streamlines field)
  (unless (symbol? id)
    (raise-argument-error 'streamlines "symbol?" id))
  (unless (list? seeds)
    (raise-argument-error 'streamlines "list?" seeds))
  (for ([seed (in-list seeds)])
    (check-vec2 'streamlines seed))
  (check-direction 'streamlines direction)
  (check-positive 'streamlines "step-size" step-size)
  (check-steps 'streamlines steps)
  (unless (opacity? opacity)
    (raise-argument-error 'streamlines "opacity?" opacity))
  (check-nonnegative 'streamlines "stroke-width" stroke-width)
  (group
   (for/list ([seed (in-list seeds)] [index (in-naturals)])
     (streamline axes field seed
                 #:id (streamline-id id index)
                 #:direction direction
                 #:step-size step-size
                 #:steps steps
                 #:opacity opacity
                 #:stroke stroke
                 #:stroke-width stroke-width))
   #:id id))


;;;
;;; Parameter-Driven Flow Particle

;; flow-particle : axes-visual? ode-trajectory? parameter #:id symbol? ...
;;                 -> derived-visual?
;; Uses a prepared immutable trajectory. Direct numerical calls remain available
;; through ode-flow-position, but an animated particle deliberately requires a
;; bounded trajectory so rendering avoids repeated seed-to-time integration and
;; can freeze all worker inputs before frame rendering starts.
(define (flow-particle axes trajectory phase
                       #:id id
                       #:shape [shape 'circle]
                       #:size [size 1/5]
                       #:fill [fill "crimson"]
                       #:stroke [stroke "black"]
                       #:stroke-width [stroke-width 1]
                       #:opacity [opacity 1])
  (check-axes 'flow-particle axes)
  (check-trajectory 'flow-particle trajectory)
  (unless (symbol? id)
    (raise-argument-error 'flow-particle "symbol?" id))
  (define phase-id (parameter-target-id phase 'flow-particle))
  (define metadata
    (ode-flow-particle-metadata trajectory phase-id))
  (define template-time
    (car (ode-trajectory-time-range trajectory)))
  (define (make-marker time)
    (define coordinate
      (or (ode-frame-sample-ref metadata time)
          (ode-trajectory-position trajectory time)))
    (define center
      (axes-coordinates->point axes
                                (vec2-x coordinate)
                                (vec2-y coordinate)))
    (point-marker #:id id #:center center
                  #:shape shape #:size size #:fill fill #:stroke stroke
                  #:stroke-width stroke-width #:opacity opacity))
  (derived-visual
   (make-marker template-time)
   (lambda (context _template)
     (define time (derived-context-value-ref context phase-id))
     (unless (finite-real? time)
       (raise-arguments-error
        'flow-particle
        "the phase parameter must hold a finite real ODE time"
        "phase-id" phase-id
        "value" time))
     (make-marker time))
   #:metadata metadata))


;;;
;;; Renderer Frame Preparation

;; Metadata is private to prepared flow particles. The derived-visual protocol
;; merely carries it through immutable template updates; this module owns its
;; interpretation.
(struct ode-flow-particle-metadata (trajectory phase-id)
  #:transparent)

;; current-ode-frame-samples holds an immutable hasheq mapping particle
;; metadata to immutable time->coordinate hashes. It is dynamically installed
;; by the PNG renderer around one frame job, never mutated by frame workers.
(define current-ode-frame-samples
  (make-parameter #f))

;; Reports whether an enclosing renderer has already installed the immutable
;; table.  Direct single-frame rendering uses it to avoid preparing the same
;; state again inside a PNG worker.
(define (ode-frame-samples-active?)
  (and (current-ode-frame-samples) #t))

;; call-with-ode-frame-samples : immutable-hasheq? (-> any) -> any
;; Makes a prepared frame-sample table visible while one frame is resolved.
(define (call-with-ode-frame-samples samples thunk)
  (unless (hash? samples)
    (raise-argument-error 'call-with-ode-frame-samples "hash?" samples))
  (unless (and (procedure? thunk)
               (procedure-arity-includes? thunk 0))
    (raise-argument-error
     'call-with-ode-frame-samples "procedure accepting zero arguments" thunk))
  (parameterize ([current-ode-frame-samples samples])
    (thunk)))

;; prepare-ode-frame-samples : (listof scene-state?) -> immutable-hasheq?
;; Scans raw sampled states for prepared flow particles, groups their distinct
;; phase values, and computes an immutable lookup table before renderer workers
;; start. Queries within one checkpoint segment share their full RK4 steps, so
;; the preparation pass is linear in the traversed trajectory segments and
;; selected frame values. The field is therefore not called by render workers.
(define (prepare-ode-frame-samples states)
  (unless (and (list? states) (andmap scene-state? states))
    (raise-argument-error
     'prepare-ode-frame-samples "list of scene-state? values" states))
  (define times-by-metadata (make-hasheq))
  (for ([state (in-list states)])
    (for ([metadata
           (in-list
            (append-map
             flow-particle-metadata-in-visual
             (scene-state-visuals-in-drawing-order state)))])
      (define time
        (scene-state-value-ref state
                               (ode-flow-particle-metadata-phase-id metadata)))
      (unless (finite-real? time)
        (raise-arguments-error
         'prepare-ode-frame-samples
         "a prepared flow particle phase must hold a finite real ODE time"
         "phase-id" (ode-flow-particle-metadata-phase-id metadata)
         "value" time))
      (define time-set
        (hash-ref times-by-metadata metadata #f))
      (unless time-set
        (set! time-set (make-hash))
        (hash-set! times-by-metadata metadata time-set))
      (hash-set! time-set time #t)))
  (for/fold ([samples (hasheq)])
            ([(metadata time-set) (in-hash times-by-metadata)])
    (define trajectory
      (ode-flow-particle-metadata-trajectory metadata))
    (define positions
      (prepare-trajectory-frame-samples trajectory
                                        (hash-keys time-set)))
    (hash-set samples metadata positions)))

;; frame-trajectory-query is a request relative to one canonical checkpoint.
;; `suffix-steps` counts full steps from that checkpoint; `remainder` is then
;; applied from the resulting state without changing the running state.
(struct frame-trajectory-query (time suffix-steps remainder)
  #:transparent)

;; prepare-trajectory-frame-samples : ode-trajectory? (listof finite-real?)
;;                                     -> immutable-hashof-finite-real?-vec2?
;; Resolves many values from one trajectory in batches. A direct query needs at
;; most checkpoint-every - 1 suffix steps. Here those suffixes are sorted and
;; walked only once per used checkpoint, preserving the same RK4 arithmetic for
;; every individual time while sharing the intervening full-step states.
(define (prepare-trajectory-frame-samples trajectory times)
  (if (adaptive-ode-trajectory-value? trajectory)
      ;; An adaptive trajectory already owns all accepted nodes and endpoint
      ;; derivatives. Dense lookup is pure interpolation, so freezing these
      ;; positions before worker rendering requires no field calls at all.
      (for/fold ([positions (hash)]) ([time (in-list times)])
        (check-trajectory-time 'prepare-ode-frame-samples trajectory time)
        (hash-set positions time (adaptive-trajectory-position trajectory time)))
      (prepare-fixed-trajectory-frame-samples trajectory times)))

(define (prepare-fixed-trajectory-frame-samples trajectory times)
  (define groups (make-hash))
  (for ([time (in-list times)])
    (check-trajectory-time 'prepare-ode-frame-samples trajectory time)
    (define-values (direction _full-step checkpoint-index suffix-steps remainder)
      (trajectory-query-parts trajectory time))
    (define group-key (cons direction checkpoint-index))
    (hash-update!
     groups group-key
     (lambda (queries)
       (cons (frame-trajectory-query time suffix-steps remainder) queries))
     '()))
  (define field (ode-trajectory-value-field trajectory))
  (define step-size (ode-trajectory-value-step-size trajectory))
  (for/fold ([positions (hash)])
            ([(group-key queries) (in-hash groups)])
    (define direction (car group-key))
    (define checkpoint-index (cdr group-key))
    (define full-step (* direction step-size))
    (define checkpoints
      (if (negative? direction)
          (ode-trajectory-value-backward-checkpoints trajectory)
          (ode-trajectory-value-forward-checkpoints trajectory)))
    (define checkpoint (vector-ref checkpoints checkpoint-index))
    (define sorted-queries
      (sort queries < #:key frame-trajectory-query-suffix-steps))
    (define-values (_state _suffix positions*)
      (for/fold ([state checkpoint] [completed-suffix 0] [samples positions])
                ([query (in-list sorted-queries)])
        (define suffix-steps
          (frame-trajectory-query-suffix-steps query))
        (define current-time
          (* direction checkpoint-index
             (ode-trajectory-value-checkpoint-every trajectory)
             step-size))
        (define-values (state* state-time)
          (for/fold ([point state]
                     [point-time (+ current-time
                                    (* completed-suffix full-step))])
                    ([ignored (in-range (- suffix-steps completed-suffix))])
            (values (rk4-step field point-time point full-step)
                    (+ point-time full-step))))
        (define remainder (frame-trajectory-query-remainder query))
        (define coordinate
          (if (zero? remainder)
              state*
              (rk4-step field state-time state* remainder)))
        (values state*
                suffix-steps
                (hash-set samples
                          (frame-trajectory-query-time query)
                          coordinate))))
    positions*))

;; ode-frame-sample-ref : metadata finite-real? -> (or/c false/c vec2?)
;; Returns a renderer-prepared coordinate if this frame has one.
(define (ode-frame-sample-ref metadata time)
  (define all-samples (current-ode-frame-samples))
  (cond
    [(not all-samples) #f]
    [else
     (define particle-samples (hash-ref all-samples metadata #f))
     (and particle-samples
          (hash-ref particle-samples time #f))]))

;; flow-particle-metadata-in-visual : visual? -> (listof metadata)
;; Descends ordinary semantic groups without resolving derived definitions.
(define (flow-particle-metadata-in-visual visual)
  (cond
    [(derived-visual? visual)
     (define metadata (derived-visual-metadata visual))
     (if (ode-flow-particle-metadata? metadata)
         (list metadata)
         '())]
    [(group-visual? visual)
     (append-map flow-particle-metadata-in-visual
                 (group-visual-children visual))]
    [else '()]))


;;;
;;; Internal Geometry and Validation

;; Creates a path in the containing world coordinate system. Unlike ordinary
;; function graphs, the supplied points have already passed through an axes
;; transform, so the path stores a neutral transform around its own center.
(define (make-world-path-visual points id opacity stroke stroke-width)
  (define geometry (polyline-path points))
  (define center (path-geometry-center geometry))
  (make-path-visual
   (path-geometry-translate geometry (vec2-scale -1 center))
   #:id id #:center center #:opacity opacity #:fill #f
   #:stroke stroke #:stroke-width stroke-width))

(define (rk4-step field time point step)
  (ode-state-space-rk4-step
   vec2-ode-state-space
   (lambda (field-time field-point) (call-field field field-time field-point))
   time point step))

(define (call-field field time point)
  (define result
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'ode-flow-position
             "the ODE field raised an exception"
             "point" point
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (if (procedure-arity-includes? field 3)
             (field time (vec2-x point) (vec2-y point))
             (field (vec2-x point) (vec2-y point))))
       list)))
  (unless (= (length result) 1)
    (raise-arguments-error
     'ode-flow-position
     "the ODE field must return exactly one vec2"
     "point" point
     "result count" (length result)))
  (define value (car result))
  (unless (vec2? value)
    (raise-arguments-error
     'ode-flow-position
     "the ODE field must return a finite vec2"
     "point" point
     "result" value))
  value)

(define (call-event event time point)
  (define function (ode-event-value-function event))
  (define values
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'prepare-ode-trajectory
             "the ODE event raised an exception"
             "event" (ode-event-value-name event)
             "time" time
             "point" point
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (if (procedure-arity-includes? function 3)
             (function time (vec2-x point) (vec2-y point))
             (function (vec2-x point) (vec2-y point))))
       list)))
  (unless (= (length values) 1)
    (raise-arguments-error
     'prepare-ode-trajectory
     "the ODE event must return exactly one finite real"
     "event" (ode-event-value-name event)
     "time" time
     "result count" (length values)))
  (define value (car values))
  (unless (finite-real? value)
    (raise-arguments-error
     'prepare-ode-trajectory
     "the ODE event must return a finite real"
     "event" (ode-event-value-name event)
     "time" time
     "result" value))
  value)

(define (streamline-id id index)
  (string->symbol (format "~a-~a" (symbol->string id) index)))

(define (check-field who field)
  (unless (and (procedure? field)
               (or (procedure-arity-includes? field 2)
                   (procedure-arity-includes? field 3)))
    (raise-argument-error
     who
     "procedure accepting either (x y) or (time x y) numeric arguments"
     field)))

(define (check-solver who value)
  (unless (or (not value) (adaptive-rk45? value))
    (raise-argument-error who "#f or adaptive-rk45?" value)))

(define (check-event who value)
  (unless (or (not value) (ode-event? value))
    (raise-argument-error who "#f or ode-event?" value)))

(define (check-trajectory who value)
  (unless (ode-trajectory? value)
    (raise-argument-error who "ode-trajectory?" value)))

(define (check-trajectory-time who trajectory time)
  (check-finite who "time" time)
  (define range (ode-trajectory-time-range trajectory))
  (define start-time (car range))
  (define end-time (cdr range))
  (unless (<= start-time time end-time)
    (raise-arguments-error
     who
     "time is outside the prepared trajectory range"
     "time" time
     "time-range" (cons start-time end-time))))

(define (check-checkpoint-every who value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-argument-error who "positive exact integer?" value)))

;; check-time-range : symbol? any/c -> (values finite-real? finite-real?)
;; Accepts the compact public form (cons start end), including a zero-length
;; range for a stationary or single-time query.
(define (check-time-range who value)
  (unless (and (pair? value)
               (finite-real? (car value))
               (finite-real? (cdr value))
               (<= (car value) (cdr value)))
    (raise-argument-error
     who
     "pair (cons start-time end-time) of finite reals with start-time <= end-time"
     value))
  (values (car value) (cdr value)))

(define (check-direction who value)
  (unless (memq value '(forward backward both))
    (raise-argument-error who "'forward, 'backward, or 'both" value)))

(define (check-axes who value)
  (unless (axes-visual? value)
    (raise-argument-error who "axes-visual?" value)))

(define (check-vec2 who value)
  (unless (vec2? value)
    (raise-argument-error who "vec2?" value)))

(define (check-finite who name value)
  (unless (finite-real? value)
    (raise-arguments-error who "a finite real value" name value)))

(define (check-positive who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "a positive finite real value" name value)))

(define (check-nonnegative who name value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who "a nonnegative finite real value" name value)))

(define (check-steps who value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-argument-error who "positive exact integer?" value)))
