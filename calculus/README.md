# animate/calculus

`animate/calculus` is Animate's immutable, headless calculus lesson layer.
It keeps mathematical evaluation and exposition separate from native drawing;
`animate/calculus/render` explicitly prepares the same lesson for a Pict,
Visual, or scene.

```racket
#lang racket/base
(require animate/calculus
         animate/calculus/render)

(define-calculus-lesson reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R))])
  (initially (show G))
  (step read-output (read R))
  (step vary-input (vary a #:to -2 #:duration 4)))

(define plan (compile-calculus-lesson reading-square))
(calculus-result-value
 (calculus-snapshot-ref (calculus-plan-sample plan #:at 'final)
                        '(R output))) ; => 4

(define prepared (prepare-calculus-plan plan #:width 1280 #:height 720))
(prepared-lesson->pict prepared)
(prepared-lesson->scene prepared)
```

The core module performs no typesetting, native drawing, GUI work, file I/O,
or frame rendering. Results preserve ordinary mathematical partiality:
`'outside-domain`, `'undefined`, and `'unresolved` are distinct from a defined
value. Inspect `calculus-result-status` before treating a result's value as a
number.

## Module boundary

| Module | Responsibility |
| --- | --- |
| `animate/calculus` | Declaration macros, immutable models, domains, held functions, headless plans, snapshots, profiles, and computation policy. |
| `animate/calculus/render` | Explicit output preparation plus shared Pict, Visual, and Animate scene conversion. |

Use `define-calculus-model` when an immutable mathematical model is shared
outside an individual lesson, then write `(use-model shared-model)` in place
of a lesson's `model` clause. Its public names are available to the lesson's
views, constraints, and steps while their identities and shared constraints
are retained. `define-calculus-component` creates a reusable
lexical component: `use-component` evaluates its exported parts against the
caller's live values while its private bindings remain unaddressable.
Component exports may name inputs or private-model bindings. Component input
types include `Graph`, `Function`, `Point`, and `Scalar`, plus the explicit
capabilities `(Parameter Scalar)` and `(Parameter Integer)`. A scalar input is
read-only even when its supplied value is a live parameter; only a matching
`Parameter` input lets the component's exposition change that caller parameter.

`(explain study #:mode 'collapsed)` reveals the instance's public drawable
exports as one presentation. In expanded mode, the declaration's own named
steps are inserted into the caller's headless timeline with their local
durations, delays, pauses, and `together` behavior. An expanded explanation
must be the only command in its enclosing step and cannot occur in `together`.
Its local steps have stable nested moment paths such as
`'(outer-step study local-step)`; checkpoints append their own name to that
path. Replaying the same instance in another outer step therefore creates a
new timeline occurrence without cloning its mathematics. Local `#:say`
captions take precedence while their nested step is current; otherwise the
enclosing step's caption remains current.
Private construction objects remain unavailable through `part` or snapshot
addresses. During an expanded graph construction they can be rendered through
the instance's internal namespace only when exactly one caller graph view is
compatible with their related public exports. Default `#:auxiliaries 'hide`
cleanup hides any private leaves still shown, without hiding a caller input or
public export; use `deemphasize` or `keep` only when that retained private
presentation is intentional.
Contextual mathematical forms such as `function`,
`graph`, `show`, and `read` are valid only within calculus declarations; they
do not replace ordinary Racket bindings elsewhere in the module.
`procedure-function` accepts its provider through `(external provider)` and
requires an authored `#:key`; it remains an opaque mathematical source.
Declared finite `#:breaks` are mandatory native graph gaps even if the provider
returns a finite value at that input. Provider exceptions and non-finite
returns remain explicit partial results rather than unexplained painted holes.

Finite analysis remains semantic data rather than render-frame state:
`sequence` binds an integer index at or above `#:from`, `partial-sum` is
inclusive (and yields zero for an empty range), and `iteration-map` and
`newton-iteration` evaluate every inspected prefix from their declared seed.
`sequence-points` returns only discrete indexed samples. Newton iteration
requires a derivative declared for the same function and reports a partial
result when a derivative or an update is unavailable; it never restarts from
another seed.

Candidate constructors (`level-set`, `root-point`, and `intersection-point`)
validate only author-supplied candidates. They do not search for roots.
Analysis claims retain their supplied domain, category, and nonempty
justification; they are not upgraded to machine-proved theorems.

Limits use the same distinction. `neighborhood` and
`punctured-neighborhood` retain open-domain boundaries and require positive
radii. A `limit-statement` validates its direct real parameter, target, side,
and justification without evaluating the source expression at the limiting
target. Epsilon–delta conditions require finite positive epsilon and delta;
continuity conditions report a declared limit that conflicts with the actual
function value rather than silently displaying it as continuous.
An `asymptote-line` must similarly match the finite/infinite shape and value
of its supplied limit claim; it is not inferred from the edge of a view.
The public input/output-band parts of an epsilon–delta condition evaluate to
their finite boundary interval and render as clipped graph-view guides, while
the unbounded mathematical band itself remains a semantic region.

