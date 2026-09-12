# Implemented geometry DSL — v0.9.3

This is the reference for the code in this delivery. It is narrower than the
original design proposal: features listed as deferred below are not silently
accepted. See `README.md` for installation, example commands, and validation
status.

## 1. The six layers

Mathematics is an immutable, typed dependency graph. Exposition is an ordered
sequence of pedagogical steps. Timing controls the pedagogical rhythm: the pause
before a step, the time allowed to read its narration, the duration of visual
actions, and the pause after a completed step. Presentation records visibility,
label visibility, and persistent deemphasis separately from transient highlighting.
Layout chooses a representative realization and one fixed view. Styling describes
geometry kinds, paint channels, and presentation-state treatments.

The compiler collects the complete construction before realizing its geometry.
The timeline does not execute a geometric construction afresh on every frame.
`hide` never removes an object from the mathematical graph.

## 2. Entry points

```racket
(require "geometry/core.rkt")    ; mathematics, DSL, layout, themes, timeline
(require "geometry/main.rkt")    ; all of core, plus native animate conversion
(require "geometry/render.rkt")  ; effectful image/video/subtitle output
(require "geometry/review.rkt")  ; sparse step-review images, contact sheets and ZIPs
(require (prefix-in c: "geometry/constructions.rkt")) ; standard library
;; core.rkt/main.rkt already re-export transformations.rkt and labels.rkt.
;; The latter two are also available as focused headless entry points.
```

These examples assume the importing file is in the `animate` repository root.
Adjust relative paths for another location. Installed collection paths are
`animate/geometry/core`, `animate/geometry/main`, `animate/geometry/render`, and
`animate/geometry/constructions`. Focused new entry points are
`animate/geometry/transformations` and `animate/geometry/labels`.

The geometry primitives are not the same bindings as the native `animate` Visual
constructors. Prefix an import when using both APIs.

## 3. Standalone constructions

```racket
(construction name
  (given binding ...)
  (require predicate ...)
  (layout hint ...)
  (style object-style ...)
  (initially command ...)
  (step optional-narration form ...)
  ...
  (result id ...))
```

`construction` **defines** `name` as a `geometry-program` value. It is not a
function call that renders a video. Exactly one `given` clause is required;
it may be empty. All other kinds of clause are optional. `result` is optional
for standalone programs.

A binding is `[id expression]`. A multi-result binding is
`[(id ...) expression]`. Ordinary geometry references must already be defined;
forward references and duplicate names are errors. `layout`, `style`, and
`initially` may refer forward. Names starting with `$` are reserved for generated
helper identities.

Bindings are construction-local symbolic names, not exported Racket variables.
Use `(construction-ref realization 'A)` to inspect an actual realized value.

```racket
(given [A (point -2 0)]
       [B (point)])
```

`A` has explicit coordinates; `B` is a free given. Free `(point)` is accepted
only as a named given. Outside the DSL, the ordinary `point` constructor requires
two coordinates. Anonymous nested geometry is supported:

```racket
(given [l (line (point -3 0) (point 3 0))]
       [P (point 0 0)])
```

The nested defining points are not independently drawn or labelled.

## 4. Geometry and expression vocabulary

The public mathematical value types are `Point`, `Line`, `Segment`, `Ray`,
`Circle`, `Marker`, `Label`, `Number`, `Angle`, `Side`, `Relation`, `Vector`,
`Transform`, and `Text`. Points use Cartesian coordinates with positive y upward.
`Angle`, `Side`, `Relation`, `Number`, `Vector`, `Transform`, and `Text` are
nondrawable values; binding them does not create a visual action. `Label` is an
independently controlled annotation attached to geometry.
A line, segment, ray, or circle needs distinct defining points.

| Expression | Meaning |
|---|---|
| `(point x y)` | Point at the supplied world coordinates. |
| `(point)` | Free given point, within the DSL only. |
| `(segment A B)` | Finite segment from A to B. |
| `(line A B)` | Infinite line, directed from A toward B for selectors. |
| `(ray A B)` | Ray starting at A and directed toward B. |
| `(circle A B)` | Circle centred at A and passing through B. |
| `(circle O #:radius r)` | Circle centred at O with a finite positive radius. |
| `(start-point x)` / `(end-point x)` | First/second defining point of a Line, Segment, or Ray. |
| `(angle A B C)` | Nondrawable Angle descriptor with vertex B. |
| `(angle-first a)` / `(angle-vertex a)` / `(angle-last a)` | Defining points of an Angle. |
| `'left` / `'right` | Values of type Side, usable as helper arguments. |
| `(side-of? P l side)` | Whether P is strictly on the selected side of directed l. |
| `(midpoint A B)` | Derived midpoint. |
| `(distance A B)` | Numerical distance. |
| `(length AB)` | Length of a segment. |
| `(center c)` | Centre of a circle. |
| `(intersection c d ...)` | Exactly one selected intersection. |
| `(intersections c d)` | All isolated intersections, in deterministic order. |

Arithmetic `+`, `-`, `*`, `/`, comparisons `=`, `<`, `>`, `<=`, `>=`, Boolean
`and`, `or`, `not`, and predicates `distinct?`, `noncollinear?`, and `on` are
accepted in the checked expression algebra. `Number` values are useful for
calculations and helper parameters. Length and angle Labels can display computed
measurements; generic numeric-display widgets are not part of this DSL.
Explicit presentation commands and visual layout/style targets must be drawable
geometry or Label values, not Number, Angle, Side, Relation, Vector, Transform,
or Text bindings. See section 21 for transformation expressions and semantic
label constructors.

The DSL remains a closed expression language. It does **not**
call `eval`, and arbitrary Racket applications or external variables inside a
geometry expression are not supported. Helper names are the exception: the macro
preserves their lexical Racket bindings. Supply concrete external data through
`#:givens` or `#:choices`, or use the ordinary mathematical value constructors
outside the DSL.

## 5. Intersections

```racket
[C (intersection cA cB #:side-of AB 'left)]
[B (intersection cP l #:other-than A)]
[P (intersection c l #:near Q)]
[Q (intersection c l #:far-from P)]
[(C D) (intersections cA cB)]
```

`#:side-of` accepts a directed line, segment, or ray and a `Side` value:
`'left`, `'right`, or a named/typed helper parameter of that type.
It is geometric orientation, not “top of the screen.” `#:other-than` first
checks that the excluded point really is an intersection. `#:near` and
`#:far-from` require a unique nearest/farthest candidate; ties are errors.

Without a selector, `intersection` requires exactly one point. It does not pick
an arbitrary first point when two exist. A destructuring binding checks its
expected cardinality during realization. Tangency produces one point; an empty
intersection produces no points. Coincident circles and positive-length linear
overlaps denote infinitely many points and are diagnosed rather than represented
as a finite list. Disjoint collinear segments return no points; touching ones
return their common endpoint.

For circle/circle intersections, the first result is on the left of the directed
line from the first centre to the second. For circle/linear intersections, results
are ordered along the linear object's defining direction. Segment and ray
boundaries are respected. Use semantic selectors when the order matters to the
explanation.

The numerical kernel uses floating-point calculations where needed and a
scale-relative tolerance. It is not an exact algebraic geometry engine.

## 6. Preconditions and type checking

```racket
(require (distinct? A B))
(require (on P l))
(require (noncollinear? A B C))
```

These are mathematical checks, separate from layout preferences. Checks run as
soon as their dependencies are realized. Helper preconditions are checked on the
actual caller inputs. Invalid candidate geometry is rejected by realization.

Geometry types, primitive arities, helper signatures, and ordinary references
are checked during DSL elaboration, when the defining module is instantiated,
before layout/rendering. This is **not** integration with Typed Racket, nor a
promise that `raco make` alone evaluates every construction declaration. The
included tests instantiate the modules as well.

### Assertions and relation values

`require` accepts a Boolean or Relation precondition and can reject a candidate
realization. `assert` accepts a Boolean or Relation **postcondition**:

```racket
(assert (midpoint-of M AB) (perpendicular AB m #:at M))
```

