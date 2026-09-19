#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag '("ref3d-prepared-spatial-85dc26c" "prepared-spatial-ode")]{3D: Prepared spatial ODE trajectories and vector fields}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Prepared spatial trajectories are immutable data with event-aware
preparation, explicit stopping policies, display-ready adaptive streamlines,
and deterministic seed sets.
@racket[prepare-ode-trajectory3d] records dense RK4 or Dormand--Prince
segments once; subsequent position, tangent, arc-length, and event-hit lookup
accepts any supported time in any order and never calls the author field. A
field accepts either @racket[(field x y z)] or
@racket[(field time x y z)] and must return exactly one finite @racket[vec3].
Use @racket[ode-field3d] when the field needs an explicit cache identity or
when its autonomous status matters to later flow analysis.

An @racket[ode-event3d] evaluates a finite scalar on the stored trajectory
while it is prepared. Its procedure accepts either @racket[(event point)] or
@racket[(event time point)]. A sign-changing root is found by deterministic
bisection of the dense Hermite segment; a zero at a shared accepted node is
reported once. Event directions always mean increasing @italic{physical} time,
including when the requested range runs backward. A terminal event becomes a
canonical end node and shortens the relevant side of the returned range;
nonterminal hits remain in the immutable hit vector.

@racket[trajectory-termination3d] makes every other stopping condition
explicit: a symmetric time budget about the seed, an AABB exit, an accumulated
arc-length budget, a low-speed threshold, a maximum step count, policy-owned
events, and a choice between reporting or tolerating an author-field failure.
Terminal events are checked on every accepted solver step: the first root
clips that step and prevents later steps from being accepted. Other termination
policies are resolved on the retained dense Hermite segments and recorded as
immutable termination hits. An AABB exit reports the outward face normal. On
one branch, simultaneous candidates are ordered as
field failure, terminal event in declaration order, bounds exit, arc-length
limit, low speed, maximum steps, then the requested time limit.  The returned
range ends exactly at the selected dense point when that condition can be
located inside a segment.