For differential constructions, `tangent` and `linearization` require a
`derivative-function` declared for the same held function. A
`vertical-tangent` is a separate supplied claim and therefore requires its own
nonempty justification rather than a fabricated finite slope.
`taylor-polynomial` evaluates the supplied ordered compatible derivatives;
with no derivatives it is the documented constant approximation at its base.
`approximation-error` remains signed, and `error-segment` joins the two exact
graph values at its authored input rather than measuring a screen distance.
`slope-triangle` derives directed horizontal and vertical legs, including
signed `dx` and `dy`, from an increment or a nonvertical line and authored run.
Finite geometric extents are retained: `segment` and `chord` evaluate as the
authored endpoints (including a coincident zero-length chord), `ray-through`
keeps its origin and direction, and `secant` remains an infinite line. Native
graph rendering clips only infinite extents to the active view; it does not
turn a chord into a secant. `slope` also accepts a nonvertical segment.
Visible increments and slope triangles are likewise drawn from their semantic
`from`/`to` and horizontal/vertical parts, rather than from a screen angle.
Visible `riemann-rectangles` are prepared from the exact partition, tag, and
function values in the snapshot. Positive and negative contributions retain
their sign when clipped to a graph view.
`trapezoidal-regions` use the same snapshot contract; a cell crossing the
x-axis is split at its mathematical affine zero instead of being painted as
an unsigned polygon.
`partition-marks` place fixed-size ticks at the resolved exact endpoints on a
graph view's mathematical x-axis.
Visible `interval-marker` spans preserve declared open/closed membership on
their selected graph axis, including finite unions, intersections, and holes
from `domain-except`. An `approach-marker` receives its axis and direction
from the held declaration. An `endpoint-marker` is painted closed after the
core verifies an included graph boundary, or open when a transparent held
function body supplies its exact excluded-boundary value. An unsupported
branch-limit endpoint remains unresolved; the renderer does not invent a
circle.
`region-under`, `integral-region`, and `region-between` are sampled from their
held graph functions, retaining undefined gaps. Areas between crossing graphs
split at their mathematical intersection rather than selecting one global
upper curve.
`sequence-points` render as isolated index/value markers; no continuous stroke
is inferred between integer-indexed sequence values.
`number-line-view` has a native coordinate axis for visible scalar and selected
solution markers; it is not treated as a formula panel.
Visible `sign-chart` intervals are drawn only from their supplied signed claims
and authored finite domains; the renderer does not sample a graph to establish
their signs.
Formula views prepare held `formula`, `formula-of`, and `value-readout` rows
from semantic references and current snapshot values. In particular, `ref`
keeps symbolic quantity identity while `value` and readouts display the live
value (including approximate-result provenance); formulas are never recovered
from opaque descriptor printouts. A formula with no explicit `value` leaf is
resolved once when native output is prepared and reused across frames; rows
with live values and readouts remain snapshot-dependent. Native formula rows
are typeset through the selected existing Formula/Pict backend (the default is
the project's TeX backend), including dark-profile foreground color; ordinary
graph annotations remain upright native text.
Visible `newton-diagram` objects draw each available finite update as its
semantic graph-point-to-next-axis-intercept construction. A failed or
unavailable update is not extrapolated by the renderer.
Native panel planning respects the selected layout's deterministic panel order
and `stacked`/`side-by-side` arrangement. Repeating an object in two views
creates two presentations of the same snapshot value, not two animated copies.
Use `(show (in-view plot G))` or `(hide (in-view plot G))` to change only
that presentation; `show` or `hide` on a declared view name controls its
whole presentation container. `(calculus-snapshot-visible? snapshot 'G
#:view 'plot)` reports one named presentation, while the unqualified query
reports whether the object is visible in any declared view.
Labels retain their mathematical anchors while the native adapter assigns a
stable candidate slot by label identity. Colliding labels use a bounded
clockwise fallback and a leader line rather than moving an anchor or depending
on frame request order.
For a graph view declared with `#:scale 'equal`, the native adapter letterboxes
the declared coordinate window to keep equal pixels per mathematical unit;
`'independent` continues to use the full panel without changing any slope or
other mathematical value.
When a graph view declares `#:y 'auto`, preparation samples finite visible
graph/point evidence at the profile's fixed representative states and freezes
one padded vertical window for the whole prepared lesson. Infinite lines and
bands do not manufacture an arbitrary fit, and sparse or reverse frame
selection never recomputes that window. If preparation finds no finite fit
evidence, the lesson must declare `#:y` explicitly.
An `asymptote-line` is rendered only after its supplied limit claim and line
shape have been semantically checked; an unresolved claim does not create a
decorative asymptote.
Input and coordinate readings share the same snapshot-owned point and guide
construction in graph views, so their markers and axes remain mathematically
attached under any camera window.

A `trace` command accepts a `trace-of` locus only when it uses one direct real
parameter over a closed, finite, increasing interval and the parameter starts
at that interval's left endpoint. Invalid sweeps are diagnosed during plan
compilation and do not change the sampled parameter state; a preceding
`set-parameter` can establish a valid trace start. The locus is evaluated from
its sweep definition at every sampled state: a `trace` exposes only the prefix
through the current sweep coordinate, while `show` reveals the same locus in
full. Undefined points stay as mathematical gaps.

`together` children share one pre-group state. The compiler rejects a group
when children write the same parameter, an overlapping target's same
persistent presentation property, or the same view window; rejected groups
leave no partial sampled updates behind.

`snapshot-of` accepts the documented `#:values ([parameter constant] ...)`
bindings. It fixes the requested object at those values; unlisted parameters
use the model or lesson's compiled initial values (including `#:values`
overrides), never whichever frame is currently being sampled.

