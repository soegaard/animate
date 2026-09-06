#lang racket/base

;;;
;;; Prepared Three-Dimensional ODE Flow
;;;

;; A spatial ODE trajectory is immutable numerical data.  Fixed RK4 retains
;; canonical checkpoints, while adaptive RK45 retains all accepted nodes and
;; their derivatives for dense lookup.  Both paths use private/ode-state-space
;; rather than a second hand-written vec3 integrator.


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
         "point-line-arrow3d.rkt"
         "spatial-dependency.rkt"
         "spatial-group.rkt"
         "spatial-relation.rkt"
         "spatial-relation-context.rkt"
         "spatial-visual.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide ode-trajectory3d?
         ode-trajectory3d-time-range
         ode-trajectory3d-step-size
         ode-trajectory3d-checkpoint-every
         ode-trajectory3d-solver
         ode-trajectory3d-diagnostics
         ode-trajectory3d-diagnostics?
         ode-trajectory3d-diagnostics-solver
         ode-trajectory3d-diagnostics-accepted-steps
         ode-trajectory3d-diagnostics-rejected-steps
         ode-trajectory3d-diagnostics-termination-time
         ode-trajectory3d-diagnostics-maximum-error
         prepare-ode-trajectory3d
         ode-trajectory3d-position
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

(define (ode-trajectory3d? value)
  (or (fixed-ode-trajectory3d? value)
      (adaptive-ode-trajectory3d? value)))

