# animate — SCENE-EF

> **Work in progress:** this project is under active development and its API may change.

This repository is a Manim-like animation system for Racket, with optional
Rhombus examples.

SCENE-DK extends the SCENE-CY affine-map layer through ordinary nested Visual
trees. `linear2` represents a full 2×2 matrix, `affine2` adds translation, and
`apply-affine` / `apply-matrix` interpolate a world-space map from identity
through a scene play. A named child can now be mapped inside an already-mapped
group without flattening it to pixels; its siblings and unrelated explanatory
Visuals stay independent.

SCENE-DL adds serializable named rate functions. `linear`, `(smooth)`,
`(smoothstep)`, `(rush-into)`, `(rush-from)`, `(there-and-back)`, and
`(there-and-back-with-pause)` are callable anywhere the existing easing API
accepts a procedure. Unlike an arbitrary Racket closure, they are transparent
semantic values, so automatic section-cache keys can safely include them.

SCENE-DY generalizes pure Boolean operations to simple concave and compound
closed paths. `path-union`, `path-intersection`, `path-difference`,
`path-xor`, `cutout`, `clip-to`, and `mask-with` return ordinary immutable path
geometry with reconstructed exterior and hole contours—so strokes do not reveal
the internal triangulation. Cubic boundaries are sampled with an explicit
`#:curve-samples` quality setting. The default `#:fill-rule 'odd-even` matches
the renderer; `nonzero` supports nonintersecting oriented contour nests.

SCENE-EC adds renderer-independent fill paints: `linear-gradient`,
`radial-gradient`, and `checker-pattern` are immutable semantic values with
local geometry and ordered colour stops. The Pict/racket-draw backend creates
native vector gradient brushes at render time, so painted paths, circles, and
rectangles remain normal transformable Visuals. Compatible paints animate with
`fill-color-to`; unlike paint kinds require an intentional cross-fade.

SCENE-DN extends prepared ODE trajectories with optional adaptive
Dormand–Prince RK45 integration, cubic dense lookup, time-dependent fields,
terminal scalar events, and immutable solver diagnostics. The existing
fixed-step RK4 checkpoint backend remains available. In either mode, a
`flow-particle` reads a prepared trajectory and renderer workers never call the
author field.

SCENE-DO adds `camera-view`, a frame-fixed inset that draws a named live
world-space target through a second immutable orthographic camera. The target
is resolved from the same sampled Scene as the main view, so ordinary motion,
nested transforms, and opacity remain synchronized without a copied secondary
Scene or mutable observer state.

SCENE-EE evolves that inset into an independently animated secondary camera.
`camera-view` can select several live world targets or, with no target
selection, every top-level world layer. Its camera may pan, zoom, follow a
moving world target, or animate to an existing renderer-aware fit. Rounded and
rectangular viewport clips are semantic choices; each view continues to sample
from the same immutable Scene state as the main camera.

SCENE-EF extends immutable numeric displays with scientific, significant-figure,
rational, and Cartesian-complex formatting; semantic upright unit factors; and
clipped rolling-digit displays. `change-number-to`, `count-to`, and
`count-from` are ordinary named-value animation requests, so their numbers are
interpolated directly from a sampled clip rather than kept in a mutable tracker.

SCENE-DP upgrades graph construction with deterministic spring, layered,
partite, and small outerplanar layouts. Parallel links route onto distinct live
cubic arcs, directed self-loops have matching tangent arrowheads, and edge
labels follow their routes as vertices move. Immutable BFS, DFS, and unweighted
shortest-path helpers return declaration-order vertex sequences for authored
highlight animations.

SCENE-DQ makes nonlinear deformation practical for mathematical diagrams.
`apply-pointwise` adaptively subdivides mapped geometry, breaks paths rather
than drawing false chords across failed samples, and can now address a nested
ordinary Visual through its enclosing affine maps. Jacobian/orientation queries,
an optional inverse-map mesh, and a semantic cell-sampled complex-domain colour
field make the result inspectable without a renderer-specific transform layer.

SCENE-DW extends this with time-dependent deformation. `apply-homotopy`
evaluates `H(point, alpha)` directly from immutable source geometry at each
sampled clip phase, rather than interpolating toward a precomputed endpoint.
`apply-complex-homotopy` provides the same operation over ordinary Racket
complex numbers. Both retain DQ's adaptive sampling, split discontinuities,
nested world-space targets, and random-access frame semantics.

SCENE-ED makes common explanatory marks live: `angle-between`,
`right-angle-between`, `brace-between`, `brace-label`, and
`curved-arrow-between` accept the same literal-point, parameter, visual, and
`anchor-of` endpoint descriptions as `line-between`. A pure centre or
parameter relationship is a normal derived Visual, while a measured edge or
corner anchor is resolved after sampling by the active renderer.

SCENE-DX extends matching transforms from tagged formulas to ordinary diagram
trees. `transform-matching-visuals` pairs named leaves by explicit relative
paths, unchanged nested paths, compatible shape/style, local shape fingerprints,
and finally nearby compatible geometry. Matched primitive shapes morph when
possible; other matches move by cross-fade, while unmatched material fades.

SCENE-DZ adds serializable time reparameterization to the existing `timed`
scheduler slot. `change-speed` turns a piecewise-linear speed profile into a
rate function; `cubic-bezier`, `spring`, `reverse-rate`, `compose-rate`, and
`squish-rate` provide further inspectable timing descriptions.

SCENE-DS adds a compact mathematical-effects vocabulary. `flash`, `focus-on`,
and `show-passing-flash` are temporary live overlays, so they track their
target after ordinary sampling. `wiggle` is a normal reversible rotation
composition. `grow-from-center`, `grow-arrow`, and `draw-border-then-fill`
introduce exact endpoint Visuals rather than leaving renderer-only snapshots.

SCENE-DT adds addressable probability and statistics diagrams: bar and stacked
bar charts, histograms, finite sample spaces, probability trees, box plots,
and error bars. They are ordinary immutable group trees, so an author can
target one bar, cell, branch, quartile box, or error-bar stem with the existing
scene operations.

SCENE-DV finishes a composition from measured render boxes. `align-baselines`,
`keep-inside-frame`, `avoid-overlap`, and `distribute-within` return ordinary
immutable Visuals with deterministic position corrections; they do not add a
second, live layout solver to the timeline.

SCENE-CZ builds ordinary linear-algebra diagrams on that map layer.
`number-plane`, `basis-vectors`, `vector-arrow`, and
`linear-transformation-diagram` return addressable immutable groups, not a
special Scene subclass. Apply a matrix to the diagram group and keep matrix
notation or explanatory text as separate top-level Visuals.

SCENE-DC adds deterministic two-dimensional ODE flow. Fixed-step RK4 computes
streamlines directly and supplies immutable prepared trajectories for animated
particles. Canonical checkpoints plus a batched renderer preparation pass avoid
repeated seed-to-time integration while retaining random-access frame results.
SCENE-DD adds static integer/decimal labels and a `parameter-display` derived
Visual with fixed left, right, sign, or decimal anchors.

SCENE-DE makes renderer-measured attachments composable through an acyclic
dependency chain: `follow-anchor`, `keep-above`, `keep-below`, `keep-left-of`,
and `keep-right-of` remain live after ordinary scene sampling. SCENE-DF extends
the existing matrix/table group tree with per-axis sizes or an `'auto` measured
snapshot, so named cells keep their paths while columns and rows fit contents.

SCENE-CY-C adds `apply-pointwise`: a whole top-level Visual can be deformed by
a world-space point function. Path geometry is sampled before the map is
applied, so a complex square map visibly bends grid lines instead of merely
moving their Bézier control points. SCENE-DA adds `complex->point`,
`point->complex`, `complex-plane`, and `apply-complex-function`; SCENE-DB adds
the corresponding `polar->point` / `point->polar`, `polar-plane`, and
`polar-graph` builders. The combined example is
`examples/pointwise-complex-and-polar.rkt`.

SCENE-DG turns the authored-timeline audio and caption records into a real
FFmpeg assembly step. `audio-cue` can trim, delay, scale, and fade a source;
`subtitle` values write SRT or WebVTT; and `assemble-authored-mp4!` or
`mux-authored-video!` produce a video with AAC audio and MP4 captions.
SCENE-DH adds conservative automatic fingerprints for section frame caches,
plus `render-authored-mp4!`: it renders invalidated complete sections as
visual-only partial movies, stream-copies their concatenation, then muxes the
authored media once at the end.

SCENE-DJ fills out the everyday mathematical drawing vocabulary with
path-backed `ellipse`, `annulus`, `sector`, `regular-polygon`, `star`, and
`rounded-rectangle`, plus `arc-between-points`, `curved-arrow`,
`double-arrow`, and grouped `labeled-point`. They use the existing Visual and
path protocols, so they are not renderer-only conveniences. See
`examples/shape-catalogue.rkt`.

SCENE-CX adds immutable mathematical graph and directed-network diagrams.
`graph` and `digraph` return ordinary nested group trees: vertices live at
paths such as `'(network vertices A)` and derived edges at
`'(network edges A->B)`. Moving a vertex with the usual scene API regenerates
its incident line or arrow from the sampled endpoint positions; labels follow
the same immutable dependency relationship. SCENE-DP extends the initial
positioning vocabulary with deterministic spring, layered, partite, and
outerplanar layouts; parallel curves and self-loops use the same live derived
edge relationship.

SCENE-CW adds an immutable authoring layer around ordinary scenes.
`make-authored-timeline` stores named half-open sections, cue markers, and
audio-placement metadata without altering scene sampling. A selected section
uses the full scene's original output-frame grid, but writes its PNGs locally
from `frame-000000.png`, ready for direct MP4 encoding. SCENE-DH subsequently
made the section cache automatic for serializable scenes and caller-declared
assets, while SCENE-DG turns its recorded audio/caption data into a final FFmpeg
mux step.

SCENE-CV makes camera animation composable. `camera-pan-to`, `camera-pan-by`,
`camera-zoom-to`, `camera-zoom-by`, `camera-follow`, and camera-fit requests
can now be wrapped with `timed` and placed in `succession`,
`animation-group`, or `lagged-start`. They use the same deterministic local
intervals as Visual requests: touching camera motions hand off exactly, while
overlapping requests may still only change disjoint camera components. A timed
follow samples its target only within its own interval, then holds its final
camera view.

SCENE-CU adds `traced-path`: a pure position function is sampled over an
explicit animated phase parameter from `#:start-time` to the current value.
The trace is reconstructed at arbitrary time, not accumulated from previously
rendered frames. `#:trail-length` supplies a deterministic moving window, and
`#:dissipate?` returns independently faded path segments.

SCENE-CT adds regular matrix and table group trees. `matrix` places affine
Visual entries in named `row-N`/`col-N` groups with individually targetable
square brackets; `table` uses the same paths and adds a shared grid. Existing
nested animation, attention, copying, styling, and attachment APIs therefore
work on cells directly—for example, `(matrix-entry-path 'A 1 2)` returns
`'(A row-1 col-2)`.

SCENE-CS adds renderer-measured paragraphs and rich text spans. `paragraph`
supports explicit lines, wrapping at a local world-space width, line spacing,
and per-line alignment; `rich-text` combines ordinary strings with styled
`text-span` values. The resulting immutable Visual keeps the existing anchor,
affine-transform, opacity, cache, and renderer-aware layout behavior.

SCENE-CR adds semantic styling for named formula fragments. `formula-select`
returns the ordinary nested Visual path for a part, while `formula-style`,
`formula-color`, and `formula-color-map` immutably colour or fade selected
parts. `tagged-formula`, `math-tex`, and `glyph-tex` also accept `#:color-map`.
Styled tagged SVG fragments are recoloured by the SVG adapter itself, so their
existing TeX layout, semantic identity, matching, and motion all remain intact.

SCENE-CQ adds adaptive function plotting. `sample-adaptive-function-path` and
`adaptive-function-graph` begin from a deterministic display-space grid, then
compare quarter, midpoint, and three-quarter probes with their chord before
subdividing. They preserve gaps at explicit exclusions and detected vertical
asymptotes rather than clipping a false connecting line through a pole.

SCENE-CP adds axes-aware helpers for coordinate-system and calculus diagrams:
graph points and labels, projections, secants, numeric tangents, filled areas,
and midpoint Riemann rectangles. They are ordinary immutable values, so a
`derived-visual` can rebuild one from an animated parameter without an updater.

SCENE-CO adds mathematical annotation geometry: cubic arcs, dashed paths,
angle and right-angle marks, braces with labels, and a renderer-aware
`surrounding-rectangle`. They are ordinary semantic paths/groups where possible,
so they compose with the existing style and path-animation machinery.

SCENE-CN adds dynamic endpoint geometry. `line-between`, `segment-between`,
`arrow-between`, and `ray-from` sample literal points, parameter handles, and
top-level or nested Visual references at each scene time. `anchor-of` also
selects a live rendered-box edge or corner, so diagram edges remain connected
to moving vertices without frame-by-frame mutation.

SCENE-CL adds explicit stationary formula parts. Alongside a rewrite's primary
anchor, `#:stationary` names matched fragments that retain their current
individual transforms. This makes it possible to keep, for example, `2x`, `=`,
and an existing `5` still while introducing `- 1` on the right.

SCENE-CK makes attention effects live. `circumscribe` and `indicate` measure
their target from the sampled state after simultaneous motion, scale, rotation,
or formula changes. `callout` also accepts `#:target-anchor` to follow one of a
target's nine live rendered-box anchors rather than only its reference point.

SCENE-CJ adds shape-aware primitive contour morphing. A circle/rectangle pair
uses a canonical eight-segment perimeter beginning at the right midpoint and
passing through matching cardinal and corner positions. A square therefore
rounds into a circle evenly instead of inheriting an arbitrary path start.

SCENE-CI makes source-package creation reproducible. `info.rkt` omits local
`tmp/` experiments, rendered MP4s, compiled artifacts, and Finder metadata
from `raco pkg create --source`; the preserved Rhombus examples remain in the
source package but are excluded from normal compilation.

SCENE-CH adds automatic explanatory camera framing. `camera-focus` frames one
top-level or nested Visual path together with an explicit list of contextual
Visuals; `camera-fit-scene` now accepts the same nested paths. Both measure the
selected child in its fully composed world coordinates, which makes it natural
to zoom from an overview into an SVG or formula detail without hand-computing a
camera center and width.

SCENE-CG adds `transform-shape`, a high-level Visual replacement transition.
It transforms one top-level Visual into a fresh destination Visual: path,
circle, and rectangle endpoints use automatic contour correspondence and an
interpolated outline, while groups and unsupported/custom Visuals use the safe
cross-fade fallback. The exact destination Visual is installed at the end, so
ordinary geometry diagrams can change representation without leaking temporary
path proxies into later clips.

SCENE-CF adds structured formula derivations. `formula-step` describes an
explicit algebraic rewrite, including correspondence and mismatch choices;
`formula-derivation` turns those steps into anchored rewrite clips with a pause
and optional explanatory label before every transition. It deliberately
sequences author-provided mathematics rather than attempting algebra inference.

SCENE-CE extends `circumscribe` and `indicate` to nested Visual paths. Their
temporary renderer-measured outlines are placed around the selected child in
its fully composed world coordinates, so an imported SVG part or formula child
can be emphasized without rebuilding its parent diagram.

SCENE-CD adds live attachments to top-level and nested Visual paths.
`attach-to` makes an ordinary world-space Visual follow the sampled reference
point of its target, while `callout` now accepts the same nested paths for its
frame-fixed leader. Both compose every enclosing group/formula transform, so an
SVG subpart may move, rotate, and scale with its parent without manual geometry.

SCENE-CC adds named layout anchors for renderer-aware composition. Every
measured render box has the same nine anchors—`top-left`, `top`, `top-right`,
`left`, `center`, `right`, `bottom-left`, `bottom`, and `bottom-right`—so a
Visual can be placed at a point or aligned to a different anchor of another
Visual without manually calculating text, formula, SVG, or stroke extents.

SCENE-CB extends `transform-from-copy` to nested Visual paths. A source such as
`'(rocket-diagram rocket window)` is resolved to its independently drawable
world transform and inherited opacity when a clip compiles, while the original
child remains in its group. This lets a copy of an imported SVG subpart travel
to a new top-level Visual without manually rebuilding the diagram.

SCENE-CA extends SCENE-BZ's opt-in, conservative glyph-outline morphing to a
single dvisvgm glyph path with compatible closed contours. For example,
multi-contour relation glyphs such as `\leq` and `\geq` can interpolate their
outlines while preserving contour traversal. Differently painted glyphs,
multiple painted paths, open geometry, or incompatible contour topology retain
the established moving cross-fade.

SCENE-BY adds `glyph-tex`: it asks `dvisvgm` to expose the visible glyph leaves
of one complete TeX expression as `glyph-0`, `glyph-1`, and so on. Matching is
then automatic when two leaves have the same rendered outline, even though TeX
and dvisvgm were run separately for the two formulas. Use an ordinary explicit
`formula-part-match` only for a changed glyph such as `+` becoming `-`.

```racket
(define before (glyph-tex #:id 'equation "x + 3 = 7"))
(define after  (glyph-tex #:id 'equation "x = 7 - 3"))

(transform-matching-glyphs
 before after
 #:matches (list (formula-part-match 'glyph-1 'glyph-3))
 #:changed-mode 'morph)
```

SCENE-BX adds `rewrite-formula`, a formula-aware convenience operation for
staged algebra. It combines ordinary matching, copies, routes, and mismatch
policy with one fixed named anchor—normally `=`. The target TeX layout is
translated when `scene-play` compiles the transition, so each later rewrite
uses the actual preceding equation rather than a stale construction template.

```racket
(scene-play scene
            (rewrite-formula before after #:anchor 'equals)
            #:duration 1)
```

SCENE-BW adds source-preserving copies, temporary attention effects, and
arbitrary routes for formula parts. `transform-from-copy` keeps an existing
Visual in the scene while a transient copy travels to a newly introduced
destination. `circumscribe` and `indicate` measure a rendered top-level Visual,
then draw a temporary outline around it without mutating the target.
`formula-part-copy` applies the same idea to named TeX fragments, so one term
can remain visible while copies travel into newly added formula positions.

SCENE-BU refines `write-in` to closely follow Manim's `Write`: it reveals each
path by ordered Bézier-curve slots, then transitions the completed outline to
the final fill and stroke. `#:reveal 'arc-length` remains available when a
constant-speed pen motion is preferable. `unwrite` removes an existing writable
Visual in reverse leaf and path order. The effects work with path Visuals,
groups, the common shapes from `svg->visual`, and tagged TeX formulas. SVG/TeX
endpoints retain their ordinary renderer exactly; the path-only representation
is used only while an animation runs.

```racket
(scene-play (make-scene)
            (write-in logo #:order 'document)
            #:duration 2)

(scene-play scene-with-logo
            (unwrite 'logo)
            #:duration 2)
```

`#:order` may be `'document` (the default) or `'left-to-right`.  Leaves overlap
by a small default stagger; `#:lag-ratio` and `#:outline-stroke-width` make that
timing and outline explicit. The name is `write-in`, rather than `write`, to
avoid shadowing Racket's output procedure. `#:reverse? #t` reverses a write,
and `#:rate-func` is evaluated separately for each staggered leaf.

SCENE-BS adds full-layout tagged TeX formulas. `tagged-formula` typesets one
complete formula through `latex` and `dvisvgm`, then turns explicitly declared
fragments into rigid SVG groups at their TeX-determined positions.
`transform-matching-formula` moves unchanged fragments automatically and fades
changed fragments. This requires the external `latex` and `dvisvgm` executables
when a tagged formula is constructed; rendering sampled animation frames does
not rerun TeX.

SCENE-BO/BP adds bounded shared renderer resource caches and full-fidelity SVG
Visuals via the catalog `svg` package. Use `svg-image` for an SVG that should
keep gradients, clipping, text, CSS, and other renderer-level features while
still participating in ordinary motion, scaling, rotation, and fades:

```racket
(define logo (svg-image "assets/logo.svg"
                        #:id 'logo
                        #:width 8 #:height 4))

(scene-play (scene-add (make-scene) logo)
            (fade-in logo)
            #:duration 1)
```

Use `svg->visual` when you instead need stable nested elements for individual
animation. Its SVG paths and common shapes become normal Visuals, and named
`<g>`/element IDs work with nested scene targeting:

```racket
(define logo (svg->visual "assets/logo.svg" #:id 'logo))

(stroke-color-to '(logo mark outline) "red")

```

SCENE-AZ adds reusable immutable scene-value handles. They remove repeated
symbols while retaining the timeline model from SCENE-AY:

```racket
(define center (parameter 'center (vec2 0 0)))

(scene-play
 (scene-set-value (make-scene) center)
 (value-to center (vec2 4 2))
 #:duration 2)
```

SCENE-AY makes named scene values generic interpolable semantic values. Scalars,
points, and semantic RGBA colors use the same immutable timeline API:

```racket
(scene-play
 (scene-set-value (make-scene) 'point (vec2 0 0))
 (value-to 'point (vec2 4 2))
 #:duration 2)
```

Derived Visuals read the sampled `vec2` directly, removing the need to maintain
separate `x` and `y` tracker values.

SCENE-AX extends SCENE-AW's pure derived Visuals so one derived Visual may read
another resolved top-level Visual from the same immutable sampled scene state:

```racket
(define leader
  (derived-visual
   (circle #:id 'leader #:center origin #:radius 1)
   (lambda (context template)
     (visual-with-position
      template
      (vec2 (derived-context-value-ref context 'x) 0)))))

(define follower
  (derived-visual
   (circle #:id 'follower #:center origin #:radius 1/2)
   (lambda (context template)
     (visual-with-position
      template
      (vec2+ (visual-position
              (derived-context-visual-ref context 'leader))
             (vec2 0 2))))))
```

Dependency lookup is on demand rather than drawing-order based. Ordinary Visuals
return directly; derived Visual dependencies resolve recursively. Resolution
uses a local memo table for one traversal and detects dependency cycles such as
`a -> b -> a` explicitly. Nothing is written back into the immutable scene
state, so separate arbitrary-time samples still resolve from their own state.

The context exposes named semantic-value and Visual presence/lookup operations.
Nested group children are available by stable paths, including to derived
resolvers. Direct animation of a derived Visual itself is still rejected;
animate its value sources or the ordinary Visuals it depends on instead.

SCENE-CX v0.98.0 builds on immutable parameters and generic values, dynamically
derived groups, stable nested addressing, full-layout formula correspondence,
sampled plots, SVG/image import, renderer-resource caching, live attention,
canonical primitive morphs, stationary formula parts, live layout anchors,
mathematical annotations, coordinate/calculus helpers, semantic formula part
styling, renderer-measured multiline rich text, addressable matrices/tables,
deterministic traced loci, composable camera timing, reproducible
section-oriented rendering metadata, and live endpoint-derived network edges.

The public package version is `1.5.0`. The public module's bindings are covered
by the Scribble reference source.

## Documentation source

The complete Scribble reference source remains in
[`scribblings/animate.scrbl`](scribblings/animate.scrbl), but
it is deliberately not registered with Racket's documentation system. Installing
this package therefore does not build or hook up documentation.

Install the package from a checkout:

```sh
raco pkg install --auto --name animate --link "$(pwd)"
```

Create a clean source archive for distribution:

```sh
raco pkg create --source .
```

The package metadata omits generated frames, rendered videos, local `tmp/`
experiments, compiled bytecode, and Finder metadata. Rhombus examples remain in
the archive for reference but are omitted from normal compilation.

Install directly from GitHub:

```sh
raco pkg install --auto --name animate https://github.com/soegaard/animate.git
```

The documentation source can still be rendered manually when needed:

```sh
scribble --htmls --dest doc scribblings/animate.scrbl
```

### Optional Rhombus examples

Rhombus examples are preserved in [`examples/rhombus`](examples/rhombus), but
the package omits that directory from normal compilation and test discovery.
They can be run separately in an environment where Rhombus is installed.

Every public API addition must have a defining Scribble entry in the same
change. Every public signature or behavior change must update the existing
reference entry in the same change. The rule is recorded in
[HOUSE_STYLE.md](HOUSE_STYLE.md).

## Quick example

Run two relative rotations sequentially in one scene clip:

```racket
#lang racket/base

(require animate)

(define card
  (rectangle #:id 'card
             #:width 2
             #:height 1
             #:center origin))

(define animation
  (scene-play
   (scene-add (make-scene) card)
   (succession
    (rotate-by card 1)
    (rotate-by card 1))
   #:duration 2))
```

At one second the first rotation has reached exactly one radian. The second
request is compiled from that boundary state and reaches exactly two radians at
the scene endpoint. No earlier rendered frame is needed to obtain either state.

## Arrows and axes

### Arrow geometry

`arrow` accepts distinct start and end points in one containing coordinate
system. It stores local shaft geometry around their midpoint. The optional
`#:rotation` and `#:scale` arguments then act around that midpoint, in the same
way as for line and path Visuals.

The shaft is ordered from start to end. `arrow-visual-start`,
`arrow-visual-end`, and `arrow-visual-point-at` return points after the current
affine transform has been applied. A progress of zero selects the start, one
selects the end, and one half selects the midpoint.

Tip length and width are local world-unit geometry and therefore participate in
semantic scale. Stroke width remains cosmetic and is not multiplied by semantic
scale. `#:start-tip?` and `#:end-tip?` independently control the two triangular
tips. Both may be false.

### Axis ranges and ticks

An `axis-range` stores minimum, maximum, and positive tick step. The interval
must contain zero because SCENE-Q draws the two axes through numeric coordinate
`(0, 0)`. The computed span must remain a positive finite real, so an inexact
endpoint subtraction that overflows is rejected. `axis-range-tick-values`
returns nonzero integer multiples of the tick step in increasing order,
including an endpoint when it is such a multiple.
Zero is omitted because the x and y shafts already intersect there. Exact
endpoint indexes are handled exactly. Inexact endpoint indexes use a fixed
relative tolerance of `1e-12`, so ordinary decimal ranges do not lose expected
endpoint ticks solely because of binary floating-point rounding.

An axes Visual maps the full x range to `#:x-length` local world units and the
full y range to `#:y-length` local world units. Each resulting unit length
must remain positive and finite. The two unit lengths can differ:

```racket
(axes-x-unit-length coordinate-axes)
(axes-y-unit-length coordinate-axes)
```

`#:tick-size` is the full geometric tick length. Setting it to zero hides ticks
without changing the stored ranges. `#:x-tip?` and `#:y-tip?` control triangular
tips at the maximum-coordinate endpoints.

### Coordinate conversion

`axes-coordinates->point` applies the numeric-to-local mapping and the complete
axes affine transform:

```racket
(axes-coordinates->point coordinate-axes 3 2)
```

The numeric coordinate does not have to lie inside the displayed ranges. This
is useful for extrapolation and for positioning objects just outside the visible
axes.

`axes-point->coordinates` performs the inverse mapping. Positive scale factors
make that inverse well-defined. Round trips involving nonzero rotation normally
produce inexact numbers because trigonometric operations are inexact.

### Rendering, layout, and animation

The built-in arrow and axes renderers derive ordinary semantic path geometry,
then use the existing path backend. Shafts and ticks are open paths. Tips are
closed filled triangles. Closed tips use sharp miter joins; open shafts use round
caps and sharp internal joins.

A custom Pict renderer before the defaults may replace the complete arrow or
axes rendering. Semantic opacity is still applied after renderer dispatch.
Relative layout measures the complete selected render box, including tips,
ticks, cosmetic stroke padding, and any custom renderer padding.

Arrow and axes Visuals implement the basic, affine, and opacity protocols. They
can therefore be moved, rotated, non-uniformly scaled, faded, placed in groups,
and sampled on the ordinary timeline without arrow-specific animation code.

## Sampled function graphs

### Sampling grid

`sample-function-path` accepts an axes Visual and a procedure that accepts one
x value. It samples a closed interval in increasing order. `#:sample-count`
counts points, not segments, and must be an exact integer of at least two. Both
endpoints are always sampled. The default interval is the x range stored by the
axes:

```racket
(sample-function-path coordinate-axes
                      (lambda (x) (* x x))
                      #:sample-count 201)
```

Use `#:x-min` and `#:x-max` to select another finite increasing interval. With
exact bounds and an exact sample count, intermediate x values are exact rational
numbers whenever the arithmetic permits it.

Each call must return exactly one real number or `#f`. Finite reals create
samples. `#f`, positive infinity, negative infinity, and NaN create gaps. Other
values, zero or multiple values, and raised exceptions produce focused errors.
An isolated finite sample creates no drawn segment. The procedure is not stored
in the returned path or Visual.

### Discontinuities, clipping, and interpolation

`#:max-jump` can reject adjacent finite samples whose numeric y difference is
larger than a nonnegative threshold. No heuristic is used when the option is
`#f`. Known discontinuities should still return `#f` explicitly.

Accepted segments are clipped to the axes rectangle by default. Clipping is
segment-based, so a crossing ends exactly on the boundary. Pass `#:clip? #f`
to retain out-of-range geometry.

