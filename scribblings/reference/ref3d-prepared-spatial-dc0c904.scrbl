#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-dc0c904"]{3D: Reading prepared trajectories}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(ode-trajectory3d? [value any/c]) boolean?]{Recognizes a prepared
immutable spatial trajectory.}
@defproc[(ode-trajectory3d-position [trajectory ode-trajectory3d?]
                                     [time finite-real?]) vec3?]{Returns the
position at a supported time. Every prepared lookup reads only stored data.}
@defproc[(ode-trajectory3d-time-range [trajectory ode-trajectory3d?])
         (cons/c finite-real? finite-real?)]{Returns its supported range.}
@defproc[(trajectory-segment3d? [value any/c]) boolean?]{Recognizes one
immutable dense segment retained by a prepared trajectory. Segment records are
returned by @racket[ode-trajectory3d-segments]; clients inspect them but do not
construct them directly.}
@defproc[(trajectory-segment3d-bounds [segment trajectory-segment3d?]) aabb3?]{Returns
the conservative bounds of the segment's cubic Hermite path. The box covers
coordinate extrema in the interior as well as its endpoint positions.}
@defproc[(ode-trajectory3d-segments [trajectory ode-trajectory3d?]) vector?]{Returns
the immutable, increasing-time vector of dense @racket[trajectory-segment3d?]
values. A segment's @racket[trajectory-segment3d-bounds] is an @racket[aabb3?]
covering all coordinate extrema of its cubic Hermite path, not merely its two
endpoints.}
@defproc[(ode-trajectory3d-event-hits [trajectory ode-trajectory3d?]) vector?]{Returns
an immutable vector of @racket[ode-event-hit3d?] records, sorted by increasing
physical time. Simultaneous hits use event declaration order as their
tie-break. Each hit records its event identifier, dense root time and position,
event value, physical crossing direction, segment index, iteration count, and
root-finding provenance.}
@defproc[(ode-trajectory3d-termination [trajectory ode-trajectory3d?]) vector?]{Returns
the immutable, increasing-physical-time vector of selected
@racket[trajectory-termination-hit3d?] records. There is normally zero or one
hit for a one-sided trajectory and up to two for a range extending on both
sides of the seed.}
@defproc[(ode-trajectory3d-step-size [trajectory ode-trajectory3d?])
         (or/c positive? false/c)]{Returns a fixed path's RK4 step, or
@racket[#f] for an adaptive path.}
@defproc[(ode-trajectory3d-checkpoint-every [trajectory ode-trajectory3d?])
         (or/c exact-positive-integer? false/c)]{Returns a fixed path's
checkpoint preparation metadata, or @racket[#f] for an adaptive path.  It does
not cause later reintegration.}
@defproc[(ode-trajectory3d-solver [trajectory ode-trajectory3d?]) any/c]{Returns
the immutable fixed-RK4 or adaptive-RK45 solver setting.}
@defproc[(ode-trajectory3d-derivative [trajectory ode-trajectory3d?]
                                       [time finite-real?]) vec3?]{Returns the
stored dense-output tangent at a supported time.}
@defproc[(ode-trajectory3d-speed [trajectory ode-trajectory3d?]
                                  [time finite-real?]) nonnegative-real?]{Returns
the tangent magnitude.}
@defproc[(ode-trajectory3d-arc-length-at [trajectory ode-trajectory3d?]
                                          [time finite-real?]) nonnegative-real?]{
Returns accumulated arc length from the prepared range start.}
@defproc[(ode-trajectory3d-time-at-arc-length [trajectory ode-trajectory3d?]
                                               [arc-length nonnegative-real?])
         finite-real?]{Inverts the prepared arc-length table deterministically.}
@defproc[(ode-trajectory3d-diagnostics [trajectory ode-trajectory3d?]) any/c]{Returns
immutable solver, field-evaluation, step, dense-segment, termination, and
arc-length diagnostics for both fixed and adaptive trajectories.}

@bold{Current T5 limits.} Arc length uses deterministic adaptive Simpson
integration of each stored Hermite segment's tangent magnitude. Each segment
retains an immutable cumulative table whose intervals are measured by the same
integrator; arc-length endpoints remain numerical rather than symbolic. The
low-speed policy isolates ordinary interior extrema of the stored Hermite
tangent magnitude and bisects the first threshold crossing; it does not yet
require a configurable run of consecutive slow observations. T2 detects
sign-changing roots and exact/tolerance-zero endpoints, but does not search for
an isolated tangency whose sampled event values retain the same sign. AABB
exits are split at all dense-coordinate extrema and then bisected; numerical
roots remain tolerance-limited, although an accepted face node is preserved
exactly. A standalone streamline without a time limit has the documented
eight-unit safety horizon. Seed sets create finite immutable points; they do
not infer seeding topology from a field. Curve @racket['parameter] spacing is
the stored polyline sample index rather than a source-function parameter,
surface sets require a retained parametric evaluator/range, and Poisson's
floating geometric candidates are repeatable rather than a mathematical
blue-noise certificate. Streamline separation uses display-sample segments and
a cell hash, so it is an explicit finite geometric policy rather than a proof
about the continuous ODE. Independent sets retain canonical order but this
pure layer does not concurrently call arbitrary author field procedures.
Poincare extraction detects endpoint/sign-changing crossings in retained dense
segments. It does not search inside a same-sign segment for an isolated tangent,
and an included tangent is only an explicit endpoint contact. Return maps retain
only first/second crossings, not a proof of a global map. Equilibria and local linearization are covered by their own reference
chapter.