A top-level assertion may refer forward. A step-local assertion uses only objects
already introduced at that point:

```racket
(step "The two halves have equal length."
  [AM (segment A M)] [MB (segment M B)]
  (assert (equal-length AM MB)))
```

Neither form creates an object or consumes an action-duration slot. The surrounding
step still has its narration/read delay/pause. Assertions are checked against the
chosen realization **after layout selection**; a false assertion does not make the
search try another candidate until the result happens to satisfy the claim.
Helper assertions remain active even when the helper call is collapsed.

Relation expressions produce first-class nondrawable values. Their truth is tested
by `require`, `assert`, Boolean `and`/`or`/`not`, and marker creation, rather than
assuming every relation value is true merely because it is not `#f`:

```racket
[claim (equal-length AB AC)]
(assert claim)
[marks (marker claim)]
```

The supported relation vocabulary remains `perpendicular`, `parallel`,
`equal-length`, `equal-angle`, `collinear`, and `midpoint-of`.
`collinear` has no built-in marker visualization. All checks are numerical, not
formal proofs for every input. Ill-conditioned near-degeneracies can require a
less extreme set of givens.

## 7. Timing

A construction can declare its default exposition rhythm directly in the DSL:

```racket
(timing
  [opening-pause 0.6]
  [read-delay 1.0]
  [action-duration 0.9]
  [step-pause 0.5])
```

The fields mean:

- `opening-pause`: quiet time before the first step begins;
- `read-delay`: time after a step's narration becomes current and before its
  first visual action starts;
- `action-duration`: default duration of each ordinary action;
- `step-pause`: time after the final action of a step before the next step begins.

For example,

```racket
(step "Start with the segment AB."
  [AB (segment A B)])
```

first makes the narration current, waits for `read-delay`, reveals `AB` over
`action-duration`, and then rests for `step-pause`. With several sequential
actions, `read-delay` occurs only once before the first action and `step-pause`
only once after the last. A `(together ...)` group occupies one action slot.

Individual steps can override the construction defaults:

```racket
(step #:read-delay 1.2
      #:duration 1.4
      #:pause 1.0
  "This is the key step."
  [C (intersection cA cB #:side-of AB 'left)])
```

`#:read-delay`, `#:duration`, and `#:pause` override `read-delay`,
`action-duration`, and `step-pause` respectively for that step. Timing values
must be nonnegative, except `action-duration`/`#:duration`, which must be
positive. A construction may contain at most one top-level `timing` clause.

Expanded helper steps inherit the outer construction's effective timing policy;
the helper's mathematical and expository structure is retained without forcing a
separate global clock policy on the caller.

For compatibility with the initial prototype API, `construction->timeline` and
`construction->scene` still accept `#:hold` and `#:opening-hold`; they are aliases
for `#:step-pause` and `#:opening-pause`. Explicit API keyword arguments override
the DSL timing values.

## 8. Exposition and presentation

Drawable givens are shown initially by default; nondrawable values are never shown. Named points have their identifier as a
label; curves are unlabelled unless explicitly requested. The optional first
string in a `step` is narration metadata. The example renderer displays it as a
caption by default and also exports it to SRT; it does not synthesize speech.

```racket
(initially (hide A B))
(step "Start with A and B." (show A B))
```

`initially` sets persistent state without an entrance animation. Later bindings
introduce their geometry and reveal it at that step. Mathematical realization
can look ahead to later objects even though the exposition has not introduced
them yet.

| Command | Effect |
|---|---|
| `(show id ...)` | Show existing geometry, retaining its label preference and persistent style state. |
| `(hide id ...)` | Hide the object and its label, without deleting its geometry. |
| `(show-label id ...)` | Enable labels; a hidden object remains hidden. |
| `(hide-label id ...)` | Disable labels independently of the object. |
| `(deemphasize id ...)` | Enter a persistent secondary presentation state. |
| `(normalize id ...)` | Restore normal persistent presentation. |
| `(highlight id ...)` | Transient highlight; restore the previous persistent state afterward. |

Showing an already shown object, hiding an already hidden object, and redundant
persistent state changes are no-ops. Hiding and showing does not forget whether
a label was disabled or an object was deemphasized.

Commands in one step are sequential. Multiple targets of **one** command animate
together. Explicit `together` supports disjoint leaf actions/bindings:

```racket
(step "Join C to both endpoints."
  (together [AC (segment A C)]
            [BC (segment B C)]))
```

Nested `together`, expanded helpers inside `together`, and simultaneous actions
on the same target are rejected in v0.1.

Label changes for objects newly introduced in the same step are applied before
those objects appear. Thus this does not flash the labels briefly:

```racket
(step "Mark the intersections."
  [(C D) (intersections cA cB)]
  (hide-label C D))
```

Use a later step to deliberately reveal those labels. `highlight` is not
accepted in `initially`, because it is an event rather than an initial state.

## 9. Construction choices and layout

```racket
[A (choose (point-on l #:except P))]
```

`choose` introduces a constrained free point, not random sampling during
playback. `point-on` accepts a line, segment, ray, or circle, with an optional
excluded point. A `choose` must be a named step binding; nested anonymous choices
are not supported.

A free given belongs to the problem. A `choose` belongs to the method. Both are
realized once, along with the consequences of all helper calls, using a
deterministic finite candidate search. The same source, options, and inputs
select the same realization within this implementation.

```racket
(layout
  (focus P A B C D)
  (prefer (distance A P) 1.5))
```

Implemented layout forms:

| Form | Meaning |
|---|---|
| `(focus id ...)` | Include these objects' relevant anchors and prefer balanced placement. |
| `(keep-visible id ...)` | Include these objects' relevant anchors in fitting. It does not issue a `show` command. |
| `(fit-circle id ...)` | Include each named circle's full extent in the fixed view. This is opt-in; it does not show the circle. |
| `(prefer expression target)` | Soft numerical preference. |
| `(prefer expression target weight)` | Same, with an explicit positive weight. |
| `(constrain predicate)` | Hard condition on this realization. |
| `(pin A (point x y))` | Exact realization of a free given/choice point; cannot move derived geometry. |

Layout fits the points and incidences relevant at any time in the exposition,
not just the final visible state. A through-point circle contributes its centre
and defining point; later named intersections contribute their own anchors. A
radius-only circle contributes its centre, not the synthetic circumference point
used internally to start its reveal. **Whole helper circles do not have to fit
the view.** Lines and outlying helper arcs are clipped at the view boundary. A
completely hidden, unused large helper does not force a zoom out.

Use `(layout (fit-circle k))` when the circle itself is the subject, as in a
tangent or circumcircle lesson. The four axis extrema of `k` are added to the
fit, with the ordinary margin and padding. The hint may refer forward. It is
validated as a Circle and remains a hard requirement for an explicitly fixed
view; the system does not silently zoom a fixed camera. This is separate from
label placement and does not change the circle or make it visible.

The default camera is fitted once and stays fixed throughout the exposition.
Use an explicit view and choice as an escape hatch:

```racket
(define view
  (make-geometry-view #:center (point 0 0)
                      #:world-width 14 #:aspect 16/9 #:margin 0.1))

(define timeline
  (construction->timeline perpendicular-through-point
    #:view view
    #:choices (hash 'A (point -1.4 0))))
```

`#:givens` overrides supplied input values; `#:choices` fixes named construction
choices. Types and mathematical constraints still apply. A pin and an explicit
override for the same name are an error. `#:samples` increases the deterministic
candidate budget (default 256). Failure means no valid candidate was found in
that budget; it is **not** a proof that the constraints are unsatisfiable.

Automatic native label placement now uses measured text boxes and a shared,
visibility-aware label/marker placement pass. It is frozen before animation,
so labels do not jump around from frame to frame. The pure core retains an
estimated-metrics mode. Sections 14–15 describe reveal and placement metadata. The adapter's `#:labels` argument accepts an immutable or
ordinary hash mapping an object identifier to an explicit label-centre point:

```racket
(geometry-timeline->scene timeline
  #:labels (hash 'P (point 0 -0.45)))
```