The new `#:interpolation` option accepts:

```racket
'linear
'smooth
```

`'linear` is the SCENE-R behavior and remains the default. `'smooth` converts
each accepted point run to interpolating cubic Bézier segments using a uniform
Catmull-Rom rule. Clipping happens before smooth interpolation. When clipping is
enabled, generated control points are clamped to the axes rectangle. Since a
Bézier curve lies in the convex hull of its control points, the resulting curve
remains inside the displayed rectangle. Clamping can reduce tangent continuity
near a clipping boundary.

### Adaptive subdivision

`sample-adaptive-function-path` and `adaptive-function-graph` use the same
immutable axes-local result as the fixed sampler, but begin with a small,
display-uniform exploration grid and recursively test quarter, midpoint, and
three-quarter samples of each interval:

```racket
(adaptive-function-graph coordinate-axes
                         (lambda (x) (/ 1 x))
                         #:id 'reciprocal
                         #:initial-sample-count 17
                         #:max-deviation 1/100
                         #:max-depth 12)
```

An interval is subdivided when any of those probes differs from its matching
chord position by more than `#:max-deviation`, measured in the untransformed
local geometry of the axes. The quarter probes avoid accepting a crest or
trough merely because the midpoint happens to be chord-collinear.
`#:max-depth` bounds this work per initial interval. On a log x axis, both the
initial grid and every refinement probe are uniform in log display space.

The adaptive sampler treats an exact division-by-zero evaluation as a gap and,
by default, refines then breaks sample pairs that lie beyond opposite visible y
boundaries. `#:max-jump` remains available as an explicit numeric break rule.
Use `#:excluded-intervals` to force a gap even when a finite function does not
identify it itself:

```racket
(sample-adaptive-function-path coordinate-axes f
                               #:excluded-intervals
                               (list (cons -1/10 1/10)))
```

Each exclusion is an increasing `(cons minimum maximum)` or two-element list;
overlaps are merged. No finite exploration grid can discover a frequency that
aliases all of its initial samples, so increase `#:initial-sample-count` for
that case.

### Axes-local geometry and transform snapshots

`sample-function-path` returns path geometry in the untransformed local axes
coordinates. `function-graph` wraps that geometry in a path Visual whose
translation, rotation, and scale copy the axes transform at construction time.
The axes and graph are independent immutable values afterward.

## Coordinate and calculus helpers

SCENE-CP provides compact static builders for the diagrams that repeatedly
occur in introductory calculus. `graph-point` and `graph-label` use the axes'
actual coordinate conversion; `vertical-line-to-graph` and
`horizontal-line-to-graph` draw projection lines. `secant-line`, `tangent-line`,
and `secant-slope-group` express the derivative picture directly:

```racket
(secant-slope-group coordinate-axes parabola 1 h #:id 'secant)
(tangent-line coordinate-axes parabola 1 #:id 'tangent)
```

`area-under-graph` and `area-between-curves` produce closed filled paths, while
`riemann-rectangles` produces one closed subpath per midpoint rectangle. All
three use display-uniform samples, including on log x axes. They require finite
function values; use the adaptive graph APIs for discontinuous strokes rather
than attempting to fill across a pole.

The helpers are snapshots. To animate a changing secant or Riemann construction,
rebuild the helper in a `derived-visual` from an immutable scene parameter. See
[`examples/secant-to-tangent.rkt`](examples/secant-to-tangent.rkt).

## Parametric curves and data plots

### Ordered parameter domains

A `parameter-range` stores a significant start and end value:

```racket
(parameter-range 0 1)
(parameter-range 1 -1)
```

The two values must be distinct finite reals, and their difference must remain
finite. A decreasing range is valid and samples in decreasing order. The closed
domain always includes both endpoints.

`sample-parametric-path` calls a one-argument procedure once for each parameter
sample. Each call must return exactly one `vec2` or `#f`:

```racket
(sample-parametric-path
 coordinate-axes
 (lambda (parameter)
   (vec2 (* parameter parameter)
         (* parameter parameter parameter)))
 #:parameter-range (parameter-range -2 2)
 #:sample-count 201)
```

A `vec2` is one numeric coordinate. `#f` breaks the current run. Exceptions and
invalid result counts or values are errors that report the parameter value.
The procedure is not retained after construction.

`parametric-curve` adds identity, style, opacity, and an axes-transform snapshot
to the sampled path:

```racket
(parametric-curve coordinate-axes
                  curve-procedure
                  #:id 'curve
                  #:parameter-range (parameter-range -2 2)
                  #:interpolation 'smooth)
```

### Ordered point series

`data-series-path` consumes a proper list whose order is the traversal order:

```racket
(data-series-path
 coordinate-axes
 (list (vec2 -2 0)
       (vec2 -1 1)
       #f
       (vec2 1 -1)
       (vec2 2 0))
 #:interpolation 'smooth)
```

A `#f` entry creates an explicit gap. Empty input and a single finite point are
valid but create no drawn segment. The implementation does not sort points by x
or remove repeated points.

`data-plot` wraps the resulting path in a styled path Visual with the axes
transform copied at construction time.

### Maximum distance and shared interpolation

Parametric and data operations accept `#:max-distance`. It compares the
Euclidean distance between adjacent numeric-coordinate samples before axes
scaling. A pair farther apart than the threshold becomes a gap. The default
`#f` applies no distance heuristic.

Both operation families use the same `'linear` and `'smooth` interpolation
rules as sampled function graphs. Two-point smooth runs are represented by one
line-equivalent cubic with controls at one third and two thirds of the segment.
Longer runs use uniform Catmull-Rom tangents. Gaps, rejected pairs, and
clipped-out segments always separate runs.

The results are ordinary path geometry and path Visuals. Existing `create`,
`uncreate`, movement, rotation, non-uniform scale, fading, groups, layout, and
custom path renderers work without a parametric- or data-specific timeline
protocol.

## Relative layout

### Render boxes

`visual-layout-box` renders one Visual locally, divides the Pict width and height
by the camera scale, and places the resulting symmetric box around the Visual's
reference position. The result uses mathematical y-up coordinates:

```text
left <= right
bottom <= top
```

The box is a **render box**, not a tight visible-ink bound. Built-in text,
formula, group, and path renderers deliberately use symmetric local Pict boxes
around their semantic anchors. Transparent reserved space therefore remains
part of layout. Global opacity does not change the box.

`visuals-layout-box` returns the union of a list of boxes. It returns `#f` for an
empty list. Use `layout-box-width`, `layout-box-height`, and
`layout-box-center` for common queries.

Layout is renderer-aware. Measuring a nonempty formula with the built-in
renderer can invoke `latex-pict`, LaTeX, and Poppler. A custom renderer can
supply different metrics. Font substitution, TeX versions, camera scale, and
renderer choice can therefore change layout. Use the same `#:camera` and
`#:renderers` values for layout and final rendering.

### Alignment and placement

SCENE-CC's common anchor vocabulary is:

```racket
'top-left     'top     'top-right
'left         'center  'right
'bottom-left  'bottom  'bottom-right
```

`visual-layout-anchor` measures the selected point, `visual-place-at` moves a
selected point to an explicit coordinate, and `visual-align-to` aligns two
independently chosen points. For example, this positions a caption's lower-left
corner at a panel's upper-right corner:

```racket
(visual-align-to caption panel
                 #:anchor 'bottom-left
                 #:reference-anchor 'top-right)
```

As with every layout operation, the result is an immutable snapshot. It uses the
same camera and renderer list as final rendering, but does not create a live
constraint that tracks later animation.

`align-baselines` puts a list of Visual reference y coordinates on one shared
baseline; for text made with `#:vertical-alignment 'baseline`, that is its
typographic baseline. `keep-inside-frame` moves one measured render box just
far enough into the camera viewport, including a chosen margin. `avoid-overlap`
applies an order-preserving greedy pass along the horizontal or vertical axis,
and `distribute-within` puts reference positions at equal intervals between two
explicit endpoints. Each is a construction-time snapshot, so run it again when
the constituent Visuals or the camera changes.

The independent alignment functions preserve the unselected coordinate:

```racket
(visual-align-horizontal label panel 'left)
(visual-align-vertical label panel 'top)
```

Relative placement accepts a nonnegative gap in world units:

```racket
(visual-place-above title formula
                    #:gap 1/2
                    #:horizontal-alignment 'center)

(visual-place-right-of label diagram
                       #:gap 1/4
                       #:vertical-alignment 'top)
```

The above and below operations support left, center, and right alignment. The
left-of and right-of operations support bottom, center, and top alignment.

### Ordered arrangements

`arrange-visuals-horizontally` leaves the first Visual fixed and places each
later Visual to the right of its predecessor. `arrange-visuals-vertically`
leaves the first fixed and places each later Visual below its predecessor.
Input and result order are significant and identities are preserved.

Pass `#:center` to translate the completed union as one composition:

```racket
(arrange-visuals-vertically visuals
                            #:gap 1/3
                            #:center origin)
```

`visuals-center-at` performs only that final union-centering operation. Empty
lists are valid and remain empty.

## Copies, attention, and flexible formula routes

`transform-from-copy` is Animate's counterpart to Manim's
`TransformFromCopy`. It leaves a present source Visual unchanged, renders a
moving temporary cross-fade, and adds the destination Visual only when the clip
finishes:

```racket
(define source-dot
  (circle #:id 'source-dot #:center (vec2 -2 0) #:radius 1))
(define copied-dot
  (circle #:id 'copied-dot #:center (vec2 2 0) #:radius 1))

(scene-play (scene-add (make-scene) source-dot)
            (transform-from-copy 'source-dot copied-dot
                                 #:path-arc 3/4)
            #:duration 1)
```

The source may be a present top-level id or an explicit nested path through
built-in groups/formula assemblies. A nested source is frozen with every
enclosing transform and opacity composed into it, so the copy is rendered as an
independent top-level layer while the original child stays in place. It must be
a non-derived affine opacity Visual; the destination must be a new top-level
Visual absent at clip start. During the interior of the clip, the temporary
copy cross-fades from the source's rendered form to the destination's rendered
form along the requested route. At progress zero and one there is no temporary
overlay, and completion installs the exact destination value.

```racket
(transform-from-copy '(rocket-diagram rocket window) enlarged-window
                     #:path-arc 1/2)
```

`circumscribe` draws, holds, and erases a rounded outline. `indicate` pulses
the same kind of outline. Both accept a top-level id or an explicit nested path,
are temporary, and do not change the selected Visual's transform, style, or
opacity:

```racket
(scene-play scene
            (circumscribe '(rocket-diagram rocket window) #:color "goldenrod")
            #:duration 1)

(scene-play scene
            (indicate 'equation #:color "goldenrod")
            #:duration 1)
```

The outline is measured through the ordinary Pict renderer when the clip is
compiled, so it follows the rendered extent of text, SVG, tagged TeX, and
composites rather than relying on a guessed formula box. It is a clip-start
snapshot: use a later clip when a target itself moves or changes shape.

### Copying formula parts

`formula-part-copy` names an existing source part, an otherwise unmatched
destination part, and a route. Pass those descriptors through `#:copies` on
`transform-formula-parts` or `transform-matching-formula`. The source remains
in the ordinary correspondence; each named destination receives a transient
copy instead of an ordinary fade-in.

This is useful for showing one operation on both sides of an equation. The
following step is algebraically valid: it adds `x` to both sides of `x = 2`.
The original `x` is matched normally while two copies travel to the added terms:

```racket
(transform-matching-formula
 source
 destination
 #:matches
 (list (formula-part-match 'original-x 'original-x)
       (formula-part-match 'equals 'equals)
       (formula-part-match 'two 'two))
 #:copies
 (list (formula-part-copy 'original-x 'added-x-left upper-route)
       (formula-part-copy 'original-x 'added-x-right lower-route)))
```

The destination of a `formula-part-copy` must be unmatched in the ordinary
correspondence, and at most one copy can claim it. One source part may create
any number of copies. Copies use the same rigid-fragment move or cross-fade as
matched formula parts, so they do not morph TeX glyph outlines.

`formula-arc` remains the concise route descriptor. For a custom route, use
`formula-relative-path` with a path beginning at `(vec2 0 0)` and ending at
`(vec2 1 0)`. It is mapped at compilation to the actual chord between the
source and destination; positive local y points to the chord's left:

```racket
(define upper-route
  (formula-relative-path
   (polyline-path
    (list (vec2 0 0) (vec2 1/2 2/5) (vec2 1 0)))))

(formula-part-path 'left-term 'moved-left-term upper-route)
```

Use a `formula-part-path` in `#:part-paths` to route an ordinary matched pair,
or use the same route directly in `formula-part-copy`. `transform-matching-tex`
also accepts these routes in `#:path-map`. See
`examples/copying-and-emphasizing-formula-parts.rkt` for the complete rendered
example.

### Structured formula derivations

`formula-step` stores one explicit destination formula and its animation
choices. `formula-derivation` applies the steps in order, pauses before every
rewrite, and can replace one explanatory label at a chosen position:

```racket
(formula-derivation
 scene initial-equation
 #:anchor 'equals
 #:explanation-position (vec2 0 -5/2)
 #:steps
 (list
  (formula-step after-subtracting-six
                #:explanation "Subtract 6 from both sides")
  (formula-step after-evaluating
                #:explanation "Evaluate 21 - 6")))
```

The builder chains endpoint templates safely, so the named anchor is resolved
from the actual preceding scene formula. Each `formula-step` still accepts
explicit matches, copy paths, routes, mismatch policy, duration, and a per-step
anchor override. It does not parse TeX, verify the algebra, choose steps, or
decide which parts should move.

## Tagged formula layouts

`tagged-formula` is the full-layout alternative to manually positioned formula
parts. Give each contiguous TeX fragment a name, and Animate typesets the whole
formula as one document. The resulting `formula-assembly` preserves TeX's
normal spacing, kerning, scripts, and alignment while exposing each declared
fragment as a rigid movable part:

```racket
(define initial
  (tagged-formula
   #:id 'equation
   #:font-size 2/5
   (formula-fragment 'a-square "a^2")
   (formula-fragment 'plus "+")
   (formula-fragment 'b-square "b^2")
   (formula-fragment 'equals "=")
   (formula-fragment 'c-square "c^2")))

(define rearranged
  (tagged-formula
   #:id 'rearranged
   #:font-size 2/5
   (formula-fragment 'b-square "b^2")
   (formula-fragment 'equals "=")
   (formula-fragment 'c-square "c^2")
   (formula-fragment 'minus "-")
   (formula-fragment 'a-square "a^2")))

(scene-play (scene-add (make-scene) initial)
            (transform-matching-formula initial rearranged)
            #:duration 2)
```

`transform-matching-formula` first accepts optional explicit
`formula-part-match` values through `#:matches`; it then pairs every remaining
fragment whose source and typesetting options are exactly equal, in source
order. In the example, `a^2`, `b^2`, `=`, and `c^2` move rigidly, while `+`
fades out and `-` fades in. It does not infer algebraic meaning or morph glyph
outlines.

The constructor invokes `latex` and `dvisvgm` once for each endpoint formula,
so those executables must be on `PATH` when the scene is built. A fragment must
be a nonempty contiguous piece of valid TeX that leaves visible ink. The
resulting SVG groups are cached by the normal renderer; frame sampling and
rendering use no external TeX process.

Run the example with:

```sh
racket examples/tagged-formula-transitions.rkt \
  frames/tagged-formula-transitions \
  tagged-formula-transitions.mp4
```

`examples/solving-linear-equation.rkt` is a second tagged-formula example. It
solves \(2x+1=5\) through \(2x=5-1\), \(2x=4\),
\(\frac{2x}{2}=\frac{4}{2}\), and \(x=2\), keeping the equals sign fixed
throughout.

### Semantic formula styling

Named tagged fragments are also a styling namespace. Colour at construction
time without putting colour commands into TeX:

```racket
(tagged-formula
 #:id 'equation
 #:color-map (hash 'unknown "royalblue" 'constant "firebrick")
 (formula-fragment 'unknown "2x")
 (formula-fragment 'plus " + ")
 (formula-fragment 'constant "3")
 (formula-fragment 'equals " = ")
 (formula-fragment 'result "7"))
```

For an existing assembly, `(formula-select formula 'constant)` produces the
nested path `'(equation constant)` understood by `indicate`, `circumscribe`,
and `fill-color-to`. `formula-color`, `formula-style`, and `formula-color-map`
instead return new assemblies with selected whole fragments styled. They keep
the formula's original TeX layout and SVG crop; matching fragments with equal
paint retain their normal rigid motion in a rewrite.

### Automatic glyph layouts

`glyph-tex` is the lower-level complement to explicit `formula-fragment` and
`math-tex` groups. It typesets one complete expression, then exposes its visible
dvisvgm `<use>` leaves as `glyph-0`, `glyph-1`, and so on. Each glyph keeps the
complete expression's TeX layout, but `transform-matching-glyphs` compares the
referenced dvisvgm path outline instead of the whole formula source. Thus exact
unchanged glyphs move automatically between separately compiled formulas:

```racket
(define before (glyph-tex #:id 'equation "x + 3 = 7"))
(define after  (glyph-tex #:id 'equation "x = 7 - 3"))

(scene-play (scene-add (make-scene) before)
            (transform-matching-glyphs
             before after
             #:matches
             (list (formula-part-match 'glyph-1 'glyph-3)))
            #:duration 2)
```

By default, the explicit match cross-fades the old `+` into the new `-`; add
`#:changed-mode 'morph` to interpolate compatible closed-contour glyph outlines.
The unchanged `x`, `3`, `=`, and `7` leaves are detected automatically. The generated names
are intentionally positional. Use `tagged-formula` or `math-tex` when an author
needs a stable semantic term such as `a-square` or an entire fraction; dvisvgm
glyph leaves are not TeX tokens, and repeated glyphs pair greedily in source
order. `rewrite-formula` also works directly with `glyph-tex` assemblies when
one generated glyph should be anchored.

## Named formula parts

`formula-part` associates a local symbol name with one `formula-visual`. The
formula Visual identity must equal the part name:

```racket
(formula-part
 'numerator
 (latex-formula "n(n+1)"
                #:id 'numerator
                #:center (vec2 0 1/2)))
```

`latex-formula-part` is the shorter constructor. It accepts the same formula
options as `latex-formula`, but uses `#:name` and installs that name as the
formula Visual identity:

```racket
(latex-formula-part "n(n+1)"
                    #:name 'numerator
                    #:center (vec2 0 1/2)
                    #:mode 'inline
                    #:font-size 1/3)
```

Part names are local to one formula assembly. Address a part as a nested Visual
path such as `'(equation numerator)` for ordinary lookup or compatible nested
animation. Formula-part transformations update the complete containing assembly
through a checked correspondence. Two different assemblies may use the same
local names.

A formula assembly stores parts in explicit back-to-front order:

```racket
(formula-assembly parts
                  #:id id
                  #:center origin
                  #:rotation 0
                  #:scale 1
                  #:opacity 1)
```

Every part is typeset independently. Its `#:center`, rotation, scale, opacity,
mode, size, preamble, options, and anchor remain local semantic values. The
assembly does not ask TeX to lay out the fragments as one formula, so the caller
must choose part positions explicitly. Parts can overlap when their local
anchors are placed too close together.

The assembly itself is an affine opacity Visual. Its scale must be uniform,
like an ordinary group, because the current parent-transform model has no shear
component. Parts can still have their own non-uniform local scales.

Use the lookup operations to inspect the local namespace:

```racket
(formula-assembly-visual-part-names source)
;; => '(a-square plus b-square equals c-square)

(formula-assembly-visual-has-part? source 'plus)
;; => #t

(formula-assembly-visual-ref source 'plus)
;; => a formula-part value
```

Replacing the ordered parts is immutable:

```racket
(formula-assembly-visual-with-parts source new-parts)
```

The result preserves the assembly identity, reference position, transform, and
opacity.

## Manual formula correspondence

A `formula-part-match` names one source part and one destination part:

```racket
(formula-part-match 'left-term 'moved-left-term)
```

A `formula-correspondence` stores the complete source and destination
assemblies plus an ordered list of matches:

```racket
(formula-correspondence source destination matches)
```

Validation requires:

- every named source part to exist;
- every named destination part to exist;
- each source name to appear at most once;
- each destination name to appear at most once.

The match list order is significant and determines the order of matched
interior transition layers. Equal part names are not matched automatically. A
caller can provide an empty match list deliberately.

A part omitted from the match list is explicit unmatched data. The two query
functions return unmatched names in the original part order.

## Transforming corresponding formula parts

Create a timeline request with:

```racket
(transform-formula-parts correspondence)
```

The identity of `formula-correspondence-source` identifies the top-level formula
assembly that must already be present in the scene. The current assembly must
have exactly the same ordered local part names as the correspondence source.
Compilation uses the **current** formula values, transforms, and opacities, so a
preceding clip may have changed them without invalidating the correspondence.

The correspondence destination is a part-layout template. At completion, its
ordered part list replaces the current source part list, but these outer
destination fields are not copied:

```text
top-level identity
reference position
rotation
scale
opacity
```

The current source assembly keeps those fields. A semantically unchanged tagged
fragment retains its source SVG crop at the destination transform, preventing a
last-frame renderer-resource swap. A simultaneous `move-to`,
`rotate-to`, `rotate-by`, `scale-to`, `scale-by`, or `fade-to` request can change
the corresponding independent component.

### Matched parts

For a matched pair, local translation, rotation, and x/y scale are interpolated
componentwise from the current source formula to the destination formula.

When all typesetting data are equal, the pair is rendered as one moving layer.
The comparison includes:

```text
LaTeX source
formula mode
font size
preamble
document-class options
Preview-package options
horizontal anchor
vertical anchor
```

Identity, transform, and opacity are intentionally excluded from that
comparison.

When any typesetting field differs, the source and destination formulas move
along the same interpolated transform while the source fades out and the
destination fades in. This is a cross-fade, not a path morph between glyph
outlines.

### Unmatched parts and ordering

Source-only parts keep their current local transform and fade to zero.
Destination-only parts appear at their destination local transform and fade
from zero. `#:mismatch-mode 'fade-transform` instead pairs remaining source and
destination parts in their respective orders, then moves and cross-fades each
pair.

`#:copies` claims selected otherwise-unmatched destination names before either
unmatched policy is applied. A claimed destination is supplied by a transient
copy of the named current source part; that source can still be matched and
remain visible in the formula.

At an interior sample, layer order is:

1. unmatched-source or mismatch cross-fade layers;
2. matched layers in explicit correspondence order;
3. copy layers in destination part order;
4. remaining destination-only layers in destination part order.

A changed matched pair contributes its source layer immediately followed by its
destination layer. Interior layers use deterministic temporary local symbols
beginning with `__formula-transition-`. They are visible in sampled interior
states, but they are not stable endpoint names and should not be used in later
correspondences. Exact destination names are restored at completion.

### Endpoints, easing, and conflicts

Progress zero uses the exact current source part list. Ordinary interior samples
use the shared eased progress. Structural completion installs the destination
part layout even when an unusual easing procedure does not return one at the
end. Such easing can therefore create a deliberate discontinuity at the clip
boundary.

`transform-formula-parts` changes the formula-parts and presence coordination
components. It can run with affine changes and `fade-to`, but it conflicts with:

```text
another formula-part transformation of the same assembly
fade-in or fade-out of the same assembly
another presence-changing request for the same assembly
```

The assembly remains present throughout the transformation. The presence
component reservation prevents request-order-dependent removal or introduction
at completion.

## Formula model

Construct a formula with:

```racket
(latex-formula source
               #:id id
               #:center origin
               #:rotation 0
               #:scale 1
               #:opacity 1
               #:mode 'display
               #:font-size 1
               #:preamble ""
               #:document-class-options '()
               #:preview-options '()
               #:horizontal-alignment 'center
               #:vertical-alignment 'center)
```

`source` is a LaTeX mathematical snippet, without surrounding dollar signs or
math delimiters. It is copied into immutable model storage. Multiline LaTeX
source is allowed. An empty source string is valid and renders as transparent
one-pixel local geometry without invoking TeX.

The modes are:

```text
inline               \( source \)
display              \( \displaystyle source \)
display-environment  \[ source \]
```

The `display` mode is the default because it gives display-style mathematics
with a tight formula box. The real display environment can include larger
horizontal margins supplied by TeX.

The formula font size is measured in local world units. The adapter typesets at
LaTeX's natural size and then maps the selected 10pt, 11pt, or 12pt document
base to the requested world-unit size. Other preamble changes can still alter
formula metrics. Formula width and height also depend on the source itself;
separate formula Visuals can overlap when their anchors are too close.

The source can be replaced immutably:

```racket
(formula-visual-with-source identity "a^2+b^2=c^2")
```

Identity, transform, opacity, mode, size, preamble, options, and alignment are
preserved.

## Typesetting requirements

Formula rendering uses the `latex-pict` Racket package. The package is listed
as a runtime dependency. The rendering machine must also provide a working
`pdflatex` command and the Poppler library required by `racket-poppler`.

When `latex-pict` is installed from the package catalog, use the same Racket
installation that runs this project:

```sh
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  latex-pict
```

For a local checkout, a permanent linked installation is usually more
convenient:

```sh
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  --link \
  "/Users/soegaard/Dropbox/GitHub/latex-pict"
```

A one-command alternative is to prepend the checkout to `PLTCOLLECTS`:

```sh
PLTCOLLECTS="/Users/soegaard/Dropbox/GitHub/latex-pict:" \
  "/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/formula-visuals.rkt \
  frames/formula-visuals \
  formula-visuals.mp4
```

The trailing colon is significant: it keeps Racket's normal collection paths
after the added checkout. Use matching `racket` and `raco` executables so a
package is not linked into one Racket installation and then loaded from
another.

The adapter loads `latex-pict` only when a nonempty formula is rendered. This
means pure model construction, timeline sampling, and non-formula rendering do
not launch TeX. A missing package or native dependency produces a focused error
that names the requested `latex-pict` binding.

Formula source and preamble are trusted input. This prototype does not sandbox
the TeX process, so it should not render untrusted LaTeX in a security-sensitive
application.

`latex-pict` caches repeated complete TeX documents. Animation frames that use
the same formula source and options can therefore reuse its typesetting result;
ordinary Pict scale, rotation, opacity, and placement happen afterward.

## Plain-text model

Construct one text line with:

```racket
(plain-text content
            #:id id
            #:center origin
            #:rotation 0
            #:scale 1
            #:opacity 1
            #:font-size 1/2
            #:font-face #f
            #:font-family 'default
            #:font-style 'normal
            #:font-weight 'normal
            #:color "black"
            #:horizontal-alignment 'center
            #:vertical-alignment 'center)
```

`content` must be a string. It can be empty and can contain Unicode
characters. It cannot contain a carriage return or newline in this prototype.

The constructor copies `content` into immutable model storage. A mutable
`#:font-face` string is copied in the same way. Later changes to the source
strings cannot change the Visual.

A text Visual implements:

```racket
gen:visual
gen:affine-visual
gen:opacity-visual
```

It therefore works with the existing generic operations:

```racket
visual-id
visual-position
visual-with-position
visual-transform
visual-with-transform
visual-rotation
visual-with-rotation
visual-scale
visual-with-scale
visual-opacity
visual-with-opacity
```

Replace only the semantic content with:

```racket
(text-visual-with-content label "New content")
```

The result preserves identity, position, rotation, scale, opacity, font data,
color, and alignment. The original Visual is unchanged.

## Font data

The portable font-family values are:

```racket
'default
'decorative
'roman
'script
'swiss
'modern
'symbol
'system
```

The supported font styles are:

```racket
'normal
'italic
'slant
```

The supported weights are:

```racket
'normal
'bold
'light
```

`#:font-face` is either a preferred face-name string or `#f`. When it is `#f`,
the renderer selects a face from the portable family. A requested face may be
substituted when it is not available in the rendering environment.

`#:font-size` is a positive finite real measured in local world units. The
camera converts it to pixels at render time. Semantic scale is applied after
that conversion, so a non-uniform scale can stretch the text independently in
x and y.

The model stores `#:color` without Pict-specific validation. The built-in Pict
renderer interprets it as a Pict color value. A custom renderer may use another
style representation.

## Anchor alignment

A text Visual's `#:center` is an anchor, not necessarily the geometric center
of the visible glyphs.

Horizontal choices are:

```text
left    the left edge lies at the reference position
center  the horizontal center lies at the reference position
right   the right edge lies at the reference position
```

Vertical choices are:

```text
top       the top edge lies at the reference position
center    the vertical center lies at the reference position
baseline  the font baseline lies at the reference position
bottom    the bottom edge lies at the reference position
```

Alignment is resolved on the untransformed text box. Scale and rotation are
then applied around the selected anchor.

For example, a left-baseline label grows to the right from its position:

```racket
(plain-text "x-axis"
            #:id 'x-label
            #:center (vec2 -4 -2)
            #:font-size 2/5
            #:font-style 'italic
            #:horizontal-alignment 'left
            #:vertical-alignment 'baseline)
```

