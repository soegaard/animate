#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     animate/calculus
                     animate/calculus/render
                     animate/text-content
                     (only-in pict pict?)))

@title[#:tag "reference-calculus"]{Calculus lessons}

@defmodule[animate/calculus
           #:use-sources (animate/calculus/main
                           animate/calculus/private/core)]

This module declares immutable single-variable calculus lessons. It is a
headless semantic API: importing it does not create a Pict, access a font,
open a window, or write a frame. Native conversion is in
@racketmodname[animate/calculus/render].

@defform[(define-calculus-model model-id
           (model [name expression] ...)
           maybe-constraints)]{
Defines @racket[model-id] as an immutable mathematical model. A
@racket[maybe-constraints] clause has the form
@racket[(constraints boolean-expression ...)]. Bindings are ordered: an
expression can use earlier bindings, but not later ones.
}

@defform[(define-calculus-lesson lesson-id
           (model [name expression] ...)
           (views [view-name view-expression] ...)
           clause ...
           (step step-id step-option ... command ...))]{
Defines @racket[lesson-id] as a @racket[calculus-lesson?]. One @racket[model]
or @racket[(use-model model-expression)] clause and one nonempty
@racket[views] clause are required, as is at least one named @racket[step].
The two model clauses are mutually exclusive. @racket[use-model] evaluates
its ordinary lexical expression once, imports that immutable model's public
names into the declaration, and retains its constraints and object identities.
Optional clauses are @racket[roles], @racket[initially],
@racket[constraints], and @racket[timing]. A lesson declaration constructs data
only; compile it explicitly before inspecting values or preparing output.
}

@section{Caption text}