(define (ode-trajectory3d-time-range trajectory)
  (check-trajectory3d 'ode-trajectory3d-time-range trajectory)
  (if (adaptive-ode-trajectory3d? trajectory)
      (cons (adaptive-ode-trajectory3d-start-time trajectory)
            (adaptive-ode-trajectory3d-end-time trajectory))
      (cons (fixed-ode-trajectory3d-start-time trajectory)
            (fixed-ode-trajectory3d-end-time trajectory))))

(define (ode-trajectory3d-step-size trajectory)
  (check-trajectory3d 'ode-trajectory3d-step-size trajectory)
  (and (fixed-ode-trajectory3d? trajectory)
       (fixed-ode-trajectory3d-step-size trajectory)))

(define (ode-trajectory3d-checkpoint-every trajectory)
  (check-trajectory3d 'ode-trajectory3d-checkpoint-every trajectory)
  (and (fixed-ode-trajectory3d? trajectory)
       (fixed-ode-trajectory3d-checkpoint-every trajectory)))

(define (ode-trajectory3d-solver trajectory)
  (check-trajectory3d 'ode-trajectory3d-solver trajectory)
  (if (adaptive-ode-trajectory3d? trajectory)
      (adaptive-ode-trajectory3d-solver trajectory)
      'fixed-rk4))

(define (ode-trajectory3d-diagnostics trajectory)
  (check-trajectory3d 'ode-trajectory3d-diagnostics trajectory)
  (and (adaptive-ode-trajectory3d? trajectory)
       (adaptive-ode-trajectory3d-diagnostics trajectory)))

(define (ode-trajectory3d-diagnostics? value)
  (ode-trajectory3d-diagnostics-value? value))
(define ode-trajectory3d-diagnostics-solver
  ode-trajectory3d-diagnostics-value-solver)
(define ode-trajectory3d-diagnostics-accepted-steps
  ode-trajectory3d-diagnostics-value-accepted-steps)
(define ode-trajectory3d-diagnostics-rejected-steps
  ode-trajectory3d-diagnostics-value-rejected-steps)
(define ode-trajectory3d-diagnostics-termination-time
  ode-trajectory3d-diagnostics-value-termination-time)
(define ode-trajectory3d-diagnostics-maximum-error
  ode-trajectory3d-diagnostics-value-maximum-error)

; prepare-ode-trajectory3d : procedure? vec3?
;                            #:time-range (cons/c finite-real? finite-real?)
;                            [#:step-size positive-finite-real?]
;                            [#:checkpoint-every positive-exact-integer?]
;                            [#:solver (or/c #f adaptive-rk45?)]
;                            -> ode-trajectory3d?
;; Fields accept either (x y z) or (time x y z).  Preparation is the only
;; operation that creates a trajectory; all returned values are immutable and
;; safe to look up in arbitrary order.
(define (prepare-ode-trajectory3d field seed
                                  #:time-range time-range
                                  #:step-size [step-size 1/20]
                                  #:checkpoint-every [checkpoint-every 16]
                                  #:solver [solver #f])
  (check-field3d 'prepare-ode-trajectory3d field)
  (check-vec3 'prepare-ode-trajectory3d seed)
  (check-positive 'prepare-ode-trajectory3d "step-size" step-size)
  (check-checkpoint-every 'prepare-ode-trajectory3d checkpoint-every)
  (define-values (start-time end-time)
    (check-time-range 'prepare-ode-trajectory3d time-range))
  (unless (or (not solver) (adaptive-rk45? solver))
    (raise-argument-error 'prepare-ode-trajectory3d
                          "(or/c #f adaptive-rk45?)" solver))
  (if solver
      (prepare-adaptive-trajectory3d field seed start-time end-time solver)
      (fixed-ode-trajectory3d
       field seed start-time end-time step-size checkpoint-every
       (build-checkpoints3d field seed 1 step-size checkpoint-every (max 0 end-time))
       (build-checkpoints3d field seed -1 step-size checkpoint-every (max 0 (- start-time))))))

; ode-trajectory3d-position : ode-trajectory3d? finite-real? -> vec3?
;; Fixed lookup continues from one canonical checkpoint.  Adaptive lookup uses
;; stored-node Hermite interpolation and never invokes the author field.
(define (ode-trajectory3d-position trajectory time)
  (check-trajectory3d 'ode-trajectory3d-position trajectory)
  (check-trajectory3d-time 'ode-trajectory3d-position trajectory time)
  (if (adaptive-ode-trajectory3d? trajectory)
      (adaptive-trajectory3d-position trajectory time)
      (fixed-trajectory3d-position trajectory time)))

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
;;; Static Curves and Vector Fields

(define (streamline3d field seed
                      #:id id
                      #:direction [direction 'both]
                      #:step-size [step-size 1/20]
                      #:steps [steps 120]
                      #:radius [radius 1/30]
                      #:sides [sides 8]
                      #:color [color "royalblue"]
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
   #:id id #:radius radius #:sides sides #:color color #:opacity opacity))

(define (streamlines3d field seeds
                       #:id id
                       #:direction [direction 'both]
                       #:step-size [step-size 1/20]
                       #:steps [steps 120]
                       #:radius [radius 1/30]
                       #:sides [sides 8]
                       #:color [color "royalblue"]
                       #:opacity [opacity 1])
  (check-field3d 'streamlines3d field)
  (unless (list? seeds) (raise-argument-error 'streamlines3d "list?" seeds))
  (for ([seed (in-list seeds)]) (check-vec3 'streamlines3d seed))
  (check-symbol 'streamlines3d id)
  (group3d
   (for/list ([seed (in-list seeds)] [index (in-naturals)])
     (streamline3d field seed #:id (child-id3d id index)
                   #:direction direction #:step-size step-size #:steps steps
                   #:radius radius #:sides sides #:color color #:opacity opacity))
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
                        #:radius [radius 1/50]
                        #:color [color "royalblue"]
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
  (check-positive 'vector-field3d "radius" radius)
  (unless (color-spec? color)
    (raise-argument-error 'vector-field3d "color-spec?" color))
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
        color))
  (group3d
   (for/list ([entry (in-list nonzero)] [index (in-naturals)]
              #:do [(define seed (car entry))
                    (define derivative (cdr entry))
                    (define magnitude (vec3-length derivative))
                    (define length (display-length magnitude))]
              #:when (positive? length))
     (define direction (vec3-normalize derivative))
     (arrow3d seed (vec3+ seed (vec3-scale length direction))
              #:id (child-id3d id index)
              #:radius radius #:tip-length (/ length 4)
              #:tip-radius (* 3/2 radius)
              #:color (display-color magnitude) #:opacity opacity))
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
                         #:radius [radius 1/10]
                         #:color [color "tomato"]
                         #:opacity [opacity 1]
                         #:tangent-length [tangent-length #f]
                         #:tangent-color [tangent-color "darkorange"]
                         #:tangent-radius [tangent-radius 1/35])
  (check-trajectory3d 'flow-particle3d trajectory)
  (check-symbol 'flow-particle3d id)
  (check-positive 'flow-particle3d "radius" radius)
  (unless (color-spec? color) (raise-argument-error 'flow-particle3d "color-spec?" color))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'flow-particle3d "finite real in [0, 1]" opacity))
  (when tangent-length (check-positive 'flow-particle3d "tangent-length" tangent-length))
  (when tangent-length (check-positive 'flow-particle3d "tangent-radius" tangent-radius))
  (when tangent-length
    (unless (color-spec? tangent-color)
      (raise-argument-error 'flow-particle3d "color-spec? tangent-color" tangent-color)))
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
       (point3d position #:id id #:radius radius #:color color #:opacity opacity)]
      [else
       (define derivative
         (or (and sample (ode3d-frame-sample-derivative sample))
             (call-trajectory-field3d trajectory time position)))
       (define has-tangent? (positive? (vec3-length derivative)))
       (define direction
         ;; `arrow3d` deliberately rejects a degenerate segment.  Retain the
         ;; stable relation shape at an equilibrium, but make that placeholder
         ;; invisible instead of falsely depicting an arbitrary +x tangent.
         (if has-tangent? (vec3-normalize derivative) x-axis3))
       (group3d
        (list (point3d position #:id 'marker #:radius radius #:color color #:opacity opacity)
              (arrow3d position
                       (vec3+ position (vec3-scale tangent-length direction))
                       #:id 'tangent #:radius tangent-radius
                       #:tip-length (/ tangent-length 4)
                       #:tip-radius (* 3/2 tangent-radius)
                       #:color tangent-color
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
                      #:radius [radius 1/10]
                      #:color [color "tomato"]
                      #:opacity [opacity 1])
  (unless (list? trajectories)
    (raise-argument-error 'flow-cloud3d "list?" trajectories))
  (for ([trajectory (in-list trajectories)])
    (check-trajectory3d 'flow-cloud3d trajectory))
  (check-symbol 'flow-cloud3d id)
  (group3d
   (for/list ([trajectory (in-list trajectories)] [index (in-naturals)])
     (flow-particle3d trajectory phase #:id (child-id3d id index)
                      #:radius radius #:color color #:opacity opacity))
   #:id id))


;;;
;;; Batch Frame Preparation

;; Like the established 2D flow preparation, these dynamic samples are built
;; before parallel PNG workers are launched.  A fixed trajectory may call the
;; field while preparing a frame table, but the later spatial relation resolver
;; only reads these frozen values.
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
                       (call-trajectory-field3d trajectory time position)))
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
  (call-field3d
   (if (adaptive-ode-trajectory3d? trajectory)
       (adaptive-ode-trajectory3d-field trajectory)
       (fixed-ode-trajectory3d-field trajectory))
   time position))

(define (call-field3d field time point)
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'prepare-ode-trajectory3d "the 3D ODE field raised an exception"
             "point" point "exception message" (exn-message exception)))])
      (call-with-values
       (lambda ()
         (if (procedure-arity-includes? field 4)
             (field time (vec3-x point) (vec3-y point) (vec3-z point))
             (field (vec3-x point) (vec3-y point) (vec3-z point))))
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
  (unless (and (procedure? field)
               (or (procedure-arity-includes? field 3)
                   (procedure-arity-includes? field 4)))
    (raise-argument-error who
                          "procedure accepting (x y z) or (time x y z)" field)))

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