A right-baseline label grows to the left:

```racket
(plain-text "right endpoint"
            #:id 'right-label
            #:center (vec2 4 -2)
            #:horizontal-alignment 'right
            #:vertical-alignment 'baseline)
```

## Rendering

The default renderer list now contains these leaf renderers in significant
first-match order:

```text
circle
rectangle
path
arrow
Cartesian axes
plain text
LaTeX formula
```

Groups and formula assemblies are composed by the high-level Pict adapter
when no explicit renderer supports the complete composite Visual. The same
ordered renderer list is passed recursively to every formula part.

The built-in text renderer performs these steps:

```text
semantic font data and local font size
        ↓
camera-dependent platform font
        ↓
one-line Pict text drawing and color
        ↓
anchor-centered local Pict box
        ↓
semantic x/y scale
        ↓
semantic rotation
        ↓
stable local bitmap rasterization
        ↓
semantic opacity after renderer dispatch
        ↓
scene, group, or formula-assembly placement
```

Since version `0.50.1`, nonempty plain text is rasterized at a stable local
origin before scene placement. This prevents Pango/Cairo from rerasterizing the
same moving glyph run at a different device-space origin on every frame, which
can otherwise make inter-letter spacing appear to breathe during smooth motion.
The default text renderer caches common immutable appearances. Position, Visual
ID, opacity, and camera center do not invalidate that cache; content, font data,
color, alignment, semantic scale/rotation, and camera pixel scale do. Camera pan
therefore reuses the glyph raster, while camera zoom rerasterizes at the new
resolution. The cache is renderer-local and bounded to 256 appearances and
32 MiB. Adapter-native color objects that cannot be safely snapshotted bypass
the cache but are still rasterized at local origin on each render.

An empty string produces a transparent one-pixel local Pict. This is stable
empty geometry, like an empty path or empty group. Formula rendering is unchanged
by this correction.

A custom renderer placed before the defaults can replace built-in text
rendering:

```racket
(struct label-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (text-visual? visual))
   (define (pict-renderer-render _renderer _visual _camera)
     custom-label-pict)])

(define renderers
  (cons (label-renderer) default-pict-renderers))
```

The high-level adapter still applies semantic opacity after the custom
renderer returns.

## Groups and transforms

A text, formula, or complete formula assembly is an ordinary affine child
in a group:

```racket
(group
 (list
  (rectangle #:id 'background
             #:width 5
             #:height 2
             #:fill "cornflowerblue")
  (latex-formula "x^2+y^2=1"
                 #:id 'grouped-formula
                 #:font-size 4/5))
 #:id 'labeled-panel
 #:center (vec2 2 1)
 #:rotation 1/5
 #:scale 3/2
 #:opacity 4/5)
```

The group compositor resolves the group's uniform scale and rotation through
the child transform before rendering. Text and formula anchors remain local
reference points. A formula assembly resolves its own parts after inheriting
the outer group transform. Child opacity is applied before composite opacity.

The existing animation requests can target a top-level text, formula, formula
assembly, or a group containing those values:

```racket
(scene-play scene
            (move-to 'label (vec2 3 1))
            (rotate-to 'label 1/2)
            (scale-to 'label (vec2 3/2 3/4))
            (fade-to 'label 1/4)
            #:duration 2)
```

Those four requests affect disjoint components and can run simultaneously.
`fade-in` can introduce an absent text, formula, or formula assembly, and
`fade-out` removes it at the structural endpoint.

Nested group children are direct scene-state lookup and timeline targets through
paths such as `'(labeled-panel grouped-formula)`. Their local transforms remain
relative to the containing group.

## Determinism and typesetting environments

The semantic text and formula values are deterministic and immutable. Formula
source, preamble, ordered options, mode, alignment, transform, and opacity are
all explicit values.

Plain-text rendering is byte-identical when the Racket version, operating
system, installed fonts, rendering backend, camera, and semantic values are the
same. Formula rendering additionally depends on the installed TeX distribution,
LaTeX packages, `latex-pict`, Poppler, and their versions. `latex-pict` caches
repeated documents, but its output can change when that environment changes.

Tests that compare formula PNG bytes should therefore either use one fixed TeX
environment or inject a deterministic formula renderer, as the SCENE-M through
SCENE-U rendering suites do.

## Example movies

Render the canonical SCENE-AU unified-style example as PNG frames and an MP4:

```sh
racket examples/unified-style-transitions.rkt \
  frames/unified-style-transitions \
  unified-style-transitions.mp4

open unified-style-transitions.mp4
```

The disk changes motion and four style properties in parallel; the rectangle
demonstrates a delayed timed style transition, and the final succession treats
each `style-to` as one composition child.

The SCENE-AT color example remains available as:

```sh
racket examples/animating-colors.rkt \
  frames/animating-colors \
  animating-colors.mp4

open animating-colors.mp4
```

The shapes move while fill and stroke colors interpolate independently; one
marker also demonstrates alpha-bearing semantic RGBA interpolation.

The SCENE-AS stroke-width example remains available as
`examples/animating-stroke-width.rkt`:

```sh
racket examples/animating-stroke-width.rkt \
  frames/animating-stroke-width \
  animating-stroke-width.mp4

open animating-stroke-width.mp4
```

The ring, rectangle, route, and arrow change cosmetic width while several of
them move or rotate at the same time. The final clip returns all four widths to
a thin endpoint.

The SCENE-AR duration-scaling example remains available as
`examples/duration-scaled-compositions.rkt`, and the SCENE-AQ lagged-start
example remains available as
`examples/lagged-start-animations.rkt`, the SCENE-AP parallel-group example as
`examples/parallel-animation-groups.rkt`, the SCENE-AO succession example as
`examples/successive-animations.rkt`, and the SCENE-AN local-timing example as
`examples/local-animation-timing.rkt`.

For the SCENE-AM correspondence example, run `examples/per-pair-match-penalties.rkt`.
The lower panel there adds a large penalty to original pair `(0 . 0)`, so the global
forced assignment swaps the two real destination identities and the curves cross.

The SCENE-AL per-subpath-penalty comparison remains available:

```sh
racket examples/per-subpath-topology-penalties.rkt \
  frames/per-subpath-topology-penalties \
  per-subpath-topology-penalties.mp4

open per-subpath-topology-penalties.mp4
```

The upper panel uses one shared low cost and therefore replaces both distant
pairs. The lower panel raises the death cost of original source index 0 and the
birth cost of original destination index 1, so the globally assigned upper pair
remains a real morph while the lower pair still collapses/regrows.

The SCENE-AK per-subpath-anchor example remains available:

```sh
racket examples/per-subpath-topology-anchors.rkt \
  frames/per-subpath-topology-anchors \
  per-subpath-topology-anchors.mp4

open per-subpath-topology-anchors.mp4
```

The two lower source curves collapse into separate marked hubs while two new
closed loops grow from those corresponding hubs. A surviving upper curve visibly
changes shape at the same time.

The SCENE-AJ penalized-correspondence comparison remains available:

```sh
racket examples/penalized-topology-changing-morphs.rkt \
  frames/penalized-topology-changing-morphs \
  penalized-topology-changing-morphs.mp4

open penalized-topology-changing-morphs.mp4
```

The upper path uses default forced correspondence and sweeps from the left source
to the distant right destination. The lower path uses birth/death penalties of
2 and instead collapses/regrows locally.

The SCENE-AI explicit shared-anchor example remains available:

```sh
racket examples/anchored-topology-changing-morphs.rkt \
  frames/anchored-topology-changing-morphs \
  anchored-topology-changing-morphs.mp4

open anchored-topology-changing-morphs.mp4
```

The lower source curve collapses into a marked red hub at the origin while a new
lower closed loop grows from that same hub. A surviving upper curve visibly
changes shape at the same time.

The SCENE-AH default bounds-center example remains available:

Render the canonical SCENE-AH topology-changing morph as PNG frames and an MP4:

```sh
racket examples/topology-changing-morphs.rkt \
  frames/topology-changing-morphs \
  topology-changing-morphs.mp4

open topology-changing-morphs.mp4
```

The surviving closed loop and open curve both visibly change geometry. A lower
open curve has no destination partner and collapses to its own bounds center,
while a new lower closed loop grows from its destination bounds center. The
example deliberately scrambles destination order, open direction, and closed
phase/direction so the surviving real correspondence is exercised too.

The SCENE-AG equal-count mixed-topology comparison remains available:

Render the canonical SCENE-AG mixed-topology correspondence comparison as PNG frames and an MP4:

```sh
racket examples/mixed-compound-morph-correspondence.rkt \
  frames/mixed-compound-morph-correspondence \
  mixed-compound-morph-correspondence.mp4

open mixed-compound-morph-correspondence.mp4
```

Both panels contain one compound geometry with interleaved open curves and closed
loops. Every intended destination counterpart also changes shape. The destination
preserves the open/closed storage pattern so ordinary normalization is legal, but
swaps identities within both topology classes and scrambles traversal
direction/phase. The upper panel follows stored order and sweeps objects across
the scene. The lower panel uses `morph-to-mixed-compound-aligned`, which solves
the open and closed assignments independently, so every green object now visibly
morphs while staying with its spatially sensible counterpart.

The SCENE-AF all-open compound comparison remains available:


```sh
racket examples/open-compound-morph-correspondence.rkt \
  frames/open-compound-morph-correspondence \
  open-compound-morph-correspondence.mp4

open open-compound-morph-correspondence.mp4
```

Both panels begin from the same two-open-subpath source and target the same
visible destination, whose subpath order is swapped and whose two traversals are
reversed. The upper panel uses `morph-to-normalized`, so the curves cross-pair by
storage order. The lower panel uses `morph-to-open-compound-aligned`, which
chooses the global subpath assignment and endpoint direction independently for
each pair.

The SCENE-AE one-open-path comparison remains available:


```sh
racket examples/open-morph-correspondence.rkt \
  frames/open-morph-correspondence \
  open-morph-correspondence.mp4

open open-morph-correspondence.mp4
```

Both panels begin from the same open source path and target the same visible
destination, which is deliberately stored from right to left. The upper panel
uses `morph-to-normalized`, so opposite endpoints are paired by storage order.
The lower panel uses `morph-to-open-aligned`, which compares forward and reversed
destination traversal and selects the spatially better endpoint correspondence.

The SCENE-AD compound correspondence comparison remains available:

```sh
racket examples/compound-morph-correspondence.rkt \
  frames/compound-morph-correspondence \
  compound-morph-correspondence.mp4

open compound-morph-correspondence.mp4
```

Both panels begin from the same compound source and target the same stored
destination, whose inner and outer loops are deliberately reversed in subpath
order. The upper panel uses `morph-to-normalized`, so outer and inner loops
cross-pair by storage order. The lower panel uses `morph-to-compound-aligned`,
which globally pairs the loops and then aligns phase/direction within each pair.

The SCENE-AC one-loop correspondence comparison remains available:

```sh
racket examples/automatic-morph-correspondence.rkt \
  frames/automatic-morph-correspondence \
  automatic-morph-correspondence.mp4

open automatic-morph-correspondence.mp4
```

Both panels begin from the same source loop and target the same stored
destination. The upper panel uses `morph-to-normalized`, so its stored vertex
order creates a visibly twisting correspondence. The lower panel uses
`morph-to-aligned`, which first selects the low-distance phase/direction and
therefore morphs according to spatial correspondence instead of storage order.

The SCENE-AB reversal/phase example remains available:

```sh
racket examples/reversed-and-cyclic-paths.rkt \
  frames/reversed-and-cyclic-paths \
  reversed-and-cyclic-paths.mp4
```

The SCENE-AA joined-offset example remains available:

```sh
racket examples/joined-offset-paths.rkt \
  frames/joined-offset-paths \
  joined-offset-paths.mp4
```

Render the canonical SCENE-U camera example as PNG frames and an MP4:

```sh
racket examples/camera-pan-and-zoom.rkt \
  frames/camera-pan-and-zoom \
  camera-pan-and-zoom.mp4

open camera-pan-and-zoom.mp4
```

The example fades in an axes diagram and a sampled graph, then pans and zooms
while a marker moves across the graph. It returns to the original overview and
holds the final frame. Six and a half seconds at 30 frames per second produce
195 frames.

The SCENE-S parametric-and-data example remains available:

```sh
racket examples/parametric-data-plots.rkt \
  frames/parametric-data-plots \
  parametric-data-plots.mp4

open parametric-data-plots.mp4
```

The example draws a smooth nodal cubic and a smooth ordered observation series
while fading in the axes. It then dims the data series, rotates the parametric
curve, and holds the final state. Four seconds at 30 frames per second produce
120 frames.

The SCENE-R sampled-function example remains available:

```sh
racket examples/function-graphs.rkt \
  frames/function-graphs \
  function-graphs.mp4

open function-graphs.mp4
```

The SCENE-Q arrow-and-axes example remains available:

```sh
racket examples/arrows-and-axes.rkt \
  frames/arrows-and-axes \
  arrows-and-axes.mp4

open arrows-and-axes.mp4
```

The SCENE-P fitted-layout example remains available:

```sh
racket examples/relative-layout.rkt \
  frames/relative-layout \
  relative-layout.mp4

open relative-layout.mp4
```

The SCENE-O formula-part transformation remains available:

```sh
racket examples/transforming-formula-parts.rkt \
  frames/transforming-formula-parts \
  transforming-formula-parts.mp4
```

With a local `latex-pict` checkout that is not linked as a package, prepend its
repository root to `PLTCOLLECTS` for formula examples:

```sh
PLTCOLLECTS="/Users/soegaard/Dropbox/GitHub/latex-pict:" \
  "/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/relative-layout.rkt \
  frames/relative-layout \
  relative-layout.mp4
```

The trailing colon preserves Racket's normal collection paths. Use the `racket`
and `raco` executables from the same Racket installation.

Earlier examples remain available:

```text
examples/moving-circle.rkt
examples/moving-shapes.rkt
examples/transforming-shapes.rkt
examples/path-shapes.rkt
examples/creating-paths.rkt
examples/curved-paths.rkt
examples/morphing-paths.rkt
examples/normalized-morphs.rkt
examples/fading-visuals.rkt
examples/grouped-visuals.rkt
examples/text-visuals.rkt
examples/markers-scatter-areas.rkt
```

## Tests

The new SCENE-AU semantic model suite is:

```text
tests/scene-au-test.rkt
```

It covers full and partial unified style requests, immediate/deferred capability
validation, exact primitive endpoints, property-specific overlap conflicts,
compatible affine/style concurrency, succession chaining, `timed`, `lagged-start`,
and structural introduction.

The new SCENE-AU renderer and output suite is:

```text
tests/scene-au-render-test.rkt
```

It checks integrated style+motion rendering, fixed frame dimensions, exact stored
style endpoints, and byte-identical repeated PNG output.

The new SCENE-AT semantic model suite is:

```text
tests/scene-at-test.rkt
```

It covers semantic RGBA construction and X11-style/hex parsing, fill/stroke capability
protocols, exact textual endpoints, alpha interpolation, independent style
components, overlap conflicts, AN--AR timing, structural introduction, absent
paint validation, and third-party protocol validation.

The new SCENE-AT renderer and output suite is:

```text
tests/scene-at-render-test.rkt
```

It checks visible fill/stroke interpolation, adapter propagation through
path-derived built-ins, alpha rendering, fixed frame dimensions, and
byte-identical repeated PNG output.

The SCENE-AS semantic model suite remains:

```text
tests/scene-as-test.rkt
```

It covers the public stroke-width protocol, every built-in stroke-bearing Visual,
request validation, exact numeric endpoints, exact/inexact custom-setter coercion,
zero width, renderer-independent large semantic widths, scatter/callout exclusions,
compatible parallel components, overlap conflicts, sequential chaining, local
timing, structural introduction, and third-party protocol validation.

The SCENE-AS renderer and output suite remains:

```text
tests/scene-as-render-test.rkt
```

It checks visible width interpolation, simultaneous motion, independent adapter
propagation for all seven built-in protocol types, width-zero hairline rendering,
the default Pict backend's 255-pixel width limit, fixed frame dimensions, and
byte-identical repeated PNG rendering.

The SCENE-AR duration-scaling suites remain regression tests:

```text
tests/scene-ar-test.rkt
tests/scene-ar-render-test.rkt
```

The prior SCENE-AR suite originally covered timed composite construction, nested
timed children, proportional succession spans, scaled delays, duration-scaled
parallel groups, generalized lag timing, easing inheritance, structural events,
conflicts, camera-follow, and exact endpoints.


The SCENE-AQ lagged-start suites remain regression tests:

```text
tests/scene-aq-test.rkt
tests/scene-aq-render-test.rkt
```

The SCENE-AP parallel-group suites remain regression tests:

```text
tests/scene-ap-test.rkt
tests/scene-ap-render-test.rkt
```

The SCENE-AO succession suites remain regression tests:

```text
tests/scene-ao-test.rkt
tests/scene-ao-render-test.rkt
```

The SCENE-AN local-timing suites remain regression tests:

```text
tests/scene-an-test.rkt
tests/scene-an-render-test.rkt
```

The SCENE-AM semantic model suite remains a regression test:

```text
tests/scene-am-test.rkt
```

It covers forced-mode reassignment, numeric AJ death+birth rejection, exact-cost
ties, unequal-count forced pairing, mixed-topology original-index semantics,
key/value/range validation, immutable request capture, exact endpoints, and
component conflicts.

The SCENE-AM renderer and output suite remains a regression test:

```text
tests/scene-am-render-test.rkt
```

It compares geometric-only and pair-penalized correspondence, checks fixed frame
dimensions and exact final storage, and verifies byte-identical repeated PNG
output.

The SCENE-AL semantic model suite is:

```text
tests/scene-al-test.rkt
```

It covers sparse birth/death cost maps, original source/destination index
semantics under global reordering and mixed topology, shared-cost fallback,
one-sided overrides, immutable request capture, numeric-mode and map validation,
exact timeline endpoints, and component conflicts.

The SCENE-AL renderer and output suite is:

```text
tests/scene-al-render-test.rkt
```

It compares shared AJ costs against sparse per-subpath costs, checks fixed frame
dimensions and exact final storage, and verifies byte-identical repeated PNG
output.

The SCENE-AK semantic model suite remains a regression test:

```text
tests/scene-ak-test.rkt
```

It covers sparse birth/death maps, original source/destination index semantics,
shared-anchor fallback, explicit `'bounds-center` overrides, SCENE-AJ voluntary
unmatched slots, immutable request capture, map validation, exact timeline
endpoints, and component conflicts.

The SCENE-AK renderer and output suite remains a regression test:

```text
tests/scene-ak-render-test.rkt
```

It compares independently anchored slots against one shared hub, checks fixed
frame dimensions and exact final storage, and verifies byte-identical repeated
PNG output.

The SCENE-AJ semantic model suite remains a regression test:

```text
tests/scene-aj-test.rkt
```

It covers forced-only backward compatibility, low/high numeric penalties, exact
cost ties, selective global match rejection, unequal-count numeric mode, anchor
placement for voluntary births/deaths, exact timeline endpoints, option
validation, and component conflicts.

The SCENE-AJ renderer and output suite remains a regression test:

```text
tests/scene-aj-render-test.rkt
```

It compares forced sweeping correspondence against local penalized
collapse/regrowth, checks fixed frame dimensions and exact final storage, and
verifies byte-identical repeated PNG output.

The SCENE-AI semantic model suite remains a regression test:

```text
tests/scene-ai-test.rkt
```

It covers default bounds-center compatibility, explicit birth/death points, pure
birth/death, local-coordinate semantics, SCENE-AG reduction when counts match,
exact timeline endpoints, option validation, normalization, and component
conflicts.

The SCENE-AI renderer and output suite remains a regression test:

```text
tests/scene-ai-render-test.rkt
```

It covers shared explicit-anchor rendering, fixed frame dimensions, exact final
destination representation, deterministic bitmap sampling, and byte-identical
repeated PNG output.

The SCENE-AH semantic model suite remains a regression test:

```text
tests/scene-ah-test.rkt
```

It covers rectangular open/closed assignment, simultaneous birth/death,
in-place seed centers, pure birth from empty, pure death to empty, exact
reduction to SCENE-AG, normalization compatibility, exact structural endpoints,
component conflicts, and invalid degenerate real subpaths/options.

The SCENE-AH renderer and output suite remains a regression test:

```text
tests/scene-ah-render-test.rkt
```

It covers four-slot interior birth/death rendering, fixed frame dimensions,
exact destination representation, deterministic bitmap sampling, and
byte-identical repeated PNG output.

The SCENE-AG semantic model suite remains a regression test:

```text
tests/scene-ag-test.rkt
```

It covers interleaved open/closed topology, independent class assignment,
open-direction and closed phase/direction alignment, homogeneous reductions,
forward-only mode, exact structural endpoints, component conflicts, and invalid
empty/topology-count/degenerate inputs.

The SCENE-AG renderer and output suite remains a regression test:

```text
tests/scene-ag-render-test.rkt
```

It covers mixed-topology renderer integration, fixed frame dimensions, exact
destination representation, deterministic bitmap sampling, and byte-identical
repeated PNG output.

The new SCENE-AF semantic model suite is:

```text
tests/scene-af-test.rkt
```

It covers reordered/reversed multi-open correspondence, global-versus-greedy
assignment, deterministic exact ties, one-subpath reduction to SCENE-AE,
forward-only mode, normalized timeline integration, exact structural endpoints,
component conflicts, and invalid empty/unequal/closed/mixed/degenerate inputs.

The new SCENE-AF renderer and output suite is:

```text
tests/scene-af-render-test.rkt
```

It covers renderer integration, fixed frame dimensions, exact destination
representation, deterministic bitmap sampling, and byte-identical repeated PNG
output.

The SCENE-AE semantic model suite remains a regression test:

```text
tests/scene-ae-test.rkt
```

It covers reversed endpoint correspondence, forward-only mode, exact no-op and
forward-tie behavior, cubic paths, timeline integration, exact structural
endpoints, path-geometry conflicts, and invalid closed/compound/degenerate
inputs.

The SCENE-AE renderer and output suite remains a regression test:

```text
tests/scene-ae-render-test.rkt
```

It covers renderer integration, fixed frame dimensions, exact destination
representation, deterministic bitmap sampling, and byte-identical repeated PNG
output.

The SCENE-AD semantic model suite remains a regression test:

```text
tests/scene-ad-test.rkt
```

It covers reordered multi-loop correspondence, global-versus-greedy assignment,
deterministic exact ties, one-loop reduction to SCENE-AC, forward-only mode,
timeline integration, exact structural endpoints, component conflicts, and
invalid empty/unequal/open/degenerate compound paths.

The SCENE-AD renderer and output suite remains a regression test:

```text
tests/scene-ad-render-test.rkt
```

It covers compound renderer integration, fixed frame dimensions, exact endpoint
representation, deterministic bitmap sampling, and byte-identical repeated PNG
output.

The SCENE-AC semantic model suite remains a regression test:

```text
tests/scene-ac-test.rkt
```

It covers phase-only alignment, reverse-plus-phase alignment, forward-only
selection, deterministic no-op ties, cubic interior phase alignment, timeline
integration, exact endpoints, component conflicts, and validation.

The SCENE-AC renderer and output suite remains a regression test:

```text
tests/scene-ac-render-test.rkt
```

It covers ordinary renderer integration, fixed frame dimensions, exact endpoint
representation, deterministic repeated bitmap sampling, and byte-identical PNG
output.

The SCENE-AB semantic model suite remains a regression test:

```text
tests/scene-ab-test.rkt
```

It covers open/closed line and cubic reversal, fraction reversal semantics,
closed-loop phase changes at vertices and segment interiors, validation, direct
path-motion/orientation reuse, and normalized morph preparation.

The SCENE-AB renderer and output suite remains a regression test:

```text
tests/scene-ab-render-test.rkt
```

It covers pixel-identical rendering of equivalent reversed/cycled closed loops,
pixel-stable camera following during reverse traversal, and byte-identical
repeated PNG output.

The SCENE-AA semantic model suite remains a regression test:

```text
tests/scene-aa-test.rkt
```

It covers miter, bevel, and round outside joins, inside intersections, signed
offsets, miter-limit fallback, closed paths, cubic/degenerate validation, and
direct path-motion/orientation reuse of generated joined geometry.

The SCENE-AA renderer and output suite remains a regression test:

```text
tests/scene-aa-render-test.rkt
```

It covers visibly distinct join geometry, camera-follow traversal through a
round cubic connector, and byte-identical repeated PNG output.

The SCENE-Z semantic model suite remains a regression test:

```text
tests/scene-z-test.rkt
```

It covers total-arc-length tangents and normals, stationary cubic endpoints,
forward/reverse signed normal offsets, tangent-derived rotation, additive
rotation offsets, transformed path Visual routes, component conflicts, and
camera following of an offset target.

The SCENE-Z renderer and output suite is:

```text
tests/scene-z-render-test.rkt
```

It covers exact rendered tangent orientation, rendered normal-offset placement,
pixel-stable camera following of offset motion, and byte-identical repeated PNG
output.

The SCENE-Y semantic model suite remains a regression test:

```text
tests/scene-y-test.rkt
```

It covers total-arc-length point lookup, unequal line lengths, cubic traversal,
implicit closed edges, reverse motion, transformed and stale-id path Visual
routes, translation conflicts, discontinuity rejection, coordinate-domain
validation, and sampled-state camera following through a polyline elbow.

The SCENE-Y renderer and output suite is:

```text
tests/scene-y-render-test.rkt
```

It covers rendered arc-length placement, pixel-stable camera following at a path
bend, frame counts, and byte-identical repeated PNG output. The corrected
SCENE-X demonstration has a separate frame-by-frame regression:

```text
tests/scene-x-example-test.rkt
```

The SCENE-X overlay/callout suites remain regression tests:

```text
tests/scene-x-test.rkt
tests/scene-x-render-test.rkt
```

The SCENE-U animated-camera suites remain regression tests:

```text
tests/scene-u-test.rkt
tests/scene-u-render-test.rkt
```

The SCENE-T number-line and coordinate-decoration suites remain regression
tests:

```text
tests/scene-t-test.rkt
tests/scene-t-render-test.rkt
```

The SCENE-S parametric and data-plot suites also remain regression tests:

```text
tests/scene-s-test.rkt
tests/scene-s-render-test.rkt
```

Run the complete regression suite with the same Racket installation used for
examples and package setup:

```sh
raco make main.rkt

raco test tests/scene-a-test.rkt \
          tests/scene-a-render-test.rkt \
          tests/scene-b-test.rkt \
          tests/scene-b-render-test.rkt \
          tests/scene-c-test.rkt \
          tests/scene-c-render-test.rkt \
          tests/scene-e-test.rkt \
          tests/scene-e-render-test.rkt \
          tests/scene-f-test.rkt \
          tests/scene-f-render-test.rkt \
          tests/scene-g-test.rkt \
          tests/scene-g-render-test.rkt \
          tests/scene-h-test.rkt \
          tests/scene-h-render-test.rkt \
          tests/scene-i-test.rkt \
          tests/scene-i-render-test.rkt \
          tests/scene-j-test.rkt \
          tests/scene-j-render-test.rkt \
          tests/scene-k-test.rkt \
          tests/scene-k-render-test.rkt \
          tests/scene-l-test.rkt \
          tests/scene-l-render-test.rkt \
          tests/scene-m-test.rkt \
          tests/scene-m-render-test.rkt \
          tests/scene-n-test.rkt \
          tests/scene-n-render-test.rkt \
          tests/scene-o-test.rkt \
          tests/scene-o-render-test.rkt \
          tests/scene-p-test.rkt \
          tests/scene-p-render-test.rkt \
          tests/scene-q-test.rkt \
          tests/scene-q-render-test.rkt \
          tests/scene-r-test.rkt \
          tests/scene-r-render-test.rkt \
          tests/scene-s-test.rkt \
          tests/scene-s-render-test.rkt \
          tests/scene-t-test.rkt \
          tests/scene-t-render-test.rkt \
          tests/scene-u-test.rkt \
          tests/scene-u-render-test.rkt \
          tests/scene-v-test.rkt \
          tests/scene-v-render-test.rkt \
          tests/scene-w-test.rkt \
          tests/scene-w-render-test.rkt \
          tests/scene-x-test.rkt \
          tests/scene-x-render-test.rkt \
          tests/scene-x-example-test.rkt \
          tests/scene-y-test.rkt \
          tests/scene-y-render-test.rkt \
          tests/scene-z-test.rkt \
          tests/scene-z-render-test.rkt \
          tests/scene-aa-test.rkt \
          tests/scene-aa-render-test.rkt \
          tests/scene-ab-test.rkt \
          tests/scene-ab-render-test.rkt \
          tests/scene-ac-test.rkt \
          tests/scene-ac-render-test.rkt \
          tests/scene-ad-test.rkt \
          tests/scene-ad-render-test.rkt \
          tests/scene-ae-test.rkt \
          tests/scene-ae-render-test.rkt \
          tests/scene-af-test.rkt \
          tests/scene-af-render-test.rkt \
          tests/scene-ag-test.rkt \
          tests/scene-ag-render-test.rkt \
          tests/scene-ah-test.rkt \
          tests/scene-ah-render-test.rkt \
          tests/scene-ai-test.rkt \
          tests/scene-ai-render-test.rkt \
          tests/scene-aj-test.rkt \
          tests/scene-aj-render-test.rkt \
          tests/scene-ak-test.rkt \
          tests/scene-ak-render-test.rkt \
          tests/scene-al-test.rkt \
          tests/scene-al-render-test.rkt \
          tests/scene-am-test.rkt \
          tests/scene-am-render-test.rkt \
          tests/scene-an-test.rkt \
          tests/scene-an-render-test.rkt
```

