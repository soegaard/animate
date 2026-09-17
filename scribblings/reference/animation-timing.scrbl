#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "reference-animation-timing"]{Combining and timing requests}

Run requests together, in order, or with staggered starts.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(timed
          [request (or/c succession-animation-request?
                         animation-group-animation-request?
                         lagged-start-animation-request?
                         style-to-animation-request?
                         value-to-request?
                         move-to-request?
                         move-along-path-request?
                         orient-along-path-request?
                         rotate-to-request?
                         rotate-by-request?
                         scale-to-request?
                         scale-by-request?
                         stroke-width-to-request?
                         fill-color-to-request?
                         stroke-color-to-request?
                         fade-to-request?
                         fade-in-request?
                         fade-out-request?
                         enter-request?
                         leave-request?
                         morph-to-request?
                         morph-to-normalized-request?
                         morph-to-aligned-request?
                         morph-to-open-aligned-request?
                         morph-to-open-compound-aligned-request?
                         morph-to-mixed-compound-aligned-request?
                         morph-to-topology-changing-request?
                         morph-to-compound-aligned-request?
                         transform-formula-parts-request?
                         create-request?
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)]
          [#:start start (and/c finite-real? (>=/c 0)) 0]
          [#:duration duration (and/c finite-real? positive?) 1]
          [#:easing easing
                    (or/c false/c (procedure-arity-includes/c 1))
                    #f])
         timed-animation-request?]{

Wraps one Visual or named-scalar animation request, unified style transition, or sequential, parallel, or lagged
composition with explicit local timing. At top level in a later
@racket[scene-play], @racket[start] and @racket[duration] are literal seconds from
the play-clip start, and @racket[(+ start duration)] must not exceed the enclosing
clip duration.

Inside @racket[succession], @racket[animation-group], or @racket[lagged-start],
the same values are intrinsic timing units. The direct child contributes
@racket[(+ start duration)] units to its parent schedule; the parent then scales
that span proportionally into its assigned interval. The scaled start portion is
a delay during which the wrapped content has no effect.

When @racket[easing] is @racket[#f], the timed request inherits its enclosing
timing context. A supplied procedure overrides that inherited easing. For a leaf
it applies only to that leaf; for a timed composition it becomes the inherited
easing of all descendant leaves unless a nested timed child supplies another
easing. Easing changes interpolation, not schedule allocation.

Before the concrete local start, the wrapped content has no effect. During its
active interval it is sampled using local normalized progress; after its active
endpoint, its exact semantic endpoint is held. SCENE-CV permits timed wrappers
inside Visual/scalar and camera compositions and permits a composition itself to
be wrapped. Another @racket[timed] wrapper is not a valid @racket[request]
value. A timed @racket[camera-follow] samples its target only while its own
interval is active, then holds the resulting endpoint view.
}

@defproc[(timed-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request wrapper created by
@racket[timed].
}

@defproc[(succession
          [request (or/c timed-animation-request?
                         succession-animation-request?
                         animation-group-animation-request?
                         lagged-start-animation-request?
                         style-to-animation-request?
                         value-to-request?
                         move-to-request?
                         move-along-path-request?
                         orient-along-path-request?
                         rotate-to-request?
                         rotate-by-request?
                         scale-to-request?
                         scale-by-request?
                         stroke-width-to-request?
                         fill-color-to-request?
                         stroke-color-to-request?
                         fade-to-request?
                         fade-in-request?
                         fade-out-request?
                         enter-request?
                         leave-request?
                         morph-to-request?
                         morph-to-normalized-request?
                         morph-to-aligned-request?
                         morph-to-open-aligned-request?
                         morph-to-open-compound-aligned-request?
                         morph-to-mixed-compound-aligned-request?
                         morph-to-topology-changing-request?
                         morph-to-compound-aligned-request?
                         transform-formula-parts-request?
                         create-request?
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...)
         succession-animation-request?]{

Creates a sequential visual animation composition. When a succession is passed
to @racket[scene-play], it occupies the enclosing play clip's complete duration;
when nested, it occupies the interval assigned by its parent.

An unwrapped direct child contributes one intrinsic timing unit. A direct
@racket[timed] child contributes @racket[(+ start duration)] units. The direct
child spans are placed consecutively in argument order and their total is scaled
to the succession's concrete assigned duration. Thus unwrapped children still
receive equal shares exactly as in SCENE-AO, while explicit timed durations act
as proportional sequence weights. A timed child's start portion is a scaled hold
delay before its active content.

A bare nested composition still counts as one direct child, preserving AO--AQ
parent allocation. Wrap that nested composition with @racket[timed] when it
should reserve a non-unit or delayed parent-level span. Once assigned an interval,
the nested composition recursively applies its own timing rule.

Every leaf is compiled against the exact semantic state at its own start
boundary. Relative requests therefore chain from prior endpoints, and SCENE-AN's
structural introduction, removal, same-ID reintroduction, overlap checks, and
direct arbitrary-time sampling are reused. Easing is inherited independently by
each leaf; a nested timed child may override it.

At least one child is required. A single list of valid children is accepted in
place of separate arguments. Ordinary Visual and camera requests, unified style
transitions, timed Visual/camera composition wrappers, and nested successions,
animation groups, or lagged starts are valid children. Camera center and
world-width overlap rules apply after expansion.
}

@defproc[(succession-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a composition created by
@racket[succession].
}

@defproc[(animation-group
          [request (or/c timed-animation-request?
                         succession-animation-request?
                         animation-group-animation-request?
                         lagged-start-animation-request?
                         style-to-animation-request?
                         value-to-request?
                         move-to-request?
                         move-along-path-request?
                         orient-along-path-request?
                         rotate-to-request?
                         rotate-by-request?
                         scale-to-request?
                         scale-by-request?
                         stroke-width-to-request?
                         fill-color-to-request?
                         stroke-color-to-request?
                         fade-to-request?
                         fade-in-request?
                         fade-out-request?
                         enter-request?
                         leave-request?
                         morph-to-request?
                         morph-to-normalized-request?
                         morph-to-aligned-request?
                         morph-to-open-aligned-request?
                         morph-to-open-compound-aligned-request?
                         morph-to-mixed-compound-aligned-request?
                         morph-to-topology-changing-request?
                         morph-to-compound-aligned-request?
                         transform-formula-parts-request?
                         create-request?
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...)
         animation-group-animation-request?]{

Creates a parallel visual animation composition. When a group is passed to
@racket[scene-play], it occupies the enclosing play clip's complete duration;
when nested, it occupies the interval assigned by its parent.

Every unwrapped direct child has one intrinsic timing unit. A direct
@racket[timed] child has span @racket[(+ start duration)]. All children share the
group start; their spans are scaled against the longest direct span so the
longest child reaches the group endpoint. Shorter children finish earlier and
hold their exact endpoints. If no direct child is timed, every span is one and
SCENE-AP's original full-interval timing is unchanged.

A timed child's scaled start portion is a delay. A bare nested succession, group,
or lagged start still contributes one parent-level unit and recursively expands
inside the concrete interval it receives; wrap that nested composition with
@racket[timed] to give it an explicit non-unit span.

Existing component rules still apply after complete expansion: compatible
components such as translation and rotation may share one target, while two
positive-overlap updates to the same target/component are rejected. The final
leaves use the SCENE-AN scheduler, preserving exact-boundary compilation,
structural semantics, easing inheritance, camera-follow behavior, and direct
arbitrary-time sampling.

At least one child is required. A single list of valid children is accepted in
place of separate arguments. Unified style transitions, camera requests, timed
Visual/camera composition wrappers, and nested compositions are valid group
children. Camera center and world-width overlap rules apply after expansion.
}

@defproc[(animation-group-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a composition created by
@racket[animation-group].
}

@defproc[(lagged-start
          [request (or/c timed-animation-request?
                         succession-animation-request?
                         animation-group-animation-request?
                         lagged-start-animation-request?
                         style-to-animation-request?
                         value-to-request?
                         move-to-request?
                         move-along-path-request?
                         orient-along-path-request?
                         rotate-to-request?
                         rotate-by-request?
                         scale-to-request?
                         scale-by-request?
                         stroke-width-to-request?
                         fill-color-to-request?
                         stroke-color-to-request?
                         fade-to-request?
                         fade-in-request?
                         fade-out-request?
                         enter-request?
                         leave-request?
                         morph-to-request?
                         morph-to-normalized-request?
                         morph-to-aligned-request?
                         morph-to-open-aligned-request?
                         morph-to-open-compound-aligned-request?
                         morph-to-mixed-compound-aligned-request?
                         morph-to-topology-changing-request?
                         morph-to-compound-aligned-request?
                         transform-formula-parts-request?
                         create-request?
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1/4])
         lagged-start-animation-request?]{

Creates a staggered visual animation composition. Each unwrapped direct child
has one intrinsic timing unit; a direct @racket[timed] child has span
@racket[(+ start duration)]. Let those spans be @italic{s0}, @italic{s1}, and so
on. The first raw child starts at zero, and each following raw start is the
previous raw start plus @italic{r} times the previous child's span, where
@italic{r} is @racket[lag-ratio]. The complete raw schedule envelope is then
scaled to the concrete interval assigned to the lagged composition.

When every direct span is one, this reduces exactly to the SCENE-AQ formula
@racket[(/ D (+ 1 (* (sub1 n) r)))]. More generally,
@racket[#:lag-ratio 0] has duration-scaled @racket[animation-group] timing and
@racket[#:lag-ratio 1] has duration-scaled @racket[succession] timing even when
child spans differ. Intermediate ratios overlap according to the previous
child's span; ratios greater than one may leave hold gaps.

A timed child's start portion becomes scaled delay before its active content. A
bare nested composition contributes one parent-level unit and recursively applies
its own rule in the interval it receives; wrap it with @racket[timed] for an
explicit parent-level duration or delay. All expanded leaves use the SCENE-AN
scheduled-leaf engine, so exact boundary compilation, conflict validation,
structural ordering, easing inheritance, and arbitrary-time sampling remain
unchanged.

At least one child is required. A single list of valid children is accepted in
place of separate arguments. Unified style transitions, camera requests, timed
Visual/camera composition wrappers, and nested compositions are valid lagged
children. Camera center and world-width overlap rules apply after expansion.
}

@defproc[(lagged-start-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a composition created by
@racket[lagged-start].
}

@defproc[(stagger-map
          [targets target-sequence?]
          [template (or/c request-template? procedure?)]
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1/4]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward]
          [#:delay delay (or/c #f delay-plan?) #f])
         any/c]{

Creates a deferred semantic stagger. @racket[targets] is resolved exactly once
against the scene state at this mapped composition's local start. Its immutable
snapshot is then ordered, indexed, instantiated, conflict-checked, and lowered
through the normal @racket[lagged-start] scheduler. A procedure template receives
exactly one @racket[target-ref?], not a target/index pair. The reference records
the stable path, source order index, scheduled order index, and any available
selection/formula metadata.

@racket[#:order] changes scheduled order only. It never changes a reference's
source index. An empty resolved sequence is a contract error. Procedure-backed
templates are supported for in-process authoring but are explicitly
nonserializable; @racket[request-template?] communicates that distinction.

With no @racket[#:delay], @racket[stagger-map] uses
@racket[(index-delay lag-ratio)] and lowers through the ordinary
@racket[lagged-start] timing rule. A custom delay plan is independent of
@racket[#:order] and lowers to explicit timed children in a parallel envelope.
Position-driven plans use frozen world positions from the map's local start and
raise a capability error when a target has no 2D position.
}

@defthing[stagger-requests procedure?]{
An alias for @racket[eager-stagger-map]. It is provided for code that reads more
naturally as an eager request-building step.
}

@defproc[(repeat-animation
          [request any/c]
          [count exact-positive-integer?])
         succession-animation-request?]{

Eagerly expands to @racket[count] copies of @racket[request] in ordinary
@racket[succession]. Relative operations therefore accumulate from prior exact
endpoints, while absolute requests naturally stabilize after their first copy.
No runtime loop or reset is inserted.
}

@defproc[(ping-pong
          [forward any/c]
          [backward any/c]
          [#:count count exact-positive-integer? 1])
         succession-animation-request?]{

Eagerly expands an explicit @racket[forward], @racket[backward] pair for each
requested count. It does not infer a reverse operation from a destination
request; exact return behavior is the author's explicit pair semantics.
}