This changes label placement only, never the geometric point.

## 10. Typed reusable constructions

```racket
(define-construction perpendicular-bisector
  (given [A : Point]
         [B : Point])
  (results Line)
  (require (distinct? A B))
  (step "Draw the first circle." [cA (circle A B)])
  (step "Draw the second circle." [cB (circle B A)])
  (step "Mark their intersections." [(C D) (intersections cA cB)])
  (step "Join the intersections." [m (line C D)])
  (result m))
```

Input types and the result signature are mandatory. Positional multi-results
use `(results Point Point Line)` with `(result C D m)` and a corresponding
multi-result binding at the call site. The helper value is a checked descriptor,
not an ordinary Racket geometry procedure; invoke it inside a construction DSL
expression.

```racket
;; Collapsed: show only the public result as one known technique.
(step "Construct the perpendicular bisector."
  [m (perpendicular-bisector A B)])

;; Expanded: expose the same helper's internal construction steps.
(step "Construct the perpendicular bisector."
  (expand [m (perpendicular-bisector A B)]))
```

An expanded helper can leave its local auxiliary objects alone (the default),
hide them, or keep them subdued after completing its exposition:

```racket
(expand [M (c:bisect-segment A B)] #:auxiliaries 'keep)
(expand [M (c:bisect-segment A B)] #:auxiliaries 'hide)
(expand [M (c:bisect-segment A B)] #:auxiliaries 'deemphasize)
```

Cleanup affects only drawable identities created by that call, excluding public
result aliases. Existing caller objects are not hidden or restyled. The cleanup
is an uncaptioned action with the normal action duration and no independent
reading/end pause. It changes presentation only; hidden nodes remain in the
mathematical dependency graph. A result introduced by a helper retains the
caller's identifier and normal label controls.

The eight standard helpers are described in section 17 and in
`docs/CONSTRUCTIONS.md`. `bisect-segment` is the constructed midpoint; it is not
an alias for the coordinate-level `midpoint` operation.

Calls receive distinct internal identities. Returned objects have the caller's
names. Helper colors follow their result aliases; helper styles on input
parameters do not restyle the caller's givens. Helper-local initial state applies
when expanding that helper, not at the beginning of the outer video.

All helper nodes and choices participate in the outer realization. Collapsed
private objects stay hidden and do not contribute their full extents. Internal
`prefer` hints have one quarter of their authored weight; explicit outer hints
retain their weight. Hard mathematical/layout conditions remain hard.

Helpers can be imported with ordinary Racket module imports, including
`prefix-in` and re-exports. Two different prefixes for the same helper are both
recognized in one construction. This is shown in the supplied bisector example. Recursive construction
helpers, named result records, and interactive expansion during playback are not
implemented.

## 11. Themes, colors, and units

```racket
(define lesson-theme
  (geometry-theme
    (stroke [width 2.5])
    (point [radius 0.055] [color-family blue])
    (label [font-size 0.30] [font-family roman] [font-style italic])
    (circle [color-family aqua]
      (deemphasized (stroke [dash (7 5)])))
    (normal [color-variant d])
    (deemphasized [color-variant c] [opacity 0.75])
    (highlighted (stroke [width 4.5]))))
```

A geometry theme extends the default geometry theme unless an explicit
`#:extends parent` is provided. This is literal declarative syntax: `blue`, `a`,
`roman`, and dash lists are data, not variable references. A color-family
assignment selects a family; state rules choose the variant. The letters do not
have a universal “muted” meaning independent of the native color theme.

Supported geometric kind selectors: `point`, `segment`, `line`, `ray`, `circle`. The presentation-only `compass-guide` and `compass-attention` selectors style the movable transferred-radius carrier and its attention halo.
Supported state selectors: `normal`, `deemphasized`, `highlighted`.
Marker subtypes additionally support `right-angle-marker`, `length-marker`,
`parallel-marker`, and `angle-marker`; they inherit the generic `marker` rules.

Supported paint/label selectors: `stroke`, `fill`, `label`.
Kinds may contain channels or states; a state may contain channels; a
kind/state combination may contain channels. Other selector nesting is rejected.

`color-family`, `color-variant`, `color`, and `opacity` can affect the object's
main appearance or an explicit channel. `width` and `dash` belong in a `stroke`
rule. Point markers have a `radius`; labels have `font-size`, `font-family`,
`font-face`, `font-style`, `font-weight`, and `offset`.

**Units are inherited from `animate`:**

| Property | Unit |
|---|---|
| Coordinates, radius, label font size, label offset, layout distances | Local world length. |
| Stroke width | Cosmetic stroke-width value, applied through the native Visual protocol. |
| Dash on/off lengths | Cosmetic lengths converted using the selected camera width and output size. |
| Opacity | Number in `[0,1]`. |
| View margin | Fraction of each view dimension reserved at each edge. |
| Durations | Seconds. |

For example, font size `0.30` in a 12-unit-wide world is 2.5% of the world width.
The DSL does not automatically reinterpret `0.30` as a fraction or convert it to
30 typographic points. A cosmetic width of `2` is **not** two world units.

Colors become native unresolved `animate/colors` palette/role tokens, and are
resolved by the native color theme at the render boundary. The adapter uses the
native stroke-width, stroke-color, fill-color, opacity, and color-mix APIs.

```racket
(style
  [cA [color-family blue]]
  [cB [color-family aqua]]
  [m  [color-family gold] (stroke [width 3])])
```

Style precedence is channel defaults, kind rules, label defaults/kind-label
rules, normal rules, persistent-state rules, transient-highlight rules, and then
object-specific overrides. Family-only overrides keep the state-selected
variant. An exact `[color blue-a]`, `[color "#336699"]`, or `[color foreground]`
overrides family resolution, but opacity and stroke width can still animate.
`[color #f]` means transparent; `[color inherit]` resumes family resolution.

For an existing native color value or computed property, use the procedural
amendment function rather than the literal macro:

```racket
(require (prefix-in c: "colors.rkt")) ; for a root-level authoring file
(define custom-theme
  (geometry-theme-set lesson-theme 'point
    (list (list 'color (c:rgb-color 30 90 180)))))
```

A selector path such as `'(circle deemphasized stroke)` is also accepted by
`geometry-theme-set`. Native color-theme selection is a separate render option:
`#:color-theme` on the geometry output functions corresponds to the native
renderer’s `#:theme`.

Circles are mathematical circumference curves in this version. Their interiors
are not filled. Fill styling is used for point markers. Semantic role rules such
as `auxiliary`/`result` are deferred; use explicit object styles and
`deemphasize` instead.

## 12. Realization, timelines, native scenes, and output

```racket
(define realized
  (realize-construction program
    #:samples 256 #:aspect 16/9 #:margin 0.1 #:padding 0.45))

(define timeline
  (make-geometry-timeline realized
    #:theme lesson-theme #:action-duration 0.9 #:hold 0.8 #:opening-hold 0.6))

(define frame (sample-geometry-timeline timeline 3.25))
(define scene (geometry-timeline->scene timeline #:width 1280 #:height 720))
```

`construction->timeline` combines realization and exposition compilation and
accepts those options plus `#:view`, `#:givens`, and `#:choices`.
`construction->scene` adds output dimensions, `#:captions?`, `#:labels`, and
`#:background`. `geometry-timeline->scene` rejects dimensions whose aspect ratio
differs from the realized view; re-realize at the desired aspect first.

`geometry-timeline->visual` returns a native group for one time, and
`geometry-timeline->camera` returns the corresponding native camera. The native
scene contains one immutable clock value and a pure relation Visual. Sampling
in any order does not rerun layout or depend on a prior frame. Persistent cache
keys are deliberately not claimed for the opaque relation closure.

Introspection includes `geometry-program-nodes`, `construction-dependencies`,
`construction-ref`, `geometry-realization-choices`,
`geometry-realization-diagnostics`, `geometry-timeline-events`,
`geometry-timeline-cues`, and `geometry-timeline-duration`. Transparent record
accessors are exported from `core.rkt`.

