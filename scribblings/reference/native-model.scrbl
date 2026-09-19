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

@title[#:tag "model" #:style 'toc]{Native model details}

This chapter collects precise meanings and restrictions for reference.
For a gradual introduction, start with @secref["guide-getting-started"].

@declare-exporting[animate #:use-sources (animate/main)]

This section explains the terms used throughout the reference.

@section[#:tag "ref-native-model-s01"]{World Coordinates}

A scene uses mathematical coordinates. Positive x points right. Positive y
points up. A @deftech{camera} converts these world coordinates to pixels, where
positive y points down.

Lengths in ordinary Visual values are normally measured in world units. Camera
width and height are measured in pixels. Rotation is measured in
counter-clockwise radians.

A frame-space Visual uses @deftech{frame space}, an origin-centered
mathematical coordinate system attached to the output frame. Positive x points
right and positive y points up. The frame-space wrapper captures its visible
width when it is constructed, so later world-camera pan and zoom do not move or
resize the overlay. Rendering uses the current output pixel width and height,
so the same frame-space coordinates scale with the output resolution.

@section[#:tag "ref-native-model-s02"]{Visuals and Identity}

A @deftech{Visual} is semantic model data. It is not a Pict. Every Visual has a
stable symbol identity and a reference position. A Visual may also implement
the affine-Visual protocol for rotation and scaling and the opacity-Visual
protocol for global opacity. A group is a Visual whose ordered children are
other affine Visuals.

Identity is explicit:

@racketblock[
(circle #:id 'moving-circle)
]

Two top-level Visuals with the same identity cannot be present in one scene
state. Immutable updates must preserve identity. A group's direct children must
have distinct identities and no descendant may reuse that group's identity. The
same local child identity may occur in separate branches, since complete nested
paths remain distinct. A custom affine Visual is treated as one leaf.

Built-in group and formula children are addressable with a nonempty nested
Visual path such as @racket['(equation numerator)] or
@racket['(A row-1 col-2)]. Formula-part names form a local namespace inside one
formula assembly; a formula-part transformation still targets the containing
top-level assembly and updates its parts collectively.

@section[#:tag "ref-native-model-s03"]{Text and Formulas}

A @deftech{plain-text Visual} stores one line of Unicode text together with
font, color, alignment, transform, and opacity data. The string is copied into
immutable model storage. Plain-text model values do not contain a Pict,
@racket[font%] object, drawing context, or platform font handle.

A @deftech{formula Visual} stores a LaTeX mathematical snippet together with
its display mode, semantic font size, preamble, ordered typesetting options,
alignment, transform, and opacity. Formula source and option strings are also
copied into immutable model storage. A formula model value does not contain a
Pict, PDF page, Poppler value, cached TeX result, or running process.

Font and formula sizes are measured in local world units. Horizontal and
vertical alignment select the point of the untransformed text or formula box
that lies at the Visual's reference position. Alignment is resolved first;
scale and rotation are then applied around that anchor. Both kinds of Visual
can be top-level scene values or ordinary affine children of a group.

Plain text supports one line only. Carriage returns and newline characters are
rejected. Formula source may contain line breaks because they can be meaningful
to LaTeX. An empty plain-text or formula string is valid and produces stable
transparent local geometry.

Formula rendering is a separate adapter effect. A nonempty formula requires
@racketmodname[latex-pict], LaTeX, and Poppler when it is converted to a Pict.

A @deftech{formula assembly} stores explicitly named formula parts in
back-to-front order. An ordinary assembly uses independently typeset formula
Visuals at caller-selected local positions. A @deftech{tagged formula} instead
typesets all author-declared fragments in one TeX document and records each
fragment as an SVG group at its TeX-determined local position. A
@deftech{formula correspondence} records an explicit one-to-one list of source
and destination-part names. The @racket[transform-formula-parts] request
compiles it against the current source assembly and produces deterministic
moving and fading layers.

@section[#:tag "ref-native-model-s04"]{Paths}

A @deftech{path} is local semantic geometry. It contains ordered subpaths, and
each subpath contains a start point followed by ordered line or cubic Bézier
segments. Subpaths may be open or closed. A line segment stores its endpoint.
A cubic segment stores two control points and its endpoint; its start is the
previous point in the subpath.

Traversal order is also reveal order. Path length is measured in local world
units. A closed subpath includes its implicit straight edge back to its start.
Line length is computed directly from its endpoints. Cubic length is a
deterministic approximation. Partial geometry selects an interval of the total
ordered arc length and preserves cubic segments as cubic segments.

Path geometry does not contain world translation, Pict values, drawing
contexts, or pixels. A path Visual combines local path geometry with an affine
transform and style. @racket[morph-to] interpolates paths that already have
corresponding structure. @racket[morph-to-normalized] first applies the limited
cubic normalization described by @racket[path-geometry-normalize-for-morph].
@racket[morph-to-aligned] additionally selects closed-loop phase/direction before
that normalization. @racket[morph-to-open-aligned] selects the endpoint direction
for one open source/destination pair before normalization.
@racket[morph-to-open-compound-aligned] globally pairs equal-count open subpaths
and selects endpoint direction independently within each pair.
@racket[morph-to-mixed-compound-aligned] partitions compound correspondence by
open/closed topology, globally pairs within each class, and then restores source
subpath order before normalization. @racket[morph-to-topology-changing] extends
that correspondence with deterministic births/deaths when topology-class subpath
counts differ. Birth and death seeds default to bounds centers; explicit
shared local anchor points are also supported. Optional finite birth and death
costs allow a poor real correspondence to be replaced by local collapse and
regrowth even when topology counts match. Sparse per-subpath overrides select
birth and death anchors and numeric costs using the original endpoint subpath
indexes. Sparse additive real-match penalties use original source/destination
index pairs.
@racket[morph-to-compound-aligned] first globally pairs
equal-count closed subpaths and applies the same loop alignment within every
pair. @racket[create] and @racket[uncreate] animate semantic partial paths. None of
these operations animate a finished Pict.

@racket[transform-shape] is the higher-level replacement operation for ordinary
diagram shapes. It changes a present top-level Visual into a fresh destination
Visual. Atomic built-in paths, circles, and rectangles use automatic outline
correspondence; groups and other endpoint types use an intentional cross-fade
fallback rather than claiming a contour correspondence they do not have.

@racket[transform-matching-visuals] extends that operation over the leaves of
ordinary group trees. It first honors explicit relative paths, then searches
stable leaf paths and conservative built-in shape correspondence. Formula and
glyph transitions retain their more specialized tagged-TeX matching API.

@section[#:tag "ref-native-model-s05"]{Arrows and Cartesian Axes}

An @deftech{arrow Visual} stores one ordered shaft from a start point to an end
point. The untransformed midpoint is its reference position. Optional triangular
tips can be attached independently to the start and end. Tip dimensions are
local world-unit geometry. Stroke width is cosmetic output style.

An @deftech{axis range} stores a minimum, maximum, and regular positive tick
step. The range must contain zero because the built-in Cartesian axes cross at
numeric coordinate @tt{(0, 0)}. Tick values are ordered nonzero multiples of
the step that lie in the closed range.

An @deftech{axes Visual} maps the complete numeric x and y ranges to explicit
local x and y lengths. It contains two shafts, regular ticks, and optional tips
at the maximum x and y endpoints. Numeric coordinates can be converted to
points in the axes' containing coordinate system and converted back again. The
conversion includes the axes' translation, rotation, and positive scale.

Arrows and axes are pure semantic values. Their model modules do not contain
Picts, drawing paths, drawing contexts, pixels, or text labels. The built-in
adapter derives ordinary path geometry when rendering them.

@section[#:tag "ref-native-model-s06"]{Sampled Function Graphs}

A @deftech{sampled function graph} is ordinary semantic path geometry produced
from a one-variable numeric procedure and an axes Visual. Sampling happens once
when @racket[sample-function-path] or @racket[function-graph] is called. The
returned value does not retain the procedure.

Finite real results become ordered samples. @racket[#f], positive infinity,
negative infinity, and NaN create explicit breaks. An optional maximum y jump
can reject a connection between two finite samples. Accepted segments are
clipped to the displayed axes rectangle by default.

Function graphs use explicit @racket['linear] or @racket['smooth]
interpolation. Linear remains the default. Smooth interpolation converts every
accepted run to semantic cubic Bézier segments derived from uniform Catmull-Rom
tangents. Clipping happens before interpolation, and smooth controls are clamped
to the axes rectangle when clipping is enabled.

A graph Visual copies the axes translation, rotation, and scale at construction
time. It is an ordinary path Visual and therefore uses the existing path
renderer, opacity protocol, group composition, @racket[create],
@racket[uncreate], and affine animation requests.

@section[#:tag "ref-native-model-s07"]{Parametric Curves and Data Plots}

A @deftech{parameter range} stores an ordered start and end value. The values
may increase or decrease. Parametric sampling includes both endpoints and calls
a one-argument procedure in that order. Each call returns one @racket[vec2] or
@racket[#f]. A coordinate becomes one sample; @racket[#f] creates a gap.

An @deftech{ordered data series} is a proper list of @racket[vec2] values and
@racket[#f] gaps. List order is traversal order. The library does not sort the
points by x, infer time order, or remove repeated coordinates.

Parametric and data plots can reject adjacent samples farther apart than an
explicit Euclidean distance in numeric-coordinate units. They share the same
segment clipping, run construction, and linear or smooth interpolation rules
as function graphs. Empty input, one isolated point, or an isolated finite
sample creates no drawn segment.

@racket[parametric-curve] and @racket[data-plot] return ordinary path Visuals
whose transforms are construction-time snapshots of their axes. The sampling
procedure and input point list are not stored.


@section[#:tag "ref-native-model-s08"]{Point Markers, Scatter Plots, and Filled Areas}

A @deftech{point-marker Visual} stores one closed marker shape, local size,
fill, stroke, affine transform, and opacity. A @deftech{scatter plot} is an
ordered semantic group of such markers placed from numeric coordinates in an
axes snapshot. Marker identities are deterministic and include the original
input index. Gaps and clipped points are omitted without renumbering later
markers.

A @deftech{filled coordinate area} is ordinary closed path geometry derived
from accepted function-graph or ordered-data runs. Each visible run is closed
to one horizontal numeric baseline. Discontinuous runs remain separate. Smooth
interpolation keeps cubic graph segments rather than flattening them. Area
Visuals store only geometry, style, transform, and opacity; they do not retain
the sampling procedure or source list.

@section[#:tag "ref-native-model-s09"]{Scene States and Scenes}

A @deftech{scene state} is one complete snapshot of the top-level Visuals in a
scene. It stores both an identity lookup table and a significant drawing
order. Drawing order is back to front: later Visuals are painted over earlier
Visuals. A group occupies one top-level entry; its children keep a separate
back-to-front order inside the group.

A @deftech{scene} is an immutable timeline. A scene contains chronological
play and wait clips. Each play clip stores its complete starting state and
compiled animation endpoints. Sampling one frame does not depend on sampling
any earlier frame.

@section[#:tag "ref-native-model-s10"]{Transforms}

An @racket[affine-transform] value stores translation, rotation, and scale. Components are
applied in this fixed order:

@centered{@bold{scale, then rotate, then translate}}

Scale is stored as positive x and y factors. Separate @racket[linear2] and
@racket[affine2] values represent a full matrix and translation.
@racket[apply-affine] and @racket[apply-matrix] map a world Visual through
those values. These operations also accept ordinary nested paths: a named
child can be mapped inside an already-mapped group without flattening the
group. Visual implementations use the decomposed affine-Visual protocol; the
general-map wrapper carries full maps through a nested group tree.

A group may be translated and rotated normally, but its own scale must be
uniform. A uniform parent scale and rotation compose exactly with each child's
existing decomposed transform. Allowing a non-uniform parent scale followed by
a rotated child can create shear, which the decomposed transform model cannot
represent. Use @racket[apply-affine] on the complete top-level group when that
is the intended mathematical operation.

@section[#:tag "ref-native-model-s11"]{Groups}

A @deftech{group} is a semantic composite Visual. Its child list is stored in
significant back-to-front order. Child positions are local to the group anchor.
A child can itself be a group, so transforms can be nested.

During rendering, the group rotation and uniform scale are inherited by each
child. The group translation places the complete composite in its parent
coordinate system. Child opacity is applied to each child, and group opacity
is applied to the complete composed result. Thus, opacity values multiply
through nested groups.

Groups contain model values only. They do not contain Picts or renderer
callbacks. The Pict adapter composes their children recursively and passes the
same explicit renderer list to every descendant.

@section[#:tag "ref-native-model-s12"]{Relative Layout}

Relative layout is an adapter-level calculation. It renders a Visual with an
explicit camera and renderer list, converts the resulting Pict dimensions back
to world units, and returns immutable position updates. It is not stored in a
scene, group, formula assembly, or Visual model value.

A layout box is the complete symmetric Pict box around a Visual's reference
position. It includes transparent padding and anchor padding; it is not a tight
outline of visible ink. Layout must use the same camera and renderer list as the
final rendering when exact spacing matters.

@section[#:tag "ref-native-model-s13"]{Opacity}

Global opacity is semantic model data in the closed interval from zero through
one. Zero means completely transparent. One means fully opaque. Intermediate
values multiply the complete rendered Visual, including fill and stroke.

Opacity is applied after Pict renderer selection. It does not change a Visual's
geometry, identity, drawing order, Pict bounds, or reference position. A
zero-opacity Visual remains in the scene state until an operation removes it.

@section[#:tag "ref-native-model-s14"]{Time and Frames}

Scene time is measured in seconds. Exact rational times work and are useful in
tests. For a scene duration @italic{D} and frame rate @italic{fps}, the frame
count is:

@centered{@tt{ceiling(D * fps)}}

Frame @italic{n} samples the scene at exact time @italic{n/fps}. The exact scene
endpoint is not normally a frame sample. Add a wait clip when the final state
must remain visible.
