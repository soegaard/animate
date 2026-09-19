#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate/main
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@(require "../private/reference-examples.rkt")

@; Animate Visuals reference revision R1 (20260919).
@title[#:tag "ref-visuals-ode"]{ODE Trajectories and Streamlines}


@declare-exporting[animate/main]


Use @racket[ode-flow-position] for a direct fixed-step calculation,
@racket[prepare-ode-trajectory] for repeated time lookup, and @racket[streamline]
or @racket[flow-particle] for scene content. Fixed RK4 checkpoints and adaptive
RK45 dense output have different preparation and lookup behavior, described
below. Ordinary function and data plots are in @secref["ref-visuals-plots"].

See also @secref["ref-visuals-plots"], @secref["ref-visuals-relations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "ode-flow"]{Deterministic ODE Flow and Streamlines}

The ODE operations turn a two-dimensional vector field into reproducible
integral-curve geometry. A two-argument field is autonomous; a three-argument field receives
time first. Fixed-step fourth-order Runge--Kutta (RK4) is the default,
with the caller selecting the step size and number of streamline steps. Neither
the direct numerical solver nor a prepared trajectory depends on a prior
rendered frame. @racket[prepare-ode-trajectory] stores immutable canonical RK4
checkpoints, so an animated particle does not recompute the complete
seed-to-time prefix for every frame. The renderer batches selected frame times
by checkpoint interval, sharing each interval's full RK4 suffix steps.

An optional deterministic adaptive Dormand--Prince 5(4) backend is also available.
It stores accepted endpoint derivatives for cubic Hermite dense lookup, accepts
time-dependent fields, can stop at one scalar sign-crossing event, and records
immutable diagnostics. Once an adaptive trajectory is prepared, dense lookup
and frame rendering never invoke the author field.

Both trajectory families express their numerical operations through an
immutable @racket[ode-state-space]. The built-in
@racket[real-ode-state-space], @racket[vec2-ode-state-space], and
@racket[vec3-ode-state-space] values make the shared RK4 and RK45 algorithms
explicit; @racket[(numeric-vector-ode-state-space n)] creates a fixed-length
immutable numeric-vector state space. These values are useful when building a
numerical extension, while the ordinary two-dimensional and spatial trajectory
constructors remain the author-facing API.

@subsection[#:tag "ref-visuals-ode-lookup-1"]{Solver State Spaces}

@defstruct*[ode-state-space ([dimension exact-positive-integer?]
                             [add procedure?]
                             [subtract procedure?]
                             [scale procedure?]
                             [norm procedure?]
                             [interpolate procedure?]
                             [finite? procedure?])
  #:transparent]{
Describes finite vector-space operations for the shared solver kernel. Its
procedures must consistently operate on the declared dimension; @racket[finite?]
recognizes the immutable state representation. Prepared numeric-vector states
are immutable to prevent a retained mutable input from changing a trajectory.
}
@defthing[real-ode-state-space ode-state-space?]{The one-dimensional real state space.}
@defthing[vec2-ode-state-space ode-state-space?]{The two-dimensional @racket[vec2] state space.}
@defthing[vec3-ode-state-space ode-state-space?]{The three-dimensional @racket[vec3] state space.}
@defproc[(numeric-vector-ode-state-space [dimension exact-positive-integer?])
         ode-state-space?]{Creates a space whose states are immutable vectors
of exactly @racket[dimension] finite reals.}

@subsection[#:tag "ref-visuals-ode-lookup-2"]{Direct Fixed-Step Integration}

@defproc[(ode-flow-position
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [time finite-real?]
          [#:step-size step-size (and/c finite-real? positive?) 1/20])
         vec2?]{

Returns the RK4 solution beginning at coordinate-space @racket[seed] at time
zero and integrated through signed @racket[time]. A two-argument field receives
numeric coordinate x and y values; a three-argument field receives time, x,
and y. It must return one finite @racket[vec2] derivative. A positive time
advances the field; a negative time integrates it backwards.

The final partial step is included, so the requested time is reached exactly
in ordinary arithmetic rather than rounded to a step-grid endpoint. This is a
fixed-step solver, not an adaptive tolerance-controlled integrator.
}

@; visuals-reference-r1 example: ode-1
A constant field gives uniform motion from the seed.

@examples[#:eval reference-eval
  (define position
    (ode-flow-position (lambda (x y) (vec2 1 0))
                       origin 1 #:step-size 1/4))
  (eval:check (= (vec2-x position) 1) #t)
  (eval:check (= (vec2-y position) 0) #t)
]


@subsection[#:tag "ref-visuals-ode-lookup-3"]{Adaptive Configuration and Events}

@defproc[(adaptive-rk45
          [#:relative-tolerance relative-tolerance (and/c finite-real? positive?) 1e-6]
          [#:absolute-tolerance absolute-tolerance (and/c finite-real? positive?) 1e-8]
          [#:initial-step initial-step (and/c finite-real? positive?) 1/10]
          [#:minimum-step minimum-step (and/c finite-real? positive?) 1e-8]
          [#:maximum-step maximum-step (and/c finite-real? positive?) 1]
          [#:maximum-steps maximum-steps exact-positive-integer? 100000])
         adaptive-rk45?]{

Creates immutable configuration for the deterministic Dormand--Prince embedded
5(4) adaptive solver. The step bounds must satisfy
@racket[minimum-step <= initial-step <= maximum-step]. The relative and
absolute tolerances form the usual componentwise scale
@racket[atol + rtol * max(abs(previous), abs(candidate))].
}

@defproc[(adaptive-rk45? [value any/c]) boolean?]{
Recognizes immutable adaptive Dormand--Prince solver configuration.
}

@defproc[(ode-event
          [function (or/c (procedure-arity-includes/c 2)
                          (procedure-arity-includes/c 3))]
          [#:direction direction (or/c 'any 'increasing 'decreasing) 'any]
          [#:name name symbol? 'event])
         ode-event?]{

Creates one terminal scalar event for adaptive preparation. Like a field,
@racket[function] accepts either @racket[(x y)] or @racket[(time x y)] and
must return one finite real. A sign crossing ends the trajectory; increasing
and decreasing select the crossing orientation. The root is located by
deterministic bisection over the accepted step's cubic dense output.
}

@defproc[(ode-event? [value any/c]) boolean?]{Recognizes an adaptive terminal event declaration.}

@subsection[#:tag "ref-visuals-ode-lookup-4"]{Prepared Trajectories}

@defproc[(ode-trajectory? [value any/c]) boolean?]{

Returns @racket[#t] for an immutable prepared fixed-RK4 or adaptive-RK45
trajectory.
}

@defproc[(prepare-ode-trajectory
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:time-range time-range (cons/c finite-real? finite-real?)]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:checkpoint-every checkpoint-every exact-positive-integer? 16]
          [#:solver solver (or/c false/c adaptive-rk45?) #f]
          [#:event event (or/c false/c ode-event?) #f])
         ode-trajectory?]{

Prepares a closed time range expressed as @racket[(cons start-time end-time)],
where @racket[start-time] is at most @racket[end-time]. The trajectory stores
immutable states at canonical multiples of @racket[step-size], spaced by
@racket[checkpoint-every] full steps in both the positive and negative
directions from the seed at time zero.

For a lookup, the trajectory begins at the preceding checkpoint between zero
and the requested time, takes fewer than @racket[checkpoint-every] full steps,
and then takes the usual final remainder step. It therefore preserves the
fixed-RK4 numerical meaning of @racket[ode-flow-position] without repeating a
long prefix for each frame.

The field must be pure and stable for the lifetime of the prepared value. The
library cannot determine whether an arbitrary Racket procedure's captured state
has changed.

When @racket[solver] is @racket[#f], this is the established fixed-RK4
checkpoint trajectory. @racket[event] is then rejected. With an
@racket[adaptive-rk45?] value, accepted Dormand--Prince endpoint positions and
derivatives are stored instead. @racket[event], when supplied, truncates the
actual supported range at its dense scalar root.
}

@defproc[(ode-trajectory-time-range [trajectory ode-trajectory?])
         (cons/c finite-real? finite-real?)]{

Returns the supported closed time range. For a trajectory stopped by an
adaptive event, the relevant endpoint is the detected dense root rather than
the original requested boundary.
}

@defproc[(ode-trajectory-step-size [trajectory ode-trajectory?])
         (or/c (and/c finite-real? positive?) false/c)]{

Returns the fixed RK4 step size, or @racket[#f] for an adaptive trajectory.
}

@defproc[(ode-trajectory-checkpoint-every [trajectory ode-trajectory?])
         (or/c exact-positive-integer? false/c)]{

Returns the number of full RK4 steps between stored canonical checkpoints, or
@racket[#f] for an adaptive trajectory.
}

@defproc[(ode-trajectory-solver [trajectory ode-trajectory?])
         (or/c 'fixed-rk4 adaptive-rk45?)]{

Returns @racket['fixed-rk4] for the established checkpoint backend or the
immutable @racket[adaptive-rk45?] value that prepared an adaptive trajectory.
}

@defproc[(ode-trajectory-diagnostics [trajectory ode-trajectory?])
         (or/c false/c ode-trajectory-diagnostics?)]{

Returns @racket[#f] for fixed RK4. An adaptive trajectory returns transparent
diagnostics containing solver name, accepted and rejected step counts,
termination time/reason, and the maximum componentwise scaled embedded error.
The error is a local control diagnostic, not a global proof of solution error.
}

@defproc[(ode-trajectory-diagnostics? [value any/c]) boolean?]{
Recognizes the immutable diagnostics returned for a prepared adaptive ODE
trajectory.
}

@defproc[(ode-trajectory-position [trajectory ode-trajectory?]
                                   [time finite-real?])
         vec2?]{

Returns the prepared position at @racket[time]. Fixed trajectories reproduce
the existing checkpoint/remainder RK4 path. Adaptive trajectories use stored
cubic Hermite dense output and do not call the field. The time must lie inside
the actual supported range, which may end early at an event root.
}

@subsection[#:tag "ref-visuals-ode-lookup-5"]{Streamlines and Flow Particles}

@defproc[(streamline-points
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120])
         (listof vec2?)]{

Returns the coordinate-space RK4 samples for one streamline. @racket['forward]
goes from time zero through positive time; @racket['backward] returns points in
increasing geometric order from negative time to the seed; @racket['both]
combines both directions without duplicating the seed.
}

@defproc[(streamline
          [axes axes-visual?]
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:id id symbol?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         path-visual?]{

Converts @racket[streamline-points] through @racket[axes] into one ordinary
world-space path Visual. The axes conversion is captured when the streamline is
constructed. It does not clip, stop at axes bounds, or retain the field
procedure after construction.
}

@defproc[(streamlines
          [axes axes-visual?]
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seeds (listof vec2?)]
          [#:id id symbol?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         group-visual?]{

Builds an ordinary group of streamline paths. Seed number @italic{n} becomes
the direct child named by @tt{id-n}; for example, the first child of
@racket['flow] is reachable at @racket['(flow flow-0)].
}

@defproc[(flow-particle
          [axes axes-visual?]
          [trajectory ode-trajectory?]
          [phase (or/c symbol? scene-parameter?)]
          [#:id id symbol?]
          [#:shape shape point-marker-shape? 'circle]
          [#:size size (and/c finite-real? positive?) 1/5]
          [#:fill fill any/c "crimson"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 1]
          [#:opacity opacity opacity? 1])
         derived-visual?]{

Creates a parameter-driven point marker. At every scene sample,
@racket[phase]'s finite real value selects a position from @racket[trajectory],
which is then converted through @racket[axes]. The phase must remain within the
trajectory's declared range.

Before @racket[render-frames!] creates frame workers, it samples all requested
phase values and freezes the corresponding particle coordinates in an immutable
table. The preparation pass walks each used checkpoint interval once, sharing
full RK4 suffix steps among its selected times. Workers only read those
coordinates; they never call the author field. Direct arbitrary-time scene
sampling remains deterministic through
@racket[ode-trajectory-position].

For an adaptive trajectory, the preparation pass instead reads its stored dense
output directly; no numerical integration or field call occurs after the
trajectory has been prepared.
}

@(close-eval reference-eval)
