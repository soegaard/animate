#lang racket/base

;;;
;;; Deterministic ODE Flow and Streamlines
;;;

;; Integrates a two-dimensional autonomous field with fixed-step RK4. Direct
;; numerical queries remain history-free, while prepared trajectories retain
;; immutable canonical checkpoints so animation rendering does not recompute a
;; seed-to-time prefix for every frame.


;;;
;;; Imports and Exports

(require racket/list
         "axes-visual.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "parameter.rkt"
         "path-geometry.rkt"
         "point-marker-visual.rkt"
         "scene-state.rkt"
         "visual-model.rkt")

(provide ode-flow-position
         ode-trajectory?
         ode-trajectory-time-range
         ode-trajectory-step-size
         ode-trajectory-checkpoint-every
         prepare-ode-trajectory
         ode-trajectory-position
         streamline-points
         streamline
         streamlines
         flow-particle
         prepare-ode-frame-samples
         call-with-ode-frame-samples)


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
     (define state
       (for/fold ([point seed]) ([ignored (in-range whole-count)])
         (rk4-step field point full-step)))
     (define remainder (- time (* whole-count full-step)))
     (if (zero? remainder)
         state
         (rk4-step field state remainder))]))


;;;
;;; Prepared Fixed-Step Trajectories

;; ode-trajectory-value stores canonical fixed-RK4 checkpoints for one initial
;; value problem. The forward and backward vectors hold positions at step
;; indices 0, checkpoint-every, 2*checkpoint-every, ... from time zero. They
;; are immutable after construction, so lookup is independent of query order
;; and safe to share among renderer workers.
(struct ode-trajectory-value
  (field seed start-time end-time step-size checkpoint-every
         forward-checkpoints backward-checkpoints)
  #:transparent)

;; ode-trajectory? : any/c -> boolean?
(define (ode-trajectory? value)
  (ode-trajectory-value? value))

;; ode-trajectory-time-range : ode-trajectory? -> pair?
;; Returns the closed supported range as (cons start-time end-time).
(define (ode-trajectory-time-range trajectory)
  (check-trajectory 'ode-trajectory-time-range trajectory)
  (cons (ode-trajectory-value-start-time trajectory)
        (ode-trajectory-value-end-time trajectory)))

;; ode-trajectory-step-size : ode-trajectory? -> positive-finite-real?
(define (ode-trajectory-step-size trajectory)
  (check-trajectory 'ode-trajectory-step-size trajectory)
  (ode-trajectory-value-step-size trajectory))

;; ode-trajectory-checkpoint-every : ode-trajectory? -> positive-exact-integer?
(define (ode-trajectory-checkpoint-every trajectory)
  (check-trajectory 'ode-trajectory-checkpoint-every trajectory)
  (ode-trajectory-value-checkpoint-every trajectory))

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
                                #:checkpoint-every [checkpoint-every 16])
  (check-field 'prepare-ode-trajectory field)
  (check-vec2 'prepare-ode-trajectory seed)
  (check-positive 'prepare-ode-trajectory "step-size" step-size)
  (check-checkpoint-every 'prepare-ode-trajectory checkpoint-every)
  (define-values (start-time end-time)
    (check-time-range 'prepare-ode-trajectory time-range))
  (ode-trajectory-value
   field seed start-time end-time step-size checkpoint-every
   (build-checkpoints field seed 1 step-size checkpoint-every
                      (max 0 end-time))
   (build-checkpoints field seed -1 step-size checkpoint-every
                      (max 0 (- start-time)))))

;; ode-trajectory-position : ode-trajectory? finite-real? -> vec2?
;; Looks up one time in a prepared trajectory. The selected checkpoint is always
;; between time zero and the query; integration never reverses direction from a
;; later point. At most checkpoint-every - 1 full steps plus one remainder step
;; are needed after the constant-time checkpoint lookup.
(define (ode-trajectory-position trajectory time)
  (check-trajectory 'ode-trajectory-position trajectory)
  (check-trajectory-time 'ode-trajectory-position trajectory time)
  (define field (ode-trajectory-value-field trajectory))
  (define-values (direction full-step checkpoint-index suffix-steps remainder)
    (trajectory-query-parts trajectory time))
  (define checkpoints
    (if (negative? direction)
        (ode-trajectory-value-backward-checkpoints trajectory)
        (ode-trajectory-value-forward-checkpoints trajectory)))
  (define checkpoint
    (vector-ref checkpoints checkpoint-index))
  (define state
    (for/fold ([point checkpoint])
              ([ignored (in-range suffix-steps)])
      (rk4-step field point full-step)))
  (if (zero? remainder)
      state
      (rk4-step field state remainder)))

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
  (define (advance point count)
    (for/fold ([state point]) ([ignored (in-range count)])
      (rk4-step field state full-step)))
  (define checkpoints
    (let loop ([checkpoint-index 0] [state seed] [reversed '()])
      (if (= checkpoint-index checkpoint-count)
          (reverse reversed)
          (loop (add1 checkpoint-index)
                (if (= checkpoint-index (sub1 checkpoint-count))
                    state
                    (advance state checkpoint-every))
                (cons state reversed)))))
  (vector->immutable-vector (list->vector checkpoints)))

;; whole-step-count : finite-real? positive-finite-real? -> exact-nonnegative-integer?
;; Mirrors ode-flow-position's canonical full-step decision exactly.
(define (whole-step-count time step-size)
  (inexact->exact (floor (/ (abs time) step-size))))

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
        (define state*
          (for/fold ([point state])
                    ([ignored (in-range (- suffix-steps completed-suffix))])
            (rk4-step field point full-step)))
        (define remainder (frame-trajectory-query-remainder query))
        (define coordinate
          (if (zero? remainder)
              state*
              (rk4-step field state* remainder)))
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

(define (rk4-step field point step)
  (define half-step (/ step 2))
  (define k1 (call-field field point))
  (define k2 (call-field field (vec2+ point (vec2-scale half-step k1))))
  (define k3 (call-field field (vec2+ point (vec2-scale half-step k2))))
  (define k4 (call-field field (vec2+ point (vec2-scale step k3))))
  (vec2+
   point
   (vec2-scale
    (/ step 6)
    (vec2+ k1
           (vec2+ (vec2-scale 2 k2)
                  (vec2+ (vec2-scale 2 k3) k4))))))

(define (call-field field point)
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
       (lambda () (field (vec2-x point) (vec2-y point)))
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

(define (streamline-id id index)
  (string->symbol (format "~a-~a" (symbol->string id) index)))

(define (check-field who field)
  (unless (and (procedure? field)
               (procedure-arity-includes? field 2))
    (raise-argument-error who "procedure accepting two numeric arguments" field)))

(define (check-trajectory who value)
  (unless (ode-trajectory? value)
    (raise-argument-error who "ode-trajectory?" value)))

(define (check-trajectory-time who trajectory time)
  (check-finite who "time" time)
  (define start-time (ode-trajectory-value-start-time trajectory))
  (define end-time (ode-trajectory-value-end-time trajectory))
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