`limit-transition` verifies a matching finite slope-limit claim for two
nonvertical lines through the same anchor in a shared graph view. Its source
must be visible and its distinct target hidden at action start. A valid
transition hides the finite source line and reveals the target without
assigning the limit to its approaching parameter; an invalid transition leaves
presentation state unchanged.

`focus` and `restore-view` act only on a declared graph view. Focus evaluates
and freezes its finite x/y window at action start, then changes only the view's
camera window; it does not mutate graph domains, points, or parameters.
For a view with `#:y 'auto`, the focus track uses that same preparation-time
frozen fit as its baseline, so focus and restore remain deterministic without
re-fitting a frame. `restore-view` returns to the declared (or frozen auto-fit)
initial window.

## Appearance profiles

Profiles are immutable presentation policy. A `calculus-theme` may inherit a
base theme and add ordered `calculus-style` rules. Rules can select a semantic
kind, declared role, presentation state, public target address, and view. Each
cosmetic property cascades independently: view, target, state, role, and kind
are compared in that order of specificity, with later equal-specificity rules
winning. A derived theme inherits its base background and foreground as well as
its base rules.

```racket
(define emphasis-profile
  (calculus-profile
   #:theme
   (calculus-theme
    #:base dark-calculus-theme
    #:rules
    (list (calculus-style #:kind 'point #:fill "#79B8FF"
                          #:marker-radius (calculus-px 5))
          (calculus-style #:target 'R #:stroke "#79B8FF"
                          #:dash 'solid)))))
```

Styles can set stroke/fill colors (including alpha), stroke width, dash,
opacity, marker radius, and formula font size. Native styling changes only the
prepared paint: graph coordinates, object identities, finite cells, open and
closed endpoint topology, and sampled values stay semantic. A syntactically
valid style that names an unknown root address or view produces a compilation
diagnostic rather than silently disappearing in native output.

The selected `calculus-motion` `#:parameter-easing` policy determines only
intermediate `vary`, `approach`, and `trace` positions. Both `'linear` and
`'smoothstep` preserve the same authored start, endpoint, and domain path.

## Test

From the repository root:

```sh
/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --all
```

The tests sample all six complete Guide lessons headlessly and prepare/rasterize
each one at 1280×720, alongside candidate validation, finite sequences and
Newton prefixes, supplied derivatives, piecewise function values, domains,
deterministic action sampling, component capabilities and private-export
visibility, external functions, and shared native output dimensions.
The core gate also audits the complete ordinary export inventory for both
modules. Use `--core`, `--native`, or `--docs` to run one release gate in
isolation; `--process` runs the ten-worker reconstruction and byte-parity
check and requires the recorded Racket 9.3.0.2 toolchain.

To create a human-review bundle after the automated gates pass, use a new
output directory:

```sh
/Applications/Racket\ v9.3.0.2/bin/racket calculus/review-examples.rkt \
  --all --profiles light,dark,textbook --workers 10 --clips --output calculus-review
```

The bundle contains sparse full-resolution transition stills, paginated contact
sheets, short fixed-cadence MP4 transition clips, a local `index.html`, and a
small manifest that records the selected profiles, dimensions, toolchain, and
companion process-gate worker capacity. `--clips` requires `ffmpeg` on `PATH`;
omit it when only still evidence is needed.
The still renderer intentionally does not transfer Pict closures to workers;
the separately automated `--process` gate certifies real worker reconstruction.
The review command refuses to replace an existing bundle, so retain each
review under a new output name.

To collect a comparable resource baseline without writing frames, run the
complete fixture set at a fixed resolution and retain the fresh datum report:

```sh
/Applications/Racket\ v9.3.0.2/bin/racket calculus/benchmark.rkt \
  --iterations 3 --profiles light,dark,textbook --width 1280 --height 720 \
  --output NEW-BENCHMARK.rktd
```

The report records raw per-repeat timing plus exact compile, preparation,
headless-sampling, and native-bitmap counters. It is evidence for this exact
machine and toolchain, not a portable speed claim.

[`VALIDATION.md`](VALIDATION.md) records which release-evidence layers have
actually run and which review/documentation work remains open.