## Module boundaries

The pure semantic camera-animation, frame-space, arrow, axes, coordinate-series,
sampled-graph, parametric, data-plot, point-marker, scatter-area, text, formula,
and named-part implementations live in:

```text
private/camera-animation.rkt
private/frame-space.rkt
private/arrow-visual.rkt
private/axes-visual.rkt
private/coordinate-series.rkt
private/function-graph.rkt
private/parametric-data-plot.rkt
private/point-marker-visual.rkt
private/scatter-area-plot.rkt
private/text-visual.rkt
private/formula-visual.rkt
private/formula-parts-visual.rkt
private/formula-part-transition.rkt
```

They import only pure semantic camera, geometry, transform, Visual, or other
semantic-model modules. They do not import Pict, `racket/draw`, bitmap,
filesystem, process, browser, or JavaScript APIs.

Renderer-aware camera fitting lives separately in:

```text
private/camera-framing.rkt
```

That adapter may measure Picts through `private/relative-layout.rkt`, but the
resulting camera-fit request stores only a semantic center and visible width.

`private/function-graph.rkt`, `private/parametric-data-plot.rkt`, and
`private/scatter-area-plot.rkt` call supplied procedures only during
construction and store only ordered semantic path geometry or marker values.
`private/coordinate-series.rkt` contains shared clipping, run-building,
interpolation, and numeric-distance rules. These modules contain
no Pict, drawing-context, bitmap, filesystem, process, browser, or JavaScript
values.

The built-in circle, rectangle, path, arrow, axes, and plain-text renderers
live in:

```text
private/shape-pict-renderers.rkt
```

The arrow and axes adapters convert their semantic local geometry to the same
path-rendering code used by ordinary path Visuals. The semantic modules do not
import Pict or `racket/draw`.

The LaTeX formula renderer and shared anchor layout live in:

```text
private/latex-formula-pict-renderer.rkt
private/anchored-pict.rkt
```

Renderer dispatch, semantic opacity, frame-space placement, and callout leader
composition remain in:

```text
private/pict-adapter.rkt
```

Renderer-aware measurement and immutable relative placement live in:

```text
private/relative-layout.rkt
```

That module is an adapter module, not a pure semantic-model module. It may
render text, formulas, groups, and custom Visuals to determine their boxes.

The complete path is:

```text
semantic marker, arrow, axes, coordinate-plot, text, formula,
or formula-assembly model
        ↓
matched formula-transition planning and scene-state sampling
        ↓
composite-transform resolution
        ↓
explicit first-supporting renderer selection
        ↓
platform-font or latex-pict rendering
        ↓
semantic opacity
        ↓
scene, group, or formula-assembly placement
        ↓
bitmap / PNG / optional MP4
```

## Limitations and follow-on ideas

This is the running design backlog for version `1.5.0`. Every completed SCENE
stage must update it with the limitations, edge cases, and useful next ideas
revealed by that stage. When a later stage delivers an item, retain its history
in that stage's notes and revise this list to state the remaining boundary
precisely; do not silently lose the follow-on idea that led to the work.

### Text, formulas, and layout

- SCENE-CS adds explicit multiline `paragraph` text, measured word wrapping,
  line spacing/alignment, rich inline text spans, and a first-line baseline
  anchor. It does not hyphenate, justify, shape bidirectional/complex scripts,
  flow text around Visuals, embed formula/Visual spans, or provide a general
  markup/CSS language. Adjacent spans are independent Pict runs, so the font
  backend cannot kern or ligate across a span boundary.
- SCENE-DV's finishing helpers measure complete renderer boxes and return static
  position snapshots. They do not solve general two-dimensional packing,
  account for rotation or future motion, create live constraints, reserve
  semantic safe areas, or infer a true baseline for arbitrary non-text Visuals.
  `avoid-overlap` is deliberately a deterministic one-axis greedy pass, not a
  global optimal layout algorithm.

### Matrices and tables

- SCENE-DF gives matrices and tables a regular, immutable nested-group shape
  plus fixed scalar dimensions, explicit per-column/per-row size lists, or an
  `'auto` construction-time measurement. Auto sizing uses the active default
  Pict renderer once, then produces an ordinary renderer-independent group.
  It does not dynamically remeasure after a text/formula changes or choose a
  size from future animation frames.
- Matrices and tables retain SCENE-CT's stable paths:
  rows are `row-N`, cells are `col-N`, and matrix brackets/table grid lines are
  ordinary addressable path Visuals. Cell dimensions and inter-cell gaps are
  explicit world-space values; the constructors do not yet measure entries to
  choose column widths, row heights, or delimiter size automatically. A cell's
  supplied reference position is intentionally replaced by its grid position.
- Matrix delimiters are square brackets only. Tables currently have one shared
  rectangular grid and no header semantics, per-cell fills, alternating rows,
  spanning cells, decimal alignment, separators, or automatic overflow/wrapping.
  A future presentation table should build on these stable paths rather than
  bypassing them with a renderer-only object.

### Traces and temporal sampling

- SCENE-CU traces one author-supplied position procedure over an explicit scalar
  phase parameter. It has no frame-history dependence, but cannot infer a locus
  from arbitrary moving Visuals, reconstruct a nonfunctional simulation, adapt
  sample density to curvature, split discontinuities automatically, or retain a
  physical fading history. `#:dissipate?` uses deterministic piecewise-opacity
  path segments; it is not a particle/trail simulation.

### Composable camera motion

- SCENE-CV schedules existing pan, zoom, fit, and clip-local follow requests in
  the same `timed`, sequential, parallel, and lagged trees as Visuals. It does
  not add camera rotation, animated pixel dimensions/background, persistent
  follow across clips, continuously recomputed fit, safe-area framing, or
  overlapping camera clips. A `camera-fit` remains the static center/width
  snapshot created by the existing fit helpers.
- Positive-duration overlap may still update each camera component only once:
  center changes (pan, follow, fit) conflict with one another and width changes
  (zoom, fit) conflict with one another. A pan/follow and a zoom may run in
  parallel. Follow expects a world-space target to remain available for its
  active interval; it is not a general relation that survives a removal.
- SCENE-EE's `camera-view` renders one target, an explicit nonempty target list,
  or all top-level world-space layers through an independently animated inset
  camera. Explicit nested paths resolve in world coordinates; all-layer views
  intentionally do not descend into groups and exclude all frame-space overlays
  (including other views) to avoid recursion. The only viewport clips are the
  fixed-style `rectangle` and `rounded` borders; there is no arbitrary clip
  path, separately styleable frame, viewport title/control child, or automatic
  frame-overlay collision avoidance. A selected or followed target cannot be
  frame-space.
- Secondary-camera pan, zoom, follow, and fit work only on a top-level named
  `camera-view`. Follow preserves a target's reference-position offset, rather
  than centering or tracking its rendered box, and requires the target to remain
  available in world space for the active clip. A fit is the existing measured
  center/width snapshot, not a continuously recomputed fit. Secondary views do
  not add camera rotation, perspective, animated pixel dimensions/background,
  or a persistent observer across clips. As with the main camera, one view may
  update center once and visible width once in an overlapping interval; a
  pan/follow and a zoom can run together.

### Video authoring, assembly, and caching

- SCENE-DG has no timeline editor, section-aware preview player, waveform
  display, audio-duration inspection, ducking/side-chain mixing, multi-track
  buses, audio/video rate conversion controls, or an interactive clip-arranging
  UI. `audio-cue` validates placement, trim, gain, and fades, but opens the
  source only during FFmpeg assembly; codec failures and source durations are
  therefore reported there. MP4 output carries `mov_text` captions from SRT or
  WebVTT, but does not burn styled captions into pixels.
- `assemble-authored-mp4!` works from one numbered PNG sequence;
  `mux-authored-video!` deliberately replaces rather than preserves any audio
  already present in its visual input. `render-authored-mp4!` requires one or
  more contiguous named sections that cover the entire scene, so its joined
  partials preserve the original global frame grid. A deliberately partial
  export can still use `render-timeline-section!`, `encode-mp4!`, and
  `concatenate-mp4!` explicitly.
- SCENE-DL makes the built-in `linear`, `smooth`, `smoothstep`, `rush-into`,
  `rush-from`, `there-and-back`, and `there-and-back-with-pause` rate functions
  callable serializable values. They can be cached safely, but custom procedures
  still deliberately disable automatic reuse because their implementation cannot
  be hashed. The initial vocabulary has no cubic-Bézier authoring form, spring or
  physics easing, inverse/time-reparameterization operation, externally named
  user-defined rate-function registry, or interpolation-specific overshoot.
- SCENE-DH uses `'auto` by default for selected-section cache keys. The
  fingerprint includes the serializable scene value, selected bounds and source
  frames, FPS, camera and renderer representations, Racket version, and bytes
  of caller-declared `#:asset-files`. It intentionally disables automatic reuse
  when an arbitrary procedure appears in the scene representation, because
  procedure source cannot be hashed safely. It also cannot discover external
  SVG/image, font, TeX-toolchain, FFmpeg-build, or transitive asset dependencies:
  list such files in
  `#:asset-files`, use an explicit versioned `#:cache-key`, or pass `#f` to
  force a fresh render. Partial-MP4 manifests reuse only compatible locally
  encoded visual clips; FFmpeg itself is still required for encoding, joining,
  and muxing.

### Mathematical shape catalogue

- SCENE-DJ's ellipse, annulus, sector, regular polygon, star, and rounded
  rectangle are cubic/path geometry, not new semantic leaf types. This keeps
  them portable through existing path operations, but does not retain a
  separately editable radius, corner, side, or star-point parameter after
  construction. The default renderer uses odd-even fill for annulus holes;
  there are no gradients, patterns, clipping, or automatic self-intersection
  repair.
- SCENE-DM supports Boolean fill geometry only for one simple convex closed
  contour in each operand. Cubic segments are uniformly sampled at
  `#:curve-samples` pieces per cubic, so the result is polygonal rather than an
  exact Bézier Boolean. Union, difference, and XOR are returned as disjoint
  fill partitions; use `#:stroke #f` on a result when interior partition edges
  should not be drawn. General concave/compound contours, exact curve
  intersections, reconstructed exterior outlines, fill-rule selection,
  clipping paths, and self-intersection repair remain follow-on work.
- `arc-between-points` and `curved-arrow` are circular and require a nonzero
  sweep strictly smaller than a full turn. They do not select a route around
  obstacles, dynamically follow moving endpoints, or support elliptical/
  Bézier route geometry. A `derived-visual` can rebuild one from sampled points.
  `labeled-point` is a static dot/text group; it has no automatic label
  collision avoidance, box-anchor placement, or mathematical typesetting.
- SCENE-DS effects are intentionally a focused subset. `wiggle` is rotational
  (not a per-glyph or per-control-point deformation); `flash` and `focus-on`
  use a rendered target box; `show-passing-flash` currently requires a path
  Visual; and growth is an introduction effect for a supplied new Visual.
  There is no generic wave/blink engine, effect composition preset, or
  renderer-specific shader effect.

### Probability and statistics

- SCENE-DT supplies compact, addressable diagram constructors rather than a
  statistical-analysis system. Bar-chart axes, legends, categories, automatic
  tick selection, data-derived labels, pie/density/violin plots, and confidence
  interval calculations remain author responsibilities. Histograms use equal
  width bins; sample-space cells deliberately have equal geometry even when
  their labels carry unequal weights. Probability trees are explicit finite
  branch trees and do not verify conditional-probability totals. Box plots use
  interpolated quartiles and show no outlier convention.

### Linear algebra diagrams

- SCENE-CZ supplies `number-plane`, `vector-arrow`, `basis-vectors`, and a
  canonical `linear-transformation-diagram` as ordinary nested groups. The
  name `vector-arrow` deliberately avoids shadowing Racket's base `vector`
  constructor. Numeric tick labels and `vector-label` are static snapshots;
  they do not follow separately animated targets yet. There are no ghost
  vectors, basis-coordinate formulas, matrix multiplication helpers, or a
  persistent linear-transformation scene abstraction—use `apply-matrix` on the
  returned diagram group.

### Pointwise, complex, and polar maps

- SCENE-DQ adaptively subdivides each mapped segment until its midpoint has a
  mapped chord error no larger than `#:tolerance` (or `#:max-depth` is met).
  `#:discontinuities 'split` treats a raised error, non-`vec2` result, or
  nonfinite complex result as a path break; `#:discontinuities 'error` is the
  strict alternative. The map procedure should therefore be pure: adaptive
  refinement may call it repeatedly at the same source point. This is still a
  sampled approximation, not an exact symbolic transformation of a Bézier
  curve, and it has no automatic branch-cut analysis or asymptote clipping.
- A nested ordinary target is resolved in world coordinates and rebased through
  its invertible enclosing affine map, leaving its siblings addressable. A
  nested request through a singular enclosing map, a derived Visual, or a
  frame-space overlay is rejected. Text, images, and custom affine leaves
  remain legible at their original affine placement; they are not warped.
- Text, images, and custom affine leaves have no exposed path outline. They
  remain legible at their original world placement while sibling geometric
  leaves deform; an application needing warped glyphs or pixels must provide
  an explicit vector/raster conversion. The exact original Visual is retained
  at the first frame, but mapped circles and rectangles deliberately become
  sampled paths thereafter.
- SCENE-DQ's `pointwise-jacobian`, determinant, and orientation helpers use a
  centred finite difference; they are local numerical diagnostics, not
  symbolic differentiation. `inverse-map-mesh` only samples an explicitly
  supplied inverse. `complex-domain-coloring` is a semantic rectangular cell
  field rather than a continuous raster shader.
- SCENE-DW's `apply-homotopy` evaluates an author-supplied pure `H(p, alpha)`
  from the immutable clip-start source at every positive eased clip phase; it
  does not integrate from a preceding frame or interpolate to an endpoint map.
  Authors normally make `H(p, 0)` equal `p`; the exact original Visual remains
  at time zero. Adaptive subdivision is deterministic at each requested phase,
  but remains a sampled approximation and can use a different refinement tree
  at different phases. As with DQ, failed samples can split a path but there is
  no automatic branch-cut, topology-transition, or continuity analysis over
  the full time interval.
- SCENE-DA treats Racket complex values as world points. `complex-plane` is a
  conventional static Cartesian grid with Re/Im labels; `complex-domain-color`
  and `complex-domain-coloring` use argument for hue and optional modulus for
  brightness. `apply-complex-function` defaults to strict failures so an
  accidental non-complex result remains visible; select `#:discontinuities
  'split` to make an intentional pole/domain boundary split its paths.
- SCENE-DB provides static radial rings/rays and evenly sampled polar curves.
  `point->polar` uses `atan`'s interval `[-pi, pi]` and reports angle zero at
  the origin. `polar-graph` accepts signed radii for conventional rose curves,
  but does not adapt around discontinuities, detect self intersections, avoid
  label collisions, animate polar labels, or provide arc-length parameterizing.

### Streamlines and ODE flow

- SCENE-DC integrates autonomous two-dimensional fields with fixed-step RK4.
  `prepare-ode-trajectory` has explicit time range, step size, and checkpoint
  stride. The supplied field must be pure and stable for that trajectory's
  lifetime; a prepared particle's phase must remain inside its declared range.
  Its fixed-RK4 mode deliberately has no adaptive error tolerance, event
  detection, domain/boundary stopping, stiff solver, higher-dimensional state,
  or numerical-analysis diagnostics. A field error is reported rather than
  silently making a gap.
- SCENE-DN additionally accepts a three-argument time-dependent field and an
  `adaptive-rk45` solver with scalar terminal events. Its stored cubic dense
  output is deterministic after preparation, but it is not a stiff solver, has
  no higher-order dense-output polynomial, event priority/composition, event
  action/reset, simultaneous-root handling, automatic domain boundaries,
  adaptive streamline construction, tangent-arrow orientation, pulse effects,
  or tracer-cloud API yet. The reported embedded error is a solver diagnostic,
  not a formal global error bound. Fixed RK4 keeps the established exact
  checkpoint/remainder semantics; it deliberately does not accept events.
- `streamline` and `streamlines` are static sampled geometry. `flow-particle`
  consumes an immutable prepared trajectory. During `render-frames!`, the
  required positions are batched by checkpoint interval and frozen before worker
  frames begin, so workers do not call the author field. There are no
  automatically advected tracer clouds,
  animated streamline drawing, arrowheads/tangent orientation, collision
  handling, field-aware seeding, or flow-map/Jacobian analysis yet.

### Numeric displays

- SCENE-EF formats finite reals as integers, fixed decimals, scientific values,
  significant figures, or bounded-denominator rationals; Cartesian complex
  values format their real and imaginary components independently. Semantic
  units are upright Unicode factors and superscripts, not a dimension-analysis,
  locale, TeX-math, or SI-prefix system. Scientific notation deliberately uses
  plain `e+3` text for consistency with the ordinary text renderer.
- Rational formatting is a deterministic nearest fraction search bounded by
  `#:max-denominator`; it is a display approximation, not symbolic arithmetic.
  Complex formatting has no polar mode, branch-aware formatting, or automatic
  simplification of zero components.
- `parameter-display` reads a scalar scene parameter through a derived Visual.
  Its left/right/center/sign anchors use ordinary text anchors; `decimal`
  anchors two separately rendered text pieces at the decimal point. Integer
  parameter displays round a finite sampled value to the nearest integer.
- `rolling-number-display` is a derived vector digit wheel, not a stateful
  frame cache. It accepts nonnegative finite real values below its declared
  integer-slot limit and rolls during the final tenth of each digit interval.
  Digit width is a nominal monospaced advance rather than renderer-measured
  tabular-figure layout; it has no negative counters, arbitrary overflow,
  locale-aware separators, or arbitrary textual transitions.

### Live layout relationships

- SCENE-DE composes renderer-measured top-level attachment relationships only
  when their visual-ID dependency graph is acyclic. The public conveniences
  follow a centre/edge/corner anchor and can keep content above, below, left,
  or right of a target; chain cycles raise a deterministic error at rendering.
- It is not a general constraint solver: there is no collision avoidance,
  baseline alignment, inside-frame fitting, rotation inheritance, automatic
  reflow, nested layout attachments, or relative placement that survives as a
  separately targetable semantic child. A renderer-aware attachment still
  cannot be animated directly.

### Mathematical graphs and networks

- SCENE-DP adds deterministic spring, layered-DAG, partite, and planar
  outer-embedding layouts to the existing manual/circle/tree vocabulary. The
  spring algorithm is a fixed construction-time force iteration, not an
  interactive simulation; it has no pinned nodes, overlap removal, incremental
  relaxation, or graph-size-dependent adaptive budget. Layered layout requires
  an acyclic directed graph. Partite layout requires named vertex partitions.
  The current `planar` mode searches only a crossing-free circular outerplanar
  embedding (with an exhaustive search through eight vertices), so it rejects
  many planar non-outerplanar graphs rather than claiming an incorrect drawing.
- Parallel edges use cubic route lanes and self-loops use a fixed upward loop.
  Their labels follow analytic route midpoints and directed tips follow the
  final tangent, but they do not avoid vertices/labels, route around obstacles,
  choose side/loop orientation semantically, preserve a hand-authored curve
  through a topology change, or support general spline/orthogonal routing.
  A declared `#:weight` scales only the default cosmetic stroke; it is not a
  weighted shortest-path calculation or statistical visual encoding.
- `graph-bfs`, `graph-dfs`, and unweighted `graph-shortest-path` return stable
  vertex-name lists from author edge declarations. They create no animation,
  have no priority queue/weighted path support, and do not provide graph
  mutation, connectivity, flow, centrality, or automatic pedagogical timings.
- A graph is currently intended as a top-level semantic group. Its own affine
  motion, rotation, and scale are supported, but embedding a graph inside an
  arbitrary separate group cannot yet rewrite the internally stored endpoint
  paths. Animate its named vertex paths to rearrange it. Derived edge geometry
  requires endpoints to remain distinct at every sampled time.

- Renderer layout boxes are symmetric semantic boxes, not tight visible-ink
  bounds. SCENE-CC now provides all nine cardinal/corner anchors plus generic
  one-time placement/alignment, but there are still no live constraints,
  responsive reflow, automatic collision avoidance, or baseline alignment
  between separate Visuals.
- Ordinary formula assemblies typeset parts independently, so their positions
  and spacing remain explicit. `tagged-formula` typesets author-declared
  fragments together, but it is not a TeX parser: every fragment must be a
  contiguous valid TeX piece with visible ink.
- `formula-correspondence-auto` and `transform-matching-formula` match whole
  rendering-equivalent fragments in order. `glyph-tex` and
  `transform-matching-glyphs` additionally match exact dvisvgm glyph outlines
  in source order. Its opt-in `#:changed-mode 'morph` interpolates one painted,
  identically styled dvisvgm glyph path when all of its contours are positive-
  length, closed, and compatible in count and traversal direction. Contours are
  globally paired without reversal. Accents or glyphs using multiple painted
  paths, open geometry, incompatible contour topology, changed paint styles,
  and unsupported SVG geometry keep the moving cross-fade. Neither mode
  performs algebra or semantic name/token matching.
- SCENE-CR styles only whole, author-named formula parts. It does not parse TeX
  to find substrings, infer algebraic terms, create rich inline spans,
  cancellation marks, underbraces, gradients, or per-glyph semantic groups
  (except when an author explicitly uses `glyph-tex`). A fragment whose colour
  changes across a rewrite uses the established cross-fade fallback; use
  `fill-color-to` on `formula-select` for a deliberate in-place colour change.
- `formula-part-copy` can copy one whole named fragment to any number of
  explicitly named unmatched destinations, and formula parts can now follow
  circular or normalized custom paths. It still has no semantic algebra,
  automatic choice of pedagogically meaningful copies/routes, glyph-level
  grouping, or true TeX-outline morphing.
- `rewrite-formula` translates the full destination layout around one explicit
  named anchor and now accepts `#:stationary` matched fragments whose exact
  current transforms override that layout. It still cannot infer which parts
  should be fixed, preserve an arbitrary constraint relationship between
  several changing terms, or know algebraic operations such as cancellation or
  adding a term to both sides. SCENE-CF's `formula-derivation` sequences
  explicit rewrite steps, pauses, labels, and per-step stationary choices, but
  still does not validate algebra, parse TeX, select a pedagogical next step,
  or make the explanation labels reflow automatically.
- Tagged formulas need external `latex` and `dvisvgm` when they are constructed.
  `glyph-tex` exposes dvisvgm glyph leaves with positional names and supports
  per-glyph motion plus conservative closed-contour outline morphs, but it has
  no TeX/Unicode glyph map, semantic TeX parser, semantic grouping, arbitrary
  topology/counter morphing, or automatic choice of changed glyphs.

### Geometry and transforms

- SCENE-DK makes `apply-affine` and `apply-matrix` work for ordinary nested
  paths, including a child inside an already mapped group. The child remains a
  semantic Visual, so subsequent nested style and affine requests do not modify
  flattened pixels. A nested request is rebased through each enclosing affine
  map and therefore retains world-coordinate meaning. It cannot be applied
  through a singular enclosing affine map; general maps still conflict with
  ordinary move/rotation/scale requests for the same target in one overlapping
  clip.
- Core path geometry has line and cubic Bézier segments, but no quadratic Bézier
  or arc segment type. SVG quadratic commands are converted to cubics on import.
- A motion route is a clip-start snapshot. It does not deform with an animated
  route Visual in the same clip, and there is no exact cubic offsetting,
  offset-self-intersection cleanup, or curvature-aware banking.
- `move-along-path` deliberately requires one positive-length continuous
  subpath; it cannot traverse discontinuous multi-subpath geometry.
- `transform-from-copy` is a whole-Visual moving cross-fade, not a shape or
  glyph morph. Its source may be a top-level Visual or a child reached through
  built-in group/formula paths; its composed transform and opacity are frozen at
  clip compilation. Copies do not follow a simultaneously animated source or
  route, cannot start in a derived root, and still introduce only a new
  top-level destination.
- `transform-shape` replaces a top-level source with a fresh top-level
  destination. Circle/rectangle pairs now use a canonical cardinal perimeter
  correspondence, while other atomic path/circle/rectangle pairs retain the
  general geometry policy. Groups, images, text, formulas, SVG trees, and
  custom Visuals use the static-position cross-fade fallback. It has no
  semantic subobject pairing, shape-tree morphing, renderer-specific outline
  conversion, appearance-aware contour scoring, or animated fallback route.
  Explicit `#:mode 'morph` rejects an endpoint pair without one safe atomic
  outline correspondence.
- Path morphing has no semantic hole/topology inference, direct open-to-closed
  correspondence, appearance-aware matching, arbitrary per-pair scoring
  callbacks, or general global geometric optimisation beyond its current
  topology-class assignment and numeric additive pair penalties.
- `write-in` now follows each leaf by Bézier-curve order, which matches Manim's
  partial-VMobject reveal; `#:reveal 'arc-length` is an explicit constant-speed
  alternative. `#:reverse?` and `unwrite` reverse leaf/path traversal, but
  there is still no pen nib geometry or independent per-contour scheduling.
  Gradients, patterns, masks, filters, SVG text, and arbitrary custom renderer
  Visuals are not writable. Unsupported paint specifications become exact only
  at the endpoint rather than interpolating through the fill phase.

### Visuals, plots, and SVG

- Derived Visuals are read-only computed output and cannot be animated directly;
  animate their values or the ordinary Visuals they depend on instead.
  `attach-to` retains its pure derived-Visual centre-to-centre operation and now
  also supports live renderer-box target/self anchors. Renderer-aware attachments
  are top-level render-time wrappers, so they remain deterministic for one sampled
  state/camera/renderer combination without introducing derived-layout feedback
  cycles. They do not yet avoid other labels, inherit target rotation, support
  attachment chains, or provide a general constraint solver.
- SCENE-CN supplies deterministic live endpoints for new lines, segments,
  arrows, and finite rays. Existing `line`/`arrow` values remain static
  geometry, and dynamic endpoint definitions cannot yet be `create`d,
  `uncreate`d, grouped, chained, or used as another relationship's target.
- SCENE-ED extends angle, right-angle, brace, brace-label, and curved-arrow
  annotations with live endpoint descriptions. It deliberately does not infer
  that rays are perpendicular or tangent, route a curved arrow around an
  obstacle, prevent a dynamic label collision, or maintain a group of
  renderer-measured annotations as a target. The ordinary static `angle`,
  `right-angle`, and `curved-arrow` constructors remain the direct way to draw
  a fixed mark.
- SCENE-DX matches ordinary affine/opacity leaves below a replaced top-level
  root. Its automatic semantic fallback is deliberately conservative: it knows
  built-in paths, circles, and rectangles, but does not derive application
  meaning from arbitrary SVG/text/custom Visuals, preserve a repeated leaf
  through a structural split/merge, or route a match around another diagram
  element. Use `visual-match` for an intentional pairing or formula APIs for
  TeX/glyph semantics.
- SCENE-DZ's `change-speed` controls only the rate at which a request consumes
  its own local unit interval. It does not retime an entire previously-built
  scene, infer a duration from physical velocity, or coordinate multiple
  independently scheduled requests. `spring` may overshoot under direct use;
  ordinary scene playback clamps a progress value to its [0,1] endpoint range.
  A `derived-visual` can nevertheless rebuild ordinary annotations from sampled
  geometry, as the stage example does.
- SCENE-CP supplies axes-aware numeric snapshots for common calculus diagrams.
  Tangents use a symmetric finite difference rather than symbolic or automatic
  differentiation; areas require a finite function over one interval; Riemann
  rectangles have no adaptive error estimate or signed-area bookkeeping. The
  helpers do not infer pedagogical labels, choose an approximation method, or
  become live by themselves.
- SCENE-CQ adaptively subdivides using quarter, midpoint, and three-quarter
  chord-deviation tests and breaks visible opposite-side asymptotes or
  caller-excluded intervals. It does not prove continuity, locate a pole
  exactly, solve roots, use a pixel-space error tolerance, preserve an error
  bound after smooth interpolation, or detect a curve that aliases every probe
  in an initial interval. There are still no per-point style tables, error
  bars, or pixel-fixed marker sizes.
- `svg->visual` is intentionally structural and supports groups plus common
  geometric leaves with unitless translation transforms. Complex SVG transforms
  and renderer features should use `svg-image`, which preserves their appearance
  but does not expose their elements for individual animation.
