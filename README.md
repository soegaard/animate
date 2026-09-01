# animate — SCENE-AX

> **Work in progress:** this project is under active development and its API may change.

This repository is the dependency-driven derived-geometry stage of a Manim-like
animation system for Racket, with optional Rhombus examples.

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

The context now exposes scalar and top-level Visual presence/lookup operations.
Nested group children remain internal to their group and are not dependency
lookup targets. Direct animation of a derived Visual itself is still rejected;
animate its scalar sources or the ordinary Visuals it depends on instead.

SCENE-AX v0.50.0 is based on the green SCENE-AW v0.49.0 baseline. Version
`0.50.1` corrects moving plain-text rendering without changing the public API.

The public package version is `0.50.1`. The public module exports `454` bindings,
all covered by the Scribble reference.

## Documentation source

The complete Scribble reference source remains in
[`scribblings/animate.scrbl`](scribblings/animate.scrbl), but
it is deliberately not registered with Racket's documentation system. Installing
this package therefore does not build or hook up documentation.

Install the package from a checkout:

```sh
raco pkg install --auto --name animate --link "$(pwd)"
```

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

### Axes-local geometry and transform snapshots

`sample-function-path` returns path geometry in the untransformed local axes
coordinates. `function-graph` wraps that geometry in a path Visual whose
translation, rotation, and scale copy the axes transform at construction time.
The axes and graph are independent immutable values afterward.

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

Part names are local to one formula assembly. They are not top-level scene
identities and are not direct `scene-play` targets. formula-part transformations update them
collectively through the containing assembly and a checked correspondence. Two
different assemblies may use the same local names.

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
exact ordered part list replaces the current source part list, but these outer
destination fields are not copied:

```text
top-level identity
reference position
rotation
scale
opacity
```

The current source assembly keeps those fields. A simultaneous `move-to`,
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
from zero.

At an interior sample, layer order is:

1. source-only layers in source part order;
2. matched layers in explicit correspondence order;
3. destination-only layers in destination part order.

A changed matched pair contributes its source layer immediately followed by its
destination layer. Interior layers use deterministic temporary local symbols
beginning with `__formula-transition-`. They are visible in sampled interior
states, but they are not stable endpoint names and should not be used in later
correspondences. Exact destination names are restored at completion.

### Endpoints, easing, and conflicts

Progress zero uses the exact current source part list. Ordinary interior samples
use the shared eased progress. Structural completion installs the exact
destination part list even when an unusual easing procedure does not return one
at the end. Such easing can therefore create a deliberate discontinuity at the
clip boundary.

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

Nested group children are still not direct scene-state lookup or timeline
targets. Animate their top-level group, or place the child at the top level when
it needs an independent target.

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

## Current limitations

This prototype still does not provide:

- multiple text lines, wrapping, paragraphs, or rich spans;
- baseline alignment between separate text or formula Visuals;
- tight visible-ink bounds distinct from symmetric renderer boxes;
- constraints, wrapping, dynamic reflow, or responsive layout;
- automatic TeX tokenization or character-level identities;
- automatic spacing or layout of independently typeset formula parts;
- direct animation of a nested formula part or group child;
- automatic name, token, or glyph matching between formula parts;
- glyph-outline morphing between changed formula parts;
- formula coloring outside explicit LaTeX source and preamble commands;
- non-uniform group scale, shear, reflection, or arbitrary affine matrices;
- a motion route that deforms dynamically while its path Visual is animated in
  the same clip, exact cubic-source offset curves, offset self-intersection
  cleanup, or curvature-aware banking;
- discontinuous multi-subpath motion traversal; `move-along-path` deliberately
  requires one positive-length continuous subpath;
- semantic hole/topology inference, direct open-to-closed correspondence,
  appearance-aware matching, arbitrary per-pair scoring callbacks beyond
  SCENE-AM numeric additive pair penalties, or general global geometric path
  optimization beyond topology-class assignment;
- quadratic Bézier or arc segment types;
- direct endpoint animation or `Create`/`Uncreate` support for arrow and axes
  Visuals;
- logarithmic axes;
- adaptive error-controlled sampling, per-point style tables, error bars,
  filled areas between two curves, or pixel-fixed marker sizes;
- camera rotation, animated pixel dimensions, or animated background styles;
- persistent camera-follow state across clips, continuously recomputed fit while
  target geometry changes, asymmetric safe areas, or multiple simultaneous views;
- anchor presets such as frame corners/edges, automatic overlay collision
  avoidance, responsive wrapping, curved or arrow-headed callout leaders, or
  callout attachment to nested child geometry rather than a top-level reference
  position;
- mixing frame-space wrappers directly inside ordinary world-space groups;
- timed camera requests, nested timed wrappers, explicit trailing holds inside
  a timed child span, or timeline-relative scheduling across separate play clips;
- three-dimensional scenes;
- a browser editor.



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
  tests/scene-ax-text-raster-test.rkt
```

## SCENE-AW: pure derived Visuals

Version `0.49.0` adds pure top-level Visual definitions driven by immutable
sampled scalar values.

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

SCENE-AW introduced scalar-only `derived-context?` lookup through
`derived-context-value-has?` and `derived-context-value-ref`. SCENE-AX extends
that same context with resolved top-level Visual lookup. Resolvers remain pure,
return a non-derived Visual, and preserve the template top-level ID. Concrete
results are never persisted into scene state, so arbitrary-time and repeated-
frame sampling remain deterministic when the resolver is pure.

Direct animation requests targeting a derived Visual are rejected. Animate the
named scalar inputs with `value-to`; the derived Visual reflects those values at
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
