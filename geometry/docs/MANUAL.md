# Implemented geometry DSL — v0.1

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
```

These examples assume the importing file is in the `animate` repository root.
Adjust relative paths for another location. Installed collection paths are
`animate/geometry/core`, `animate/geometry/main`, and `animate/geometry/render`.

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
`Circle`, and `Number`. Points use Cartesian coordinates with positive y upward.
A line, segment, ray, or circle needs distinct defining points.

| Expression | Meaning |
|---|---|
| `(point x y)` | Point at the supplied world coordinates. |
| `(point)` | Free given point, within the DSL only. |
| `(segment A B)` | Finite segment from A to B. |
| `(line A B)` | Infinite line, directed from A toward B for selectors. |
| `(ray A B)` | Ray starting at A and directed toward B. |
| `(circle A B)` | Circle centred at A and passing through B. |
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
geometry, not `Number` bindings.

The DSL is deliberately a closed expression language in v0.1. It does **not**
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

`#:side-of` accepts a directed line, segment, or ray and `'left` or `'right`.
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

## 7. Timing

A construction can declare its default exposition rhythm directly in the DSL:

```racket
(timing
  [opening-pause 0.6]
  [read-delay 0.7]
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

Givens are shown initially by default. Named points have their identifier as a
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
| `(prefer expression target)` | Soft numerical preference. |
| `(prefer expression target weight)` | Same, with an explicit positive weight. |
| `(constrain predicate)` | Hard condition on this realization. |
| `(pin A (point x y))` | Exact realization of a free given/choice point; cannot move derived geometry. |

Layout fits the points and incidences relevant at any time in the exposition,
not just the final visible state. A circle contributes its centre and defining
point; later named intersections contribute their own anchors. **Whole circles
do not have to fit the view.** Lines and outlying helper arcs are clipped at the
view boundary. A completely hidden, unused large helper does not force a zoom out.

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

Automatic label placement is an eight-direction heuristic using approximate
label boxes and the complete relevant diagram. It is frozen before animation,
so labels do not jump around from frame to frame. It is not a measured-font
collision solver. The adapter's `#:labels` argument accepts an immutable or
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

Calls receive distinct internal identities. Returned objects have the caller's
names. Helper colors follow their result aliases; helper styles on input
parameters do not restyle the caller's givens. Helper-local initial state applies
when expanding that helper, not at the beginning of the outer video.

All helper nodes and choices participate in the outer realization. Collapsed
private objects stay hidden and do not contribute their full extents. Internal
`prefer` hints have one quarter of their authored weight; explicit outer hints
retain their weight. Hard mathematical/layout conditions remain hard.

Helpers can be imported with ordinary Racket module imports, including
`prefix-in`, as shown in the supplied bisector example. Recursive construction
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
represented. Label placement uses approximate boxes and may need explicit
placement. Typography, colors, and widths need visual validation on the target
renderer and intended output size. Qualitative font choices come from the normal
label style; transitions are intended for color, opacity, radius, stroke width,
and numeric size, not animated font-family changes.

The main extension boundaries are the checked expression vocabulary, numerical
geometry operations, realization candidate generation/scoring, immutable
presentation events, and the native adapter. More capable geometry or layout
implementations can replace these without changing the mathematical meaning of
`show`, `hide`, `deemphasize`, or `highlight`.