- The dvisvgm adapter used by tagged-formula `write-in` expands path `<defs>`
  and local `<use>` references with matrix, translation, and scale transforms.
  It is deliberately not a general animated SVG renderer; author SVGs needing
  broad SVG fidelity still belong in `svg-image`.

### Cameras, overlays, and timelines

- Cameras have pan, zoom, fit, nested-path focus, and clip-scoped follow, but
  no rotation, animated pixel dimensions/background, persistent follow across
  clips, continuously recomputed fitting, asymmetric safe areas, automatic
  choice of explanatory context, or multiple simultaneous views. `camera-focus`
  is a clip-start snapshot and still requires the author to select the context
  that belongs in the explanation.
- World-space render boxes now have cardinal/corner layout anchors, and SCENE-CD
  callout leaders can follow nested-child paths through parent transforms.
  SCENE-CK additionally lets a leader select a live target-box edge or corner.
  Frame corner/edge anchors, automatic overlay collision avoidance, responsive
  overlay wrapping, curved or arrow-headed leaders, and frame-space wrappers
  inside ordinary world-space groups are still absent.
- `circumscribe` and `indicate` target nested Visual paths using a composed
  world-space render box. SCENE-CK remeasures that box from the sampled target,
  so the outline follows same-clip motion, rotation, scale, and formula shape
  changes. It still follows rendered boxes rather than visible glyph contours,
  and does not respond to camera/renderer changes in the same clip.
- Local `timed` scheduling and nested compositions apply to both Visual and
  camera requests. Separate `scene-play` clips still cannot overlap or be
  scheduled relative to one another.

### Outside the current scope

- Three-dimensional scenes and a browser editor are not provided.
- Formula source and preamble are trusted input; the optional TeX renderer is
  not sandboxed. The Scribble source is included but intentionally not registered
  with Racket's documentation system.



## SCENE-AX: dependency-driven derived geometry

Version `0.50.1` keeps the `0.50.0` public API and dependency semantics unchanged
and corrects moving plain-text rendering. The default text renderer freezes each
local text appearance to an alpha bitmap before scene placement and reuses a
bounded renderer-local cache across position-only motion and camera pan. This
keeps glyph pixels—and therefore apparent inter-letter spacing—stable while the
text moves. Appearance changes and camera zoom rerasterize at the new resolution.

Version `0.50.0` extends the read-only derived context with top-level Visual
dependencies:

```racket
(derived-visual
 (rectangle #:id 'label #:center origin #:width 2 #:height 1)
 (lambda (context template)
   (define anchor
     (derived-context-visual-ref context 'anchor))
   (visual-with-position
    template
    (vec2+ (visual-position anchor) (vec2 0 2)))))
```

`derived-context-visual-has?` tests top-level Visual presence without resolving
anything. `derived-context-visual-ref` returns the concrete resolved Visual for
that ID. Derived dependencies resolve recursively, may point forward or backward
in drawing order, and may combine freely with scalar dependencies.

Resolution detects self-cycles and multi-Visual cycles explicitly. One local
resolution traversal memoizes successfully resolved dependencies so a shared
dependency is consistent within that traversal; no concrete result is retained
in scene state or reused by a later sample.

Rendering, callouts, camera follow/fitting, and named path-source lookup continue
to use the same resolved scene-state operations, so they inherit dependency-graph
behavior automatically.

Render the canonical example with:

```sh
racket examples/dependency-driven-geometry.rkt \
  frames/dependency-driven-geometry \
  dependency-driven-geometry.mp4
```

Run the focused stage tests with:

```sh
raco test tests/scene-l-render-test.rkt \
  tests/scene-aw-test.rkt tests/scene-aw-render-test.rkt \
  tests/scene-ax-test.rkt tests/scene-ax-render-test.rkt \
  tests/scene-ax-text-raster-test.rkt tests/scene-ay-test.rkt \
  tests/scene-az-test.rkt tests/scene-ba-test.rkt tests/scene-bb-test.rkt \
  tests/scene-bc-test.rkt tests/scene-bd-bf-test.rkt tests/scene-bk-test.rkt \
  tests/scene-bm-test.rkt tests/scene-bl-test.rkt tests/scene-bn-test.rkt \
  tests/scene-bj-test.rkt tests/scene-bh-test.rkt tests/scene-bg-test.rkt \
  tests/scene-svg-render-test.rkt tests/scene-bo-bp-test.rkt \
  tests/scene-bq-br-test.rkt tests/scene-bs-test.rkt
```

## SCENE-BS: tagged full-formula layouts

Version `0.68.0` adds `formula-fragment`, `tagged-formula`, and
`transform-matching-formula`. A tagged formula uses one `latex` → `dvisvgm`
compilation to preserve TeX's complete layout, then isolates each declared
fragment as an SVG group. Exact unchanged fragments move as a single rigid
layer; changed or unmatched fragments retain the existing fade behavior.
Explicit `#:matches` take precedence before the remaining exact fragments are
automatically paired. Construction needs `latex` and `dvisvgm`; rendering the
finished scene does not rerun either program. The formula limitations backlog
above records the deliberately retained boundaries: author-declared fragments,
no semantic algebra/glyph matching, and no glyph-outline morph.

## SCENE-BT: animated vector write

Version `0.69.0` adds `write-in`, a generic two-phase vector introduction for
path Visuals and ordered path groups. Each leaf is first revealed by arc length
as a temporary outline; once complete, that outline transitions to the leaf's
final fill and stroke. The default stagger is `min(0.2, 4/N)` for `N` leaves.
Use `#:order 'left-to-right` when visual placement rather than SVG/document
order should control the sequence, or pass `#:lag-ratio` explicitly.

`svg->visual` circles and rectangles are normalised to temporary paths, and a
tagged formula expands dvisvgm's glyph path definitions and local `<use>`
instances only while `write-in` is compiled. The endpoint remains the original
semantic SVG tree or tagged formula, so its normal renderer is restored exactly
after the clip. Construction remains the only step that invokes TeX; rendering
or sampling a write animation never invokes it again.

## SCENE-BU: Manim-style write refinement

Version `0.70.0` makes `write-in` use Manim's equal-Bézier-curve partial reveal
by default, rather than measuring physical arc length. The former behavior is
still available through `#:reveal 'arc-length`. Staggered leaves now receive
clip and write rate functions after their own start offsets, so nonlinear
easing does not postpone later leaves. `#:reverse? #t` writes in reverse, and
`unwrite` removes an existing writable Visual by reversing both leaf order and
path traversal. The outline-to-fill phase and exact endpoint restoration remain
unchanged.

## SCENE-CI: source-package hygiene

Version `0.83.0` adds explicit source-package omission metadata. A
`raco pkg create --source` archive includes the Racket implementation, examples,
tests, README, and Scribble source while excluding generated MP4s, temporary
frames/experiments, compiled artifacts, and local Finder metadata. The Rhombus
examples remain present for reference, but `compile-omit-paths` keeps them out
of normal Racket compilation.

## SCENE-CH: explanatory camera focus

Version `0.82.0` adds `camera-focus`, a focused fit for an instructional
subject and the Visuals that explain it:

```racket
(scene-play scene
            (camera-focus scene
                          '(launch rocket-diagram rocket window)
                          #:context (list 'focus-note)
                          #:padding 1/2)
            #:duration 1)
```

The subject can be a top-level Visual, its identity, or a nested Visual path.
The optional `#:context` list accepts the same forms. Each selected child is
resolved with all enclosing transforms and opacity composed into world space
before renderer-aware box measurement. `camera-fit-scene` now supports nested
paths in `#:targets` as well. These requests remain snapshots of the scene's
current endpoint, so they frame the author-selected explanation cleanly but do
not independently track later motion or choose context automatically.

`examples/explanatory-camera-focus.rkt` moves from a rocket overview to its
nested window plus an explanatory card, then restores the overview.

## SCENE-CG: general shape transforms

Version `0.81.0` adds `transform-shape`, which replaces a present top-level
Visual by a fresh top-level destination:

```racket
(scene-play scene
            (transform-shape square disk)
            #:duration 1)
```

In the default `#:mode 'auto`, a path, circle, or rectangle on each side is
converted to a local path and given automatic topology-aware correspondence.
Circle/rectangle pairs first use SCENE-CJ's canonical eight-segment perimeter
at the right midpoint, cardinal points, and interleaved corners. This makes
square-to-circle morphs symmetric. Pass `#:correspondence 'perimeter` to
require that primitive policy or `#:correspondence 'path` to select the
general stored-path policy.
The intermediate outline moves with interpolated placement while source and
destination paint styles cross-fade. The exact destination Visual replaces the
source at completion. Composite, image, text, formula, SVG-tree, and custom
Visual endpoints do not pretend to have a single contour: they automatically
cross-fade instead. Use `#:mode 'morph` to require a geometric transition or
`#:mode 'cross-fade` to select the fallback explicitly.

`examples/general-shape-transform.rkt` shows a rectangle becoming a circle by
outline interpolation, followed by a composite diagram changing through the
safe cross-fade policy.

## SCENE-CF: structured formula derivations

Version `0.80.0` adds `formula-step` and `formula-derivation`. A step stores a
caller-selected formula endpoint, correspondence/mismatch choices, transition
duration, pre-transition pause, and optional one-line explanation. The builder
applies every step through `rewrite-formula`, so an anchor such as `equals` is
resolved from the actual previous scene endpoint instead of a stale template.

`examples/structured-formula-derivation.rkt` reduces `3x + 6 = 21` to `x = 5`.
Each author-selected algebraic step pauses with a concise explanation before its
formula transition begins.

The feature sequences explicit mathematics; it does not parse TeX, prove that a
rewrite is valid, select a pedagogical route, or infer explanations.

## SCENE-CY: general affine maps

Version `0.99.0` adds a full affine-map layer without changing the historical
`affine-transform` API. `linear2` stores the matrix

\[
\begin{pmatrix}a & b\\ c & d\end{pmatrix},
\]

in ordinary row order. `affine2` uses the corresponding augmented rows
`(affine2 a b h c d k)`, where `(h,k)` is the translation. `apply-affine`
applies an `affine2` after the target's existing map; `apply-matrix` is the
translation-free convenience form. Matrix entries and translation interpolate
directly from the identity map, which makes a shear continuous and also gives a
defined (possibly singular) intermediate path for a reflection.

```racket
(define shear
  (linear2 1 1
           0 1))

(scene-play
 (scene-add (make-scene) diagram)
 (apply-matrix 'diagram shear)
 #:duration 3)
```

The initial CY release mapped one complete top-level world Visual. SCENE-DK
extends that model to ordinary nested paths: map a diagram as a whole, then map
`'(diagram unit-square)` without flattening the diagram. The request is still
specified in world coordinates; internally it is rebased through the enclosing
maps before it is stored on the child. A singular enclosing affine map cannot
be rebased, and the decomposed `affine-transform` protocol remains available
for existing Visual implementations. See
`examples/semantic-nested-affine-transforms.rkt`.

For example, this maps the complete diagram first and subsequently reflects its
named square:

```racket
(define sheared
  (scene-play
   (scene-add (make-scene) diagram)
   (apply-matrix 'diagram (linear2 1 3/5
                                  0 1))
   #:duration 2))

(scene-play
 sheared
 (apply-matrix '(diagram unit-square) (linear2 -1 0
                                              0 1))
 #:duration 2)
```

## SCENE-DL: serializable rate functions

Named rate functions retain the ordinary callable easing interface while also
carrying transparent data. Use them wherever `#:easing` or `#:rate-func` takes a
one-argument procedure:

```racket
(scene-play
 scene
 (timed (move-to 'dot (vec2 4 0))
        #:duration 2
        #:easing (smooth #:inflection 10))
 #:duration 2)
```

`linear` remains the default callable value. The other initial constructors are
`smoothstep`, `rush-into`, `rush-from`, `there-and-back`, and
`there-and-back-with-pause`; SCENE-DZ additionally offers `cubic-bezier`,
`spring`, `reverse-rate`, `compose-rate`, `squish-rate`, and `change-speed`.
Built-in values appear as semantic data in a scene,
so `render-timeline-section!` can derive an automatic cache key; an arbitrary
lambda remains legal but deliberately bypasses automatic cache reuse. See
`examples/serializable-rate-functions.rkt`.

## SCENE-DY: General Boolean path geometry and clipping

Boolean operations work on immutable local `path-geometry` values, then the
result becomes a normal `path-visual` when it is time to render it. Every input
contour must be simple and closed, but may be concave; each operand may contain
multiple contours. Cubic segments are uniformly sampled into
`#:curve-samples` straight pieces (16 by default), so curve results are
deterministic polygonal approximations rather than exact Bézier intersections.

The default `#:fill-rule 'odd-even` exactly matches the fill rule used by the
path renderers: a nested inner contour makes a hole regardless of orientation.
Use `#:fill-rule 'nonzero` for conventional oriented compound paths; it accepts
nonintersecting contour boundaries and treats reversed inner loops as holes.
Boolean results reconstruct their exterior and hole loops, so a normal stroke
shows only the true boundary—not ear-clipping seams.

```racket
(define left
  (polygon-path
   (list (vec2 0 0) (vec2 4 0) (vec2 4 4) (vec2 0 4))))

(define right
  (polygon-path
   (list (vec2 2 0) (vec2 6 0) (vec2 6 4) (vec2 2 4))))

(define overlap (path-intersection left right))
(define left-only (cutout left right))

(make-path-visual overlap #:id 'overlap
                  #:fill "mediumpurple" #:stroke "indigo" #:stroke-width 3)
```

`path-union`, `path-difference`, and `path-xor` complete the set. With two
paths, `clip-to` and `mask-with` are readable intersection aliases. With an
affine Visual plus a local mask path, they instead return a `clipped-visual`
that clips the complete vector content at render time:

```racket
(clip-to (latex-formula "f(x)" #:id 'formula)
         viewport-path
         #:id 'cropped-formula)
```

The wrapper is itself an ordinary affine/opacity Visual, so moves, rotations,
and fades apply to its content and path together. See
`examples/general-boolean-clipping.rkt`.

Current limits: the default `odd-even` rule repairs proper self-crossings but
rejects touching or overlapping segments; `nonzero` rejects crossing contour
boundaries; and curved input is flattened rather than preserved as cubic
output.

## SCENE-EC: semantic vector paints

Fill styles can now be semantic paints rather than only solid colours. A paint
contains no `racket/draw` object or cached bitmap: it is ordinary immutable
scene data, so it survives scene sampling, nesting, clipping, and affine motion.
The built-in Pict renderer installs its native brush only while drawing the
shape.

```racket
(define warm-to-cool
  (linear-gradient
   (vec2 -2 0) (vec2 2 0)
   (list (paint-stop 0 "tomato")
         (paint-stop 1 "gold"))))

(define disk-glow
  (radial-gradient
   origin 1
   (list (paint-stop 0 "white")
         (paint-stop 1 "mediumpurple"))))

(define tiles
  (checker-pattern "aliceblue" "lightsteelblue" #:cell-size 1/4))

(scene-play
 (scene-add (make-scene)
            (rectangle #:id 'panel #:width 4 #:height 2
                       #:fill warm-to-cool #:stroke "navy"))
 (fill-color-to 'panel
                (linear-gradient
                 (vec2 0 -1) (vec2 0 1)
                 (list (paint-stop 0 "deepskyblue")
                       (paint-stop 1 "mediumpurple"))))
 #:duration 2)
```

Gradient points and radii use the receiving Visual's local coordinate system.
They therefore rotate, scale, and move with that Visual, including when the
Visual is wrapped by `clip-to` or `mask-with`. A `paint-stop` offset is in
`[0, 1]`; each gradient has at least two nondecreasing stops. A radial gradient
can also set `#:focal-center` and `#:focal-radius`.

Solid textual colours and `rgba-color` values remain paints, so existing fill
code needs no change. `paint-lerp` and `fill-color-to` interpolate only pairs
of the same kind: two solids, two linear gradients with the same number of
stops, two radial gradients with the same number of stops, or two checker
patterns. Exact endpoints remain the original objects. To change a solid into a
gradient (or otherwise change paint kinds), overlap the two Visuals and use the
existing fade/cross-fade composition deliberately.

Current limits: paints apply to fills only; strokes remain solid colours. The
default Pict renderer uses native vector gradients, but a checker tile is a
deterministic device-aligned stipple and does not yet follow an enclosing affine
transform. Formula, SVG, image, and custom renderers keep their own paint
semantics until they opt into the paint protocol. See
[`examples/semantic-paints.rkt`](examples/semantic-paints.rkt).

## SCENE-DN: adaptive and time-dependent ODE flow

The existing two-argument field form remains an autonomous field. A field that
accepts three arguments receives `(time x y)`, allowing non-autonomous systems.
Pass an `adaptive-rk45` solver to `prepare-ode-trajectory` to store accepted
Dormand–Prince endpoints and cubic dense-output data rather than fixed RK4
checkpoints. An `ode-event` is a scalar whose selected sign crossing terminates
the prepared range.

```racket
(define projectile-field
  (lambda (time x y)
    (vec2 1 (- 2 time))))

(define trajectory
  (prepare-ode-trajectory
   projectile-field origin
   #:time-range (cons 0 5)
   #:solver (adaptive-rk45 #:relative-tolerance 1e-8)
   #:event (ode-event (lambda (_time _x y) y)
                      #:direction 'decreasing
                      #:name 'ground-contact)))
```

The actual trajectory range ends at the dense event root. Its
`ode-trajectory-diagnostics` reports accepted/rejected steps, termination, and
the largest scaled embedded error. `flow-particle` accepts either prepared
trajectory kind and freezes its requested positions before render workers
start. See `examples/adaptive-ode-trajectory.rkt`.

## SCENE-DO: zoom and multi-view cameras

`camera-view` places a world-space target in a second, orthographic camera
canvas that is pinned in the output frame. It is useful for a close-up, a
simultaneous overview, or a stable explanatory inset while the main camera
pans and zooms.

```racket
(define inset
  (camera-view 'diagram
               #:id 'zoom
               #:camera (make-camera #:width 480
                                     #:height 270
                                     #:world-width 3
                                     #:center origin)
               #:frame-camera main-camera
               #:at (vec2 4 3/2)
               #:width 3))

(scene-add (make-scene #:camera main-camera) diagram inset)
```

The inset target is looked up after ordinary Scene sampling, then rendered
through its own camera. Thus, a marker moved with `(move-to '(diagram marker)
...)` appears in both views on the same frame. The inset itself is a normal
frame-space Visual: it may be moved, rotated, scaled, faded, or removed.
Direct `visual->pict` rendering deliberately rejects it because resolving its
live target requires a sampled Scene. See `examples/zoom-camera-inset.rkt`.

## SCENE-EE: animated secondary cameras

A `camera-view` may select one positional target, a nonempty `#:targets` list,
or—when neither is supplied—every top-level world-space layer in drawing order.
The latter is useful for an overview; frame-space labels, controls, callouts,
and other insets are deliberately excluded to prevent recursive views. Use
`#:clip 'rounded` for a rounded viewport border (the historical
`'rounded-frame` spelling is accepted as an alias).

```racket
(define detail
  (camera-view #:id 'detail
               #:targets '(terrain route rover)
               #:camera detail-camera
               #:frame-camera main-camera
               #:at (vec2 19/5 2)
               #:width 18/5
               #:clip 'rounded))

(define route-fit
  (camera-fit-visuals (list route beacon)
                      #:camera detail-camera
                      #:padding 1/2))

(scene-play scene
            (animation-group
             (move-along-path 'rover route-path)
             (camera-view-follow 'detail 'rover)
             (camera-view-zoom-by 'detail 2)
             (camera-view-pan-to 'overview (vec2 1/2 0)))
            #:duration 3
            #:easing (smooth))

(scene-play scene (camera-view-fit 'detail route-fit) #:duration 2)
```

The view camera is an immutable field of the frame-space Visual. A follow is
therefore evaluated after ordinary world motion at each requested sample; it
does not retain rendered frames or mutable integration history. Its target
keeps the same initial world-space offset inside the inset while the view may
zoom simultaneously. `camera-view-fit` consumes the existing snapshot returned
by `camera-fit-visuals`, `camera-fit-scene`, or `camera-fit-layout-box`; compute
that snapshot with the inset camera so its aspect ratio is correct. See
`examples/secondary-camera-views.rkt`.

## SCENE-EF: numeric animation II

Numeric values remain ordinary immutable scene parameters. `change-number-to`
accepts finite real or Cartesian-complex destinations, while `count-to` reads a
finite-real clip-start value and `count-from` declares both finite-real
endpoints explicitly.

```racket
(define counter (parameter 'counter 0))
(define speed (parameter 'speed 0))

(define display
  (rolling-number-display counter #:id 'counter-display
                          #:integer-digits 2 #:decimal-places 1))

(define speed-display
  (parameter-display speed #:id 'speed-display
                     #:kind 'scientific
                     #:unit (unit-product (unit "m")
                                          (unit "s" #:power -2))))

(scene-play
 (scene-add (scene-set-value (scene-set-value (make-scene) counter) speed)
            display speed-display)
 (animation-group (count-from counter 0 42.7)
                  (change-number-to speed 12700))
 #:duration 3)
```

`format-scientific`, `format-significant`, `format-rational`, and
`format-complex` also create deterministic strings for static labels. Rolling
wheels derive their current and next glyphs directly from the sampled number;
they do not retain a previous bitmap or mutable counter. See
`examples/numeric-animation-ii.rkt`.

## SCENE-DP: graph layouts and live curved edges

Graph construction gains four deterministic layout snapshots: `spring`,
`layered`, `partite`, and `planar`. A spring layout uses a fixed Jacobi force
iteration, layered layout requires an acyclic `digraph`, partite layout reads
each vertex's `#:partition`, and the initial planar layout searches for a
crossing-free outerplanar circular embedding. The returned graph remains the
same named group tree, so any named vertex can still be animated normally.

```racket
(define network
  (digraph
   (list (graph-vertex 'start)
         (graph-vertex 'state)
         (graph-vertex 'finish))
   (list (graph-edge 'start 'state #:id 'accept #:label "accept" #:weight 3/2)
         (graph-edge 'start 'state #:id 'reject #:label "reject")
         (graph-edge 'state 'state #:id 'retry)
         (graph-edge 'state 'finish #:id 'done))
   #:id 'network
   #:layout 'layered
   #:parallel-edge-separation 1/2))

(scene-play
 (scene-add (make-scene) network)
 (move-to (graph-vertex-path 'network 'state) (vec2 3/2 0))
 #:duration 2)
```

Multiple edges are automatically assigned distinct cubic lanes. A directed
loop has a tangent-aligned arrowhead, and edge labels sample the same curve as
their shaft. `#:weight` multiplies the default edge stroke width; an individual
edge can override its stroke, stroke width, or route curvature. The pure
`graph-bfs`, `graph-dfs`, and `graph-shortest-path` helpers return stable symbol
lists that an author can turn into explicit highlight timings. See
`examples/graph-layouts-and-curved-edges.rkt`.

## SCENE-DQ: robust pointwise maps

`apply-pointwise` now samples adaptively and can turn a failed point-map sample
into a visible path break. This is useful for curved complex maps and for
reciprocal functions with a pole. The requested map always has world-coordinate
meaning, even when its target is a named descendant of an ordinary transformed
group.

```racket
(scene-play
 (scene-add (make-scene) reciprocal)
 (apply-pointwise 'reciprocal
                  (lambda (p)
                    (define x (vec2-x p))
                    (if (zero? x)
                        (error 'reciprocal "pole")
                        (vec2 (/ 1 x) (vec2-y p))))
                  #:samples 1
                  #:tolerance 1/32
                  #:discontinuities 'split)
 #:duration 2)
```

`pointwise-jacobian`, `pointwise-jacobian-determinant`, and
`pointwise-orientation` inspect a map near one point. `inverse-map-mesh`
builds a mapped grid from an explicit inverse function. For complex diagrams,
`complex-domain-color` returns one semantic RGBA colour and
`complex-domain-coloring` creates an addressable cell field. See
`examples/robust-pointwise-maps.rkt`.

## SCENE-DS: mathematical animation effects

`flash` emits radial rays and `focus-on` expands a ring around a live rendered
target. `show-passing-flash` shows a moving arc-length interval of a path;
each of these effects removes its overlay at the clip endpoints. `wiggle` is a
reversible ordinary rotation succession. The three introduction forms below
preserve exact semantic endpoint Visuals:

```racket
(scene-play
 (make-scene)
 (grow-from-center dot)
 (grow-arrow velocity)
 (draw-border-then-fill region)
 #:duration 2)
```

See `examples/mathematical-effects.rkt`.

## SCENE-DT: probability and statistical diagrams

The statistical constructors return normal named groups. The path helpers make
their nested parts convenient animation targets:

```racket
(define scores
  (bar-chart '(3 7 5 4)
             #:id 'scores
             #:labels '("A" "B" "C" "D")))

(scene-play
 (scene-add (make-scene) scores)
 (flash (bar-chart-bar-path 'scores 2))
 #:duration 1)
```

`stacked-bar-chart`, `sample-space`, `probability-tree`, `box-plot`, and
`error-bars` use the same ordinary group model. `probability-branch` describes
the finite immutable input tree and `error-bar-point` describes a value with a
nonnegative symmetric error. See `examples/probability-and-statistics.rkt`.

## SCENE-DV: deterministic layout finishing

The new layout helpers use exactly the same renderer-aware measurements as the
existing placement functions, but solve common finishing operations directly:

```racket
(define cards
  (avoid-overlap
   (list card-a card-b card-c)
   #:direction 'right
   #:gap 1/4))

(define labels
  (align-baselines (list x-label plus-label y-label)))

(define in-frame
  (keep-inside-frame caption #:margin 1/4))
```

`distribute-within` gives an ordered list equally spaced reference positions on
one axis. All four helpers return new immutable Visual values; they never alter
the original Visuals or maintain constraints after construction. See
`examples/layout-finishing.rkt`.

## SCENE-DW: time-dependent homotopies

`apply-homotopy` is the direct time-dependent counterpart of
`apply-pointwise`. Instead of calculating a final map and blending each source
point toward it, it evaluates the supplied map at the current eased local phase:

```racket
(scene-play
 (scene-add (make-scene) grid)
 (apply-homotopy
  'grid
 (lambda (point alpha)
    (vec2 (+ (vec2-x point)
             (* alpha (sin (* 2 (vec2-y point)))))
          (vec2-y point))))
 #:duration 3
 #:easing (smooth))
```

At every frame, geometric source points are placed at `H(point, alpha)` from
the same immutable clip-start geometry. The result is therefore independent of
render order. `apply-complex-homotopy` applies the analogous two-argument
function to Racket complex values. Both forms inherit adaptive sampling,
split/error discontinuity policy, and nested world-space target support from
`apply-pointwise`. See `examples/time-dependent-homotopies.rkt`.

## SCENE-ED: live mathematical annotations

The annotation constructors parallel `line-between` when their geometry is
defined by moving points:

```racket
(define base
  (brace-label (anchor-of 'A 'bottom #:offset (vec2 0 -1/12))
               (anchor-of 'B 'bottom #:offset (vec2 0 -1/12))
               "base" #:id 'base #:offset -1/12))

(define mark (right-angle-between 'B 'A 'C #:id 'right-mark))
(define relation
  (curved-arrow-between (anchor-of 'C 'right) (anchor-of 'B 'top)
                        #:id 'relation #:angle -1))
```

With literal `vec2` endpoints these functions return the familiar fixed
path/group Visuals. A parameter or centre reference produces a normal pure
`derived-visual`; a non-centre `anchor-of` produces a top-level,
renderer-resolved definition. The latter is useful when an annotation must meet
the visible edge of a moving circle, formula, or other rendered Visual.
`examples/live-mathematical-annotations.rkt` demonstrates both modes.

## SCENE-DX: transform matching for diagrams

`transform-matching-visuals` replaces one ordinary root Visual by another while
using its named leaves as a correspondence tree:

```racket
(scene-play
 (scene-add (make-scene) before)
 (transform-matching-visuals
  before after
  #:matches (list (visual-match '(source-dot) '(result-dot))))
 #:duration 2)
```

The empty list in a `visual-match` denotes an atomic root; otherwise each list
is a path below `before` or `after`. Explicit pairs win. The automatic matching
then uses equal relative paths, exact built-in type/style, exact local shape,
and nearest remaining path/circle/rectangle geometry. Compatible shapes share
the existing normalized morph interior. Other matched leaves interpolate their
affine placement while cross-fading their content; unmatched leaves fade by
default, or use moving cross-fades under `#:mismatch-mode 'fade-transform`.
The exact destination tree is installed at the end. See
`examples/transform-matching-visuals.rkt`.

## SCENE-DZ: time reparameterization

Use a speed profile as the local `#:easing` of an existing `timed` request:

```racket
(define middle-fast
  (change-speed '((0 1/2) (1/3 3) (2/3 3) (1 1/2))))

(scene-play
 scene
 (timed (move-to 'dot (vec2 4 0))
        #:duration 4 #:easing middle-fast)
 #:duration 4)
```