Fresh points fade/scale into place. Segments stroke toward their second endpoint;
lines grow through their defining points. A solid circle uses cubic arc segments,
revealing in both directions from its through-point. `show`/`hide` use opacity.
Secondary styles interpolate, with cross-fading when dash patterns differ.
Highlighting returns to the prior persistent style. These are renderer policies,
not extra mathematical operations.

```racket
(render-geometry-stills! timeline "geometry-output/stills")
(render-geometry-frames! timeline "geometry-output/frames"
  #:fps 30 #:supersample 2 #:mp4 "construction.mp4")
(write-geometry-subtitles! timeline "construction.srt")
```

Output functions are in `render.rkt`. Full output additionally accepts
`#:workers`; both image output functions accept dimensions, `#:fps`,
`#:supersample`, `#:color-theme`, `#:captions?`, and `#:labels`. MP4 encoding uses
the existing native FFmpeg support. Merely requiring the examples does not
launch their command-line runner or write output.

During `read-delay`, `opening-pause`, and `step-pause`, geometry often has no
active visual event. In v0.8.2-style rendering, those semantically identical
frames are not rasterized repeatedly. The renderer first samples the immutable
geometry timeline, collapses duplicate visual states (including the
caption when captions are enabled), renders one representative PNG for each
unique static state, and then materializes the ordinary numbered frame sequence
from those representatives. Animated spans are still rendered frame-by-frame.
This optimization applies automatically to `render-geometry-frames!`,
`render-geometry-frames/report!`, and shard-local `render-geometry-frame-indices!`.
It does not change the movie timing or the `frame-000000.png` naming convention.

### Drawing order

Lines and rays are rendered behind segments and circles; markers and points
follow in front. Source order is retained within each of these four groups.
A later helper line therefore no longer repaints an existing gold segment blue.
The object's color remains its own theme/style color; this does not change its
mathematics, visibility, reveal timing, or the helper's color outside that segment.

## 13. Explicit limits and extension points

This version has no physical compass/straightedge animation, audio synthesis,
formal proof checking, interactive dragging, animated givens, camera choreography,
or general constraint solver. Free lines, arbitrary positive-length choice
domains, named result records, recursive helpers, and arbitrary Racket geometry
operations inside the DSL are not supported. Geometry and helper parameters are
realized once; only exposition and visual treatments vary during playback.

Intersection calculations are numerical and can become ill-conditioned near
coincidence or tangency. Coincident/overlapping loci are reported rather than
represented. Annotation placement is a bounded candidate search and may need explicit
placement. The native adapter measures text; the pure core can estimate it. Typography, colors, and widths need visual validation on the target
renderer and intended output size. Qualitative font choices come from the normal
label style; transitions are intended for color, opacity, radius, stroke width,
and numeric size, not animated font-family changes.

The main extension boundaries are the checked expression vocabulary, numerical
geometry operations, realization candidate generation/scoring, immutable
presentation events, and the native adapter. More capable geometry or layout
implementations can replace these without changing the mathematical meaning of
`show`, `hide`, `deemphasize`, or `highlight`.



## Semantic markers

The DSL now supports semantic diagram markers. Markers are first-class drawable values,
so they can be bound to names, styled, shown/hidden, highlighted, and returned from helpers.

### Marker expressions

```racket
(marker (perpendicular AB m #:at M))
(marker (equal-length AB AC BC))
(marker (angle A B C))
(marker (equal-angle (angle A B C) (angle D E F)))
(marker (parallel l1 l2))
(marker (midpoint-of M AB))
```

Supported relations:

- `(perpendicular l m)` or `(perpendicular l m #:at P)` where `l` and `m` are lines,
  segments, or rays. Without `#:at`, the construction must determine a unique
  intersection point.
- `(equal-length s1 s2 ...)` for two or more segments of equal length.
- `(angle A B C)` for the angle with vertex `B`.
- `(equal-angle a1 a2 ...)` for two or more equal angle specifications.

`parallel` marks matching directions with chevrons; `midpoint-of` marks the
segment's two equal halves. Top-level and step-local `assert` forms accept supported
relations or Boolean expressions without adding visual objects. Checks are numerical
for the selected realization, not a proof for all possible givens.

### Example

```racket
(step "M is the midpoint, and the two lines are perpendicular."
  [right-angle (marker (perpendicular AB m #:at M))]
  (highlight m M right-angle))
```

### Styling markers

Markers use the `marker` selector in themes and object styles.
Useful properties are `size`, `spacing`, `radius`, `color`, and stroke width.

```racket
(geometry-theme
  (marker (size 0.18) (spacing 0.08) (radius 0.28)
          (normal (color foreground))))

(style
  [right-angle [color-family gold]]
  [equal-sides [size 0.16]])
```

## 14. Object-specific reveals

Fresh bindings now use a type-specific reveal. The mathematics and timing remain
unchanged; only the path exposed at a given action progress changes.

| Object | Default reveal | Alternatives |
|---|---|---|
| Point | Fade/scale into its fixed position (`pop`) | `fade` |
| Segment | From its first endpoint (`from-start`) | `from-end`, `from-center`, `fade` |
| Ray | From its finite origin (`from-start`) | `fade` |
| Line | Outward from its defining region (`from-center`) | `fade` |
| Circle | Two fronts from its through-point (`bidirectional`), or automatic compass transfer when a radius comes from a visible length/distance | `compass`, `clockwise`, `counterclockwise`, `bidirectional`, `fade` |
| Marker | Draw each constituent glyph (`draw`) | `fade` |

`auto` selects the default for any drawable kind. For a radius-defined circle,
`auto` additionally inspects the radius provenance. If the radius is directly a
segment length or point-to-point distance (possibly through Number aliases and
expanded-helper argument/result aliases), it uses the `compass` reveal. Literal
radii and arbitrary arithmetic keep the ordinary circle reveal. A two-point
`(circle O P)` remains `bidirectional` by default.

State commands are unchanged: `show` fades in the complete object, `hide` fades
it out, and showing an object again does not replay its original construction
stroke. The transient compass guide exists only during the original `reveal`
action and is not a geometry node.

A construction may override fresh-binding reveals:

```racket
(construction lesson
  (given [A (point -2 0)] [B (point 2 0)])
  (reveal
    [AB from-end]
    [cA clockwise])
  (step "Join the two points." [AB (segment A B)])
  (step "Draw the circle with centre A through B." [cA (circle A B)]))
```

The `reveal` clause can refer forward. Unsupported combinations such as a
clockwise point reveal are rejected before realization. A reusable helper's
rules follow its renamed objects; a caller's rule for a returned object wins.
Explicit `[c compass]` also works for `(circle O P)`, using `OP` as the transferred
measure. Forcing `compass` on a radius with no geometric provenance, such as
`(circle O #:radius 3)`, is diagnosed when the rendered scene is prepared.

Segments and rays are revealed **before** viewport clipping. An offscreen
endpoint does not become a new mathematical endpoint at the edge of the frame.
For infinite lines, the defining midpoint is clamped onto the visible interval
before the two fronts are formed. At zero progress there is no drawn stroke;
at completion the whole visible curve is present.

A default circle has two independent fronts starting exactly at the supplied
through-point. Its final boundary and every intermediate solid arc use native
cubic Beziers. Dash patterns start at the reveal origin rather than being
re-centred at each frame.

### Compass-transfer circle reveal

For a circle whose radius is copied from visible geometry, the mathematical
object is still an ordinary Circle. The presentation layer retains the original
radius expression and derives a temporary movable carrier from forms such as:

```racket
[c1 (circle O #:radius (length AB))]
[c2 (circle O #:radius (distance A B))]
[r  (length AB)]
[c3 (circle O #:radius r)]
```

The fresh reveal is deliberately slower and more explicit than an ordinary
curve reveal. Unless action duration is explicitly overridden, a compass reveal
gets a **10.0 second** action. Within that action the carrier:

1. is drawn directly on top of the source measure;
2. moves a small distance onto a nearby line parallel to the source;
3. receives a single glow-like attention pulse;
4. moves rigidly to the new circle centre without changing length or direction;
5. receives a second attention pulse after arrival; and
6. rotates once counterclockwise while its free endpoint traces the circle.

The parallel offset chooses the side that best stays inside the usable frame and
away from the caption band. The eventual carrier orientation at the new centre
continues to prefer an early sweep that stays visible. The source geometry itself
never moves.

The carrier's length is constant through offset, transport, and sweep. During
the sweep its moving endpoint is exactly the endpoint of the partial circle arc.
The carrier fades near the end of the sweep and is absent from the settled state,
so later `show`/`hide` operations never replay the transfer.

Automatic provenance deliberately recognizes only a direct `(length segment)` or
`(distance point point)` chain. Expressions such as `(* 2 (length AB))`, `(+ r 1)`,
or a literal radius do not invent a source and therefore use the ordinary reveal.

Two semantic theme selectors style the temporary presentation:

- `compass-guide` is the solid movable carrier;
- `compass-attention` is the wide translucent under-stroke used for each pulse.

Both use the theme's highlight color by default. They are presentation-only and
do not participate in layout, labels, assertions, intersections, helper results,
or the final geometry graph.

Review bundles use seven samples for compass rows:
`read`, `pickup`, `source-attention`, `transport`, `target-attention`, `sweep`, and
`settled`. These samples are specified in reveal-progress space; review planning
inverts the timeline's smoothstep easing before choosing timestamps.

The `divide-segment-five` library example deliberately repeats the same
compass-transfer construction five times. Its construction circles remain visible
as an accumulated record of equal steps, then fade together after the fifth point
has been established.

## 15. Labels and marker placement

The renderer prepares an immutable `annotation-plan` once for a scene. It uses
Animate's measured text boxes, the fixed view, and the timeline's visibility
states. Invisible objects on another gallery plate no longer push a visible
label away. Labels and markers are considered together, including potential
collisions during fades and highlights.

The placement pass tries several label sides/distances, tick positions,
right-angle quadrants and angle radii. It prefers to avoid point discs, labels
crossing curves, overlapping annotations, and the caption band. A curve retained
in the final diagram has greater placement weight than a transient helper curve;
this avoids sacrificing the finished diagram to a passing construction circle.
An automatic label on an angle marker stays on the interior angular bisector,
with alternative radial distances, rather than moving into an unrelated sector.
An explicit `label-side`, `label-at`, or point-relative `label-offset` remains an escape hatch. Geometry does
not move. A label keeps one position throughout its lifetime, including
hide/show cycles and out-of-order sampling. No layout search occurs per frame.

### Label hints

```racket
(layout
  (label-side A 'left)
  (label-side B 'right)
  (label-side C 'above)
  (label-at M (point 0.42 -0.32))
  (label-text alpha "α"))
```

`label-side` is a preference. Its values are `auto`, `above`, `below`, `left`,
`right`, `above-left`, `above-right`, `below-left`, and `below-right`. A different
side may be selected to avoid a stronger collision.

`label-at` is a fixed label-centre location in world coordinates. It neither
moves the mathematical object nor silently yields to automatic placement.
The adapter's existing `#:labels` hash has higher precedence than `label-at`.

`label-offset` pins an automatic **Point** label relative to its realized point.
It also accepts an independent **Label**, relative to that Label's target point,
segment midpoint, or angle vertex (see section 21):

```racket
(layout (label-offset P1 (point -0.54 -0.08)))
```

The two finite literal numbers are local-world offsets from the point to the
label centre, not absolute coordinates or pixel distances. This keeps a label
near its point while allowing the givens to change. It leaves the point and font
size unchanged. The planner reserves the pinned text box and reports unresolved
collisions without moving it. Precedence is `#:labels`, then `label-at`, then
`label-offset`, then automatic placement/`label-side`. Helper-relative offsets
follow the caller's result aliases; later caller hints override the helper's
hint of the same kind. The five Pᵢ labels in `divide-segment-five.rkt` use this.

Conflicting or offscreen fixed positions are retained and reported.

`label-text` changes the displayed string, not the object's identity or its
label visibility. Strings must be nonempty and single-line. For example:

```racket
(layout (label-text alpha "α"))
(step "The arc identifies the angle α."
  [alpha (marker (angle A O B))]
  (show-label alpha))
```

For a marker spanning several objects, its one named label is anchored to the
first member. Use separately named angle markers to label individual angles.

### Marker hints

```racket
(layout
  (marker-position equal-sides 0.42)
  (marker-quadrant right-angle 2)
  (marker-radius alpha 0.34))
```

`marker-position` fixes a fraction strictly between 0 and 1 along each marked
segment or visible linear interval. For a midpoint marker, the same fraction
is used on **each half**, not on the whole segment.

`marker-quadrant` chooses 1, 2, 3 or 4. These are relative to the first object's
directed axis and its left side: `(+,+)`, `(-,+)`, `(-,-)`, `(+,-)` respectively.
Only quadrants whose marked arms actually lie on the supplied segments/rays
are admitted. No new point or intersection is created. Impossible fixed
quadrants are diagnosed instead of drawing a square on imaginary extensions.

`marker-radius` fixes an angle arc's radius in local world units. The three
marker hints are checked against the realized marker kind. Metadata may refer
forward and is remapped through reusable helpers; caller hints take precedence.

### Marker-specific themes

Generic marker rules are inherited by the more specific selectors:

```racket
(geometry-theme
  (marker
    (stroke [width 2]))
  (right-angle-marker [size 0.18])
  (length-marker [size 0.18])
  (parallel-marker [size 0.18])
  (angle-marker [radius 0.28]))
```

For length/midpoint marks the rendered tick length is `0.8 × size`, preserving
the accepted shorter ticks. Square side length is `size` without that factor.
Stroke width remains cosmetic; sizes, radii and label offsets remain world
lengths. Automatic layout changes placement, not the right-angle square size.

Equality/parallel classes receive distinct tick/arc/chevron counts when they
are visible together. Shared members and result aliases retain matching
notation. Non-overlapping gallery plates can reuse counts. Pattern counts do
not constitute a proof of any relation beyond the marker's checked statement.

### Caption space

When captions are enabled, the caption font size is `0.025 × world-width`,
expressed in world units like Animate's other text dimensions. This gives the
same relative text scale in a wide and a narrow construction view; there is no
fixed world-size cap. The adapter measures the narration paragraphs and
reserves a bottom band large enough for the tallest caption. Labels and markers
avoid that band. A background panel prevents construction curves running through
the caption. `#:captions? #f` / `--no-captions` removes both reserve and panel.
Explicit scene backgrounds are also used for the panel.

### Inspection and limits

```racket
(define plan
  (geometry-timeline->annotation-plan timeline
    #:width 1280 #:captions? #t))

(annotation-plan-labels plan)
(annotation-plan-marker-placements plan)
(annotation-plan-marker-counts plan)
(annotation-plan-texts plan)
(annotation-plan-label-boxes plan)
(annotation-plan-warnings plan)
```

The native plan reports `animate-text` metrics. The headless API
`prepare-geometry-annotations` uses conservative estimated text boxes by default;
it accepts `#:measure-label` (a procedure returning width and height in world
units), `#:metrics`, `#:caption-height` and `#:world-per-pixel` for other clients.

The bounded three-pass search is deterministic, not a guarantee of perfect
packing. Warnings include `outside-safe-area`, `annotation-overlap`, and
`label-geometry-overlap`. Pins are never silently moved to eliminate a warning.
A dense diagram may need a wider view, shorter text, or a placement hint.
The example runner's `--describe` output now includes native annotation metrics,
warnings, and selected label positions.

## 16. Gallery and tests

`examples/gallery.rkt` retains the original plates and adds segment-direction,
circle-direction, fade-only, Greek angle-label, and crowded-diagram plates.
Narration describes the mathematical objects rather than announcing visual
emphasis operations. Inspect it under both `--light` and `--dark`.