@racket[flow-particle3d] is a semantic spatial relation. Before an image or
preview worker resolves it, Animate samples its requested phase values into an
immutable table. Thus worker rendering reads positions and tangents only; it
does not evaluate the field procedure. The fixed solver's
@racket[#:checkpoint-every] value is diagnostic preparation metadata; it does not change lookup cost.

@racket[prepare-streamline3d] uses the same dense prepared trajectory but adds
an explicit choice of parameterization. @racket['time] means
@italic{dp/ds = F(p)}, preserving the field's speed. @racket['arc-length]
means @italic{dp/ds = F(p)/||F(p)||}; it therefore requires an autonomous
field and ends at an equilibrium rather than inventing a direction. The
prepared display samples are recursively subdivided in world coordinates until
the chord error, tangent turn, and segment length satisfy an immutable
@racket[streamline-sample-policy3d]. Camera zoom does not change their points.
For a bidirectional streamline, the returned samples run from the backward end
through one copy of the seed to the forward end; the seed index and per-branch
diagnostics remain inspectable.

@racketblock[
(define lorenz-path
  (prepare-ode-trajectory3d
   (ode-field3d
    (lambda (x y z) (vec3 (* 10 (- y x)) (- (* x (- 28 z)) y)
                          (- (* x y) (* 8/3 z))))
    #:cache-key 'lorenz-10-28-8/3)
   (vec3 0 1 21/20)
   #:time-range (cons 0 20)
   #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-6)))

(define phase (parameter 'time 0))
(flow-particle3d lorenz-path phase #:id 'particle #:tangent-length 1)
]

@defproc[(prepare-ode-trajectory3d
          [field any/c]
          [seed vec3?]
          [#:time-range time-range (cons/c finite-real? finite-real?)]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:checkpoint-every checkpoint-every exact-positive-integer? 16]
          [#:solver solver any/c #f]
          [#:events events list? '()]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:cancellation-token cancellation-token any/c #f])
         ode-trajectory3d?]{Prepares one immutable spatial trajectory over the
closed range @racket[(cons start-time end-time)]. The seed is at time zero;
the range may extend on either side of it. Terminal event hits may shorten
that closed range. @racket[#:events] and policy-owned events form one
declaration-ordered set whose identifiers must be distinct. A preview
cancellation token is checked before and between solver steps and before event
root refinement; cancellation raises rather than returning a partial trajectory.}
@defproc[(ode-field3d [procedure procedure?]
                       [#:cache-key cache-key any/c #f]
                       [#:autonomous? autonomous? (or/c boolean? 'auto) 'auto]
                       [#:parallel-safe? parallel-safe? boolean? #f]) any/c]{
Constructs explicit author-time field metadata.  The procedure is used only
during numerical preparation; a prepared trajectory retains its cache key but
not this procedure. In @racket['auto] mode, a three-argument field is
autonomous and a four-argument field is non-autonomous; a procedure accepting
both arities requires an explicit declaration. @racket[parallel-safe?] is an
author assertion permitting @racket[#:parallel? 'auto] preparation to use
worker threads. It defaults to @racket[#f].}
@defproc[(fixed-rk4-solver3d [#:step-size step-size positive? 1/20])
         any/c]{Constructs fixed-step RK4 solver settings.}
@defproc[(adaptive-rk45-solver3d [#:relative-tolerance relative-tolerance positive? 1e-6]
                                 [#:absolute-tolerance absolute-tolerance positive? 1e-9]
                                 [#:initial-step initial-step positive? 1/20]
                                 [#:minimum-step minimum-step positive? 1e-9]
                                 [#:maximum-step maximum-step positive? 1]
                                 [#:maximum-steps maximum-steps exact-positive-integer? 100000])
         any/c]{Constructs immutable adaptive RK45 settings.
An @racket[adaptive-rk45] setting is also accepted.}
@defproc[(ode-event3d [#:id id symbol?]
                       [#:function function procedure?]
                       [#:direction direction (or/c 'any 'increasing 'decreasing) 'any]
                       [#:terminal? terminal? boolean? #t]
                       [#:value-tolerance value-tolerance positive? 1e-9]
                       [#:time-tolerance time-tolerance positive? 1e-9]
                       [#:maximum-iterations maximum-iterations exact-positive-integer? 64]
                       [#:cache-key cache-key any/c #f]
                       [#:parallel-safe? parallel-safe? boolean? #f]
                       [#:root-kind root-kind (or/c 'crossing 'touching 'both) 'crossing]
                       [#:initial-subdivisions initial-subdivisions exact-positive-integer? 4]
                       [#:maximum-depth maximum-depth exact-nonnegative-integer? 12]) any/c]{Constructs an
event descriptor. Event identifiers must be distinct in one preparation call.
The optional cache key describes the opaque event procedure for a future
persistent preparation cache; the completed trajectory itself never retains
the procedure. A non-safe event makes automatic parallel preparation fall back
to serial execution. Initial uniform dense-segment subdivisions isolate
multiple sign-changing roots; @racket['touching] retains a sampled contact
whose neighbouring event values have the same sign, and @racket['both]
retains both kinds. Root finding remains tolerance-limited.}
@defproc[(ode-event-hit3d? [value any/c]) boolean?]{Recognizes one immutable
prepared event-hit record. Its accessors begin with
@tt{ode-event-hit3d-}, including @tt{ode-event-hit3d-time},
@tt{ode-event-hit3d-position}, and @tt{ode-event-hit3d-provenance}.}
@defproc[(trajectory-termination3d
          [#:time-limit time-limit (or/c false/c nonnegative-real?) #f]
          [#:arc-length-limit arc-length-limit (or/c false/c nonnegative-real?) #f]
          [#:bounds bounds (or/c false/c aabb3?) #f]
          [#:minimum-speed minimum-speed (or/c false/c nonnegative-real?) #f]
          [#:maximum-steps maximum-steps exact-positive-integer? 100000]
          [#:events events list? '()]
          [#:on-field-error on-field-error (or/c 'error 'terminate) 'error])
         trajectory-termination3d?]{Constructs an immutable stopping policy.
A time limit constrains absolute physical time to
@racket[(- time-limit)] through @racket[time-limit]. An AABB means the first
exit from a nonempty box, not a request to clip the displayed mesh. The arc
budget is measured independently from the seed on each branch. A field error
normally remains an author error; @racket['terminate] instead ends at the last
accepted node and records a @racket['field-error] hit.}
@defproc[(trajectory-termination3d? [value any/c]) boolean?]{Recognizes a
termination policy. Accessors begin with @tt{trajectory-termination3d-}.}
@defproc[(trajectory-termination-hit3d? [value any/c]) boolean?]{Recognizes an
immutable winning-policy record. Its accessors begin with
@tt{trajectory-termination-hit3d-}; @tt{reason}, @tt{time}, @tt{position},
and @tt{details} are deliberately serializable inspection data.}
@defproc[(streamline-sample-policy3d
          [#:maximum-chord-error maximum-chord-error nonnegative-real? 1/100]
          [#:maximum-turn-angle maximum-turn-angle nonnegative-real? (/ pi 12)]
          [#:maximum-segment-length maximum-segment-length positive? 1/4]
          [#:minimum-segment-length minimum-segment-length positive? 1/2000])
         streamline-sample-policy3d?]{Constructs an immutable, world-space
display resampling policy. The minimum length is an explicit recursion floor
and must not exceed the maximum length. Accessors begin with
@tt{streamline-sample-policy3d-}.}
@defproc[(prepare-streamline3d
          [field any/c]
          [seed vec3?]
          [#:direction direction (or/c 'forward 'backward 'both) 'forward]
          [#:parameterization parameterization (or/c 'time 'arc-length) 'time]
          [#:solver solver any/c (adaptive-rk45-solver3d)]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:sample-policy sample-policy streamline-sample-policy3d?
                           (streamline-sample-policy3d)]
          [#:cancellation-token cancellation-token any/c #f])
         prepared-streamline3d?]{Prepares one immutable streamline. If no
policy is supplied, preparation uses a finite eight-unit time budget. A
supplied policy with no time limit uses the same finite safety horizon unless
another termination condition ends first. A preview worker can pass its
cooperative cancellation token; cancellation is checked before numerical steps
and while the retained curve is resampled, and returns no partial streamline.}
@defproc[(prepared-streamline3d? [value any/c]) boolean?]{Recognizes an
immutable prepared streamline. Its accessors begin with
@tt{prepared-streamline3d-}; @tt{curve-samples} is an immutable vector of
world-space @racket[vec3] values and @tt{seed-index} names the seed's sole
joined occurrence.}
@defproc[(adaptive-streamline3d [prepared prepared-streamline3d?]
                                [#:id id symbol?]
                                [#:style style any/c]
                                [#:opacity opacity real? 1]) spatial-visual?]{Converts
prepared display samples to an ordinary spatial curve. A zero-length prepared
streamline lowers to an empty named group rather than a fictitious segment.}
