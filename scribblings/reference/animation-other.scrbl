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

@title[#:tag "reference-animation-other"]{Other animation requests}

Additional request constructors and their predicates.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(apply-pointwise
          [target (or/c visual? symbol? visual-path?)]
          [map-point (procedure-arity-includes/c 1)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'split])
         apply-pointwise-request?]{

Creates a world-space point-map request. At each positive clip
progress, every supported geometric sample @racket[p] moves to
@racket[(map-point p)] by ordinary linear interpolation. @racket[map-point]
must return a finite @racket[vec2?] for every retained sample.

Path Visuals, circles, rectangles, axes, and arrows are converted to sampled path
geometry. Groups retain their ordinary hierarchy and names. A nested target is
resolved into world coordinates and rebased through its invertible enclosing
affine map, preserving its siblings and their paths. Text, images, and other
affine leaves without an exposed path remain at their original resolved world
placement so they stay legible; they are not secretly raster-warped. The
request rejects derived Visuals and frame-space overlays.
It conflicts with simultaneous same-target spatial, style, opacity, formula,
or path changes, because it replaces the complete sampled Visual tree.

@racket[#:samples] gives the initial positive number of pieces per original
line or cubic segment. With the default @racket[#:adaptive? #t], intervals
whose mapped midpoint differs from their mapped chord by more than
@racket[#:tolerance] are bisected, up to @racket[#:max-depth]. At
@racket['split] discontinuity policy, a raised error or an invalid map result
omits that interval and leaves adjacent valid fragments disconnected;
@racket['error] propagates it. Point maps should be pure because refinement
may call them more than once at a source point.
}

@defproc[(apply-pointwise-request? [value any/c]) boolean?]{
Returns @racket[#t] for a request created by @racket[apply-pointwise].
}

@defproc[(apply-homotopy
          [target (or/c visual? symbol? visual-path?)]
          [homotopy (procedure-arity-includes/c 2)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'split])
         apply-homotopy-request?]{

Creates a time-dependent world-space deformation request. At each
positive eased clip phase @racket[alpha], every supported geometric source
sample @racket[p] is placed directly at @racket[(homotopy p alpha)]. This is
not an endpoint map blended toward its final value: sampling a frame at any
time evaluates the same immutable clip-start geometry and phase.

The exact source Visual is retained at clip time zero; authors normally supply
@racket[(homotopy p 0)] equal to @racket[p]. The map must be pure, may be
called repeatedly at a source point by adaptive refinement, and must return a
finite @racket[vec2?] for every retained sample. Nested targets, supported
geometric leaves, adaptive sampling, and @racket['split] versus
@racket['error] discontinuity semantics are the same as for
@racket[apply-pointwise]. As a sampled approximation, phase-dependent adaptive
refinement can choose different path subdivisions at different phases; this API
does not infer continuous topology changes over the full time interval.
}

@defproc[(apply-homotopy-request? [value any/c]) boolean?]{
Returns @racket[#t] for a request created by @racket[apply-homotopy].
}

@defproc[(apply-wave
          [target (or/c visual? symbol? visual-path?)]
          [#:direction direction vec2? (vec2 0 1)]
          [#:amplitude amplitude (and/c finite-real? (>=/c 0)) 1/5]
          [#:wavelength wavelength (and/c finite-real? positive?) 1]
          [#:cycles cycles (and/c finite-real? (>=/c 0)) 1]
          [#:phase phase finite-real? 0])
         apply-wave-request?]{

Creates a target-local sinusoidal path deformation. @racket[direction] is
normalized in the target's immutable local affine frame; it selects both the
wave-coordinate axis and displacement direction. The displacement amplitude is
multiplied by a zero-at-both-ends sine-squared envelope, so each interior frame
is sampled directly from the captured source geometry and the exact source
Visual is restored at completion.

The request uses the adaptive pointwise path mapper.
It supports ordinary affine, world-space Visuals with exposed geometry and
rejects derived and frame-space Visuals. Because it temporarily replaces the
sampled target tree, it conflicts with simultaneous target movement, style,
opacity, formula, and path writers.
}

@defproc[(apply-wave-request? [value any/c]) boolean?]{
Returns @racket[#t] for a request created by @racket[apply-wave].
}

@defproc[(pointwise-jacobian
          [map-point (procedure-arity-includes/c 1)]
          [point vec2?]
          [#:step step (and/c finite-real? positive?) 1/1000])
         linear2?]{
Approximates the local Jacobian by centred finite differences. It is an
inspection helper, not symbolic differentiation.
}

@defproc[(pointwise-jacobian-determinant
          [map-point (procedure-arity-includes/c 1)]
          [point vec2?]
          [#:step step (and/c finite-real? positive?) 1/1000])
         finite-real?]{
Returns the determinant of @racket[pointwise-jacobian] at @racket[point].
}

@defproc[(pointwise-orientation
          [map-point (procedure-arity-includes/c 1)]
          [point vec2?]
          [#:step step (and/c finite-real? positive?) 1/1000]
          [#:tolerance tolerance (and/c finite-real? positive?) 1e-8])
         (or/c 'preserving 'reversing 'singular)]{
Classifies the numerical Jacobian determinant using @racket[tolerance].
}

@defproc[(inverse-map-mesh
          [inverse-map (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min finite-real? -3]
          [#:x-max x-max finite-real? 3]
          [#:y-min y-min finite-real? -2]
          [#:y-max y-max finite-real? 2]
          [#:x-count x-count exact-integer? 7]
          [#:y-count y-count exact-integer? 5]
          [#:samples samples exact-positive-integer? 12]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:stroke stroke any/c "mediumpurple"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         group-visual?]{
Builds a regular target-space grid and adaptively maps it through the explicitly
provided inverse. This does not attempt to derive an inverse automatically.
}

@defproc[(radial-reveal-front
          [#:center center (or/c 'automatic vec2?) 'automatic]
          [#:start-radius start-radius (and/c finite-real? (>=/c 0)) 0]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         radial-reveal-front?]{

Constructs a deterministic radial reveal front. Its immutable polygonal disk
is chosen conservatively so its endpoint covers every corner of the frozen
layout box. @racket[#:start-radius] can make the initial clip nonempty.
}

@defproc[(radial-reveal-front? [value any/c]) boolean?]{
Recognizes a radial reveal front.
}

@defproc[(wipe-in
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [direction (or/c vec2? 'left 'right 'up 'down)]
          [#:origin origin (or/c 'automatic vec2?) 'automatic]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         reveal-in-request?]{

Returns @racket[reveal-in] with a @racket[linear-reveal-front]. Cardinal and
nonzero vector directions use the same normalized spelling as @racket[slide-in].
All timing, frozen-layout, and exact endpoint behavior is the generic reveal
lifecycle behavior.
}

@defproc[(wipe-out
          [target (or/c visual? symbol? visual-path?)]
          [direction (or/c vec2? 'left 'right 'up 'down)]
          [#:origin origin (or/c 'automatic vec2?) 'automatic]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         reveal-out-request?]{

Returns @racket[reveal-out] with a @racket[linear-reveal-front].
}

@defproc[(iris-in
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [#:center center (or/c 'automatic vec2?) 'automatic]
          [#:start-radius start-radius (and/c finite-real? (>=/c 0)) 0]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         reveal-in-request?]{

Returns @racket[reveal-in] with a @racket[radial-reveal-front].
}

@defproc[(iris-out
          [target (or/c visual? symbol? visual-path?)]
          [#:center center (or/c 'automatic vec2?) 'automatic]
          [#:start-radius start-radius (and/c finite-real? (>=/c 0)) 0]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         reveal-out-request?]{

Returns @racket[reveal-out] with a @racket[radial-reveal-front].
}

@defproc[(ripple
          [target (or/c visual? symbol? visual-path? visual-selection?)]
          [#:rings rings exact-positive-integer? 3]
          [#:spacing spacing (and/c finite-real? (>=/c 0)) 1/5]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/5]
          [#:color color any/c "gold"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1/4]
          [#:id id (or/c #f symbol?) #f])
         lagged-start-animation-request?]{

Eagerly expands to a @racket[lagged-start] composition of @racket[rings]
temporary, expanding outlines around @racket[target]. Each ring reads the
target's renderer-measured bounds at its own sampled time, so it follows a
concurrently moving, rotating, or scaled target without writing any target
component. The outline starts absent, grows by @racket[spacing], fades to
transparent, and is absent again at the exact local endpoint.

The expansion uses the same source-order and timing semantics as
@racket[stagger-map]. Its generated helpers have deterministic origin-derived
IDs, so simultaneous default ripples on one target are distinct. An explicit
@racket[#:id] remains authoritative; reusing it is rejected as a normal
component conflict.
}

@defthing[default-confetti-palette (listof color-spec?)]{
The immutable default palette used by @racket[confetti].
}

@defproc[(underline-sweep
          [target (or/c text-visual? symbol?)]
          [#:color color (or/c #f color-spec?) #f]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:id id (or/c #f symbol?) #f]
          [#:retain? retain? boolean? #t])
         underline-sweep-request?]{

Adds an inspectable ordinary path Visual that sweeps from the frozen text
layout's left edge to its right edge. It is retained at completion by default;
pass @racket[#:retain? #f] for a temporary helper. With no @racket[#:id], the
deterministic helper identity is derived from the target and immutable scheduler
expansion origin. Thus simultaneous default underlines of one target remain
distinct; an explicit @racket[#:id] is authoritative and must be unique.

The request accepts unrotated, unscaled text and snapshots the
text box at local clip start. Consequently it is intentionally a frozen-layout
decoration: simultaneous motion of the target does not move the line. Its
default colour is the text Visual's outer colour.
}

@defproc[(underline-sweep-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[underline-sweep].
}

@defproc[(strike-through
          [target (or/c text-visual? symbol?)]
          [#:color color (or/c #f color-spec?) #f]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:id id (or/c #f symbol?) #f]
          [#:retain? retain? boolean? #t])
         strike-through-request?]{

Adds a separately inspectable swept line through the middle of a frozen text
box. Its target, retained/temporary lifecycle, colour default, deterministic
ID rules, and unrotated/unscaled frozen-layout restriction are the same as
@racket[underline-sweep]. Underline and strike-through use different default
helper identities and can therefore be deliberately composed.
}

@defproc[(strike-through-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[strike-through].
}

@defproc[(highlight-sweep
          [target (or/c text-visual? symbol?)]
          [#:color color color-spec? "#fff2a8"]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20]
          [#:id id (or/c #f symbol?) #f]
          [#:retain? retain? boolean? #f])
         highlight-sweep-request?]{

Sweeps a filled semantic rectangle behind an unrotated, unscaled text target's
frozen clip-start text box. The highlight is temporary by default; pass
@racket[#:retain? #t] to keep the final rectangle immediately behind the text
in scene drawing order. Its default colour is @tt{#fff2a8}. The target and
helper-ID rules are the same as @racket[underline-sweep].
}

@defproc[(highlight-sweep-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[highlight-sweep].
}

@defproc[(slide-in
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [direction (or/c vec2? 'left 'right 'up 'down)]
          [#:distance distance nonnegative-real? 2])
         enter-request?]{

Returns an @racket[enter] request whose source is @racket[distance] local
world units from the authored endpoint in @racket[direction]. A cardinal symbol
names the side where the Visual begins; a nonzero @racket[vec2] is normalized,
so @racket[distance] always has the same units. The slide preserves authored
opacity rather than adding a fade.
}

@defproc[(slide-out
          [target (or/c visual? symbol? visual-path?)]
          [direction (or/c vec2? 'left 'right 'up 'down)]
          [#:distance distance nonnegative-real? 2])
         leave-request?]{

Returns a @racket[leave] request toward the named local side and removes the
target at the exact endpoint. It preserves the clip-start opacity while the
target slides away.
}

@defproc[(spin-in
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [#:turns turns finite-real? 1])
         enter-request?]{

Returns an @racket[enter] request that rotates through signed
@racket[turns] complete counter-clockwise turns before restoring the exact
authored Visual. Its opacity behavior is the default @racket[enter] behavior.
}

@defstruct*[visual-match ([source-path (listof symbol?)]
                          [destination-path (listof symbol?)])
                         #:transparent]{

An explicit correspondence between two leaf paths relative to the root Visuals
passed to @racket[transform-matching-visuals]. The empty path names an atomic
root. Every selected source and destination leaf may occur in at most one
explicit match.
}

@defproc[(cubic-bezier [#:x1 x1 (and/c finite-real? (>=/c 0) (<=/c 1)) 1/4]
                       [#:y1 y1 finite-real? 1/10]
                       [#:x2 x2 (and/c finite-real? (>=/c 0) (<=/c 1)) 1/4]
                       [#:y2 y2 finite-real? 1])
         rate-function?]{

Returns a CSS/Manim-style cubic Bézier timing curve. Its @racket[x] controls
are limited to the unit interval, so the implementation can deterministically
invert time with bisection; @racket[y] controls may overshoot.
}

@defproc[(spring [#:frequency frequency positive-real? 3]
                 [#:damping damping nonnegative-real? 6])
         rate-function?]{

Returns a damped spring timing curve. Direct intermediate evaluation can
overshoot; scene playback applies its normal unit-progress clamp. Zero and one
remain exact timeline endpoints.
}

@defproc[(change-speed [keyframes (listof (list/c finite-real? positive-real?))])
         rate-function?]{

Builds a rate from a unit-time piecewise-linear speed profile. Each keyframe is
@racket[(list time speed)]; times must strictly increase, begin at zero, and
end at one. Positive speed is integrated and normalized, so speed two travels
twice as much animation distance per wall-clock time as speed one. Use this
semantic value as the @racket[#:easing] of @racket[timed] or
@racket[scene-play].
}

@defproc[(delay-plan? [value any/c]) boolean?]{
Recognizes an immutable delay policy for a deferred mapped composition.
}

@defproc[(index-delay [ratio (and/c finite-real? (>=/c 0))]) delay-plan?]{
Starts each target after @racket[ratio] times its scheduled index. This is the
default policy corresponding to @racket[#:lag-ratio].
}

@defproc[(constant-delay [value (and/c finite-real? (>=/c 0))]) delay-plan?]{
Adds the same explicit lead-in before every mapped child.
}

@defproc[(distance-delay [point vec2?]
                         [scale (and/c finite-real? (>=/c 0))]) delay-plan?]{
Schedules targets by scaled frozen distance from @racket[point], with the
nearest resolved target at offset zero.
}

@defproc[(radial-delay [center vec2?]
                       [scale (and/c finite-real? (>=/c 0))]) delay-plan?]{
The radial spelling of a frozen-position distance delay.
}

@defproc[(wave-delay [direction vec2?]
                     [wavelength positive-real?]
                     [phase finite-real?]) delay-plan?]{
Schedules targets by their frozen projection onto a nonzero direction. The
lowest computed phase is normalized to offset zero.
}

@defproc[(eager-stagger-map
          [targets (or/c list? vector?)]
          [make-request procedure?]
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1/4]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward])
         lagged-start-animation-request?]{

Eagerly maps @racket[make-request] over a nonempty list or vector of targets,
then returns the ordinary @racket[lagged-start] composition of the requests it
produces. @racket[make-request] must accept either one argument
@racket[target], or two arguments @racket[target] and @racket[source-index].
When both arities are accepted, Animate uses the two-argument form. The source
index is the zero-based position in the original collection.

The factory runs exactly once per target, always in original source order.
@racket[#:order 'reverse] reverses only the completed child request list, so it
changes stagger scheduling but never factory evaluation order or source indexes.
@racket[#:order 'forward] is the default. The factory must produce a valid
ordinary composition child; its child-specific capability and conflict rules
are preserved unchanged.

@racket[eager-stagger-map] adds no scheduler node or timing vocabulary: its
@racket[#:lag-ratio] is passed directly to @racket[lagged-start]. Therefore it
has the same intrinsic-span scaling, exact finalization, conflict checking, and
arbitrary-time sampling behavior as an explicitly written @racket[lagged-start]
tree. For example:

@racketblock[
(eager-stagger-map targets
             (lambda (target source-index)
               (move-to target (vec2 (+ 2 source-index) 0)))
             #:lag-ratio 1/5
             #:order 'reverse)]
}

@defproc[(target-sequence? [value any/c]) boolean?]{
Recognizes an immutable deferred target query.
}

@defproc[(concrete-targets [values (or/c list? vector?)]) target-sequence?]{
Creates an immutable target-sequence snapshot from an author-supplied collection.
The collection spine is copied at construction; requests are still instantiated
only when a semantic mapper resolves the sequence.
}

@defproc[(children-of [parent (or/c visual? symbol? visual-path?)]) target-sequence?]{
Describes the direct children of a composite Visual at mapped local start.
}

@defproc[(descendants-of [root (or/c visual? symbol? visual-path?)]
                         [#:where selector (or/c #f procedure?) #f])
         target-sequence?]{
Describes depth-first source-order descendants of a composite Visual. The
optional selector filters resolved Visual values without changing their source
order.
}

@defproc[(selection-targets [selection visual-selection?]) target-sequence?]{
Describes the stable absolute paths held by a semantic visual selection.
}

@defproc[(target-ref? [value any/c]) boolean?]{Recognizes a resolved mapped target.}
@defproc[(target-ref-path [reference target-ref?]) (or/c #f visual-path?)]{
Returns the resolved stable target path when one is available.
}
@defproc[(target-ref-source-index [reference target-ref?]) exact-nonnegative-integer?]{
Returns the query's immutable source-order index.
}
@defproc[(target-ref-scheduled-index [reference target-ref?]) exact-nonnegative-integer?]{
Returns the index assigned after the map's order policy is resolved.
}
@defproc[(procedure-request-template [procedure procedure?]
                                     [#:name name symbol? 'procedure-template])
         request-template?]{
Marks an in-process one-argument target-ref procedure as intentionally
nonserializable. @racket[request-template-serializable?] distinguishes template
families; an arbitrary closure is never treated as project-serializable.
}
@defproc[(named-request-template [name symbol?]) request-template?]{
Creates a transparent serializable template reference. It contains no closure.
Project/worker code must supply a trusted registered implementation for its
name at compilation; ordinary in-process use should use
@racket[procedure-request-template] instead.
}
@defproc[(request-template? [value any/c]) boolean?]{Recognizes a request template.}
@defproc[(request-template-serializable? [value request-template?]) boolean?]{
Reports whether the template protocol marks a representation serializable.
}

@defproc[(parallel-map
          [targets target-sequence?]
          [template (or/c request-template? procedure?)]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward])
         any/c]{
Creates a deferred semantic map whose resolved children share one local start.
}

@defproc[(successive-map
          [targets target-sequence?]
          [template (or/c request-template? procedure?)]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward])
         any/c]{
Creates a deferred semantic map whose resolved children compile in succession;
each child sees the exact endpoint state of the prior child.
}

@defproc[(crossfade-subsets
          [targets (or/c list? vector?)]
          [make-entry procedure?]
          [#:exit-template make-exit procedure? fade-out]
          [#:entry-duration entry-duration positive-real? 1]
          [#:hold-duration hold-duration (and/c finite-real? (>=/c 0)) 0]
          [#:overlap overlap (and/c finite-real? (>=/c 0)) 0]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward]
          [#:remove-final? remove-final? boolean? #f])
         animation-group-animation-request?]{

Creates an explicit one-at-a-time handoff. Entry @italic{i} begins, remains for
@racket[entry-duration], optionally holds for @racket[hold-duration], then its
exit starts. Entry @italic{i+1} begins @racket[overlap] before that exit ends.
Thus @racket[#:overlap 0] is an exact non-overlapping handoff, while positive
overlap is a deliberate crossfade. The final entry remains unless
@racket[#:remove-final?] is true. @racket[overlap] may not exceed
@racket[entry-duration].

}

@defproc[(animation-order? [value any/c]) boolean?]{
Recognizes an immutable order policy for collection-expansion helpers.
}

@defproc[(forward-order) forward-order?]{
Constructs the source order policy.
}

@defproc[(forward-order? [value any/c]) boolean?]{
Recognizes a forward order policy.
}

@defproc[(reverse-order) reverse-order?]{
Constructs the reverse source order policy.
}

@defproc[(reverse-order? [value any/c]) boolean?]{
Recognizes a reverse order policy.
}

@defproc[(permutation-order [indices (or/c list? vector?)])
         permutation-order?]{

Constructs an immutable explicit ordering. Indices must be distinct exact
nonnegative integers. @racket[resolve-animation-order] checks that the policy
has exactly one in-range index for every target count before it is used.
}

@defproc[(permutation-order? [value any/c]) boolean?]{
Recognizes an explicit permutation order policy.
}

@defproc[(shuffled-order [#:seed seed exact-integer? 0]) shuffled-order?]{

Constructs a deterministic shuffle policy from an explicit exact-integer seed.
It stores no random generator and never reads global random state.
}

@defproc[(shuffled-order? [value any/c]) boolean?]{
Recognizes a seeded shuffle order policy.
}

@defproc[(resolve-animation-order
          [order animation-order?]
          [count exact-nonnegative-integer?])
         vector?]{

Resolves @racket[order] into an immutable vector of source indices for exactly
@racket[count] targets. A policy can safely be reused with several counts when
it remains valid for each one; explicit permutations report count/range errors
instead of silently dropping or duplicating targets.
}
