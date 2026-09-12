# Implemented geometry DSL — v0.8.1

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
```

These examples assume the importing file is in the `animate` repository root.
Adjust relative paths for another location. Installed collection paths are
`animate/geometry/core`, `animate/geometry/main`, `animate/geometry/render`, and
`animate/geometry/constructions`.

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
`Circle`, `Marker`, `Number`, `Angle`, `Side`, and `Relation`. Points use
Cartesian coordinates with positive y upward. `Angle`, `Side`, `Relation`, and
`Number` are nondrawable values; binding them does not create a visual action.
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
calculations and helper parameters; numerical displays are not implemented.
Explicit presentation commands and visual layout/style targets must be drawable
geometry, not `Number`, `Angle`, `Side`, or `Relation` bindings.

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

Supported kind selectors: `point`, `segment`, `line`, `ray`, `circle`.
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
| Circle | Two fronts from its through-point (`bidirectional`) | `clockwise`, `counterclockwise`, `fade` |
| Marker | Draw each constituent glyph (`draw`) | `fade` |

`auto` selects the default for any drawable kind. State commands are unchanged:
`show` fades in the complete object, `hide` fades it out, and showing an object
again does not replay its original construction stroke.

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

Segments and rays are revealed **before** viewport clipping. An offscreen
endpoint does not become a new mathematical endpoint at the edge of the frame.
For infinite lines, the defining midpoint is clamped onto the visible interval
before the two fronts are formed. At zero progress there is no drawn stroke;
at completion the whole visible curve is present.

A default circle has two independent fronts starting exactly at the supplied
through-point. Its final boundary and every intermediate solid arc use native
cubic Beziers. Dash patterns start at the reveal origin rather than being
re-centred at each frame.

Every constituent tick, chevron, square or angle arc reveals progressively.
Corresponding marks in a group share progress. Right-angle squares retain their
existing side length; equality and midpoint ticks retain their 20% reduction.

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
An explicit `label-side` or `label-at` remains an escape hatch. Geometry does
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

For copying lengths, this version assumes a **transferable compass**. The form
`(circle O #:radius r)` places its reveal through-point at `(O.x + r, O.y)`.
It does not purport to expand a strictly collapsible-compass transfer algorithm.
`(circle O P)` retains the original through-point/reveal semantics.

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

`--all` selects all 17 examples, including the gallery. `--library` selects only
the 13 application examples. `--list` prints valid names without rendering.
`--output DIR` changes the default `geometry-review` output root. Each
example/theme gets its own folder and ZIP: for example
`geometry-review/dark/square-on-segment.zip`.

Every authored step receives `step-001-read.png`, `step-001-during.png`, and
`step-001-settled.png` (with the number incremented for later rows). The bundle
also contains paginated contact sheets, `steps.txt`, `manifest.json`, and an
offline `index.html`. Images default to 1280×720, matching the movie runner;
`--width 960 --height 540` produces more compact images.

The **read** state precedes the step's actions. **During** is inside an actual
animation event, excluding reading delays and pauses. **Settled** is the exact
completed state before the next step's caption/actions. Samples are computed from
compiled step boundaries, not by dividing a narration interval into thirds.
Boundary snapshots handle zero-delay/zero-pause steps without showing the wrong
caption. Notes identify instantaneous and action-free steps, and steps containing
more transitions than a single during image can show.

Expanded helper steps are included recursively. Parent expansion steps get an
overview row, and their children get individual rows. Generated setup/cleanup is
not counted as an authored step. `--top-level-only` omits separate child rows
without changing the construction or its movie.

The direct example runner accepts `--review-stills DIR` and/or `--review-zip FILE`.
`--review-zip` alone keeps images in the directory obtained by removing `.zip`.
It also accepts `--review-top-level-only` and `--no-contact-sheet`. Review capture
is sequential and sparse; `--workers` still applies only to full movie frames.
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