The default one-second reading delay and the existing process-based `--workers`
rendering are retained. Each worker prepares its own identical fixed annotation
plan for the same view and font environment, then samples frames independently.
Within each worker, semantically identical static frames are collapsed so that
long reading pauses and between-step holds do not repeatedly rerasterize the
same image.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/examples/gallery.rkt --dark --workers 10 \
  --mp4 geometry-output/videos/dark/gallery.mp4 geometry-output/dark/gallery
```

`reveal-test.rkt` and `annotation-test.rkt` are included in the core test run.
`reveal-annotation-render-test.rkt` checks native metrics, custom text, stable
sampling, gallery setup, and rasterization. See `docs/TESTING.md` for the build
environment's validation status rather than assuming these tests were run there.


## 17. Standard construction library

The public, headless entry point is `constructions.rkt`:

```racket
(require "geometry/core.rkt"
         (prefix-in c: "geometry/constructions.rkt"))
```

| Helper | Arguments | Result |
|---|---|---|
| `perpendicular-bisector` | Two distinct Points | Line |
| `bisect-segment` | Two distinct Points | Point |
| `erect-perpendicular` | Line, Point on the line | Line |
| `drop-perpendicular` | Line, Point off the line | Line |
| `angle-bisector` | Three noncollinear Points; middle point is vertex | Ray |
| `parallel-through-point` | Line, Point off the line | Line |
| `copy-segment` | Segment, target Ray | Point |
| `copy-angle` | Angle, target Ray, Side | Ray |

The constructions use circles, rays/lines and intersections rather than a hidden
coordinate-level midpoint, projection, angle-bisector or parallel formula.
Their input types and results are mandatory signatures; postconditions check the
result. The library has no hard-coded color palette, timing policy, or renderer.

`copy-segment` returns the **endpoint** on the target ray; construct a segment
from it when required. `copy-angle` returns a ray at the target's starting point
and requires an explicit `'left`/`'right` side. `angle-bisector` returns the
internal bisector. Zero and straight source angles are rejected.

`erect-perpendicular` defines its output Line from P toward the left of the input
Line's direction. `drop-perpendicular` defines its output Line from external P
toward the second circle intersection across the input Line. These documented
orientations make subsequent ray construction unambiguous.

Standard copying helpers mark their pedagogically visible construction circles
with `fit-circle`, so the realization camera fits complete auxiliary
circumferences rather than only the centre of a radius-defined circle. This is
particularly important for large copied lengths near the caption band.

For copying lengths, this version assumes a **transferable compass**. The form
`(circle O #:radius r)` still realizes an ordinary circle numerically, but when
`r` is traceable to a segment length or point distance its first reveal now shows
that transfer explicitly with the temporary compass carrier described in
Section 14. A literal or arithmetically derived radius falls back to the ordinary
circle reveal. This presentation does not purport to expand a strictly
collapsible-compass transfer algorithm. `(circle O P)` retains its original
through-point/two-front semantics unless `[c compass]` is requested explicitly.

See `docs/CONSTRUCTIONS.md` for all contracts, algorithms, limitations, and the
thirteen application videos. The gallery adds plates showing all eight helpers
and demonstrates cleanup after expanded calls. The old `examples/helpers.rkt`
now re-exports the library's perpendicular bisector.

```racket
(construction midpoint-lesson
  (given [A (point -2 0)] [B (point 2 0)])
  (step "Join A to B." [AB (segment A B)])
  (step "Construct the midpoint."
    (expand [M (c:bisect-segment A B)] #:auxiliaries 'hide))
  (step "The two parts have equal length."
    [halves (marker (midpoint-of M AB))])
  (assert (midpoint-of M AB))
  (result M))
```

Run the library's mathematical, composition, and estimated-layout checks with
just Racket base:

```sh
racket geometry/run-tests.rkt --library
```

The full `geometry/run-tests.rkt` adds the corresponding RackUnit groups and
native integration tests. Render all thirteen library applications in both themes:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket" \
WORKERS=10 sh geometry/examples/render-library.sh both
```

The thirteen applications are square, circumcenter/circumcircle, incircle,
triangle midline, reflection, SAS triangle copy, five equal parts, tangent at a
circle point, orthocenter, regular hexagon, equilateral-triangle chain, parallel
at a prescribed distance, and standalone angle copy. The batch yields 26 MP4s
and retains PNGs/SRT files. It excludes the older three examples and gallery.

The one-second reading delay, shorter equality ticks, unchanged right-angle size,
light/dark palettes, and process-based worker renderer are retained.


## 18. Review bundles instead of full videos

Use a single launcher to review one example or all examples:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/review-examples.rkt --example square-on-segment --dark
"$RACKET" geometry/review-examples.rkt --all --both
```

`--all` selects all 19 examples, including the gallery and the transformation/semantic-label demonstrations. `--library` selects only
the 13 application examples. `--list` prints valid names without rendering.
`--output DIR` changes the default `geometry-review` output root. Each
example/theme gets its own folder and ZIP: for example
`geometry-review/dark/square-on-segment.zip`.

Every review-worthy authored step receives `step-001-read.png`,
`step-001-during.png`, and `step-001-settled.png` (with the number incremented
for later rows). Silent cleanup-only and silent no-op steps are omitted by
default because they normally contribute only duplicate or blank audit rows;
they remain part of the movie timeline. Use `--include-cleanup` to restore those
rows when debugging presentation state. The bundle also contains paginated
contact sheets, `steps.txt`, `manifest.json`, and an offline `index.html`. Images
default to 1280×720, matching the movie runner; `--width 960 --height 540`
produces more compact images.

The **read** state precedes the step's actions. **During** is inside an actual
animation event, excluding reading delays and pauses. **Settled** is the exact
completed state before the next step's caption/actions. Samples are computed from
compiled step boundaries, not by dividing a narration interval into thirds.
Boundary snapshots handle zero-delay/zero-pause steps without showing the wrong
caption. Notes identify instantaneous and action-free steps, and steps containing
more transitions than a single action image can show. Steps containing a compass
circle reveal receive seven review samples: `read`, `pickup`, `source-attention`, `transport`, `target-attention`, `sweep`, and `settled`.
Compass action samples target reveal progress rather than raw event progress; the
planner inverts the timeline's smoothstep easing before choosing their timestamps.
Mixed contact sheets use per-thumbnail phase labels instead of ambiguous global
column headings.

Expanded helper steps are included recursively. Parent expansion steps get an
overview row, and their children get individual rows. Generated setup/cleanup is never counted as an authored step. Silent authored
cleanup/no-op rows are also omitted by default; `--include-cleanup` restores
those authored rows. `--top-level-only` omits separate child rows without
changing the construction or its movie.

The direct example runner accepts `--review-stills DIR` and/or `--review-zip FILE`.
`--review-zip` alone keeps images in the directory obtained by removing `.zip`.
It also accepts `--review-top-level-only`, `--review-include-cleanup`, and
`--no-contact-sheet`. Review capture is sequential and sparse; `--workers` still
applies only to full movie frames.
`--frames`, `--mp4`, `--describe`, and worker-shard modes cannot be combined with
review mode.

A successful rerun replaces only a known managed review bundle. Unrelated files,
movie frame directories, symlinks, and hand-added files cause a refusal instead
of deletion. The ZIP is built from verified images using relative entry paths.
See `docs/REVIEW-BUNDLES.md` for the full API and file-safety rules.

`review-plan.rkt` is headless and exports the review step/sample records.
`geometry-timeline-steps` returns the timeline compiler's new step-span metadata;
the timeline record has an eighth `steps` field. Existing timeline and animation
semantics are unchanged. `geometry-timeline->visual-sampler` prepares the full
annotation layout once and accepts either a time or a frame snapshot from that
timeline; review mode uses the same sampler and native drawing APIs as the videos.


## 19. Review-driven corrections in v0.8.1

### Helper-safe narration

Use a structured caption when a reusable construction mentions diagram names:

```racket
(define-construction join-points
  (given [A : Point] [B : Point])
  (results Segment)
  (step (caption "Join " A " to " B ".")
    [s (segment A B)])
  (result s))

(construction lesson
  (given [P (point 0 0)] [Q (point 2 0)])
  (layout (label-text P "A′") (label-text Q "B′"))
  (step "Join the copied endpoints."
    (expand [PQ (join-points P Q)])))
```

The inner caption becomes `Join A′ to B′.` The symbols in `caption` are
construction-object references, not literal words or Racket variables. A part
must be a string or a named drawable object. Strings supply spacing and
punctuation. A caption can name an object introduced in its own step; a missing,
forward-to-a-later-step, or nondrawable reference is rejected.

Templates survive nested helper expansion and are resolved once in the final
standalone construction. Resolution uses the same `label-text` as the rendered
labels. Public names are reserved. A distinct active private helper object gets
a deterministic subscript when its proposed name is already used, for example
`A₁`. Proven aliases and defining-point projections reuse the public object's
name. This is not numerical point coalescing, and arbitrary nearby points are
never merged.

Ordinary string narration is unchanged and is never searched/replaced. Use
`caption` for names that must follow helper substitution; use a string for
name-independent narration. The standard helpers now do this themselves.
`caption` does not show an object, enable its label, change timing, or create a
new visual. Helpers remain independent of a concrete theme.

### Matching angle notation

Angle identity is defined by its vertex and two positive ray directions, not by
how far the defining endpoints happen to be from the vertex. Reversing the two
arms describes the same undirected angle for equality notation. Thus an angle
marker and an equal-angle group using different points on the same rays can
share the same arc pattern.

An isolated single-angle indicator starts with one arc; it does not reserve a
new equality class merely because it is another marker object. Distinct
co-visible equality groups still receive different patterns. Use `equal-angle`
when the notation is intended as an equality assertion. Two separately labelled
α indicators in the angle-copy example now have the same one-arc treatment.

### Reviewed examples

`docs/EXAMPLE-AUDIT.md` records the findings in all 17 supplied examples, the
changes, and the validation boundary. The source uses smaller pedagogical steps
for repeated operations, shows the source chord in angle copying, and adds
missing perpendicular feet/right-angle checks. Known sub-constructions are
collapsed where expansion obscured the application. The standalone helper and
gallery demonstrations retain expanded presentations.

The right-angle square size, 20%-shorter equality/midpoint ticks, one-second
default reading pause, two color themes, process renderer, and three-image
review output are preserved. Revised examples have new step numbers and times;
regenerate their review bundles rather than comparing filenames one-to-one.


## 20. Example refinements in v0.8.3

The circumcenter, incircle, orthocenter, SAS-copy and triangle-midline examples now
use distinctly scalene acute input triangles. The standalone angle copy is to
the left of its target ray, matching the original angle's side of BA. Division
labels use nearby point-relative pins. The standard helper intersections use
P/Q/R/S-style names rather than X/Y, with captions resolved to the same labels.

The hexagon's primary circumcircle has a purple family separate from its aqua
helpers. Finite edges are drawn over supporting lines/rays so the square's given
segment remains gold. The gallery inherits shared helper/layout changes while
retaining its deliberately regular figures. See `docs/EXAMPLE-REFINEMENTS.md`
for all eleven requested example corrections, regression checks, validation
boundaries, and commands to regenerate review bundles.


## 21. Mathematical transformations and semantic labels

### Mathematical images, not animation transforms

These operations construct **new geometry**. The original object is unchanged.
The new object can be intersected, used in assertions, labelled, passed to a
construction helper, and shown using its ordinary reveal policy. A rotation
operation does not animate an object travelling around its centre.

Within a `construction` or `define-construction`:

```racket
[Ap (reflect A l)]
[Bp (rotate B O (degrees 60))]
[Cp (translate C (vector 4 0))]
[Dp (dilate D O 2)]
```

Coordinates, vector components and label distances use local world units.
Angles supplied to `rotate` and `rotation` use radians. `(degrees 60)` explicitly
converts degrees to radians; `60deg` is not DSL syntax. Positive rotation is
counterclockwise in the mathematical Cartesian plane.

### Reusable transformations

A `Transform` is an immutable, nondrawable similarity. A `Vector` is an immutable,
nondrawable displacement, distinct from a Point.

```racket
[v (vector-between A B)]
[T (translation v)]
[R (rotation O (degrees 90))]
[M (reflection l)]
[D (dilation O 3/2)]

[A2 (transform T A)]
[AB2 (transform T AB)]
[k2 (transform T k)]
```

| Expression | Type and meaning |
|---|---|
| `(vector dx dy)` | Vector with finite components. |
| `(vector-between A B)` | Vector B − A. |
| `(vector-x v)`, `(vector-y v)` | Number components. |
| `(identity-transform)` | Identity Transform. |
| `(translation v)` | Translation by Vector v. |
| `(rotation O theta)` | Rotation about Point O, in radians. |
| `(reflection l)` | Reflection in an infinite Line. |
| `(dilation O k)` | Dilation about O by finite, nonzero k. |
| `(compose-transform T S ...)` | Composition, **rightmost first**. No arguments gives identity. |
| `(inverse-transform T)` | Inverse Transform. |
| `(transformation-scale T)` | Positive length factor. |
| `(transformation-orientation T)` | +1 for orientation-preserving, −1 for reversing. |
| `(transform T object)` | The image, retaining the object's type. |

The direct forms `translate`, `rotate`, `reflect`, and `dilate` put the object
first; `transform` puts the reusable Transform first.

For example:

```racket
[T (compose-transform
     (translation (vector 4 0))
     (rotation O (degrees 90)))]
[A2 (transform T A)]   ; first rotate about O, then translate
[undo (inverse-transform T)]
```

Negative dilation is allowed: it places an image point on the opposite ray from
the centre and scales its distance by `abs(k)`. In two dimensions this still
preserves orientation. Zero is rejected because it would collapse lines, rays,
circles and angles to points. Overflow, underflow to a singular transformation,
and degenerate defining geometry are errors, not silent type changes.

`reflection` requires a Line. To reflect in the supporting line of a segment,
write `(line (start-point AB) (end-point AB))` explicitly.

### Supported image types

Point, Segment, Line, Ray, Circle, Angle, Relation and Marker are supported.
A ray's origin and defining direction are transformed together. A circle's
centre and defining circumference point are transformed together; its radius
is multiplied by the Transform's positive length factor. An Angle keeps its
middle-point vertex. Reflection reverses its signed sweep but preserves its
unsigned measure.

Relation and Marker values are transformed semantically by mapping their
underlying geometry. A transformed Marker is redrawn at the current theme's
annotation sizes; its glyph strokes are not stretched. A false Relation is not
made true by transforming it. Use `assert` to check a claim as before.

Only similarities are supported: there is no shear or nonuniform scale and no
ellipse-valued image of a circle. Transformation, Number, Text, Vector and Label
values cannot themselves be transformed by `transform`.

Source styling, labels, display names, and reveal hints do not silently transfer
to an image. The new object has its own identity and ordinary type defaults.
Use `style`, `reveal`, and labels on that new object. The eight standard
straightedge/compass constructions still use their original construction
algorithms; these operations do not replace them with coordinate shortcuts.

### Procedural entry points

The tables above describe the checked DSL. `core.rkt` and `main.rkt` re-export
both new modules; they can also be required separately:

```racket
(require "geometry/transformations.rkt" "geometry/labels.rkt")
```

Outside the DSL, use `(geometry-vector dx dy)` and the accessors
`geometry-vector-x` / `geometry-vector-y`. Racket's own `vector` remains its
ordinary vector constructor. The other transformation and label procedures use
the same names and argument order as the DSL forms. An ordinary angle value is
constructed with `angle-spec`, not the DSL-only `angle` expression. Typed helper
values are still invoked within a construction, not as ordinary procedures.

### Typed helper composition

Transforms and labels can be helper inputs or results. Text is also a type, so
label text can be supplied by a caller rather than embedded in helper code.

```racket
(define-construction labelled-image
  (given [source : Segment]
         [mapping : Transform]
         [name : Text])
  (results Segment Label)
  (step "Construct and label the image."
    [image (transform mapping source)]
    [caption (length-label image name)])
  (layout (label-position caption 0.4))
  (result image caption))

;; Within a caller:
(step "Construct the reflected segment."
  (expand [(AB2 length-name)
           (labelled-image AB (reflection l) "a′")]
          #:auxiliaries 'hide))
```

The output aliases retain the helper's annotation hints. Transform, Vector and
Text bindings do not produce visual actions or consume an action duration.
A narrated step can still have a reading delay and ending pause.

### Four kinds of semantic label

A `Label` is a first-class, drawable annotation attached to geometric data.
It is not a point or curve and cannot be used as an intersection operand.

```racket
[name-A (point-label A "A′")]
[base-note (segment-label AB "5 cm")]
[a (length-label BC "a")]
[alpha (angle-label (angle B A C) "α")]
```

A label can be returned from a helper, shown or hidden, highlighted, or given
its own theme/style. Its position is found by the shared annotation planner,
not entered as a text coordinate. Text stays upright and horizontal beside a
sloping segment or reflected figure.

An `angle-label` draws a single indicating arc by default. This arc does **not**
assert equality with other angles. For matching equality notation use an
`equal-angle` marker as before, and suppress the label's additional arc:

```racket
[alpha (angle-label (angle B A C) "α" #:arc? #f)]
```

An angle label requires a nondegenerate minor angle strictly between 0 and 180
degrees, with the geometry tolerance applied near the endpoints. Right angles
are allowed and measured as 90°; use a perpendicular marker when a square is the
appropriate notation.

### Computed measurements

Omit the text to display a measurement taken from the target:

```racket
[a-value (length-label BC #:precision 2 #:unit "cm")]
[alpha-value (angle-label (angle B A C) #:precision 1)]
```

Lengths default to two decimal places; angles default to zero decimal places
and a degree symbol. `#:precision` must be an exact integer from 0 to 12.
Decimal formatting uses Racket's `real->decimal-string`, including its rounding;
precision zero is normalized to omit any trailing decimal point.
rule and fixed number of decimal places.

A unit is a **display suffix**, not a conversion. Saying `#:unit "cm"` assumes
that a world-unit length is to be interpreted as a centimetre. There is no unit
algebra in this release. Text must be a nonempty single line without tabs.

Authored text is authoritative: `(segment-label AB "5 cm")` and
`(length-label AB "a")` do not assert a numerical length. With explicit text,
formatting precision has no effect and `#:unit` is rejected; include any units
in the text itself. The numeric form is the one to use when the displayed
measurement must follow the geometry.

Formatting is resolved when the geometry is realized. Changing a given and
realizing the construction again recomputes dependent label values. It is not a
per-frame numeric updater.

To label an image, label its transformed target:

```racket
[AB2 (dilate AB O 2)]
[length-AB2 (length-label AB2 #:precision 1)]
```

The lettering is not scaled or mirrored. The length is measured from AB2.

### Independent labels versus automatic names

Points still have automatic name labels. An independent `point-label` does not
silently suppress that name or rename the point in structured captions:

```racket
(initially (hide-label A))
(step "This point is A′."
  [name-A (point-label A "A′")])
```

For a simple rename with no independent annotation lifetime, keep using:

```racket
(layout (label-text A "A′"))
```

That existing form also supplies the point's name in structured captions. Label
identifiers in captions are identifiers, not live substitutions of computed
measurement text; refer to geometry or use authored text for those explanations.

`hide name-A` hides the Label. `hide-label name-A` hides only its text; for an
angle Label the indicating arc remains until the whole Label is hidden.
Showing/hiding the target does not cascade to independent Labels, just as it
does not cascade to independent Markers. This permits a dimensional annotation
to remain while a helper curve is removed. Authors control both explicitly.

### Placement

The native adapter measures text using Animate's existing text/Pict path. The
pure core can use estimated metrics. Both use the same placement rules and
co-visibility information. Labels reserve ink space against points, curves,
markers, other labels and the caption band.

Length and segment labels try several fractions along the target and both sides
of its normal. The text is not rotated. Angle labels remain on the angular
bisector, with alternative radial distances. Their optional arcs participate
in the same planner. Point labels use candidates around their target point.

Positions are chosen once and remain fixed through hide/show, highlighting,
review sampling, and out-of-order frame access.

```racket
(layout
  ;; In triangle ABC the conventional side label a, attached to BC, is outside
  ;; the triangle: choose the half-plane opposite the third vertex A.
  (label-outside-of a A)
  (label-position a 0.4)
  (marker-radius alpha 0.34)
  (label-offset name-A (point -0.4 0.1)))
```

`label-position` applies to length/segment Labels only. Its fraction must be
strictly between 0 and 1, measured from the segment's first endpoint. It fixes
the longitudinal fraction while leaving the normal clearance automatic.

`label-outside-of` also applies to length/segment Labels. It names a Point on
the *inside* side of the supporting line; the label is constrained to the
opposite half-plane. Thus for triangle `ABC` the conventional labels are:

```racket
(layout
  (label-outside-of a A) ; a labels BC
  (label-outside-of b B) ; b labels CA
  (label-outside-of c C)) ; c labels AB
```

The reference point must not lie on the segment's supporting line.
`label-outside-of` is a geometric layout constraint, not merely a screen-space
preference, so it remains correct for sloping and transformed triangles. Do not
combine it with an explicit non-`auto` `label-side` for the same Label.
`label-side` retains its existing meaning as a preferred world direction when
no outside constraint is supplied.

`label-offset` now accepts Label as well as Point. For a Label it is relative
to the target point, segment midpoint, or angle vertex. An exact relative pin
wins over automatic `label-position` and side preferences. As before, an
absolute `label-at` overrides a relative pin, and an adapter `#:labels` override
has the highest priority.

`marker-radius` accepts an angle Label, including one with its arc suppressed,
and controls the radial starting point for its placement. Other marker-specific
hints continue to require the corresponding Marker type.

`label-text` can override a Label's displayed text as a presentation escape
hatch. Such an override intentionally replaces even a computed measurement;
it is not a numerical assertion.

The planner is heuristic. Impossible pins and very crowded/narrow-angle diagrams
can still produce explicit overlap/outside-safe-area warnings. It does not move
the underlying mathematical geometry or invent a claim to make labels fit.

### Themes and drawing order

```racket
(geometry-theme
  (label [font-size 0.28])
  (semantic-label [offset 0.14])
  (length-label (label [font-style italic]))
  (angle-label [radius 0.28] (stroke [width 2])))
```

Available selectors are `semantic-label`, `point-label`, `segment-label`,
`length-label`, and `angle-label`. Generic text defaults form the base, followed
by semantic-label, then the specific kind, then state rules and explicit object
styles. Font sizes, offsets and arc radii remain world lengths; stroke widths
remain Animate's cosmetic widths. No new font or color palette is bundled.

First-class Labels are drawn after geometric objects so later support lines
cannot paint over their text. The existing line/ray-behind-segment order,
right-angle sizes and shortened equality ticks are unchanged.

### Examples, review and tests

New standalone examples: `transformations.rkt` and `semantic-labels.rkt`. The
gallery also contains all four transformation kinds and symbolic/numeric labels.
All support light/dark themes, review triplets, ordinary videos and process
workers. The review registry now has **19 examples**; `--library` still means
the thirteen compass-and-straightedge applications.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --transform-labels
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/review-examples.rkt --example transformations --both --output geometry-review-v091
"$RACKET" geometry/review-examples.rkt --example semantic-labels --both --output geometry-review-v091
"$RACKET" geometry/review-examples.rkt --example gallery --both --output geometry-review-v091
```

For a video:

```sh
"$RACKET" geometry/examples/transformations.rkt --dark --workers 10 \
  --mp4 geometry-output/videos/dark/transformations.mp4 geometry-output/dark/transformations
```

See `TRANSFORMATIONS-AND-LABELS-PLAN.md` for the implementation plan and
`TRANSFORM-LABEL-VALIDATION.md` for what was actually executed.