Each pair is `(time speed)`, times must strictly increase from `0` to `1`, and
positive speeds are linearly interpolated before their integral is normalized
to animation progress. This means it composes cleanly with the existing local
scheduler and remains serializable for caches. `cubic-bezier`, `spring`,
`reverse-rate`, `compose-rate`, and `squish-rate` return the same kind of rate
value. See `examples/time-reparameterization.rkt`.

## SCENE-CZ: linear-algebra diagrams

Version `1.0.0` adds reusable ordinary group trees for the standard
linear-transformation picture. `number-plane` supplies named `grid`, `axes`,
and optional `labels` children. `basis-vectors` supplies `e1` and `e2` arrow
children, while `linear-transformation-diagram` combines a number plane, basis,
unit square, and arbitrary vector under stable paths such as
`'(diagram plane grid)` and `'(diagram basis e1)`.

```racket
(define diagram
  (linear-transformation-diagram #:id 'diagram
                                 #:vector-end (vec2 3 2)))

(scene-play
 (scene-add (make-scene) diagram)
 (apply-matrix 'diagram
               (linear2 1 1
                        0 1))
 #:duration 3)
```

`vector-arrow` is intentionally named to avoid shadowing Racket's base
`vector` constructor. `vector-coordinates` returns its endpoint minus start,
and `vector-label` creates a static endpoint label. See
`examples/affine-linear-transformations.rkt`.

## SCENE-CY-C: sampled pointwise maps

Version `1.3.0` adds `apply-pointwise`, a top-level world-space deformation
request. Each supported geometric leaf is sampled into a path and its samples
blend from their source positions to a caller-provided point-map result.
Sampling happens before mapping, so the square complex map bends a line into a
parabola rather than leaving it as a chord. The source Visual is exact at the
start of the clip; at later samples, semantic circles and rectangles have
become ordinary path geometry.

```racket
(scene-play
 (scene-add (make-scene) curve)
 (apply-pointwise 'curve
                  (lambda (p) (vec2 (vec2-x p) (* (vec2-y p) (vec2-y p)))))
 #:duration 2)
```

## SCENE-DA: complex planes and functions

`complex->point` and `point->complex` bridge ordinary Racket complex numbers
and world-space `vec2` values. `complex-plane` builds a labelled Cartesian
plane; `apply-complex-function` specializes `apply-pointwise` by presenting
each geometric sample as a complex value. For example,
`(apply-complex-function 'domain (lambda (z) (* z z)))` illustrates the
square map. The function result must have finite real and imaginary parts.

## SCENE-DB: polar coordinates and graphs

`polar->point` converts a radius and angle to a `vec2`; `point->polar` returns
a radius/angle reading. `polar-plane` builds ordinary named rings, rays, and
optional labels, while `polar-graph` samples `r(theta)` into a path. Signed
radii are accepted for graphing familiar roses. See
`examples/pointwise-complex-and-polar.rkt` for both a complex deformation and
a three-petal `r = 2 cos(3theta)` curve.

## SCENE-DC: deterministic streamlines

Version `1.1.0` adds fixed-step fourth-order Runge–Kutta integration for
autonomous two-dimensional fields. `ode-flow-position` computes one signed time
from the original seed. `prepare-ode-trajectory` stores immutable canonical
checkpoints over a declared time range, and `flow-particle` consumes that
trajectory. `render-frames!` freezes the actual frame positions before workers
begin, sharing full RK4 suffix steps inside each checkpoint interval. Rendering
order and worker count therefore do not change the numerical result.

```racket
(define rotation-field (lambda (x y) (vec2 (- y) x)))
(define phase (parameter 'time 0.0))
(define trajectory
  (prepare-ode-trajectory
   rotation-field (vec2 2 0)
   #:time-range (cons 0 (* 2 pi))
   #:step-size 1/10))

(flow-particle coordinate-axes trajectory phase
               #:id 'particle)
```

## SCENE-DD: numeric displays

Version `1.1.0` adds `integer`, `decimal-number`, `numeric-label`, and
`parameter-display`. Formatting has fixed decimal places, optional grouping,
explicit signs, and a trailing string unit. A dynamic display remains a pure
derived Visual: it samples a scalar scene parameter rather than maintaining a
mutable tracker. Its `#:anchor 'decimal` form holds the decimal point in place
as the whole part changes width; `'left`, `'right`, `'center`, and `'sign` are
also available.

`examples/streamlines-and-numeric-display.rkt` combines the DC and DD features:
the same phase controls an RK4 particle moving through a rotational field and a
fixed-decimal time display.

## SCENE-DE: acyclic live layout

Version `1.2.0` makes renderer-measured attachments composable. Use
`follow-anchor` for explicit anchor relationships or `keep-above`,
`keep-below`, `keep-left-of`, and `keep-right-of` for common gaps. A target may
itself be a live attachment; the renderer resolves the finite dependency chain
from its concrete target outward and reports a cycle instead of using stale
frame state.

## SCENE-DF: measured matrices and tables

Version `1.2.0` retains CT’s addressable rows and cells while allowing
`#:entry-width`/`#:entry-height` and `#:cell-width`/`#:cell-height` to be a
scalar, an explicit axis-size list, or `'auto`. The auto form measures the
existing entries once and allocates each column/row its maximum ink-box extent
plus `#:entry-padding` or `#:cell-padding`.

`examples/live-layout-and-smart-tables.rkt` demonstrates both stages: two
labels follow a scaled/moving card through a live chain, and a table snapshots
unequal text-driven column widths.

## SCENE-CX: mathematical graphs and networks

Version `0.98.0` adds graph diagrams without introducing mutable updater
objects. A graph is a normal immutable group tree; the important public paths
are stable and work with existing `move-to`, `indicate`, copy, attachment, and
style operations:

```racket
(define network
  (digraph
   (list (graph-vertex 'A #:position (vec2 -2 0) #:label "A")
         (graph-vertex 'B #:position (vec2 2 0) #:label "B"))
   (list (graph-edge 'A 'B #:label "f"))
   #:id 'network))

(scene-play
 (scene-add (make-scene) network)
 (move-to (graph-vertex-path 'network 'B) (vec2 2 2))
 #:duration 2)
```

The graph contains `vertices` and `edges` subgroups. The concrete arrow at
`'(network edges A->B line)` is a derived child that queries the sampled world
positions of `'(network vertices A)` and `'(network vertices B)`, then returns
local geometry for the graph group to render. This preserves arbitrary-time
sampling: no edge remembers any prior frame. `graph` creates plain lines;
`digraph` uses arrowheads in the declared source-to-target order. Circle and
rooted-tree layouts calculate initial positions deterministically from declared
vertex/edge order. SCENE-DP adds spring, layered, partite, and outerplanar
layout snapshots, together with live curved parallel edges and loops. See
`examples/graphs-and-networks.rkt` and
`examples/graph-layouts-and-curved-edges.rkt`.

## SCENE-CW: video-authoring workflow

Version `0.97.0` separates production metadata from the immutable scene model.
An authored timeline decorates an ordinary scene with named half-open sections,
cues, and intended audio placements:

```racket
(define timeline
  (make-authored-timeline
   scene
   #:sections (list (section 'opening 0 2)
                    (section 'derivation 2 6))
   #:cues (list (cue 'begin-derivation 2))
   #:audio-cues (list (audio-cue "narration.wav" #:start 0))))
```

`timeline-section-frame-indices` selects the same global output samples that a
complete scene render would use. `render-timeline-section!` writes precisely
those samples with fresh local names, so the result starts at
`frame-000000.png` and can be passed straight to `encode-mp4!`:

```racket
(render-timeline-section!
 timeline 'derivation "tmp/derivation-frames"
 #:fps 30 #:workers 4 #:cache-key 'derivation-v1)
(encode-mp4! "tmp/derivation-frames" "derivation.mp4" #:fps 30)
```

`authored-timeline-metadata` exposes portable section/cue/audio records. See
`examples/authoring-sections.rkt`.

## SCENE-DG/DH: media assembly and incremental movie output

Version `1.4.0` finishes the first production path on top of the immutable
timeline. Audio remains declarative until the final FFmpeg step, but it now has
actual semantics: source trimming, timeline delay, linear gain, and optional
fade-in/fade-out. Captions are ordinary timed strings and can be written as SRT
or WebVTT.

```racket
(define production
  (make-authored-timeline
   scene
   #:sections (list (section 'opening 0 2)
                    (section 'proof 2 6))
   #:audio-cues
   (list (audio-cue "narration.wav" #:start 0 #:source-start 1
                    #:duration 6 #:gain 3/4
                    #:fade-in 1/5 #:fade-out 1/2))
   #:subtitles
   (list (subtitle 0 2 "We begin with the construction.")
         (subtitle 2 6 "Now follow the proof."))))

;; Renders only invalidated sections below tmp/production, encodes each local
;; frame sequence, joins the visual streams, then adds AAC narration and SRT.
(render-authored-mp4! production "tmp/production" "production.mp4"
                       #:fps 30 #:workers 4
                       #:asset-files (list "diagram.svg"))
```

The default `'auto` section key fingerprints the serializable scene data,
section bounds, output settings, runtime, and declared asset bytes. If the
scene contains any procedure other than the built-in `linear` easing, automatic
reuse is disabled rather than risking a stale render. `render-authored-mp4!` therefore requires contiguous named
sections covering the whole scene; it produces visual-only partial MP4s, uses
FFmpeg's concat demuxer to join them, and applies audio/captions only once to
the final stream. Lower-level `assemble-authored-mp4!`,
`mux-authored-video!`, `write-subtitles!`, and `concatenate-mp4!` remain
available when a production needs a different layout. See
`examples/authored-media-assembly.rkt` for a visual explanation of the partial
movie workflow, and `examples/authoring-sections.rkt` for the underlying
timeline model.

## SCENE-DJ: expanded mathematical shapes

Version `1.5.0` adds a practical family of path-backed diagram primitives. The
closed shapes all carry their ordinary path identity, transform, opacity, fill,
and stroke, so they can be styled, created, or morphed by the existing API.
`annulus` uses the Pict path renderer’s odd-even fill rule, preserving its open
centre; `rounded-rectangle` is four straight sides joined by cubic quarter
arcs; and `arc-between-points` is a directed circular sweep selected by a
signed angle.

```racket
(define domain
  (annulus #:id 'domain #:center (vec2 -2 0)
           #:inner-radius 1/2 #:outer-radius 3/2
           #:fill "palegreen" #:stroke "forestgreen"))
(define image
  (star #:id 'image #:center (vec2 2 0)
        #:points 5 #:outer-radius 3/2 #:inner-radius 3/5
        #:fill "gold" #:stroke "saddlebrown"))
(define map-arrow
  (curved-arrow (vec2 -1/2 0) (vec2 1/2 0)
                #:id 'map #:angle (- (/ pi 2)) #:stroke "navy"))
```

`curved-arrow` returns a normal group with `shaft` and `tip` children;
`labeled-point` similarly has `dot` and `label` children. `double-arrow` is
the ordinary arrow primitive with both endpoint tips enabled. Every constructor
is exact scene data rather than a renderer-specific Pict. See
`examples/shape-catalogue.rkt`.

## SCENE-CV: composable camera motion

Version `0.96.0` gives camera requests the same local scheduler as Visual
requests. A camera leaf can be delayed, sequenced, or grouped without creating
extra clips:

```racket
(scene-play
 scene
 (succession
  (camera-pan-to (vec2 -4 0))
  (animation-group
   (camera-follow marker)
   (camera-zoom-by 2)))
 #:duration 4)
```

The first pan occupies the first half of the clip. In the second half, follow
updates the camera center from the sampled `marker`, while zoom independently
updates visible world width. `timed` applies literal local seconds at the
top-level and the established scaled spans inside a composition. A later camera
request is compiled from the exact view at its local start, so touching relative
operations such as `camera-zoom-by` chain from the prior endpoint.

The camera has two conflict components: `center` and `world-width`. Overlapping
requests must write disjoint components. Thus pan/follow plus zoom is legal,
but two simultaneous pans or a fit plus zoom is rejected. A timed follow holds
the view calculated at its own endpoint rather than tracking a target's later
motion. See `examples/composable-camera-movements.rkt`.

## SCENE-CU: deterministic traced paths

Version `0.95.0` makes a locus a pure derived Visual driven by an explicit
animated scalar parameter:

```racket
(define phase (parameter 'phase 0))
(define locus
  (traced-path phase
               (lambda (_context t) (vec2 (- t (sin t)) (- 1 (cos t))))
               #:id 'cycloid #:sample-count 181))
```

At every sampled frame, `traced-path` resamples the interval from
`#:start-time` to the current `phase`, so its result is independent of which
other frames were rendered first. Set `#:trail-length` for a deterministic
sliding interval; `#:dissipate?` expresses its age gradient as ordinary faded
path segments. `examples/traced-cycloid.rkt` shows the construction.

## SCENE-CT: matrices and tables

Version `0.94.0` adds regular matrices and tables without creating a separate
animation hierarchy. Both constructors return ordinary immutable groups, with
each row and cell available by a stable nested path:

```racket
(define A
  (matrix (list (list a11 a12)
                (list a21 a22))
          #:id 'A
          #:entry-width 3/4
          #:entry-height 3/4))

(matrix-entry-path 'A 1 2) ; => '(A row-1 col-2)
(table-cell-path 'results 2 3) ; => '(results row-2 col-3)
```

The entry Visuals are re-based at their cell centres, retaining their identity,
rotation, scale, appearance, and children. This makes the cell group itself a
convenient target for `indicate`, `circumscribe`, `move-to`, `attach-to`, or a
source for `transform-from-copy`. Matrix square brackets are named
`left-bracket` and `right-bracket`; a table also exposes its shared grid-line
paths. Separate row branches may reuse a local `col-N` identity because their
complete paths are distinct.

`examples/matrices-and-tables.rkt` selects a matrix row and vector entry, then
uses the normal copy animation to introduce the product alongside a compact
calculation table.

## SCENE-CS: multiline and rich text

Version `0.93.0` adds immutable paragraph layout and styled inline runs:

```racket
(rich-text
 #:id 'instruction
 #:width 4
 #:line-spacing 6/5
 (text-span "Step 1\n" #:font-weight 'bold #:color "navy")
 "Subtract "
 (text-span "3" #:font-weight 'bold #:color "firebrick")
 " from both sides.")
```

`paragraph` accepts one ordinary string; explicit `\n`, `\r`, and `\r\n`
break lines, while `#:width` wraps at word boundaries based on the active
renderer's actual font metrics. `#:line-alignment` controls the left, centre,
or right placement of each resulting line, independent of the Visual's outer
`#:horizontal-alignment` anchor. `#:vertical-alignment 'baseline` anchors the
first line's baseline, making a paragraph usable beside a formula or label.

`rich-text` accepts ordinary strings and `text-span` values. Each span can
override the surrounding font size, face/family, style, weight, and colour; an
unspecified property inherits the outer text style. The layout is still one
immutable `text-visual`, so it can move, fade, rotate, scale, participate in
renderer-aware layout, and use the usual cached text rendering path.

`examples/multiline-rich-text.rkt` places a styled, wrapped explanation beside
the real algebraic step `2x + 3 = 7` to `2x = 7 - 3`.

## SCENE-CR: semantic formula styling

Version `0.92.0` adds immutable styling operations for named formula parts:

```racket
(define styled
  (formula-color-map
   formula
   (hash 'unknown "royalblue"
         'constant "firebrick")))

(formula-select styled 'constant) ; => '(equation constant)
```

`formula-style` accepts one name or a nonempty list of names and can set a
colour, opacity, or both. `formula-color` is its colour-only shorthand. The
returned assembly preserves its identity, part order, TeX/SVG artifact, and
ordinary transform/opacity behaviour, so existing nested effects and matching
formula rewrites continue to apply. Tagged constructors also accept a
construction-time `#:color-map`.

Styled tagged fragments retain their actual SVG crop and are recoloured by the
SVG adapter rather than by an unreliable outer Pict colour wrapper. Equal paint
styles therefore move as one matching fragment. A changed paint participates in
the existing formula fade/cross-fade policy; animate it explicitly with
`fill-color-to` when an in-place colour transition is desired.

`examples/formula-styling.rkt` shows the real algebraic step
`2x + 3 = 7` to `2x = 7 - 3`: the named unknown, constant, and result retain
their colours while the equals sign stays fixed.

## SCENE-CQ: adaptive plotting

Version `0.91.0` adds `sample-adaptive-function-path` and
`adaptive-function-graph`. They begin with a deterministic initial grid and
recursively split intervals whose quarter, midpoint, or three-quarter sample
differs from the matching position of the chord. The path is still ordinary
axes-local geometry, so clipping, smooth interpolation, styling, and every
usual path animation continue to work.

```racket
(adaptive-function-graph axes-value tan
                         #:id 'tangent
                         #:initial-sample-count 17
                         #:max-deviation 1/100
                         #:max-depth 12)
```

The sampler preserves a gap for an exact division-by-zero evaluation, detects
the visible signature of a vertical asymptote by default, and accepts merged
`#:excluded-intervals` when the gap is author-known. The stage example compares
the separated branches of `1/x` with an adaptively refined `sin(30x)` curve.

## SCENE-CP: coordinate and calculus helpers

Version `0.90.0` adds static axes-aware diagram builders:

```racket
(secant-slope-group axes-value parabola 1 h #:id 'secant)
(tangent-line axes-value parabola 1 #:id 'tangent)
(riemann-rectangles axes-value parabola #:id 'rectangles #:count 8)
```

`graph-point`, graph labels and projection lines use the same linear/log axes
conversion as graphs. Areas and Riemann rectangles create ordinary closed path
geometry. `examples/secant-to-tangent.rkt` rebuilds `secant-slope-group` inside
a `derived-visual`, demonstrating the intended functional way to animate a
numeric construction.

## SCENE-CO: mathematical annotation geometry

Version `0.89.0` adds common explanatory marks as ordinary semantic paths:

```racket
(angle A C B #:id 'angle-mark #:radius 1/2)
(right-angle B A C #:id 'right-mark #:size 2/5)
(brace-label A B "base" #:id 'base-brace #:offset -1/2)
(surrounding-rectangle '(annotations angle-mark) #:id 'outline)
```

`arc` uses cubic Bézier segments with exact cardinal endpoints; `dashed-path`
selects arc-length pieces without flattening curves. `brace` is an open stroked
curve with a narrow unfilled centre cusp, matching Manim's visual convention.
`angle`, `right-angle`, `brace-between`, and `brace-label` are ordinary
path/group Visuals.
`surrounding-rectangle` alone needs renderer measurement, so it tracks a
top-level or nested target's current rendered bounding box with world-space
padding. It remains a top-level render-time definition to avoid layout cycles.

`examples/mathematical-annotations.rkt` uses a `derived-visual` to rebuild a
right triangle's marks from moving vertex positions, while a surrounding
rectangle follows its nested angle arc.

## SCENE-CN: dynamic endpoint geometry

Version `0.88.0` adds a small declarative vocabulary for geometry that stays
connected as its sources move:

```racket
(arrow-between 'A B #:id 'edge)
(line-between (anchor-of 'card 'right) (vec2 4 0) #:id 'leader)
(ray-from origin (vec2 3 4) #:length 2 #:id 'ray)
```

An endpoint may be a literal `vec2`, a point-valued `parameter` handle, a
top-level/nested Visual path, or `anchor-of` a Visual's selected rendered-box
anchor. Plain Visual references select the semantic center; a non-center
`anchor-of` is measured after scene sampling with the active Pict renderers.
The first three kinds return a pure `derived-visual`; the latter returns a
top-level renderer-aware definition. Both are deterministic at arbitrary sample
times. A finite `ray-from` starts at its first endpoint and points through the
second endpoint with the specified visible length.

`examples/dynamic-endpoint-geometry.rkt` moves three triangle vertices while
its sides and a corner-anchored arrow remain connected.

## SCENE-CM: live anchor constraints

Version `0.87.0` extends `attach-to` beyond SCENE-CD's renderer-independent
reference-point following. Supplying a non-center `#:target-anchor` or
`#:self-anchor` creates a top-level renderer-aware attachment:

```racket
(attach-to label 'card
           #:target-anchor 'top-right
           #:self-anchor 'bottom-left
           #:offset (vec2 1/5 1/5))
```

At every render, the sampled target is measured with the active camera and
Pict renderers. The selected anchor of `label` is then placed at the selected
anchor of `card`, plus the world-space offset. This makes labels and badges
follow target motion, scale, rotation, and layout changes without mutable
updaters. To avoid a layout feedback loop, renderer-aware attachments are
top-level only and cannot themselves be the target.

`examples/live-anchor-constraints.rkt` demonstrates a label following a card's
live upper-right corner through movement, scaling, and rotation.

## SCENE-CJ: shape-aware perimeter morphs

Version `0.84.0` refines `transform-shape` for circle/rectangle endpoints. The
automatic primitive policy creates paired eight-segment perimeters
beginning at the right midpoint. Their cardinal and diagonal positions match,
so a square's corners round uniformly while preserving exact endpoint Visuals.

`examples/perimeter-shape-morph.rkt` is the canonical square-to-circle example.

## SCENE-CK: live attention and callout anchors

Version `0.85.0` remeasures `circumscribe` and `indicate` from the sampled
target after ordinary components in their play clip. Attention therefore
follows target motion, rotation, scaling, and formula rewrites. `callout` gains
`#:target-anchor`, selecting `center` by default or any of the standard eight
edges/corners from the target's live rendered box.

`examples/live-attention-follow.rkt` moves and scales a card while both an
outline and a right-edge callout leader follow it.

## SCENE-CL: stationary formula derivations

Version `0.86.0` adds `#:stationary` to `rewrite-formula` and `formula-step`.
Each entry is a same-name symbol or explicit `formula-part-match`; it is made a
required correspondence and the destination fragment keeps its current source
transform. This supplements, rather than replaces, the one whole-layout anchor.

`examples/stationary-formula-derivation.rkt` keeps `2x`, `=`, and `5` still
while turning `2x + 1 = 5` into `2x = 5 - 1`.

## SCENE-CE: nested attention

Version `0.79.0` extends `circumscribe` and `indicate` from top-level Visuals
to an explicit nested group/formula path. When the play clip compiles, Animate
resolves the selected child with every enclosing transform and opacity composed,
measures its ordinary rendered box, and installs a temporary top-level outline
at that world-space box. The target itself is never mutated.

`examples/nested-attention.rkt` circumscribes and then pulses the `window`
inside an imported, rotated rocket SVG through the path
`(launch rocket-diagram rocket window)`.

SCENE-CK later made the outline live-follow a moving, rotating, scaling, or
rewritten target within the same clip. It still fits the renderer box rather
than visible glyph contours.

## SCENE-CD: live nested attachments

Version `0.78.0` adds `attach-to`, a small declarative way to keep ordinary
world-space content at a target's sampled reference point plus a fixed offset:

```racket
(attach-to badge '(rocket-diagram rocket window))
```

Nested dependencies now compose every enclosing group or formula transform
before a derived Visual reads their reference positions. This makes an attached
badge follow an SVG child as its parent moves, rotates, or scales. The existing
frame-space `callout` accepts the same explicit path, so its leader line follows
the child while the label itself remains fixed to the output frame.

`examples/nested-live-attachments.rkt` moves and rotates an imported rocket;
both its gold window badge and its callout leader remain attached to the nested
`(launch rocket-diagram rocket window)` path.

## SCENE-CC: named layout anchors

Version `0.77.0` adds one canonical nine-point vocabulary to the existing
renderer-aware layout system: the four corners, the four cardinal edges, and
the center. `layout-box-anchor` queries a measured box; `visual-layout-anchor`
queries a Visual; `visual-place-at` moves a selected Visual anchor to a point;
and `visual-align-to` aligns independently selected anchors of two Visuals.

The layout calculation deliberately remains immutable and one-time. It measures
the complete rendered Pict boxes using the supplied camera and renderer list,
including renderer padding and cosmetic strokes. It therefore supports text,
formula, SVG, group, and custom-renderer Visuals, but it does not watch later
motion or reflow a scene automatically.

`examples/named-layout-anchors.rkt` renders the nine points around one panel and
uses the API to attach its captions without manually deriving their text bounds.

## SCENE-CB: nested TransformFromCopy sources

Version `0.76.0` lets `transform-from-copy` take a nested Visual path through
built-in groups or formula assemblies. At clip compilation, Animate resolves
the selected child to its full world transform and inherited opacity, freezes
that snapshot as the source of the temporary overlay, and leaves the original
child in its ordinary group. The destination remains a new top-level Visual at
the exact endpoint.

`examples/nested-transform-from-copy.rkt` imports a rocket SVG and copies its
`window` subpart through the path `(rocket-diagram rocket window)` to an
independent enlarged window. This is useful for decomposing a diagram while
retaining the source object as context.

The source must remain non-derived and support affine placement and opacity.
Copies remain whole-Visual moving cross-fades frozen at clip start; they do not
track simultaneous source/route animation, morph a selected path, or install a
nested destination.

## SCENE-CA: compound glyph outline morphing

Version `0.75.0` extends `transform-matching-glyphs` with the existing opt-in
`#:changed-mode 'morph` to one identically painted dvisvgm glyph path composed
of compatible positive-length closed contours. Its destination contours are
globally paired with the source contours and phase-aligned without reversal,
then normalized to compatible cubic segments. This preserves the ordinary
outer/counter structure through interior frames while exact tagged SVG
fragments remain the endpoints.

The scope remains intentionally conservative. Multiple independently painted
paths, open geometry, a different number of contours, changed paint, and
unsupported SVG geometry retain SCENE-BY's moving cross-fade.
`examples/compound-glyph-outline-morph.rkt` renders the algebraic step
`-x \leq 3` to `x \geq -3`: the terms and minus sign move, while the
multi-contour relation glyph morphs.

## SCENE-BZ: conservative glyph outline morphing

Version `0.74.0` adds `#:changed-mode 'morph` to
`transform-matching-glyphs`. It is intentionally opt-in and applies only to a
declared changed glyph whose cropped dvisvgm SVG expands to one closed path on
both sides with identical fill, stroke, and stroke width. The destination is
phase-aligned without reversing its winding, then both contours are normalized
to compatible cubic segments and interpolated only during interior frames.
The ordinary tagged SVG fragments remain the exact start and end frames.

Everything outside that safe subset keeps SCENE-BY's moving cross-fade. This
avoids corrupting holes in letters, multi-piece accents/relations, or glyphs
whose paint style changes. `examples/glyph-outline-morph.rkt` renders the
valid algebraic step `a + b = c` to `a - b = c - 2b`, where the explicitly
matched binary `+` morphs into `-` while `2b` fades in.

## SCENE-BY: automatic glyph-level formula matching

Version `0.73.0` adds `glyph-tex` and `transform-matching-glyphs`. `glyph-tex`
uses one `latex` → `dvisvgm` compilation for a complete expression, then makes
each visible dvisvgm glyph leaf an individually movable `glyph-N` formula part.
Its automatic correspondence compares the stable SVG path outline rather than
dvisvgm's per-compilation font-definition names, so unchanged glyphs match
across independently compiled equations.

This is deliberately a renderer-level facility, not a TeX parser. A superscript
or accented character can consist of several leaves, repeated outlines match
greedily, and changed outlines cross-fade by default. The opt-in SCENE-BZ mode
initially supported the deliberately conservative one-contour subset; SCENE-CA
extends it to compatible compound closed contours. Use explicit
`formula-fragment` or `math-tex` groups whenever a semantic mathematical term
needs one stable identity. `examples/glyph-level-formula-matching.rkt` shows
`x + 3 = 7` changing to `x = 7 - 3` with `=` anchored and only `+` → `-`
declared explicitly.

## SCENE-BX: anchored formula rewrites

Version `0.72.0` adds `rewrite-formula`, the concise form for staged formula
changes with a fixed reference term:

```racket
(scene-play scene
            (rewrite-formula before after #:anchor 'equals)
            #:duration 1)
```

`#:anchor` accepts one shared part name or an explicit `formula-part-match`
when the names differ. The target layout is translated at clip compilation from
the current source formula, so a sequence may safely use independently
constructed TeX templates while retaining one fixed `=`. It preserves the
target's TeX layout as a rigid whole; it intentionally does not infer an
algebraic operation or choose other stationary terms.

`examples/solving-linear-equation.rkt` is the canonical staged example. It
solves `2x + 1 = 5` to `x = 2` without manual position-adjustment helpers.

## SCENE-BW: copies, attention, and flexible formula routes

Version `0.71.0` adds `transform-from-copy`, `circumscribe`, and `indicate`.
Copies are transient interior overlays: the source remains at its original
endpoint, the destination is absent at progress zero, and the exact destination
Visual is installed only when the clip completes. Attention effects use the
normal Pict renderer to measure the selected target, then add a temporary rounded
outline without modifying the target itself.

