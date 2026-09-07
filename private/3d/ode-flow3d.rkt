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
         "point-line-arrow3d.rkt"
         "spatial-dependency.rkt"
         "spatial-group.rkt"
         "spatial-relation.rkt"
         "spatial-relation-context.rkt"
         "spatial-visual.rkt"
         "stroke3d.rkt"
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

(struct prepared-trajectory-node3d (time position derivative) #:transparent)
(struct trajectory-segment3d (t0 t1 p0 p1 d0 d1 arc-length bounds) #:transparent)
(struct prepared-trajectory3d-value
  (time-range solver nodes segments event-hits cumulative-arcs diagnostics source-key checkpoint-every)
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
;                            -> ode-trajectory3d?
;; Fields accept either (x y z) or (time x y z).  Preparation is the only
;; operation that creates a trajectory; all returned values are immutable and
;; safe to look up in arbitrary order.
(define (prepare-ode-trajectory3d field seed
                                  #:time-range time-range
                                  #:step-size [step-size 1/20]
                                  #:checkpoint-every [checkpoint-every 16]
                                  #:solver [solver #f]
                                  #:events [events '()])
  (define normalized-field (normalize-ode-field3d 'prepare-ode-trajectory3d field))
  (check-vec3 'prepare-ode-trajectory3d seed)
  (check-positive 'prepare-ode-trajectory3d "step-size" step-size)
  (check-checkpoint-every 'prepare-ode-trajectory3d checkpoint-every)
  (check-ode-events3d 'prepare-ode-trajectory3d events)
  (define-values (start-time end-time)
    (check-time-range 'prepare-ode-trajectory3d time-range))
  (prepare-dense-trajectory3d normalized-field seed start-time end-time
                              (normalize-solver3d 'prepare-ode-trajectory3d solver step-size)
                              checkpoint-every events))

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

(struct dense-series-report3d (accepted rejected maximum-error steps) #:transparent)

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

(define (prepare-dense-trajectory3d field seed start-time end-time solver checkpoint-every events)
  (define evaluations (box 0))
  (define lower-target (min 0 start-time))
  (define upper-target (max 0 end-time))
  (define-values (backward backward-report)
    (dense-integrate-series3d field seed 0 lower-target solver evaluations))
  (define-values (forward forward-report)
    (dense-integrate-series3d field seed 0 upper-target solver evaluations))
  (define all-nodes (append (reverse (cdr backward)) forward))
  ;; Locate roots from the common dense representation.  The event procedure
  ;; is invoked only during preparation, while the field is never invoked for
  ;; root finding or later lookup.
  (define requested-nodes (dense-clip-nodes3d all-nodes start-time end-time))
  (define requested-segments (dense-make-segments3d requested-nodes))
  (define requested-hits
    (dense-event-hits3d events requested-nodes requested-segments))
  (define-values (actual-start actual-end termination-reason)
    (dense-terminal-range3d start-time end-time requested-hits events))
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
   (cons actual-start actual-end) solver nodes segments event-hits cumulative
   (dense-trajectory-diagnostics3d
    solver (unbox evaluations) accepted rejected actual-end termination-reason
    (max (dense-series-report3d-maximum-error backward-report)
         (dense-series-report3d-maximum-error forward-report))
    (vector-length segments) total (vector-length event-hits)
    (dense-event-warnings3d event-hits))
   (ode-field3d-cache-key field) checkpoint-every))

(define (dense-integrate-series3d field seed start-time target-time solver evaluations)
  (define initial
    (prepared-trajectory-node3d start-time seed
                                (call-field3d field start-time seed evaluations)))
  (cond [(= start-time target-time)
         (values (list initial) (dense-series-report3d 0 0 0 '()))]
        [(fixed-rk4-solver3d? solver)
         (dense-fixed-series3d field initial target-time
                               (fixed-rk4-solver3d-step-size solver) evaluations)]
        [else
         (dense-adaptive-series3d field initial target-time
                                  (adaptive-rk45-solver3d-settings solver) evaluations)]))

(define (dense-fixed-series3d field initial target-time step-size evaluations)
  (define direction (if (< target-time (prepared-trajectory-node3d-time initial)) -1 1))
  (let loop ([current initial] [reversed (list initial)] [steps '()])
    (define remaining (- target-time (prepared-trajectory-node3d-time current)))
    (if (zero? remaining)
        (values (reverse reversed)
                (dense-series-report3d (length steps) 0 0 (reverse steps)))
        (let* ([step (* direction (min step-size (abs remaining)))]
               [next-time (+ (prepared-trajectory-node3d-time current) step)]
               [next-position (dense-rk4-step3d field
                                                 (prepared-trajectory-node3d-time current)
                                                 (prepared-trajectory-node3d-position current)
                                                 step evaluations)]
               [next (prepared-trajectory-node3d
                      next-time next-position
                      (call-field3d field next-time next-position evaluations))])
          (loop next (cons next reversed) (cons (abs step) steps))))))

(define (dense-adaptive-series3d field initial target-time solver evaluations)
  (define direction (if (< target-time (prepared-trajectory-node3d-time initial)) -1 1))
  (let loop ([current initial]
             [step (* direction (adaptive-rk45-initial-step solver))]
             [reversed (list initial)] [accepted 0] [rejected 0]
             [maximum-error 0] [steps '()])
    (when (>= (+ accepted rejected) (adaptive-rk45-maximum-steps solver))
      (raise-arguments-error
       'prepare-ode-trajectory3d "adaptive solver exceeded maximum-steps"
       "maximum-steps" (adaptive-rk45-maximum-steps solver)
       "last-time" (prepared-trajectory-node3d-time current)
       "target-time" target-time))
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
                   (dense-series-report3d (add1 accepted) rejected next-maximum-error
                                          (reverse (cons (abs trial-step) steps))))
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
             reversed accepted (add1 rejected) next-maximum-error steps)])))

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

(define (dense-terminal-range3d start-time end-time hits events)
  (define terminal-ids
    (for/list ([event (in-list events)] #:when (ode-event3d-terminal? event))
      (ode-event3d-id event)))
  (define terminal-hits
    (filter (lambda (hit) (memq (ode-event-hit3d-event-id hit) terminal-ids)) hits))
  (define (minimum-time-hit candidates)
    (and (pair? candidates) (car candidates)))
  (define (maximum-time-hit candidates)
    ;; Keep the first declaration at an equal time; the hit list is already
    ;; increasing-time, declaration-order deterministic.
    (for/fold ([best #f]) ([candidate (in-list candidates)])
      (if (or (not best) (> (ode-event-hit3d-time candidate)
                             (ode-event-hit3d-time best)))
          candidate best)))
  (cond
    [(null? terminal-hits) (values start-time end-time 'time-range)]
    [(>= start-time 0)
     (define forward (minimum-time-hit terminal-hits))
     (if forward
         (values start-time (min end-time (ode-event-hit3d-time forward)) 'terminal-event)
         (values start-time end-time 'time-range))]
    [(<= end-time 0)
     (define backward (maximum-time-hit terminal-hits))
     (if backward
         (values (max start-time (ode-event-hit3d-time backward)) end-time 'terminal-event)
         (values start-time end-time 'time-range))]
    [else
     (define backward
       (maximum-time-hit
        (filter (lambda (hit) (<= (ode-event-hit3d-time hit) 0)) terminal-hits)))
     (define forward
       (minimum-time-hit
        (filter (lambda (hit) (>= (ode-event-hit3d-time hit) 0)) terminal-hits)))
     (values (if backward (max start-time (ode-event-hit3d-time backward)) start-time)
             (if forward (min end-time (ode-event-hit3d-time forward)) end-time)
             (if (or backward forward) 'terminal-event 'time-range))]))

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

(define (streamline3d field seed
                      #:id id
                      #:direction [direction 'both]
                      #:step-size [step-size 1/20]
                      #:steps [steps 120]
                      #:style [style (stroke3d #:color "royalblue" #:width 2)]
                      #:opacity [opacity 1])
  (check-field3d 'streamline3d field)
  (check-vec3 'streamline3d seed)
  (check-symbol 'streamline3d id)
  (check-direction 'streamline3d direction)
  (check-positive 'streamline3d "step-size" step-size)
  (check-positive-integer 'streamline3d "steps" steps)
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
            (raise-arguments-error
             'prepare-ode-trajectory3d "the 3D ODE field raised an exception"
             "point" point "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (if (procedure-arity-includes? procedure 4)
             (procedure time (vec3-x point) (vec3-y point) (vec3-z point))
             (procedure (vec3-x point) (vec3-y point) (vec3-z point))))
       list)))
  (unless (= (length results) 1)
    (raise-arguments-error 'prepare-ode-trajectory3d
                           "the 3D ODE field must return exactly one vec3"
                           "point" point "result count" (length results)))
  (define value (car results))
  (unless (vec3-finite? value)
    (raise-arguments-error 'prepare-ode-trajectory3d
                           "the 3D ODE field must return a finite vec3"
                           "point" point "result" value))
  value)

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