A @racket[step] may supply @racket[#:say] ordinary display text. Strings use
the shared inline-TeX grammar: @tt{$...$} and @tt{\(...\)} are inline
mathematics, while @tt{$$...$$} and @tt{\[...\]} are display mathematics.
Write @tt{\$} for a literal dollar sign. The headless calculus plan retains
caption source without loading TeX; parsing and the formula backend run only in
@racket[prepare-calculus-plan]. The prepared caption is reused by Pict,
Visual, and Scene sampling, so a frame never initiates TeX typesetting or
caption reflow.

For literal source or a programmatic plain-text fallback, require
@racketmodname[animate/text-content] and supply @racket[inline-text],
@racket[tex-span], or @racket[literal-text] as the @racket[#:say] value.
Ordinary string captions still inspect as their authored string through
@racket[calculus-plan-caption]. Structured values inspect as
@racket[text-content?]. Audio narration, speaker notes, and subtitle export
remain plain-text channels; no TeX source is treated as speech automatically.

@defform[(define-calculus-component component-id
           (inputs [name : type] ...)
           (model [name expression] ...)
           (exports name ...)
           maybe-constraints
           maybe-exposition)]{
Defines an immutable lexical component descriptor. The required, nonempty
@racket[exports] list can name declared inputs or private model bindings.
@racket[maybe-constraints] has the usual @racket[constraints] shape and
@racket[maybe-exposition] contains zero or more named @racket[step] forms.
The ordinary structural input types include @racket[Graph], @racket[Function],
@racket[Point], and @racket[Scalar]. Use @racket[(Parameter Scalar)] or
@racket[(Parameter Integer)] to give a component an explicit capability to
change the matching supplied direct parameter; a @racket[Scalar] input remains
read-only even when its value depends on a parameter.

Within a lesson, @racket[(use-component component-expression argument ...)]
creates one distinct instance and @racket[(part instance 'export-name)]
addresses an export. Private bindings are not public addresses. A collapsed
@racket[explain] reveals public exports. An expanded
@racket[(explain instance #:mode 'expanded)] inserts the component's lexical
steps into the caller timeline, retaining their delays, durations, pauses, and
parallel groups. It must be the only command in its enclosing step and cannot
be nested in @racket[together]. During expanded graph exposition, visible
private construction leaves use an internal renderer namespace only when they
have one unambiguous compatible caller graph view. They remain uninspectable.
The local steps have stable paths of the form
@racket['(outer-step instance local-step)]; a local checkpoint appends its
checkpoint name. A replay in another outer step therefore creates a distinct
timeline occurrence without cloning the component's mathematical instance.
While an expanded local step is current, its @racket[#:say] caption takes
precedence over the outer caption. Default auxiliary cleanup hides private
leaves still shown without hiding caller inputs or public exports; the explicit
@racket[#:auxiliaries 'deemphasize] and @racket[#:auxiliaries 'keep] policies
retain them deliberately.
}

Inside a model and its lesson clauses, the contextual vocabulary includes
@racket[parameter], domain constructors such as @racket[closed], held
@racket[function] and @racket[piecewise-function] declarations,
@racket[graph], @racket[point-on], @racket[input-reading],
@racket[derivative-function], @racket[definite-integral],
@racket[graph-view], @racket[formula-view], and exposition commands such as
@racket[show], @racket[hide], @racket[read], @racket[vary],
@racket[approach], @racket[together], and @racket[checkpoint]. These spellings
are not exports that change ordinary Racket code outside a declaration.
@racket[procedure-function] receives an opaque provider through
@racket[(external provider)] and an authored @racket[#:key]. Its declared
finite @racket[#:breaks] are mandatory native graph gaps even when the
provider returns a finite value at that input. Provider exceptions and
non-finite returns remain explicit partial results rather than unexplained
painted holes.

Finite analysis forms preserve source-declared mathematics independently of
frame order. @racket[(sequence (n) expression #:from first-index)] binds an
integer index, @racket[(partial-sum sequence #:from m #:to n)] is inclusive
and returns zero when @racket[n] is smaller than @racket[m], and
@racket[(sequence-points sequence #:through n)] represents only discrete
indexed samples. @racket[iteration-map] and @racket[newton-iteration] compute
an inspected prefix from their declared seed; a Newton derivative must be a
@racket[derivative-function] of that iteration's function. An unavailable
update remains a partial result rather than selecting a new seed.

@racket[level-set], @racket[root-point], and @racket[intersection-point]
validate supplied candidates only; none starts a hidden root search. Sign,
monotonicity, concavity, and feature declarations retain supplied scopes,
categories, and nonempty justifications. They validate that declaration data,
but do not claim to prove an interval theorem from graph samples.

Limit forms preserve a separate limiting context. @racket[neighborhood] and
@racket[punctured-neighborhood] are open domains with positive authored
radii. @racket[limit-statement] validates its direct real parameter, target,
side, and supplied justification without evaluating the source at the target.
@racket[epsilon-delta-condition] requires finite positive epsilon and delta;
@racket[continuity-condition] reports a declared limit/value mismatch as a
contradiction rather than treating it as a display preference.
@racket[asymptote-line] likewise requires its supplied line to match the
finite/infinite shape and value of its limit claim; no asymptote is inferred
from a view boundary.
The public input/output-band parts of an epsilon–delta condition evaluate to
their finite boundary interval and render as clipped graph-view guides, while
the unbounded mathematical band itself remains a semantic region.

Differential constructions retain function provenance: @racket[tangent] and
@racket[linearization] accept only a @racket[derivative-function] declared for
the same held function. @racket[vertical-tangent] is a separate supplied claim
and requires a nonempty justification rather than a fabricated finite slope.
@racket[taylor-polynomial] uses its supplied ordered compatible derivatives;
an empty derivative list produces the constant approximation at its base.
@racket[approximation-error] remains signed, while @racket[error-segment]
joins the two exact graph values at its authored input rather than measuring a
screen distance.
@racket[slope-triangle] derives its directed horizontal and vertical legs,
including signed @racket[dx] and @racket[dy], from an increment or a
nonvertical line and an authored run.
Finite geometric extents are retained: @racket[segment] and @racket[chord]
evaluate as their authored endpoints (including a coincident zero-length
chord), @racket[ray-through] keeps its origin and direction, and
@racket[secant] remains an infinite line. Native graph rendering clips only
infinite extents to the active view; it does not turn a chord into a secant.
@racket[slope] also accepts a nonvertical segment.
Visible increments and slope triangles are likewise drawn from their semantic
@racket[from]/@racket[to] and horizontal/vertical parts, rather than from a
screen angle.
Visible @racket[riemann-rectangles] are prepared from the exact partition,
tag, and function values in the snapshot. Positive and negative contributions
retain their sign when clipped to a graph view.
@racket[trapezoidal-regions] use the same snapshot contract; a cell crossing
the x-axis is split at its mathematical affine zero instead of being painted
as an unsigned polygon.
@racket[partition-marks] place fixed-size ticks at the resolved exact
endpoints on a graph view's mathematical x-axis.
Visible @racket[interval-marker] spans preserve declared open/closed membership
on their selected graph axis, including finite unions, intersections, and holes
from @racket[domain-except]. An @racket[approach-marker] receives its axis and
direction from held semantic data. An @racket[endpoint-marker] is painted
closed after the core verifies an included graph boundary, or open when a
transparent held function body supplies its exact excluded-boundary value. An
unsupported branch-limit endpoint remains unresolved; native drawing does not
invent a circle.
@racket[region-under], @racket[integral-region], and @racket[region-between]
are sampled from their held graph functions, retaining undefined gaps. Areas
between crossing graphs split at their mathematical intersection rather than
selecting one global upper curve.
@racket[sequence-points] render as isolated index/value markers; no continuous
stroke is inferred between integer-indexed sequence values.
@racket[number-line-view] has a native coordinate axis for visible scalar and
selected solution markers; it is not treated as a formula panel.
Visible @racket[sign-chart] intervals are drawn only from their supplied signed
claims and authored finite domains; the renderer does not sample a graph to
establish their signs.
Formula views prepare held @racket[formula], @racket[formula-of], and
@racket[value-readout] rows from semantic references and current snapshot
values. In particular, @racket[ref] keeps symbolic quantity identity while
@racket[value] and readouts display the live value, including approximate-result
provenance; formulas are never recovered from opaque descriptor printouts.
Rows without an explicit @racket[value] leaf are resolved once during native
preparation and reused across frames. Rows with a value leaf, and readouts,
remain snapshot-dependent.
Visible @racket[newton-diagram] objects draw each available finite update as
its semantic graph-point-to-next-axis-intercept construction. A failed or
unavailable update is not extrapolated by the renderer.
Native panel planning respects the selected layout's deterministic panel order
and @racket[stacked]/@racket[side-by-side] arrangement. Repeating an object in
two views creates two presentations of the same snapshot value, not two
animated copies.
Use @racket[(show (in-view plot G))] or @racket[(hide (in-view plot G))] to
change only that presentation; @racket[show] or @racket[hide] on a declared
view name controls its whole presentation container. A
@racket[calculus-snapshot-visible?] query with @racket[#:view] reports one
named presentation, while an unqualified query reports whether the object is
visible in any declared view.
Labels retain their mathematical anchors while the native adapter assigns a
stable candidate slot by label identity. Colliding labels use a bounded
clockwise fallback and a leader line rather than moving an anchor or depending
on frame request order.
For a graph view declared with @racket[#:scale 'equal], native preparation
letterboxes the declared coordinate window so the two mathematical axes use
equal pixels per unit. @racket['independent] continues to use the full panel;
neither policy changes a mathematical slope or point coordinate.
With @racket[#:y 'auto], preparation uses the layout profile's fixed
representative sampling policy to fit finite visible graph/point evidence once
over the prepared lesson, then retains that padded vertical window for all
still and scene requests. Infinite lines and bands do not create an arbitrary
fit, and reversed or sparse frame selection cannot trigger a new one. If no
finite fit evidence is available, preparation requires an explicit
@racket[#:y] interval.
An @racket[asymptote-line] is rendered only after its supplied limit claim and
line shape have been semantically checked; an unresolved claim does not create
a decorative asymptote.
Input and coordinate readings share the same snapshot-owned point and guide
construction in graph views, so their markers and axes remain mathematically
attached under any camera window.

@racket[trace] accepts a @racket[trace-of] locus only when it uses one direct
real parameter over a closed, finite, increasing interval and that parameter
starts at the interval's left endpoint. An invalid sweep is diagnosed during
plan compilation and leaves sampled parameter state unchanged; a preceding
@racket[set-parameter] can establish a valid start. The locus is evaluated
from its sweep definition at every sampled state: @racket[trace] exposes only
the prefix through the current sweep coordinate, while @racket[show] reveals
the same locus in full. Undefined points remain mathematical gaps.

Children of @racket[together] share one pre-group state. The compiler rejects
a group whose children write the same parameter, the same persistent
presentation property of overlapping targets, or the same view window. A
rejected group leaves no partial sampled updates behind.

@racket[snapshot-of] accepts @racket[#:values] bindings written as
@racket[([parameter constant] ...)]. It fixes the requested object at those
values, while unlisted parameters use the model or lesson's compiled initial
values, including compile-time overrides. It never captures a live rendered
frame.

@racket[limit-transition] requires a matching finite slope-limit claim for
two nonvertical lines through the same anchor in a shared graph view. The
source must be visible and the distinct target hidden at action start. A valid
transition hides the finite source and reveals the target without assigning
the limit to the approaching parameter; an invalid transition leaves
presentation state unchanged.

@racket[focus] and @racket[restore-view] act only on a declared graph view.
Focus evaluates and freezes its finite x/y window at action start, then changes
only the view's camera window; it does not mutate graph domains, points, or
parameters. In a view with @racket[#:y 'auto], the focus track uses the same
preparation-time frozen fit as its baseline, without refitting any frame.
@racket[restore-view] returns to the declared or frozen auto-fit initial
window.

Profiles are immutable presentation policy. A @racket[calculus-theme] can
inherit a base theme and append ordered @racket[calculus-style] rules. A rule
may select kind, declared role, presentation state, public target address, and
view. Each cosmetic property cascades independently; specificity compares view,
target, state, role, and kind in that order, and later equal-specificity rules
win. A derived theme inherits its base colors and rules.

@racketblock[
(define emphasis-profile
  (calculus-profile
   #:theme
   (calculus-theme
    #:base dark-calculus-theme
    #:rules
    (list (calculus-style #:kind 'point #:fill "#79B8FF"
                          #:marker-radius (calculus-px 5))
          (calculus-style #:target 'R #:stroke "#79B8FF"
                          #:dash 'solid)))))]

Styles may set stroke/fill colors (including alpha), stroke width, dash,
opacity, marker radius, and formula font size. They change native paint only:
coordinates, identities, finite cells, endpoint topology, and sampled values
remain semantic. An unknown style root address or view produces a compilation
diagnostic rather than being silently ignored by native output.

The selected @racket[calculus-motion] @racket[#:parameter-easing] policy
determines only intermediate @racket[vary], @racket[approach], and
@racket[trace] positions. Both @racket['linear] and @racket['smoothstep]
preserve the same authored start, endpoint, and domain path.

@section{Policies and headless inspection}

The ordinary public values below construct immutable policy data or inspect
immutable semantic data. They do not create native drawing objects.

@defproc*[
 ([(calculus-lesson? [value any/c]) boolean?]
  [(calculus-model? [value any/c]) boolean?]
  [(calculus-component? [value any/c]) boolean?]
  [(calculus-plan? [value any/c]) boolean?]
  [(calculus-snapshot? [value any/c]) boolean?]
  [(calculus-result? [value any/c]) boolean?]
  [(calculus-moment? [value any/c]) boolean?]
  [(calculus-profile? [value any/c]) boolean?]
  [(calculus-theme? [value any/c]) boolean?]
  [(calculus-style? [value any/c]) boolean?]
  [(calculus-layout? [value any/c]) boolean?]
  [(calculus-motion? [value any/c]) boolean?]
  [(calculus-timing? [value any/c]) boolean?]
  [(calculus-computation? [value any/c]) boolean?]
  [(calculus-length? [value any/c]) boolean?])] {
Recognize the corresponding immutable calculus value. These predicates do not
force provider evaluation or native preparation.
}

@defproc*[
 ([(calculus-px [value real?]) calculus-length?]
  [(calculus-rel [value real?]) calculus-length?]
  [(calculus-em [value real?]) calculus-length?])] {
Construct a nonnegative finite presentation length in output pixels, relative
canvas units, or annotation ems. Mathematical coordinates and domains do not
use cosmetic lengths.
}

@defproc*[
 ([(calculus-lesson-model [lesson calculus-lesson?]) calculus-model?]
  [(calculus-model-at [model calculus-model?]
                      [#:values values hash? (hash)]
                      [#:computation computation calculus-computation?
                       default-calculus-computation])
   calculus-snapshot?])] {
Expose a lesson's immutable mathematical model or sample a model directly.
Neither operation creates a view, a Pict, or a native output asset.
}

@defproc*[
 ([(calculus-plan-duration [plan calculus-plan?]) nonnegative-real?]
  [(calculus-plan-diagnostics [plan calculus-plan?]) list?]
  [(calculus-snapshot-diagnostics [snapshot calculus-snapshot?]) list?])] {
Return immutable duration or diagnostic data. Diagnostics describe source-level
validation facts rather than native pixels.
}

@defproc*[
 ([(calculus-step-start [address (or/c symbol? list?)]) calculus-moment?]
  [(calculus-step-end [address (or/c symbol? list?)]) calculus-moment?]
  [(calculus-checkpoint [address (or/c symbol? list?)]) calculus-moment?])] {
Construct exact semantic selectors for named steps or checkpoints, preserving
authored boundaries even when numeric timestamps coincide.
}

@defproc*[
 ([(calculus-result-status [result calculus-result?]) symbol?]
  [(calculus-result-method [result calculus-result?]) symbol?]
  [(calculus-result-approximate? [result calculus-result?]) boolean?]
  [(calculus-result-value [result calculus-result?]) any/c]
  [(calculus-result-message [result calculus-result?]) (or/c #f string?)]
  [(calculus-result->datum [result calculus-result?]) hash?])] {
Inspect result status, provenance, approximation, value, optional message, or
renderer-free data. A nondefined result has value @racket[#f]; use its status
to distinguish that from a defined Boolean false.
}

@defproc[(calculus-style [#:kind kind any/c #f]
                         [#:role role any/c #f]
                         [#:state state any/c #f]
                         [#:target target any/c #f]
                         [#:view view any/c #f]
                         [#:stroke stroke any/c 'inherit]
                         [#:fill fill any/c 'inherit]
                         [#:stroke-width stroke-width any/c 'inherit]
                         [#:dash dash any/c 'inherit]
                         [#:opacity opacity any/c 'inherit]
                         [#:marker-radius marker-radius any/c 'inherit]
                         [#:font-size font-size any/c 'inherit]
                         [#:label-gap label-gap any/c 'inherit])
         calculus-style?] {
Builds one selector-based cosmetic rule. Matching rules cascade by specificity,
with later equally-specific rules taking precedence.
}

@defproc[(calculus-theme [#:base base any/c #f]
                         [#:background background any/c #f]
                         [#:foreground foreground any/c #f]
                         [#:font-family font-family any/c #f]
                         [#:font-size font-size any/c #f]
                         [#:rules rules list? '()])
         calculus-theme?] {
Builds an immutable theme and, when supplied, inherits unset properties and
ordered rules from its base theme.
}

@defproc[(calculus-layout [#:arrangement arrangement symbol? 'auto]
                          [#:panel-order panel-order any/c #f]
                          [#:margin margin calculus-length? (calculus-rel 1/20)]
                          [#:gap gap calculus-length? (calculus-rel 1/30)]
                          [#:captions? captions? boolean? #t]
                          [#:caption-height caption-height calculus-length? (calculus-rel 7/50)]
                          [#:label-policy label-policy symbol? 'stable]
                          [#:fit-samples fit-samples exact-positive-integer? 257])
         calculus-layout?] {
Builds deterministic panel, caption, automatic-fit, and label-placement policy.
}

@defproc[(calculus-motion [#:graph-reveal graph-reveal symbol? 'trace]
                          [#:line-reveal line-reveal symbol? 'extend]
                          [#:reading reading symbol? 'guided]
                          [#:parameter-easing parameter-easing symbol? 'linear]
                          [#:refinement refinement symbol? 'subdivide]
                          [#:limit-transition limit-transition symbol? 'crossfade]
                          [#:focus focus symbol? 'pan-zoom]
                          [#:highlight highlight symbol? 'outline]
                          [#:reduced-motion? reduced-motion? boolean? #f])
         calculus-motion?] {
Builds presentation-motion policy without changing mathematical values, domains,
or named moments.
}

@defproc[(calculus-timing [#:opening-pause opening-pause real? 3/5]
                          [#:read-delay read-delay real? 1]
                          [#:action-duration action-duration real? 1]
                          [#:step-pause step-pause real? 3/5])
         calculus-timing?] {
Builds default temporal policy in seconds. Values must be finite and
nonnegative.
}

@defproc[(calculus-profile [#:theme theme calculus-theme? light-calculus-theme]
                           [#:layout layout calculus-layout? (calculus-layout)]
                           [#:motion motion calculus-motion? (calculus-motion)]
                           [#:timing timing calculus-timing? (calculus-timing)])
         calculus-profile?] {
Combines independently replaceable theme, layout, motion, and timing policy.
}

@defproc[(calculus-computation [#:absolute-tolerance absolute-tolerance real? 1e-10]
                               [#:relative-tolerance relative-tolerance real? 1e-8]
                               [#:derivative-step derivative-step real? 1e-4]
                               [#:integration-method integration-method symbol? 'adaptive-simpson]
                               [#:integration-budget integration-budget exact-positive-integer? 10000])
         calculus-computation?] {
Builds numerical-analysis policy independently of native rendering. Tolerances
and derivative step must be positive finite reals.
}

@defthing[light-calculus-theme calculus-theme?]{The complete light theme.}
@defthing[dark-calculus-theme calculus-theme?]{The complete dark theme.}
@defthing[classroom-light-profile calculus-profile?]{The standard light teaching profile.}
@defthing[classroom-dark-profile calculus-profile?]{The standard dark teaching profile.}
@defthing[textbook-profile calculus-profile?]{The reduced-motion textbook profile.}
@defthing[default-calculus-profile calculus-profile?]{The default classroom-light profile.}
@defthing[default-calculus-computation calculus-computation?]{The standard numerical-analysis policy.}

@defproc[(compile-calculus-lesson [lesson calculus-lesson?]
                                  [#:profile profile calculus-profile? default-calculus-profile]
                                  [#:values values hash? (hash)]
                                  [#:computation computation calculus-computation?
                                   default-calculus-computation])
         calculus-plan?]{
Compiles an immutable, headless timing plan. Overrides name only declared
parameters and must satisfy their declared domains.
}

@defproc[(calculus-plan-sample [plan calculus-plan?]
                               [#:at at (or/c 'initial 'final real? calculus-moment?) 'final])
         calculus-snapshot?]{
Samples a mathematical/presentation state without native rendering. Numeric
boundaries are right-continuous; use @racket[calculus-step-start],
@racket[calculus-step-end], or @racket[calculus-checkpoint] when an exact
semantic phase is important.
}

@defproc[(calculus-snapshot-ref [snapshot calculus-snapshot?]
                                [address (or/c symbol? (listof symbol?))])
         calculus-result?]{
Returns a structured result for a public object or part address. A nondefined
result has value @racket[#f]; distinguish it through
@racket[calculus-result-status], which reports @racket['defined],
@racket['outside-domain], @racket['undefined], or @racket['unresolved].
}

@defproc[(calculus-snapshot-visible? [snapshot calculus-snapshot?]
                                     [address (or/c symbol? (listof symbol?))]
                                     [#:view view (or/c #f symbol?) #f])
         boolean?]{
Reports effective presentation visibility. Mathematical existence and
visibility are deliberately independent. With @racket[#:view], the result is
for that declared presentation only; without it, the result is true when the
address is visible in at least one declared view.
}

@defmodule[animate/calculus/render
           #:use-sources (animate/calculus/render
                           animate/calculus/main
                           animate/calculus/private/core)]

The render adapter re-exports @racketmodname[animate/calculus] and is the
explicit bridge to native output.

@defproc*[
 ([(calculus-render-quality [#:curve-tolerance curve-tolerance real? 1/2]
                            [#:max-depth max-depth exact-positive-integer? 18])
   calculus-render-quality?]
  [(calculus-render-quality? [value any/c]) boolean?])] {
Construct or recognize bounded native curve-sampling policy. It controls
geometric approximation only, never calculus integration or derivative policy.
The curve tolerance must be a positive finite real pixel deviation and the
subdivision limit a positive exact integer.
}

@defproc[(prepare-calculus-lesson [lesson calculus-lesson?]
                                  [#:profile profile calculus-profile?
                                   default-calculus-profile]
                                  [#:values values hash? (hash)]
                                  [#:computation computation calculus-computation?
                                   default-calculus-computation]
                                  [#:width width exact-positive-integer? 1280]
                                  [#:height height exact-positive-integer? 720]
                                  [#:formula-backend formula-backend any/c 'default]
                                  [#:quality quality calculus-render-quality?
                                   (calculus-render-quality)])
         prepared-calculus-lesson?]{
Compiles and binds one lesson to a native output size. Use
@racket[prepare-calculus-plan] when a plan is already available.
}

@defproc[(prepared-lesson->pict [prepared prepared-calculus-lesson?]
                                [#:at at any/c 'final])
         pict?]{
Returns the prepared Pict at one semantic moment. The companion
@racket[prepared-lesson->visual] and @racket[prepared-lesson->scene] use the
same prepared composition and dimensions.
}

@defproc*[
 ([(prepare-calculus-plan [plan calculus-plan?]
                           [#:width width exact-positive-integer? 1280]
                           [#:height height exact-positive-integer? 720]
                           [#:formula-backend formula-backend any/c 'default]
                           [#:quality quality calculus-render-quality?
                            (calculus-render-quality)])
   prepared-calculus-lesson?]
  [(prepared-calculus-lesson? [value any/c]) boolean?]
  [(prepared-lesson-plan [prepared prepared-calculus-lesson?]) calculus-plan?]
  [(prepared-lesson->scene [prepared prepared-calculus-lesson?]) any/c]
  [(prepared-lesson->visual [prepared prepared-calculus-lesson?]
                            [#:at at any/c 'final])
   any/c])] {
Prepare an already compiled plan, recognize a prepared lesson, recover its
immutable plan, or adapt the shared prepared composition to a scene or Visual.
Preparation owns measured layout and assets; these conversions do not prepare
again.
}

@defproc[(lesson->pict [lesson calculus-lesson?]
                       [#:at at (or/c 'initial 'final real? calculus-moment?) 'final]
                       [#:profile profile calculus-profile?
                        default-calculus-profile]
                       [#:values values hash? (hash)]
                       [#:computation computation calculus-computation?
                        default-calculus-computation]
                       [#:width width exact-positive-integer? 1280]
                       [#:height height exact-positive-integer? 720]
                       [#:formula-backend formula-backend any/c 'default]
                       [#:quality quality calculus-render-quality?
                        (calculus-render-quality)])
         pict?]{
Prepares the lesson for this one call, then returns its shared semantic Pict.
@racket[lesson->visual] accepts the same keywords and returns a Visual;
@racket[lesson->scene] accepts the preparation keywords except @racket[#:at]
and returns the full prepared scene. For multiple outputs or stills, prepare
once explicitly and use the @racket[prepared-lesson->...] operations.
}

@defthing[lesson->scene procedure?]{Prepares one lesson and returns its
shared native scene composition. It accepts the preparation keywords of
@racket[lesson->pict], except @racket[#:at].}

@defthing[lesson->visual procedure?]{Prepares one lesson and returns the
shared native Visual at the requested semantic moment. It accepts the same
keywords as @racket[lesson->pict].}

@section{Release review}

The repository-owned development runner @tt{calculus/review-examples.rkt} is
not part of either public calculus module. It prepares every complete Guide
lesson once per selected profile and writes sparse, full-resolution PNG stills,
contact sheets, optional short MP4 transition clips, a local HTML index, and a
non-public evidence manifest. It
refuses to replace an existing output directory. Use it after the automated
native and process gates, for example:

@verbatim{|{
/Applications/Racket\ v9.3.0.2/bin/racket calculus/review-examples.rkt \
  --all --profiles light,dark,textbook --workers 10 --clips --output calculus-review
}|}

The @tt{--workers} value is recorded with the review evidence. Sparse stills
are made from the shared prepared Pict adapter and do not send Pict closures to
workers; @tt{calculus/run-tests.rkt --process} separately verifies the real
reconstructible project-rendering worker path. @tt{--clips} requires
@tt{ffmpeg} on @tt{PATH}; omit it when only still evidence is needed.