Formula transitions gain `formula-part-copy` through `#:copies`, allowing one
matched source fragment to populate several otherwise-unmatched destinations.
They also accept `formula-relative-path`, a route in unit-chord coordinates,
alongside the existing `formula-arc`. This makes deliberate curved term motion
possible while preserving formula correspondence's explicit, whole-fragment
model. SCENE-CB later extends the general copy source to nested Visual paths.
The limitations backlog records the remaining boundaries: no live-tracked
attention outlines, no algebraic inference, and no general glyph-outline
morphing.

The complete demonstration is:

```sh
racket examples/copying-and-emphasizing-formula-parts.rkt \
  frames/copying-and-emphasizing-formula-parts \
  copying-and-emphasizing-formula-parts.mp4
```

## SCENE-BQ/BR: concurrent output and diagnostics

Version `0.67.0` adds a bounded `#:workers` pool to `render-frames!`. On Racket
8.18 or later, workers build independent bitmaps in a parallel thread pool,
while one ordinary thread performs PNG encoding. Racket 8.12 keeps the
compatible coroutine-thread implementation. Each worker owns distinct frame
filenames; returned paths and per-frame metrics remain in frame-index order.
`render-frames/report!` returns a
`render-diagnostics` value with elapsed time, worker count, per-frame durations,
and built-in cache hit/miss/eviction deltas. The default is one worker. Custom
renderers used with more than one worker must be safe for concurrent calls.

## SCENE-BO/BP: renderer resources and full-fidelity SVGs

Version `0.66.0` unifies image, plain-text, and formula appearance caching
behind a bounded, thread-safe renderer-resource cache. Resource caches live only
at the rendering boundary: they never change immutable scene values or timeline
sampling. Plain text and image cache behavior is preserved, while repeated
formula appearances now avoid redundant typesetting.

It also adds `svg-image`, powered by the catalog `svg` package. This renders
static SVG documents with the renderer's extensive support for transforms,
gradients, clipping, masks, text, images, and CSS. Supply explicit world
dimensions; the Visual otherwise has the same affine and opacity behavior as
`image`. Use it for rendering fidelity, and retain `svg->visual` for semantic,
per-element animation.

## SCENE-BG/BI: semantic SVG import and subpart identities

Version `0.65.0` adds `svg->visual`. It reads a practical SVG subset as nested
semantic paths, circles, rectangles, and ellipses; `<g>` nodes become groups.
SVG `id` attributes become stable nested Visual paths, enabling normal lookup,
styling, animation, and morphing. Unitless `translate` transforms and basic
fill/stroke/opacity styles are supported; complex transforms should be flattened
before importing.

## SCENE-BH: bitmap image Visuals

Version `0.64.0` adds `image`, an immutable bitmap source Visual with explicit
world width and height. Images take part in standard affine movement, scaling,
rotation, opacity animation, groups, layout, camera placement, and frame
rendering. The default renderer lazily loads the source and keeps a bounded
renderer-local bitmap cache.

## SCENE-BJ: logarithmic axes

Version `0.63.0` adds `'log` x/y scales and configurable log bases to `axes`.
Logarithmic ranges must be strictly positive; the existing `'linear` scales keep
their zero-containing-range invariant. Coordinate conversion, function sampling,
vector grids, implicit-curve sampling, ticks, grids, and labels use the chosen
scale. This release also fixes SCENE-BM vector-field construction to finish after
its requested finite grid.

## SCENE-BN: dynamically derived plots

Version `0.62.0` adds `derived-function-graph`. Its two-argument field receives
the sampled read-only derived context and an x coordinate. It returns an
ordinary resolved path Visual for each scene sample; animate its parameter or
Visual dependencies, not the derived graph itself.

## SCENE-BL: implicit curves and contours

Version `0.61.0` adds `sample-implicit-path` and `implicit-curve`. A
two-argument scalar field is sampled with deterministic marching squares at a
specified level; non-finite cells become gaps. Adjacent cell segments are
stitched into deterministic open or closed contours. The resulting axes-aligned
path is a semantic snapshot and does not retain the source procedure.

## SCENE-BM: vector fields

Version `0.60.0` adds `vector-field`. It samples a two-argument procedure on an
axes-aligned numeric grid, producing a deterministic `group` of arrow children.
Zero vectors are omitted; all other arrows have stable `field-vector-x-y` IDs
and follow normal nested-path lookup and animation.

## SCENE-BK: discontinuity-aware sampled graphs

Version `0.59.0` adds `#:detect-discontinuities?` to `sample-function-path` and
`function-graph`. When enabled, adjacent samples beyond opposite sides of the
visible y range are treated as the hidden sides of a vertical asymptote rather
than clipped into a connecting segment. The default remains `#f` for compatibility;
`#:max-jump` continues to provide explicit numeric break control.

## SCENE-BF: automatic formula correspondence

Version `0.58.0` adds `formula-correspondence-auto`. It matches source parts to
the first still-unmatched destination part with the same LaTeX source and
typesetting options, in source/destination order. Renamed unchanged parts match
without boilerplate; changed or unmatched parts keep the existing fade-out/fade-
in behavior.

## SCENE-BE: explicit formula correspondence

`formula-correspondence` and `formula-part-match` remain the precise API for an
intentional one-to-one mapping, including mappings between different part names.

## SCENE-BD: addressable formula parts

Version `0.56.0` makes formula-assembly children ordinary nested Visual paths.
For example, `'(equation left-term)` can be read with `scene-ref` or animated
with `move-to`, `fade-to`, and compatible style requests. Assembly updates
rebuild its parts immutably and preserve the outer formula identity.

## SCENE-BC: group-child animation

Version `0.55.0` applies the established motion, transform, style, opacity, and
removal animation machinery to a nested path. Scheduling conflicts compare paths
structurally, so a path constructed twice still names the same child component;
different children can be animated in parallel. Child transforms remain local
to their containing group.

## SCENE-BB: stable nested Visual paths

Version `0.54.0` adds nonempty symbol paths such as `'(scatter marker)`. Use
`scene-ref`, `scene-visual-at`, scene-state lookup, or a derived context to read
the addressed leaf. Nested updates rebuild only the ancestor groups and preserve
the parent identities, transforms, opacity, child order, and unrelated children.

## SCENE-BA: dynamically derived groups

Version `0.53.0` confirms that a `derived-visual` may resolve to a concrete
`group` with a stable top-level ID while its children vary at each sampled state.
This supports pure, deterministic scene fragments such as a changing number of
markers, ticks, vertices, or terms.

## SCENE-AZ: immutable scene parameters

Version `0.52.0` introduces `(parameter id initial-value)`, an immutable handle
for one named scene value. It is deliberately distinct from Racket’s dynamic
parameters: it has no mutable current value and only identifies a value in
immutable scene state. Pass the handle to `scene-set-value` to install its
initial value, or use it wherever an existing scene-value API accepts an ID:
`value-to`, state lookup, scene lookup, removal, and derived-context lookup.

```racket
(define theta (parameter 'theta 0))

(define rotating-dot
  (derived-visual
   (circle #:id 'dot #:radius 1 #:fill "blue")
   (lambda (context template)
     (visual-with-position
      template
      (vec2 (derived-context-value-ref context theta) 0)))))

(scene-play
 (scene-add (scene-set-value (make-scene) theta) rotating-dot)
 (value-to theta 4)
 #:duration 2)
```

Run the focused stage test with:

```sh
raco test tests/scene-az-test.rkt
```

## SCENE-AY: generic interpolable scene values

Version `0.51.0` generalizes named scene values beyond finite-real scalars.
`interpolable?` identifies the current semantic kinds—finite reals, `vec2`
coordinates, and `rgba-color` values—and `interpolate-value` performs their
closed-unit-interval interpolation while preserving exact source and destination
objects at the endpoints. `scene-set-value`, `value-to`, scene value lookup, and
derived-context lookup all use this common protocol. A `value-to` request whose
source and destination kinds differ is rejected when its scene clip is compiled.

```racket
(define dot
  (derived-visual
   (circle #:id 'dot #:radius 1 #:fill "blue")
   (lambda (context template)
     (visual-with-position
      template
      (derived-context-value-ref context 'center)))))

(scene-play
 (scene-add (scene-set-value (make-scene) 'center (vec2 0 0)) dot)
 (value-to 'center (vec2 4 2))
 #:duration 2)
```

Run the focused stage test with:

```sh
raco test tests/scene-ay-test.rkt
```

## SCENE-AW: pure derived Visuals

Version `0.49.0` adds pure top-level Visual definitions driven by immutable
sampled scene values.

```racket
(derived-visual
 (circle #:id 'dot #:center origin #:radius 1)
 (lambda (context template)
   (visual-with-position
    template
    (vec2 (derived-context-value-ref context 'x) 0))))
```

`scene-state-ref` returns the persistent derived definition.
`scene-state-resolved-ref` evaluates that definition against the state and
returns its concrete Visual. `scene-state-resolved-visuals-in-drawing-order`
provides the resolved back-to-front top-level list used by rendering.

SCENE-AW introduced value lookup through
`derived-context-value-has?` and `derived-context-value-ref`. SCENE-AX extends
that same context with resolved top-level Visual lookup. Resolvers remain pure,
return a non-derived Visual, and preserve the template top-level ID. Concrete
results are never persisted into scene state, so arbitrary-time and repeated-
frame sampling remain deterministic when the resolver is pure.

Direct animation requests targeting a derived Visual are rejected. Animate the
named inputs with `value-to`; the derived Visual reflects those values at
each sampled state. Camera follow, `camera-fit-scene`, callout targets, and named
path-source lookup resolve derived targets automatically.

Render the canonical example with:

```sh
racket examples/derived-visuals.rkt \
  frames/derived-visuals \
  derived-visuals.mp4
```

Run the focused stage tests with:

```sh
raco test tests/scene-av-test.rkt tests/scene-av-render-test.rkt \
  tests/scene-aw-test.rkt tests/scene-aw-render-test.rkt
```

## SCENE-AV: animated scalar values

Version `0.48.0` adds named finite-real values to immutable scene state.

```racket
(scene-play
 (scene-set-value (make-scene) 'phase 0)
 (succession
  (value-to 'phase 1)
  (value-to 'phase 0))
 #:duration 4)
```

Scalar transitions are ordinary animation leaves with their own `scalar-value`
conflict component. Sequential leaves compile from exact prior scalar endpoints;
timed, parallel, and lagged compositions use the same scheduler as Visuals.
Scalar state is not drawn directly. In SCENE-AW, a derived Visual may consume
that sampled scalar state and therefore change rendered pixels; scenes containing
no derived Visuals retain the SCENE-AV non-rendering behavior. Visual and scalar
IDs share one global scene namespace to keep target identity unambiguous.

Run the semantic example with:

```sh
racket examples/animated-values.rkt
```

Run the focused stage tests with:

```sh
raco test tests/scene-av-test.rkt tests/scene-av-render-test.rkt
```

## SCENE-AU: unified style transitions

Version `0.47.0` adds `style-to`, a composition node for changing any nonempty
subset of fill color, stroke color, stroke width, and opacity over one shared
interval.

```racket
(style-to 'shape
          #:fill "cornflowerblue"
          #:stroke "navy"
          #:stroke-width 8
          #:opacity 3/4)
```

The operation expands to the already-established primitive requests, rather than
introducing a new style sampler or renderer path. This keeps fill color,
stroke color, stroke width, and opacity as independent scheduler components.
Only supplied properties participate in conflict detection: a `style-to` that
changes fill can overlap a separate stroke-width or opacity request, while an
overlapping fill request conflicts normally after schedule expansion.

The four keywords default to `#f`, meaning omitted. At least one property is
required. `#f` does not become a paint destination; SCENE-AT's rule that absent
fill/stroke paint is not color-interpolated remains unchanged.

`style-to` counts as one direct child for parent composition timing, then expands
its requested properties in parallel inside the interval it receives. It can be
used at top level, wrapped by `timed`, or nested in `succession`,
`animation-group`, and `lagged-start`. Direct Visual targets reuse the primitive
capability checks immediately; symbols defer those checks until `scene-play`.


## SCENE-AT: semantic fill/stroke color animation

Version `0.46.2` corrects the AT regression suite while preserving the public
API and implementation introduced in v0.46.1. The midpoint of black-to-gold is
`(rgba-color 255/2 215/2 0 1)`, and exact endpoint rendering is sampled by scene
time rather than by an out-of-range frame index.

Version `0.46.1` adds semantic `rgba-color` values, X11-style/hex color-spec parsing,
the optional `gen:fill-color-visual` and `gen:stroke-color-visual` protocols, and
absolute `fill-color-to` / `stroke-color-to` animation requests.

```racket
(scene-play
 scene
 (animation-group
  (fill-color-to 'shape "cornflowerblue")
  (stroke-color-to 'shape "navy")
  (stroke-width-to 'shape 8))
 #:duration 2)
```

Interior interpolation is componentwise over sRGB red/green/blue and alpha.
Exact start/end samples retain the original color specification instead of
normalizing it, preserving endpoint equality and sequential chaining. Semantic
RGBA values are converted to `racket/draw` colors only in the Pict adapter.

Fill color and stroke color are distinct animation components and are also
independent of stroke width, opacity, affine components, and path geometry.
Overlapping changes to the same color component conflict after schedule-tree
expansion; touching changes compile from the exact prior color endpoint.

The built-in circle, rectangle, path, and point-marker Visuals implement both
color protocols. Arrow, axes, and number-line Visuals implement stroke color.
A `scatter-plot` remains a top-level group, so its nested marker colors are not
independent scene-state animation targets. Callout `connector-stroke` is likewise
separate frame-space style and is not controlled by `stroke-color-to`. A current
`#f` fill or stroke represents missing paint and is deliberately not a color
interpolation source in this stage. Custom setters must install the requested
style exactly; for `rgba-color` that includes exact/inexact channel representation.


## SCENE-AS: semantic stroke-width animation

Version `0.45.1` is the corrected SCENE-AS baseline. Version `0.45.0` started
the style-animation track with the optional
`gen:stroke-width-visual` protocol and the `stroke-width-to` animation request.
The protocol consists of `visual-stroke-width` and `visual-with-stroke-width`;
`stroke-width?` recognizes the shared nonnegative finite-real domain.

```racket
(scene-play
 scene
 (animation-group
  (move-to 'ring (vec2 4 0))
  (stroke-width-to 'ring 12))
 #:duration 3)
```

Stroke width is a separate animation component. It can run concurrently with
translation, rotation, scaling, opacity, and path geometry changes for one
identity. Overlapping same-target width changes conflict after AN--AR schedule
expansion, while touching changes compile from the exact state at their shared
boundary.

The built-in circle, rectangle, path, arrow, axes, number-line, and point-marker
Visuals implement the protocol. Plot curves and filled areas that are path Visuals
inherit the capability. Scatter plots do not: `scatter-plot` returns a group and
its nested marker children are not independent scene-state animation targets.
Callout connector width is also intentionally separate from `stroke-width-to`.
Existing renderers consume supported built-ins' stored width fields, so AS requires
no special rendering or frame-sampling path. Custom Visuals may implement the
protocol independently of affine transforms and opacity; scene compilation
validates getter values, setter return types, identity preservation, and exact
requested endpoint installation, including exact/inexact representation.

A destination width of zero is valid and remains a semantic style value rather
than a scene-presence operation. In the default Pict/racket/draw renderer, zero
means a device-dependent hairline. The semantic predicate accepts any nonnegative
finite real so alternate renderers may support larger values, while the default
Pict backend reports a clear error above its 255-pixel pen-width limit. Width
interpolation follows the leaf easing, like movement and ordinary opacity
animation.


## SCENE-AR: duration-scaled composition timing

Version `0.44.0` makes `timed` compositional. It may wrap one ordinary Visual
request or one sequential/parallel/lagged composition, and timed values may be
direct children of all three composition constructors.

At a top-level `scene-play`, `#:start` and `#:duration` remain literal seconds.
Inside a composition they define an intrinsic child span. Untimed direct children
retain one unit; a timed direct child contributes `start + duration` units. The
parent scales those spans into its concrete assigned interval.

```racket
(scene-play
 scene
 (succession
  (move-to 'a (vec2 4 2))
  (timed (move-to 'b (vec2 4 0)) #:duration 2)
  (move-to 'c (vec2 4 -2)))
 #:duration 8)
```

The direct spans `1 : 2 : 1` become two, four, and two seconds. A nested timed
`#:start` reserves scaled delay before its active content. Bare nested
compositions still count as one direct child; wrap the nested composition itself
with `timed` when it should reserve a larger or delayed parent-level span.

Parallel groups scale every direct child against the longest direct span. Lagged
starts use the previous child's span when computing raw start offsets, then scale
the complete raw envelope. With all spans equal to one, the AQ formula is
unchanged. With unequal spans, lag ratio zero still matches parallel timing and
lag ratio one still matches succession timing.

A timed wrapper around a whole composition gives that composition one explicit
active interval:

```racket
(scene-play
 scene
 (timed
  (succession
   (move-to 'dot (vec2 4 0))
   (rotate-by 'dot 2))
  #:start 1
  #:duration 4)
 #:duration 6)
```

The wrapped succession is inactive before second one, scales its internal
schedule across seconds one through five, then holds its exact endpoint. A timed
composite easing becomes the inherited easing of its descendant leaves.

AR still keeps camera requests top-level/full-clip and rejects a timed wrapper
around another timed wrapper.


## SCENE-AQ: lagged visual animation starts

Version `0.43.0` adds `lagged-start`. For an assigned duration `D`, `n` direct
children, and lag ratio `r`, each direct child receives
`D / (1 + (n - 1) r)` seconds. Consecutive starts are separated by `r` child
durations, so the final direct child always ends exactly at the assigned outer
endpoint.

```racket
(scene-play
 scene
 (lagged-start
  (move-to 'a (vec2 4 2))
  (move-to 'b (vec2 4 0))
  (move-to 'c (vec2 4 -2))
  #:lag-ratio 1/2)
 #:duration 4)
```

This schedule gives two-second children at starts 0, 1, and 2. Ratio zero is
parallel timing; ratio one is equal-slice sequential timing; ratios greater than
one produce gaps.

Lagged starts may nest recursively with `succession` and `animation-group`. The
composition tree still expands to SCENE-AN `visual-request-spec` leaves, so
existing exact-boundary compilation, conflict checks, structural event ordering,
easing, camera-follow, and arbitrary-time sampling remain the only execution
semantics.

SCENE-AQ originally kept `timed` leaf-only and camera requests top-level.
SCENE-AR lifts the Visual timing restriction while camera requests remain
top-level/full-clip.


## SCENE-AP: parallel visual animation groups

Version `0.42.0` adds `animation-group`. A group occupies the interval assigned
by its enclosing `scene-play` or parent composition, and every direct child
receives that same complete interval.

```racket
(scene-play
 scene
 (animation-group
  (move-to 'card origin)
  (rotate-by 'card 1)
  (fade-to 'label 0))
 #:duration 3)
```

All three leaves run during the same three seconds. Existing component-conflict
rules still apply after expansion, so movement and rotation may share one target
while two overlapping movement requests for that target are rejected.

`animation-group` and `succession` may nest arbitrarily. A group nested in a
succession receives one sequence slice and gives that complete slice to all of
its children. A succession nested in a group receives the group's full interval
and subdivides it among its own children. This establishes a compositional
sequential/parallel timing tree without adding a second timeline representation.

Every composition expands to SCENE-AN scheduled Visual leaves. Equal-start leaves
compile together against one exact prepared state; later leaves compile from the
exact semantic state at their local boundary. Structural introduction/removal,
same-ID rules, easing, direct arbitrary-time sampling, and `camera-follow`
therefore reuse the same scheduler semantics.

SCENE-AP originally kept `timed` leaf-only and rejected timed wrappers and
camera requests inside compositions. SCENE-AQ added lagged starts; SCENE-AR now
adds explicit nested Visual timing while cameras remain top-level.


## SCENE-AO: successive visual animation composition

Version `0.41.0` adds `succession`. One succession occupies the interval assigned
by its enclosing `scene-play`; its direct children receive equal consecutive
shares of that interval.

```racket
(scene-play
 scene
 (succession
  (move-to 'card origin)
  (rotate-by 'card 1)
  (scale-by 'card 2))
 #:duration 3)
```

Here each child runs for one second. Every leaf uses the enclosing `scene-play`
easing on its own local progress. A relative child is compiled from the exact
semantic endpoint produced by the preceding child rather than from clip start.

A nested succession counts as one direct child of its parent and recursively
subdivides that assigned share. This establishes tree-shaped sequential
composition without introducing explicit intrinsic durations yet.

A succession may appear beside ordinary Visual requests, top-level `timed`
requests, and camera requests. Ordinary Visual and camera requests retain their
full-clip intervals. Existing AN overlap and structural checks operate on the
expanded succession leaves, so legal touching boundaries remain compositional
while positive same-component overlap with a sibling is rejected.

SCENE-AO originally accepted ordinary Visual animation requests and nested
successions. SCENE-AP extended its child grammar to include `animation-group`;
SCENE-AQ added `lagged-start`; and SCENE-AR adds timed Visual/composition
children. Camera requests remain invalid inside compositions.

## SCENE-AN: local visual animation timing

Version `0.40.0` starts the animation-composition track with `timed`. The wrapper
accepts one ordinary Visual animation request and attaches a local start,
duration, and optional easing inside an enclosing `scene-play`.

```racket
(scene-play
 scene
 (timed (move-to 'dot (vec2 4 0))
        #:start 1
        #:duration 2)
 (timed (rotate-by 'dot 1)
        #:start 0
        #:duration 1)
 #:duration 3)
```

Local intervals use seconds, not normalized fractions. A timed leaf is inactive
before its start, interpolates through its own interval, then holds its compiled
endpoint for the remainder of the clip. Omitting local `#:easing` inherits the
`scene-play` easing; supplying it overrides easing for that leaf only.

Compilation is event-based but sampling remains direct. Equal-start Visual
requests are compiled together so `fade-in`/`create` placeholders retain the
historical shared-start semantics. Later batches are compiled against the exact
state produced at their start time. Therefore touching relative requests can
legally target the same component: the later request starts from the earlier
request's endpoint. Positive-measure overlap on the same target/component is
rejected.

Structural introductions occur only at their local start. A target removed by
`fade-out` or `uncreate` cannot have another animation continue past that removal
boundary; reintroduction at the exact boundary remains legal.

Untimed Visual requests in a timed play clip span the full enclosing duration.
Camera requests also remain full-clip in this stage. `camera-follow` still tracks
the actual sampled Visual state, so a delayed or early-ending target motion is
followed faithfully without making camera timing local yet.

## SCENE-AM: per-pair real-match penalties

Version `0.39.0` lets callers add sparse semantic costs to individual real
source/destination assignment edges without replacing the geometric score:

```racket
(morph-to-topology-changing
 panel destination
 #:match-penalty-map
 (hash (cons 0 0) 20
       (cons 1 1) 5))
```

Each key is an improper pair `(cons source-index destination-index)`. Both indexes
refer to the original caller storage order even after topology partitioning and
global assignment. Values are finite nonnegative additive costs. Missing keys add
zero.

Pair penalties apply only to real same-topology edges. They do not alter open
reversal or closed-loop phase alignment; those transformations are selected first
and their geometric score is then increased by the sparse pair cost. Direct
preparation rejects out-of-range indexes and open-to-closed keys because such an
assignment edge cannot exist.

Unlike SCENE-AL's birth/death penalty maps, `#:match-penalty-map` is meaningful in
both policy modes. In `'forced` mode it can reorder which real subpaths pair while
any count-forced dummy slots remain zero-cost. In numeric AJ mode the resulting
real-edge score competes against death plus birth costs. AJ's secondary objective
still prefers a real match when the primary totals tie exactly.

Timeline requests snapshot the pair map immutably. Request construction validates
pair-key shape and numeric values immediately; clip compilation validates indexes
and topology against the actual source/destination paths.

Render the canonical example with:

```sh
racket examples/per-pair-match-penalties.rkt \
  frames/per-pair-match-penalties \
  per-pair-match-penalties.mp4

open per-pair-match-penalties.mp4
```

Focused regression suites are:

```sh
raco test tests/scene-am-test.rkt \
          tests/scene-am-render-test.rkt
```


## SCENE-AL: per-subpath birth/death penalty maps

Version `0.38.0` lets individual endpoint subpaths override SCENE-AJ's shared
numeric cost without changing geometric matching or anchor policy:

```racket
(morph-to-topology-changing
 panel destination
 #:birth-penalty 2
 #:death-penalty 2
 #:birth-penalty-map (hash 1 20)
 #:death-penalty-map (hash 0 20))
```

`#:birth-penalty-map` keys refer to the caller destination's original subpath
indexes. `#:death-penalty-map` keys refer to the clip-start source's original
subpath indexes. Topology partitioning, destination reordering, open-path
reversal, and closed-loop phase selection never renumber those keys.

Each map value is a finite nonnegative real cost. Missing keys fall back to the
shared numeric `#:birth-penalty` or `#:death-penalty`. The sparse values replace
only dummy-edge costs in AJ's augmented assignment; real source/destination
edges retain their SCENE-AC/AE geometric scores. Exact primary-cost ties still
prefer fewer topology changes.

Nonempty penalty maps require numeric shared penalty mode. They are rejected
when the shared policy is `'forced`, avoiding an ambiguous mixture of forced-only
and numeric dummy-edge semantics. SCENE-AI/AK anchor options remain independent
and determine where every unmatched slot selected by the resulting assignment
collapses or grows.

Timeline requests snapshot penalty maps into immutable hashes. Direct geometry
preparation rejects out-of-range keys immediately; request compilation checks
indexes against the actual clip-start source and stored destination.

Render the canonical example with:

```sh
racket examples/per-subpath-topology-penalties.rkt \
  frames/per-subpath-topology-penalties \
  per-subpath-topology-penalties.mp4

open per-subpath-topology-penalties.mp4
```

The shared-cost panel replaces both distant pairs. The mapped panel protects the
upper pair with high original-index costs while the lower pair still collapses
and regrows under the shared low costs.

Focused regression suites are:

```sh
raco test tests/scene-al-test.rkt \
          tests/scene-al-render-test.rkt
```


## SCENE-AK: per-subpath birth/death anchor maps

Version `0.37.0` lets individual unmatched subpaths override SCENE-AI's shared
anchor without changing assignment policy:

```racket
(morph-to-topology-changing
 panel destination
 #:birth-anchor origin
 #:death-anchor origin
 #:birth-anchor-map (hash 1 (vec2 -5 -1)
                          2 (vec2 5 -1))
 #:death-anchor-map (hash 1 (vec2 -5 -1)
                          2 (vec2 5 -1)))
```

`#:birth-anchor-map` keys refer to the caller destination's original subpath
indexes. `#:death-anchor-map` keys refer to the clip-start source's original
subpath indexes. Assignment, topology partitioning, reordering, reverse
direction, and closed-loop phase selection do not renumber those keys.

Each map value is either a finite local `vec2` or `'bounds-center`. Missing keys
fall back to `#:birth-anchor` or `#:death-anchor`. Thus a sparse map can override
only selected subpaths, and an explicit `'bounds-center` entry can opt one
subpath back into its own local center when the shared fallback is a custom hub.

The maps affect only unmatched slots, including voluntary SCENE-AJ
penalty-selected births/deaths. Matched real pairs ignore them. Timeline requests
snapshot maps into immutable hashes, preserving deterministic behavior if the
caller later mutates the original hash.

Render the canonical example with:

```sh
racket examples/per-subpath-topology-anchors.rkt \
  frames/per-subpath-topology-anchors \
  per-subpath-topology-anchors.mp4

open per-subpath-topology-anchors.mp4
```

The two lower source curves collapse into different marked hubs while two new
closed loops grow from those corresponding hubs. A surviving upper curve morphs
at the same time.

Focused regression suites are:

```sh
raco test tests/scene-ak-test.rkt \
          tests/scene-ak-render-test.rkt
```


## SCENE-AJ: penalized topology-changing correspondence

Version `0.36.0` lets topology-changing correspondence reject a poor real pair
even when no topology-count difference forces a birth or death. The default is
still the exact forced-only policy:

```racket
(path-geometry-prepare-topology-changing-morph
 source destination
 #:birth-penalty 'forced
 #:death-penalty 'forced)
```

To opt into replacement, provide both penalties as finite nonnegative numbers:

```racket
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-penalty 2
             #:death-penalty 2)
            #:duration 3)
```

Real-pair cost is the existing mean point-distance correspondence score. A death
edge costs `#:death-penalty`; a birth edge costs `#:birth-penalty`. The matcher
solves one augmented global assignment per topology class, so it can keep good
real correspondences while replacing only expensive ones. The choice is not a
greedy per-pair threshold.

When the minimum primary cost ties exactly, SCENE-AJ minimizes the number of
birth/death edges as a secondary objective. Thus a real pair is preserved when
its score equals death plus birth cost. Remaining exact assignment ties retain
the existing deterministic index order.

The two penalty keywords must use the same mode: both `'forced`, or both finite
nonnegative real numbers. Numeric penalties are local path-unit costs and do not
change SCENE-AC/AE direction/phase scoring. SCENE-AI anchor options determine the
seed position for every unmatched slot, whether unmatched by count difference or
voluntary penalty-driven rejection.

Render the canonical comparison with:

```sh
racket examples/penalized-topology-changing-morphs.rkt \
  frames/penalized-topology-changing-morphs \
  penalized-topology-changing-morphs.mp4

open penalized-topology-changing-morphs.mp4
```

Focused regression suites are:

```sh
raco test tests/scene-aj-test.rkt \
          tests/scene-aj-render-test.rkt
```


## SCENE-AI: explicit birth/death anchors

Version `0.35.0` makes SCENE-AH seed placement configurable without changing
its pairing policy. The default remains bounds-center behavior:

```racket
(path-geometry-prepare-topology-changing-morph
 source destination
 #:birth-anchor 'bounds-center
 #:death-anchor 'bounds-center)
```

To make every new destination subpath grow from one semantic local hub and every
dying source subpath collapse into that hub, provide a finite `vec2`:

```racket
(define hub (vec2 0 0))

(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-anchor hub
             #:death-anchor hub)
            #:duration 3)
```

`#:birth-anchor` is used only for unmatched destination subpaths.
`#:death-anchor` is used only for unmatched source subpaths. An explicit point is
interpreted in the path Visual's local coordinate system, so the Visual's world
translation, rotation, and scale apply afterward in the ordinary way. Matching
real subpaths never pass through either anchor merely because the option is
present.

The accepted anchor values are exactly `'bounds-center` and `vec2` values. The
geometry preparer and timeline request reject any other symbol or value. A single
explicit point is shared by all unmatched subpaths on that side. SCENE-AJ may
create additional voluntary unmatched slots through numeric penalties. SCENE-AK
adds sparse original-index overrides for those same seed positions. SCENE-AL
independently adds sparse numeric cost overrides for deciding which subpaths
become unmatched.

Render the canonical SCENE-AI example with:

```sh
racket examples/anchored-topology-changing-morphs.rkt \
  frames/anchored-topology-changing-morphs \
  anchored-topology-changing-morphs.mp4

open anchored-topology-changing-morphs.mp4
```

Focused regression suites are:

```sh
raco test tests/scene-ai-test.rkt \
          tests/scene-ai-render-test.rkt
```


## SCENE-AH: topology-changing morphs with subpath birth/death

Version `0.34.0` extends topology-aware correspondence to compounds whose open
or closed subpath counts differ.

Prepare the interior correspondence explicitly:

```racket
(define-values (prepared-source prepared-destination)
  (path-geometry-prepare-topology-changing-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph
   prepared-source prepared-destination))
```

Every real source/destination subpath must have positive finite arc length. Open
and closed topology classes are handled independently. Within each class, the
smaller side is matched globally to a subset of the larger side using the same
SCENE-AE/AF or SCENE-AC/AD correspondence scores. The rectangular assignment is
implemented by deterministic zero-cost dummy padding, so exactly the forced
count difference becomes unmatched in the default policy. SCENE-AJ adds the
optional numeric birth/death penalties described above without changing this
default.

An unmatched destination subpath receives a one-segment degenerate source seed
at that destination subpath's exact axis-aligned bounds center. An unmatched
source subpath receives the corresponding degenerate destination seed at its own
bounds center. The seed preserves the real subpath's open/closed bit. Existing
source slots remain in source order; birth-only slots are appended in caller
destination order. When topology-class counts already match, preparation reduces
exactly to SCENE-AG.

For timeline use:

```racket
(scene-play scene
            (morph-to-topology-changing panel destination)
            #:duration 3)
```

Birth/death seeds, pairing, reordering, reversal, and closed-loop phase changes
are interior correspondence only. Eased progress zero uses the exact clip-start
source. Eased progress one installs the exact caller-requested destination,
including its original subpath count, order, and traversal representations.

Render the canonical SCENE-AH example with:

```sh
racket examples/topology-changing-morphs.rkt \
  frames/topology-changing-morphs \
  topology-changing-morphs.mp4

open topology-changing-morphs.mp4
```

Focused regression suites are:

```sh
raco test tests/scene-ah-test.rkt \
          tests/scene-ah-render-test.rkt
```


## SCENE-AG: automatic mixed-topology compound morph correspondence

Version `0.33.0` adds deterministic correspondence for compound figures that may
mix open subpaths and closed loops.

Prepare a destination explicitly:

```racket
(define aligned-destination
  (path-geometry-align-mixed-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
```

The source and destination must be nonempty, every subpath must have positive
finite arc length, and the number of open subpaths must match independently from
the number of closed subpaths. Open paths are never candidates for closed loops.
Within the open class, SCENE-AE forward/reverse scores and SCENE-AF's global
assignment rule are reused. Within the closed class, SCENE-AC phase/direction
scores and SCENE-AD's global assignment rule are reused. The two class results
are then interleaved back into the source's subpath order.

For timeline use:

```racket
(scene-play scene
            (morph-to-mixed-compound-aligned panel destination)
            #:duration 3)
```

Pairing, reordering, endpoint reversal, and closed-loop phase changes are interior
correspondence only. Eased progress zero uses the exact clip-start source, while
eased progress one installs the exact caller-requested destination storage.

Render the canonical SCENE-AG example with:

```sh
racket examples/mixed-compound-morph-correspondence.rkt \
  frames/mixed-compound-morph-correspondence \
  mixed-compound-morph-correspondence.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-ag-test.rkt \
          tests/scene-ag-render-test.rkt
```


## SCENE-AF: automatic open-compound morph correspondence

Version `0.32.0` adds deterministic global correspondence for equal-count
compound figures whose subpaths are all open.

Pair and direction-align an open compound destination explicitly:

```racket
(define aligned-destination
  (path-geometry-align-open-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
```

Every source/destination pair uses SCENE-AE's total-arc-length endpoint-direction
score. The complete cost matrix is then solved with the deterministic global
minimum-cost assignment used by SCENE-AD, so pairing is not greedy. Within each
pair, reverse traversal is selected only for a strictly lower score; exact ties
keep stored forward traversal.

For timeline use:

```racket
(scene-play scene
            (morph-to-open-compound-aligned panel destination)
            #:duration 3)
```

Pairing, subpath reordering, and direction selection are interior correspondence
only. Eased progress zero uses the exact clip-start source, while eased progress
one installs the exact caller-requested destination, including its original
subpath order and stored traversal directions.

Render the canonical SCENE-AF example with:

```sh
racket examples/open-compound-morph-correspondence.rkt \
  frames/open-compound-morph-correspondence \
  open-compound-morph-correspondence.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-af-test.rkt \
          tests/scene-af-render-test.rkt \
          tests/scene-ae-test.rkt \
          tests/scene-ae-render-test.rkt
```


## SCENE-AE: automatic open-path morph correspondence

Version `0.31.0` adds deterministic endpoint-direction correspondence for one
positive finite open source/destination path.

Choose the destination traversal explicitly before normalization:

```racket
(define aligned-destination
  (path-geometry-align-open-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
```

The source and destination must each contain exactly one open subpath with
positive finite arc length. The algorithm samples both paths at the same
`#:sample-count` total-arc-length fractions, including both endpoints, and
compares mean Euclidean distance for the stored destination traversal and, when
allowed, `path-geometry-reverse` of the destination. A strict lower score is
required to select reversal; exact ties keep the caller's stored direction.

Unlike SCENE-AC closed-loop alignment, SCENE-AE performs no cyclic phase search:
the two open endpoints remain distinct. `#:allow-reverse?` defaults to `#t`, and
`#:sample-count` defaults to `64` with a minimum of `8`.

For timeline use:

```racket
(scene-play scene
            (morph-to-open-aligned panel destination)
            #:duration 3)
```

Direction selection and normalized geometry are interior correspondence only.
Eased progress zero uses the exact clip-start source, while eased progress one
installs the exact destination object requested by the caller, including its
original stored direction.

Render the canonical SCENE-AE example with:

```sh
racket examples/open-morph-correspondence.rkt \
  frames/open-morph-correspondence \
  open-morph-correspondence.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-ae-test.rkt \
          tests/scene-ae-render-test.rkt \
          tests/scene-ad-test.rkt \
          tests/scene-ad-render-test.rkt
```


## SCENE-AD: automatic compound-path morph correspondence

Version `0.30.0` adds deterministic global correspondence for equal-count
compound closed paths.

Pair and align an equal-count compound destination explicitly:

```racket
(define aligned-destination
  (path-geometry-align-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
```

Every source/destination subpath pair is scored with the same deterministic
total-arc-length correspondence used by SCENE-AC, including optional traversal
reversal and cyclic phase selection. SCENE-AD then solves one global
minimum-total-cost assignment across those pair scores. It does not greedily
commit the first source loop to its locally nearest destination.

All source and destination subpaths must be closed and have positive finite
length, and the two paths must contain the same nonzero number of subpaths.
Exact assignment ties are deterministic. `#:allow-reverse?` and
`#:sample-count` have the same meanings and defaults as in SCENE-AC.

For timeline use:

```racket
(scene-play scene
            (morph-to-compound-aligned panel destination)
            #:duration 3)
```

The paired/reordered/phase-shifted destination is an interior correspondence
only. Eased progress zero uses the exact clip-start source, while eased progress
one installs the exact destination object requested by the caller, including
its original subpath storage order.

Render the canonical SCENE-AD example with:

```sh
racket examples/compound-morph-correspondence.rkt \
  frames/compound-morph-correspondence \
  compound-morph-correspondence.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-ad-test.rkt \
          tests/scene-ad-render-test.rkt \
          tests/scene-ac-test.rkt \
          tests/scene-ac-render-test.rkt
```


## SCENE-AC: automatic closed-loop morph correspondence

Version `0.29.1` keeps the `0.29.0` public API and animation semantics unchanged. It corrects the SCENE-AC renderer regression test to use `scene-frame->bitmap` with frame indices and the public `render-frames!` API for deterministic PNG checks.

Align one closed destination loop to one closed source loop explicitly:

```racket
(define aligned-destination
  (path-geometry-align-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
```

The alignment score compares total-arc-length point samples. It searches a
complete deterministic phase grid plus exact destination edge boundaries, then
performs a fixed number of local refinement rounds. By default it evaluates both
forward and reversed traversal and keeps the lower score; exact direction ties
prefer forward traversal.

For timeline use, combine alignment and normalization in one request:

```racket
(scene-play scene
            (morph-to-aligned panel destination)
            #:duration 3)
```

Set `#:allow-reverse? #f` to keep destination traversal direction fixed.
`#:sample-count` defaults to `64` and must be an exact integer at least `8`.
Increasing it refines the deterministic geometric score at additional compile
time; it does not affect frame rate or renderer sampling.

The exact original source path is used at eased progress zero, and the exact
requested destination object is used at eased progress one. The automatically
phase-shifted/reversed representation is an interior morph correspondence only.

SCENE-AC accepts exactly one positive finite closed subpath on each side. Use
SCENE-AD when equal-count compound paths need automatic subpath pairing.

Render the canonical SCENE-AC example with:

```sh
racket examples/automatic-morph-correspondence.rkt \
  frames/automatic-morph-correspondence \
  automatic-morph-correspondence.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-ac-test.rkt \
          tests/scene-ac-render-test.rkt \
          tests/scene-ab-test.rkt \
          tests/scene-ab-render-test.rkt
```


## SCENE-AB: path reversal and cyclic starts

Version `0.28.1` keeps the `0.28.0` public API unchanged and makes cyclic
phase reconstruction numerically stable: only the edge containing the new
start is split, while every untouched segment is reused exactly. Straight
closing prefixes are represented by the semantic closed-path edge instead of
by a duplicate explicit return segment.


Reverse semantic traversal without changing the visible path:

```racket
(define reverse-route
  (path-geometry-reverse route))
```

For an open subpath, the former endpoint becomes the new start. Lines reverse
their endpoints; cubic Bézier segments reverse their endpoints and swap their
two control points. For a closed subpath, SCENE-AB keeps the original stored
start point and reverses the loop around it. The old implicit closing line is
materialized when needed, so for a positive finite closed loop:

```text
point(reverse(route), f) = point(route, 1 - f)
```

up to the deterministic cubic arc-length approximation already used by
`path-geometry-point-at`.

Move the stored start of one closed loop without changing its direction:

```racket
(define phased-route
  (path-geometry-cycle-start route 3/10))
```

The fraction is measured in the same total arc-length model as path motion. A
fraction of `0` or `1` returns the original immutable geometry. Any other
fraction becomes the new start and end of the loop. If that position lies
inside a line or cubic, the segment is split deterministically; the returned
path still traces exactly the same loop in the same forward direction.

Cyclic start adjustment requires exactly one positive-length closed subpath.
This keeps phase selection explicit rather than silently applying one phase to
unrelated compound subpaths. SCENE-AC automates phase/direction selection for
one closed source/destination pair; automatic compound-subpath pairing remains
future work.

Both operations return ordinary path geometry. They therefore compose directly:

```racket
(scene-play scene
            (move-along-path pointer
                             (path-geometry-reverse route))
            (orient-along-path pointer
                               (path-geometry-reverse route))
            #:duration 3)
```

A phase-shifted destination can likewise be passed to
`path-geometry-normalize-for-morph` or `morph-to-normalized`; SCENE-AB does not
add a separate animation request type.

Render the canonical SCENE-AB example with:

```sh
racket examples/reversed-and-cyclic-paths.rkt \
  frames/reversed-and-cyclic-paths \
  reversed-and-cyclic-paths.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-ab-test.rkt \
          tests/scene-ab-render-test.rkt \
          tests/scene-aa-test.rkt \
          tests/scene-aa-render-test.rkt
```


## SCENE-AA: continuous joined offset paths

Construct a signed parallel path from straight semantic geometry:

```racket
(define lane
  (path-geometry-offset route 3/4 #:join 'round))
```

Positive distance is to the left of the stored traversal direction; negative
distance is to the right. The output is ordinary `path-geometry`, not a style or
renderer instruction.

For an outside corner, select one of three policies:

```racket
(path-geometry-offset route 1 #:join 'miter)
(path-geometry-offset route 1 #:join 'bevel)
(path-geometry-offset route 1 #:join 'round)
```

`'miter` extends the adjacent shifted lines to their intersection. The default
miter limit is 4 times the absolute offset distance. If the outside intersection
would exceed `#:miter-limit`, the corner falls back to bevel. `'bevel` connects
the two shifted edge endpoints with one line. `'round` inserts cubic Bézier arc
pieces of at most 90 degrees around the original vertex.

Inside corners always use the natural shifted-line intersection. This keeps the
joined path moving forward along both adjacent edges; applying the short round
arc on the inside would reverse its tangent at the connector.

Open endpoints are shifted by the first/last edge normal. Closed subpaths join
cyclically, including the stored start vertex. Zero-length line edges and exact
180-degree reversals are rejected because they do not define a unique local
normal/join. In SCENE-AA, a nonzero joined offset requires line-only source
geometry; exact offsetting of cubic source curves remains future work. A zero
distance returns the original path unchanged.

The result composes directly with existing path APIs:

```racket
(scene-play scene
            (move-along-path pointer lane)
            (orient-along-path pointer lane)
            #:duration 3)
```

Because `lane` has its own line/cubic geometry and arc length, `linear` easing
means constant speed along the joined offset itself. For reverse motion, reverse
the path-motion fractions as usual. If “left of actual reverse motion” is the
goal, construct the offset with the opposite sign because
`path-geometry-offset` is defined relative to stored path direction.

SCENE-Z's `#:normal-offset` remains segment-local and therefore can jump at a
polyline corner. It is still useful when that local rule is desired or the route
is already smooth. Use a generated joined offset route when corner continuity
matters.

Render the canonical SCENE-AA example with:

```sh
racket examples/joined-offset-paths.rkt \
  frames/joined-offset-paths \
  joined-offset-paths.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-aa-test.rkt \
          tests/scene-aa-render-test.rkt \
          tests/scene-z-test.rkt \
          tests/scene-z-render-test.rkt
```


## SCENE-Z: tangent orientation and normal offsets

Sample the forward unit tangent and its left unit normal at any positive finite
semantic path fraction:

```racket
(path-geometry-tangent-at route 1/2)
(path-geometry-normal-at route 1/2)
```

Fractions use the same total ordered arc-length model as
`path-geometry-point-at`. Line tangents are exact normalized edge directions.
Cubic tangents use the derivative at the arc-length-selected curve parameter,
with deterministic one-sided probing when that derivative is zero at an
endpoint or cusp. At an exact boundary between positive traversal edges, the
preceding edge owns the point and tangent.

Offset ordinary path translation perpendicular to the current traversal:

```racket
(move-along-path marker route #:normal-offset 3/4)
```

A positive offset is to the left of the **actual motion direction**. Reversing
the fractions therefore reverses the normal:

```racket
(move-along-path marker route
                 #:start 1
                 #:end 0
                 #:normal-offset 3/4)
```

The offset is segment-local. A polyline with a sharp corner can therefore jump
between the two offset edge lines at the corner; use smooth cubic geometry when
a continuous offset trajectory is required.

Rotate an affine Visual from the same path tangent with an independent request:

```racket
(scene-play scene
            (move-along-path pointer route)
            (orient-along-path pointer route)
            #:duration 3)
```

`orient-along-path` owns the ordinary rotation component while
`move-along-path` owns translation. They can run simultaneously on one target,
but `orient-along-path` conflicts with same-target `rotate-to`, `rotate-by`, or
another orientation request. `#:rotation-offset` adds a constant angle in
radians after tangent alignment:

```racket
(orient-along-path pointer route #:rotation-offset (/ pi 2))
```

The orientation points along the requested traversal direction, so a reverse
request points opposite the path's stored forward tangent. Raw path geometry is
interpreted in the target's containing coordinate system. A path Visual or
symbol route is resolved by stable identity at clip start and transformed into
world coordinates before arc length, tangents, normals, or orientation are
computed. The route remains a clip-start snapshot.

Render the canonical SCENE-Z example with:

```sh
racket examples/path-orientation-and-offsets.rkt \
  frames/path-orientation-and-offsets \
  path-orientation-and-offsets.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-z-test.rkt \
          tests/scene-z-render-test.rkt \
          tests/scene-y-test.rkt \
          tests/scene-y-render-test.rkt
```


## SCENE-Y: arc-length path following

Sample a point from any positive finite semantic path by total ordered arc
length:

```racket
(path-geometry-point-at route 1/2)
```

For line segments this is exact Euclidean distance. Cubic Bézier traversal uses
the same deterministic adaptive arc-length table as path reveal and partial
extraction. The implicit closing edge of a closed subpath participates in the
traversal. The general lookup operation can traverse compound path geometry in
stored subpath order.

Move a top-level Visual along one continuous route:

```racket
(scene-play scene
            (move-along-path marker route)
            #:duration 3)
```

`route` may be raw path geometry, a path Visual, or the symbol identity of a
path Visual. Raw geometry is already expressed in the target's containing
coordinate system. A path Visual is resolved from the prepared clip-start state
by stable identity and its current translation, rotation, and scale are applied
to produce the world-space route. This means an earlier constructor value still
selects the current scene version of that route.

Choose a subinterval or reverse direction with `#:start` and `#:end`:

```racket
(move-along-path marker route #:start 1/4 #:end 3/4)
(move-along-path marker route #:start 1 #:end 0)
```

Both fractions are in `[0,1]`. The request uses the ordinary translation
component, so it may compose with rotation, scale, opacity, path morphing on a
different component, and camera animation, but it conflicts with another
translation request such as same-target `move-to`. Under `linear` easing,
progress is linear in total arc length. Other easing functions remap that
arc-length progress in the usual way.

Motion routes deliberately require one positive-length continuous subpath. A
compound drawing with multiple positive-length subpaths remains valid path
geometry, but using it as one motion route raises an exception rather than
teleporting across a gap. The route is a clip-start snapshot: moving or morphing
the path Visual simultaneously does not dynamically deform the route.

A path Visual route is world-space after resolution, so it cannot drive a
frame-space target. Raw path geometry can drive a frame-space target because it
is interpreted directly in that target's containing coordinate system.

Camera following now consumes the target's sampled Visual state. It therefore
tracks the elbow of a polyline or a curved route instead of linearly
interpolating between the target's clip endpoints:

```racket
(scene-play scene
            (move-along-path marker route)
            (camera-follow marker)
            (camera-zoom-by 3/2)
            #:duration 3)
```

Render the canonical SCENE-Y example with:

```sh
racket examples/path-following.rkt \
  frames/path-following \
  path-following.mp4
```

Run the focused regression tests with:

```sh
raco test tests/scene-y-test.rkt \
          tests/scene-y-render-test.rkt \
          tests/scene-x-example-test.rkt
```

## SCENE-X: fixed-in-frame overlays and callouts

Freeze an existing Visual at the screen position and scale it has through a
particular camera:

```racket
(define title
  (fixed-in-frame world-title
                  #:camera current-camera))
```

The wrapper preserves `world-title`'s stable identity. It snapshots the camera's
visible width and converts the title's current world position to an
origin-centered frame position. Later camera pan and zoom therefore affect the
world but not the overlay. Use `#:at` to choose a frame position explicitly:

```racket
(fixed-in-frame title-content
                #:camera current-camera
                #:at (vec2 0 3))
```

A frame-space wrapper is an ordinary affine/opacity Visual and can itself be
moved, rotated, scaled, faded, or removed. Its wrapped content remains
semantic Visual data and retains its own geometry and style. Wrappers stay at
top level; to make a multi-part overlay, group ordinary local content first:

```racket
(fixed-in-frame
 (group (list icon label) #:id 'legend)
 #:camera current-camera
 #:at (vec2 5 3))
```

A callout adds a leader from fixed annotation content to a world target:

```racket
(callout note
         marker
         #:camera current-camera
         #:at (vec2 4 2)
         #:connector-stroke "navy"
         #:connector-width 2)
```

A Visual target is normalized to its stable identity. At every sampled frame,
scene rendering resolves that identity against the current top-level state, so a
leader follows ordinary target movement without persistent observer state. A
`vec2` target is a fixed world point. The leader is drawn beneath the annotation
and its width is cosmetic output-pixel width. `visual->pict` returns the local
annotation only; complete scene rendering supplies the target-dependent leader.

Renderer-aware layout operates within a single coordinate domain. Frame-space
Visuals with the same captured frame width can be aligned and arranged together,
and their measured boxes remain stable under later world pan/zoom. World and
frame-space Visuals cannot be mixed in one relative-layout calculation. A
callout's layout box includes its annotation, not its cross-space leader.

Camera semantics stay world-only. `camera-fit-visuals` rejects frame-space
values. `camera-fit-scene` ignores them when fitting all current scene content and
rejects them when explicitly selected. `camera-follow` likewise rejects a
frame-space target.


The canonical SCENE-X movie uses the same piecewise-linear sample edges for
the moving marker as for the displayed quadratic graph. SCENE-Y expresses that
traversal as one `move-along-path` clip, so the marker stays on the rendered
graph while the camera executes its original continuous linear pan and zoom
trajectory.

## SCENE-W: automatic camera framing and following

Fit one already measured renderer box:

```racket
(define request
  (camera-fit-layout-box box
                         #:camera current-camera
                         #:padding 1/2))

(scene-play scene request #:duration 1)
```

The padding is measured in world units on each side before aspect-ratio
correction. The requested visible width is the larger of the padded horizontal
extent and the width needed to show the padded vertical extent at the camera's
pixel aspect ratio.

Fit a nonempty set of Visual values with the same renderer list used later:

```racket
(scene-play
 scene
 (camera-fit-visuals (list diagram title)
                     #:camera (scene-current-camera scene)
                     #:renderers default-pict-renderers
                     #:padding 1/2)
 #:duration 1)
```

Text, formulas, groups, and custom Visuals are measured through their selected
Pict renderers. Formula fitting can therefore run LaTeX. The supplied values
must share one containing coordinate system; pass a complete group rather than
one child whose position is local to that group. Measurement uses the supplied
camera once; fixed-pixel custom renderers are not remeasured at the target zoom.

Fit the current top-level scene values by stable identity:

```racket
(camera-fit-scene scene #:padding 1/2)

(camera-fit-scene scene
                  #:targets (list 'marker 'label)
                  #:padding 1)
```

With no `#:targets`, every current top-level Visual is included in back-to-front
order. A target list may contain Visual values or symbols, but each is resolved
against `scene-current-state`, so a stale constructor value still selects the
current endpoint value.

A fit request changes camera center and visible world width together. It
therefore conflicts with pan, zoom, follow, or another fit request in the same
clip. It can run with any disjoint Visual animation.

Follow one moving top-level Visual during a play clip:

```racket
(scene-play scene
            (move-to marker destination)
            (camera-follow marker)
            (camera-zoom-by 2)
            #:duration 2)
```

The target stays at its clip-start pixel position. Following uses the target's
actual sampled Visual position, so curved or piecewise `move-along-path` motion
is tracked rather than approximated by a straight interpolation between clip
endpoints. When zoom also changes the visible width, the camera center
compensates so the target remains at the same horizontal and vertical frame
coordinates. A centered target therefore remains centered. An off-center target
remains at the same off-center position.

Following is clip-local. Add `camera-follow` again in each later clip that
should continue tracking. The request changes the camera-center component and
can run with one zoom request, but not with pan, fit, or another follow request.
The target must be a top-level Visual in the prepared clip state. A target may
be introduced or removed structurally in the same clip because its motion state
exists throughout the sampled interval.

Both fit and follow endpoints obey the easing result. They have no structural
endpoint override.

Render the canonical example:

```sh
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-framing-and-following.rkt \
  frames/camera-framing-and-following \
  camera-framing-and-following.mp4

open camera-framing-and-following.mp4
```

Run the stage tests with:

```sh
"/Applications/Racket v9.3.0.2/bin/raco" make main.rkt

"/Applications/Racket v9.3.0.2/bin/raco" test \
  tests/scene-w-test.rkt \
  tests/scene-w-render-test.rkt
```


## SCENE-V: point markers, scatter plots, and filled areas

Create one marker directly:

```racket
(point-marker #:id 'sample
              #:center (vec2 2 1)
              #:shape 'diamond
              #:size 1/4
              #:fill "crimson")
```

The supported shapes are `circle`, `square`, `diamond`, `triangle-up`, and
`triangle-down`. Size is a semantic local extent in world units. Stroke width
remains cosmetic.

Construct an ordered scatter group from numeric coordinates:

```racket
(define observations
  (scatter-plot
   coordinate-axes
   (list (vec2 -2 1)
         #f
         (vec2 0 0)
         (vec2 2 1))
   #:id 'observations
   #:shape 'diamond))
```

`#f` values and clipped points are omitted. Marker identities retain the
original zero-based indexes, so the children above use indexes 0, 2, and 3.
Markers start upright and use a snapshot of the current axes transform.

Fill beneath a sampled function:

```racket
(define area
  (function-area coordinate-axes
                 function
                 #:id 'area
                 #:baseline 0
                 #:interpolation 'smooth
                 #:opacity 2/5))
```

Every accepted graph run becomes a separate closed subpath. With clipping on,
the baseline is clamped to the visible y range. `data-area` provides the same
behavior for ordered coordinate lists and explicit gaps.

Render the canonical example:

```sh
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/markers-scatter-areas.rkt \
  frames/markers-scatter-areas \
  markers-scatter-areas.mp4

open markers-scatter-areas.mp4
```


## SCENE-U: animated camera pan and zoom

A scene owns an immutable current camera:

```racket
(define initial-camera
  (make-camera #:width 1280
               #:height 720
               #:world-width 14
               #:center origin
               #:background "white"))

(define scene
  (make-scene #:camera initial-camera))
```

The camera can be changed instantaneously without adding time:

```racket
(scene-set-camera scene
                  (make-camera #:world-width 8
                               #:center (vec2 2 1)))
```

Camera requests participate in `scene-play` with Visual requests:

```racket
(scene-play scene
            (move-to marker (vec2 3 1))
            (camera-pan-to (vec2 2 1))
            (camera-zoom-by 2)
            #:duration 2)
```

`camera-pan-by` adds a world displacement to the center at clip start.
`camera-zoom-by` applies a magnification factor: values above one zoom in,
while values between zero and one zoom out. `camera-zoom-to` receives an
absolute positive visible world width.

The Visual state and camera can be sampled independently at any timeline time:

```racket
(scene-camera-at scene 3/2)
(scene-current-camera scene)
```

Camera center and visible width are independent components. They can animate
together, but two center requests or two zoom requests in one play clip are
rejected. Camera and Visual requests are compiled from the same clip start and
share one duration and easing function. Renderer-aware layout remains static;
pass `(scene-camera-at scene time)` explicitly when measuring for one sampled
view.

Render the canonical example with:

```sh
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-pan-and-zoom.rkt \
  frames/camera-pan-and-zoom \
  camera-pan-and-zoom.mp4

open camera-pan-and-zoom.mp4
```

Run the stage tests with:

```sh
"/Applications/Racket v9.3.0.2/bin/raco" make main.rkt

"/Applications/Racket v9.3.0.2/bin/raco" test \
  tests/scene-u-test.rkt \
  tests/scene-u-render-test.rkt
```
