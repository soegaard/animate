#lang scribble/manual

@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     "../main.rkt"))

@title[#:tag "animate"]{Visual Animation}

@defmodule[animate]

Visual Animation is a small, immutable animation library for Racket. It is an early step toward a Manim-like system. The library keeps
semantic scene data separate from Pict rendering and file output.

The public API in this manual is version @tt{0.86.0}. This is still a
prototype, so later versions may change names or behavior.

@table-of-contents[]

@section[#:tag "package-source"]{Source Package Hygiene}

The package is distributed as source. Create a clean source archive from a
checkout with @tt{raco pkg create --source .}. Its @filepath{info.rkt}
configuration omits local @filepath{tmp} experiments, generated rendered videos,
compiled artifacts, and Finder metadata. The optional Rhombus examples remain
in the source archive for reference, but @tt{compile-omit-paths} keeps them
out of normal Racket compilation. This manual is source-only: the package does
not register or build it automatically during installation.

@section[#:tag "quick-start"]{Quick Start}

The following program builds Cartesian axes, samples a coordinate-valued
parametric procedure, plots one ordered data series, and animates the camera at
the same time. Both curves use smooth cubic interpolation and the ordinary path
@racket[create] animation.

@racketmod[
racket/base

(require animate)

(define coordinate-axes
  (axes #:id 'coordinate-axes
        #:x-range (axis-range -4 4 1)
        #:y-range (axis-range -3 3 1)
        #:x-length 8
        #:y-length 6
        #:stroke "navy"))

(define loop-curve
  (parametric-curve
   coordinate-axes
   (lambda (parameter)
     (define x
       (- (* parameter parameter) 2))
     (vec2 x (/ (* parameter x) 2)))
   #:id 'loop-curve
   #:parameter-range (parameter-range -2 2)
   #:sample-count 181
   #:interpolation 'smooth
   #:stroke "crimson"))

(define observations
  (data-plot
   coordinate-axes
   (list (vec2 -3 -3/2)
         (vec2 -2 1/2)
         (vec2 -1 1)
         (vec2 0 1/4)
         (vec2 1 -1)
         (vec2 2 -1/2)
         (vec2 3 3/2))
   #:id 'observations
   #:interpolation 'smooth
   #:stroke "seagreen"))

(define initial-camera
  (make-camera #:world-width 14
               #:center origin))

(define animation
  (scene-wait
   (scene-play (make-scene #:camera initial-camera)
               (fade-in coordinate-axes)
               (create loop-curve)
               (create observations)
               (camera-pan-to (vec2 1 0))
               (camera-zoom-by 3/2)
               #:duration 2)
   1/2))

(render-frames! animation "frames" #:fps 30)
]

@racket[parametric-curve] calls the procedure while constructing the Visual.
It stores only immutable path geometry and a snapshot of the axes transform.
Rendering later frames does not call the procedure or read the original data
list again. The camera center and visible width are sampled from the same scene
clip as the Visual animations.

The call to @racket[render-frames!] creates numbered PNG files. To assemble them
as an MP4 file, install FFmpeg and call:

@racketblock[
(encode-mp4! "frames" "animation.mp4" #:fps 30)
]

@section[#:tag "model"]{The Model}

This section explains the terms used throughout the reference.

@subsection{World Coordinates}

A scene uses mathematical coordinates. Positive x points right. Positive y
points up. A @deftech{camera} converts these world coordinates to pixels, where
positive y points down.

Lengths in ordinary Visual values are normally measured in world units. Camera
width and height are measured in pixels. Rotation is measured in
counter-clockwise radians.

SCENE-X also has @deftech{frame space}. A frame-space Visual uses an
origin-centered mathematical coordinate system attached to the output frame.
Positive x still points right and positive y still points up. Its visible width
is captured when the frame-space wrapper is constructed, so later world-camera
pan and zoom do not move or resize the overlay. The current output pixel width
and height are still used when rendering, allowing the same semantic frame
coordinates to scale with output resolution.

@subsection{Visuals and Identity}

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
state. Immutable updates must preserve identity. A group also requires every
identity exposed through its nested built-in groups to be unique and different
from the group identity. A custom affine Visual is treated as one leaf. Nested
child identities are semantic identities, but they are not direct scene-state
lookup or animation targets in this version. Formula-part names form a separate
local namespace inside one formula assembly. Address one with a nonempty nested
Visual path such as @racket['(equation numerator)] for lookup or compatible
animation. A formula-part transformation still targets the containing top-level
assembly and updates its parts collectively.

@subsection{Text and Formulas}

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

@subsection{Paths}

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
counts differ. SCENE-AI keeps bounds-center seeds as the default and also permits
explicit shared local birth/death anchor points. SCENE-AJ optionally assigns
finite birth/death costs so a poor real correspondence may be replaced by local
collapse and regrowth even when topology counts match. SCENE-AK adds sparse
per-subpath birth/death anchor overrides keyed by original endpoint subpath
indexes. SCENE-AL adds sparse per-subpath numeric birth/death cost overrides
using those same original endpoint indexes. SCENE-AM adds sparse additive
real-match penalties keyed by original source/destination index pairs.
@racket[morph-to-compound-aligned] first globally pairs
equal-count closed subpaths and applies the same loop alignment within every
pair. @racket[create] and @racket[uncreate] animate semantic partial paths. None of
these operations animate a finished Pict.

@racket[transform-shape] is the higher-level replacement operation for ordinary
diagram shapes. It changes a present top-level Visual into a fresh destination
Visual. Atomic built-in paths, circles, and rectangles use automatic outline
correspondence; groups and other endpoint types use an intentional cross-fade
fallback rather than claiming a contour correspondence they do not have.

@subsection{Arrows and Cartesian Axes}

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

@subsection{Sampled Function Graphs}

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

@subsection{Parametric Curves and Data Plots}

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


@subsection{Point Markers, Scatter Plots, and Filled Areas}

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

@subsection{Scene States and Scenes}

A @deftech{scene state} is one complete snapshot of the top-level Visuals in a
scene. It stores both an identity lookup table and a significant drawing
order. Drawing order is back to front: later Visuals are painted over earlier
Visuals. A group occupies one top-level entry; its children keep a separate
back-to-front order inside the group.

A @deftech{scene} is an immutable timeline. A scene contains chronological
play and wait clips. Each play clip stores its complete starting state and
compiled animation endpoints. Sampling one frame does not depend on sampling
any earlier frame.

@subsection{Transforms}

An affine transform stores translation, rotation, and scale. Components are
applied in this fixed order:

@centered{@bold{scale, then rotate, then translate}}

Scale is stored as positive x and y factors. Shear, reflection, and arbitrary
affine matrices are not supported by this version.

A group may be translated and rotated normally, but its own scale must be
uniform. A uniform parent scale and rotation compose exactly with each child's
existing decomposed transform. Allowing a non-uniform parent scale followed by
a rotated child can create shear, which this transform model cannot represent.

@subsection{Groups}

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

@subsection{Relative Layout}

Relative layout is an adapter-level calculation. It renders a Visual with an
explicit camera and renderer list, converts the resulting Pict dimensions back
to world units, and returns immutable position updates. It is not stored in a
scene, group, formula assembly, or Visual model value.

A layout box is the complete symmetric Pict box around a Visual's reference
position. It includes transparent padding and anchor padding; it is not a tight
outline of visible ink. Layout must use the same camera and renderer list as the
final rendering when exact spacing matters.

@subsection{Opacity}

Global opacity is semantic model data in the closed interval from zero through
one. Zero means completely transparent. One means fully opaque. Intermediate
values multiply the complete rendered Visual, including fill and stroke.

Opacity is applied after Pict renderer selection. It does not change a Visual's
geometry, identity, drawing order, Pict bounds, or reference position. A
zero-opacity Visual remains in the scene state until an operation removes it.

@subsection{Time and Frames}

Scene time is measured in seconds. Exact rational times work and are useful in
tests. For a scene duration @italic{D} and frame rate @italic{fps}, the frame
count is:

@centered{@tt{ceiling(D * fps)}}

Frame @italic{n} samples the scene at exact time @italic{n/fps}. The exact scene
endpoint is not normally a frame sample. Add a wait clip when the final state
must remain visible.

@section[#:tag "geometry"]{Geometry}

@defstruct*[vec2 ([x finite-real?]
                  [y finite-real?])
  #:transparent]{

Represents either a point or a displacement in two-dimensional world
coordinates.

The constructor checks both fields. Infinite values and NaN values are
rejected. The structure is immutable and transparent. The public bindings
created for this structure include @racket[vec2], @racket[vec2?],
@racket[vec2-x], and @racket[vec2-y].
}

@defproc[(finite-real? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real number. Exact and
inexact finite real numbers are accepted. Complex numbers, infinities, and NaN
values are rejected.
}

@defthing[origin vec2? #:value (vec2 0 0)]{

The origin of world coordinates.
}

@defproc[(real-lerp [from finite-real?]
                    [to finite-real?]
                    [progress finite-real?])
         finite-real?]{

Returns the linear interpolation
@racket[(+ from (* progress (- to from)))]. A progress value of @racket[0]
returns @racket[from], and a progress value of @racket[1] returns @racket[to].
Values outside the unit interval perform linear extrapolation.
}

@defproc[(interpolable? [value any/c]) boolean?]{

Returns @racket[#t] for a semantic scene value that supports
@racket[interpolate-value]. In this version, finite real numbers,
@racket[vec2] coordinates, and @racket[rgba-color] values are interpolable.
}

@defproc[(interpolate-value [from any/c]
                            [to any/c]
                            [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         any/c]{

Interpolates two values of the same interpolable semantic kind over the closed
unit interval. A progress of @racket[0] returns the original @racket[from]
value and a progress of @racket[1] returns the original @racket[to] value.
Mixed kinds and noninterpolable values raise an exception.
}

@subsection{Scene Parameters}

@defproc[(parameter [id symbol?] [initial-value any/c]) scene-parameter?]{

Creates an immutable declaration for one named interpolable scene value. This
is a scene-timeline convenience handle, not a Racket dynamic parameter. Its
identity and initial value are immutable, and it has no mutable current value.
Pass it to @racket[scene-set-value] to install its initial value or wherever a
scene-value API accepts an ID.
}

@defproc[(scene-parameter? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a scene parameter declaration.
}

@defproc[(parameter-id [value scene-parameter?]) symbol?]{
Returns the stable named scene-value identity carried by @racket[value].
}

@defproc[(parameter-initial-value [value scene-parameter?]) any/c]{
Returns the interpolable initial semantic value carried by @racket[value].
}

@defproc[(vec2+ [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise sum of @racket[a] and @racket[b].
}

@defproc[(vec2- [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise difference @racket[a] minus @racket[b].
}

@defproc[(vec2-scale [scalar finite-real?] [value vec2?]) vec2?]{

Multiplies both components of @racket[value] by @racket[scalar].
}

@defproc[(vec2* [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise product of @racket[a] and @racket[b]. This operation
is used for non-uniform scale factors.
}

@defproc[(vec2-lerp [from vec2?]
                    [to vec2?]
                    [progress finite-real?])
         vec2?]{

Interpolates the x and y components independently. Like @racket[real-lerp],
this procedure permits extrapolation when @racket[progress] is outside the
unit interval.
}

@section[#:tag "path-geometry"]{Path Geometry}

Path geometry describes outlines and filled regions without using Pict. It
supports straight line segments and cubic Bézier segments. Both kinds are
semantic model values. They do not contain drawing-context commands or a
rendered approximation.

A path may contain several subpaths. Subpath order is significant. Within each
subpath, the start point comes first and segments follow in traversal order.
Each segment begins where the preceding segment ended. A closed subpath
reconnects its final endpoint to its start when it is rendered and measured.
That implicit closing edge is straight.

Length, partial extraction, and morphing use local coordinates before a
Visual's scale, rotation, or translation is applied. Compound paths traverse
one subpath fully before continuing with the next one. Morphing pairs subpaths
and segments by their stored order; it does not reorder them automatically.

@defstruct*[line-path-segment ([end vec2?])
  #:transparent]{

Represents one straight segment. The segment starts at the previous point in
its containing @racket[path-subpath] and ends at @racket[end].

The structure is immutable and transparent. Its public bindings include
@racket[line-path-segment], @racket[line-path-segment?],
@racket[line-path-segment-end], and @racket[struct:line-path-segment].
}

@defstruct*[cubic-bezier-path-segment ([control1 vec2?]
                                       [control2 vec2?]
                                       [end vec2?])
  #:transparent]{

Represents one cubic Bézier segment. The segment start is the previous point
in its containing @racket[path-subpath]. The structure therefore stores only
the two control points and the endpoint.

The curve starts in the direction from its start toward @racket[control1]. It
approaches @racket[end] from the direction of @racket[control2]. Control points
usually do not lie on the visible curve. They may lie outside the curve's
actual bounds.

The structure is immutable and transparent. Its public bindings include
@racket[cubic-bezier-path-segment],
@racket[cubic-bezier-path-segment?], the three field accessors, and
@racket[struct:cubic-bezier-path-segment].
}

@defproc[(path-segment? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a supported semantic path segment.
The supported values are @racket[line-path-segment] and
@racket[cubic-bezier-path-segment] values.
}

@defstruct*[path-subpath ([start vec2?]
                          [segments (listof path-segment?)]
                          [closed? boolean?])
  #:transparent]{

Represents one connected figure in a path.

The @racket[start] field is the first local point. The @racket[segments] list
contains segment values in significant traversal order. Each segment begins
where the preceding segment ended. An empty segment list represents one point.

When @racket[closed?] is true, rendering reconnects the last endpoint to
@racket[start] with an implicit straight edge. The edge is not stored as an
extra segment. It participates in bounds, length, partial extraction, and
rendering. A closed subpath can be filled. An open subpath is only stroked by
the built-in Pict renderer.

The structure is immutable and transparent. Its public bindings include its
constructor, predicate, three field accessors, and structure descriptor.
}

@defstruct*[path-geometry ([subpaths (listof path-subpath?)])
  #:transparent]{

Represents zero or more subpaths. Subpath order is significant for traversal,
creation, morphing, and filling. The built-in renderer combines all closed
subpaths with the odd-even fill rule, so an inner closed subpath can form a
hole.

An empty list is valid and represents geometry that draws nothing. The
structure is immutable and transparent. Its public bindings include its
constructor, predicate, field accessor, and structure descriptor.
}

@defthing[empty-path-geometry path-geometry?]{

A path-geometry value containing no subpaths. It is the semantic invisible
geometry used at the beginning of @racket[create] and at the visible end of
@racket[uncreate]. It is not a blank Pict.
}

@defproc[(path-geometry-empty? [geometry path-geometry?]) boolean?]{

Returns @racket[#t] when @racket[geometry] contains no subpaths. A geometry
value containing a point-only subpath is not empty.
}

@defproc[(path-subpath-points [subpath path-subpath?])
         (listof vec2?)]{

Returns @racket[subpath]'s start point followed by every segment endpoint. The
returned list is in significant traversal order. Cubic control points are not
included; use the cubic segment accessors to obtain them. The implicit closing
edge of a closed subpath does not repeat the start point at the end.
}

@defproc[(path-geometry-subpath-points [geometry path-geometry?])
         (listof (listof vec2?))]{

Returns one traversal-ordered start-and-endpoint list for each subpath. The
outer list preserves subpath order. Cubic control points are omitted in the
same way as by @racket[path-subpath-points].
}

@defproc[(path-geometry-map-points
          [geometry path-geometry?]
          [transform-point (procedure-arity-includes/c 1)])
         path-geometry?]{

Calls @racket[transform-point] once for every stored point and returns new path
geometry with the same subpath, segment, and closure structure. Stored points
include each subpath start, every line endpoint, and every cubic control point
and endpoint. The procedure must return a @racket[vec2] for every input point.
The original geometry is not changed.

This operation transforms local geometry only. It does not change a Visual's
reference position, rotation, or scale.
}

@defproc[(path-geometry-translate [geometry path-geometry?]
                                  [displacement vec2?])
         path-geometry?]{

Returns new geometry with @racket[displacement] added to every stored local
point. Segment kinds, subpath order, and closure are preserved.
}

@defproc[(path-geometry-reverse [geometry path-geometry?])
         path-geometry?]{

Returns path geometry with every subpath traversed in the opposite direction.
Subpath order is preserved. Line segments reverse their endpoints. Cubic
Bézier segments reverse their endpoints and exchange their first and second
control points, preserving the exact traced curve.

For an open subpath, the former final endpoint becomes the new start. For a
closed subpath, the original stored start is preserved so the loop changes
direction without also changing phase. When the original implicit closing line
has positive length, that line is materialized as the first explicit reversed
segment; the resulting synthetic closing edge is then zero length. This
representation detail can change segment count, but it does not change the
visible or measured loop.

For a positive finite closed loop, point lookup on the reversed result follows
the original loop at fraction @racket[(- 1 fraction)] (subject to the same
deterministic cubic arc-length approximation as @racket[path-geometry-point-at]).
Tangent direction is reversed correspondingly away from corner one-sided
boundaries.

The operation is purely semantic and does not apply a containing Visual
transform. Empty geometry and zero-length subpaths are valid.
}

@defproc[(path-geometry->cubic [geometry path-geometry?])
         path-geometry?]{

Converts every stored line segment in @racket[geometry] to an exactly
equivalent cubic Bézier segment. A line from @racket[start] to @racket[end]
becomes a cubic with these control points:

@racketblock[
(vec2-lerp start end 1/3)
(vec2-lerp start end 2/3)
]

The resulting cubic traces the same straight line in the same direction. An
existing cubic segment is kept unchanged. Subpath starts, subpath order,
segment order, endpoints, and closure values are preserved. Point-only
subpaths and empty geometry are valid.

Only stored line segments are converted. The implicit straight closing edge of
a closed subpath remains implicit and is not added to the segment list.

When @racket[geometry] already contains no stored line segments, the procedure
returns @racket[geometry] itself. Otherwise it returns new immutable geometry.
}

@defproc[(path-geometry-morph-normalizable?
          [from path-geometry?]
          [to path-geometry?])
         boolean?]{

Returns @racket[#t] when @racket[from] and @racket[to] can be made strictly
morph-compatible by the limited normalization performed by
@racket[path-geometry-normalize-for-morph].

The paths are normalizable when all of the following hold:

@itemlist[
 @item{They contain the same number of subpaths.}
 @item{Corresponding subpaths have the same closure value.}
 @item{Each pair of corresponding subpaths is either point-only on both sides
       or contains at least one stored segment on both sides.}
]

Stored segment counts and line-versus-cubic kinds may differ. Coordinates and
path lengths do not affect this predicate. The predicate does not change either
path.
}

@defproc[(path-geometry-align-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] with an automatically selected closed-loop cyclic
start and, when @racket[allow-reverse?] is true, traversal direction that gives
a low-distance geometric correspondence to @racket[source]. Both arguments
must contain exactly one positive-length finite closed subpath.

Correspondence is measured in total-arc-length coordinates. The procedure
samples @racket[source] at @racket[sample-count] evenly spaced fractions, scores
candidate destination phases by mean Euclidean point distance, and chooses the
lowest score deterministically. Candidate phases include a uniform full-loop
grid and every stored positive-edge boundary of the destination. A fixed number
of local refinement rounds then improves the best phase. The algorithm does not
depend on frame rate, camera scale, rendering, wall-clock time, or randomness.

When reverse traversal is allowed, the same search is performed on
@racket[(path-geometry-reverse destination)]. An exact score tie prefers the
original forward traversal. Exact phase ties prefer the smaller phase. An
already aligned destination therefore remains unchanged rather than being
reversed or split gratuitously.

The returned value is ordinary semantic path geometry. Use it before
@racket[path-geometry-normalize-for-morph] when a caller wants explicit access
to the chosen correspondence, or use @racket[morph-to-aligned] to perform both
steps during timeline compilation.

This operation deliberately handles one closed loop on each side. It does not
pair multiple subpaths, add or remove subpaths, change closure, solve arbitrary
global shape correspondence, or guarantee a globally optimal continuous phase
for every pathological curve. Increasing @racket[sample-count] makes the fixed
deterministic geometric score finer.
}

@defproc[(path-geometry-align-open-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] with the traversal direction that best matches one
open @racket[source] path. Both paths must contain exactly one open subpath with
positive finite total arc length.

The procedure samples @racket[source] and @racket[destination] at
@racket[sample-count] evenly spaced total-arc-length fractions including both
endpoints and scores mean Euclidean point distance. When
@racket[allow-reverse?] is true, the same score is computed for
@racket[(path-geometry-reverse destination)]. Reverse traversal is selected only
when its score is strictly lower; an exact score tie keeps the caller's stored
forward destination. There is no cyclic phase search for an open path.

When forward traversal wins, the exact @racket[destination] object is returned.
When reverse traversal wins, the returned geometry traces the same destination
from its former endpoint toward its former start. The operation is pure semantic
geometry and does not inspect Visual transforms, renderers, camera state, frame
rate, pixels, or output files.

Use the result before @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-open-aligned] for timeline compilation.
This operation deliberately handles one open subpath on each side; it does not
select cyclic phases, pair compound subpaths, change closure, or add/remove
subpaths.
}

@defproc[(path-geometry-align-open-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns compound @racket[destination] geometry reordered and direction-aligned
so its open subpaths correspond to the open subpaths of @racket[source]. The two
paths must contain the same nonzero number of subpaths, and every subpath must be
open with positive finite arc length.

For every source/destination subpath pair, the procedure uses the SCENE-AE
endpoint-direction score from @racket[path-geometry-align-open-for-morph]: both
paths are sampled at @racket[sample-count] inclusive total-arc-length fractions,
and destination reversal is selected only when its score is strictly lower.
One source subpath's samples are cached while every destination candidate for
that assignment row is evaluated.

After all pair costs are known, the same deterministic minimum-total-cost
assignment policy as SCENE-AD chooses one distinct destination subpath for every
source subpath. Pairing is global rather than greedy. Exact assignment ties use
the deterministic destination-index policy of
@racket[path-geometry-align-compound-for-morph], while exact per-pair direction
ties preserve the caller's stored forward traversal.

The returned value is ordinary immutable @racket[path-geometry] whose subpath
order matches source correspondence. A destination subpath whose stored
direction wins is reused exactly. When pairing and direction alignment change
nothing, the exact @racket[destination] object is returned.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-open-compound-aligned] for timeline
compilation. This specialized operation deliberately requires all subpaths to be open and
counts to match. Use @racket[path-geometry-align-mixed-compound-for-morph] when
matching-count open and closed topology is combined in one compound. Use
@racket[path-geometry-prepare-topology-changing-morph] or
@racket[morph-to-topology-changing] when topology-class counts differ.
}

@defproc[(path-geometry-align-mixed-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] reordered/aligned to the topology and subpath
correspondence of @racket[source]. The paths must be nonempty; every subpath must
have positive finite arc length; source/destination open-subpath counts must
match; and source/destination closed-subpath counts must match.

The procedure partitions both paths by @racket[path-subpath-closed?]. Open
candidates are evaluated with the SCENE-AE endpoint-direction rule used by
@racket[path-geometry-align-open-for-morph]. Closed candidates are evaluated
with the SCENE-AC phase/direction rule used by
@racket[path-geometry-align-for-morph]. The deterministic global assignment
policy is then solved independently inside the open and closed classes. An open
subpath is therefore never paired with a closed loop merely because it is
spatially nearby.

After both assignments, selected destination subpaths are placed in the exact
subpath order of @racket[source]. Each open pair may reverse only for a strictly
lower score; each closed pair may choose cyclic phase and optional reversal under
SCENE-AC's deterministic tie rules. Unchanged destination subpath objects are
reused, and when the entire correspondence is already a no-op the exact
@racket[destination] object is returned.

When one topology class is absent, this operation reduces to the corresponding
SCENE-AF all-open or SCENE-AD all-closed behavior. Use
@racket[path-geometry-prepare-topology-changing-morph] when either topology-class
count differs.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-mixed-compound-aligned] for timeline
compilation.
}

@defproc[(path-geometry-prepare-topology-changing-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64]
          [#:birth-anchor birth-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:death-anchor death-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:birth-anchor-map birth-anchor-map hash? #hash()]
          [#:death-anchor-map death-anchor-map hash? #hash()]
          [#:birth-penalty birth-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:death-penalty death-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:birth-penalty-map birth-penalty-map hash? #hash()]
          [#:death-penalty-map death-penalty-map hash? #hash()]
          [#:match-penalty-map match-penalty-map hash? #hash()])
         (values path-geometry? path-geometry?)]{

Returns two equal-count interior correspondence paths suitable for
@racket[path-geometry-normalize-for-morph] even when @racket[source] and
@racket[destination] contain different numbers of open or closed subpaths. The
first result is the prepared source and the second is the aligned/prepared
destination.

Every real subpath on either side must have positive finite arc length. The
whole source or destination may nevertheless be empty, allowing pure birth from
empty geometry and pure death to empty geometry. Open and closed topology
classes are handled independently and are never paired directly with one
another.

Within each topology class, real open pairs use the SCENE-AE
forward/reverse endpoint score and real closed pairs use the SCENE-AC
phase/direction score. With the default @racket['forced] value for both penalty
keywords, the rectangular assignment pads only the forced class-count difference
with zero-cost dummy slots; matching topology counts therefore reduce exactly to
SCENE-AG as before.

SCENE-AJ adds an optional numeric policy. When both @racket[birth-penalty] and
@racket[death-penalty] are finite nonnegative reals, the procedure solves an
augmented global assignment. A real source/destination edge costs its geometric
correspondence score, a source-to-dummy edge costs @racket[death-penalty], a
dummy-to-destination edge costs @racket[birth-penalty], and unused dummy pairs
cost zero. A poor real pair may therefore be replaced by death plus birth even
when topology counts match. Exact primary-cost ties minimize the number of
birth/death edges as a secondary objective, so equal-cost replacement does not
occur. The two penalty keywords must either both be @racket['forced] or both be
finite nonnegative real numbers. SCENE-AL additionally accepts sparse
@racket[birth-penalty-map] and @racket[death-penalty-map] hashes in numeric mode.
Birth-map keys are exact nonnegative original destination subpath indexes;
death-map keys are exact nonnegative original source subpath indexes. Map values
are finite nonnegative real costs and missing keys fall back to the corresponding
shared numeric penalty. Nonempty penalty maps are rejected in @racket['forced]
mode. The sparse costs replace dummy-edge costs only. SCENE-AM additionally
accepts @racket[match-penalty-map] in both forced and numeric modes. Each key is
@racket[(cons source-index destination-index)] using original caller subpath
indexes, and each finite nonnegative value is added to that real edge's existing
geometric correspondence score. Missing pairs add zero. Pair penalties do not
change topology classes or direction/phase alignment; they bias the global
assignment after those per-edge geometric choices are scored. In numeric mode a
penalized real edge also competes against death plus birth, while AJ's exact-tie
preference for fewer topology changes remains unchanged. Direct preparation
rejects out-of-range pair indexes and keys that name impossible open/closed
correspondence edges. @racket[allow-reverse?] and @racket[sample-count] retain
their existing correspondence meanings.

A destination subpath assigned to a dummy source is a birth. By default its
prepared source is a one-line-segment degenerate subpath at the exact
axis-aligned bounds center of that destination subpath. A source subpath assigned
to a dummy destination is a death and receives the analogous prepared destination
seed at its own bounds center. Each seed preserves the real subpath's
@racket[path-subpath-closed?] value. The controlled seeds have zero arc length;
pre-existing zero-length real subpaths are rejected before assignment.

SCENE-AI extends this placement with @racket[birth-anchor] and
@racket[death-anchor]. Each accepts exactly @racket['bounds-center] or a finite
@racket[vec2]. An explicit point is local path geometry and is shared by every
unmatched subpath on that side. SCENE-AK additionally accepts sparse
@racket[birth-anchor-map] and @racket[death-anchor-map] hashes. Birth-map keys are
exact nonnegative original destination subpath indexes; death-map keys are exact
nonnegative original source subpath indexes. Map values use the same anchor
syntax. A missing key falls back to the corresponding shared anchor, while an
explicit @racket['bounds-center] map value may override a shared @racket[vec2].
Direct preparation rejects out-of-range keys. Anchor selection affects seed
placement only; real-pair scores, direction/phase correspondence, penalties, and
slot ordering are unchanged. In numeric SCENE-AJ penalty mode the selected
assignment may contain additional voluntary unmatched slots, and those slots use
the same original-index map lookup.

All slots corresponding to real source subpaths remain first in exact source
order. Birth-only slots are appended in exact caller destination order. When
open and closed class counts already match under the default forced-only policy,
the operation reduces exactly to
@racket[path-geometry-align-mixed-compound-for-morph], returning the original
@racket[source] as the first value. Numeric penalties may intentionally produce
additional interior slots even when endpoint counts match.

Use the two results with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-topology-changing] for timeline
compilation. This stage does not infer semantic holes, pair an open subpath
directly with a closed loop, use appearance-aware scores, or accept arbitrary
per-pair scoring callbacks beyond SCENE-AM sparse numeric additions.
}

@defproc[(path-geometry-align-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns compound @racket[destination] geometry reordered and aligned so its
closed subpaths correspond to the subpaths of @racket[source]. The two paths
must contain the same nonzero number of subpaths, and every subpath must be
closed with positive finite arc length.

The procedure computes every source/destination pair cost with the SCENE-AC
closed-loop algorithm used by @racket[path-geometry-align-for-morph]. Thus each
candidate pair may choose a cyclic phase and, when @racket[allow-reverse?] is
true, reverse traversal. One source loop's score samples are cached while all
destination candidates for that source are evaluated.

After all pair costs are known, a deterministic minimum-total-cost assignment
selects one distinct destination subpath for every source subpath. Pairing is
global rather than greedy. Exact assignment ties preserve earlier source-row
matches when an equally good free destination exists and then prefer the lower
destination index. Per-pair direction and phase ties retain the SCENE-AC rules.

The returned value is ordinary immutable @racket[path-geometry] whose subpath
order matches source correspondence. When pairing and per-loop alignment change
nothing, the exact @racket[destination] object is returned. Otherwise untouched
destination subpath objects are reused whenever possible.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-compound-aligned] for timeline compilation.
This stage does not add/remove subpaths, pair open subpaths, infer semantic hole
nesting, or support topology changes.
}

@defproc[(path-geometry-normalize-for-morph
          [from path-geometry?]
          [to path-geometry?])
         (values path-geometry? path-geometry?)]{

Returns two path-geometry values that trace the same figures as @racket[from]
and @racket[to] but have corresponding structure suitable for
@racket[path-geometry-lerp]. The first result is the normalized source, and the
second result is the normalized destination.

Normalization works independently on corresponding subpaths:

@itemlist[
 @item{Every stored line segment is converted to an equivalent cubic Bézier
       segment using @racket[path-geometry->cubic].}
 @item{The target segment count is the larger of the two stored segment counts.}
 @item{The side with fewer segments repeatedly splits its longest current
       cubic at parameter @racket[1/2] until the counts match.}
 @item{Segment length is the same deterministic approximate cubic arc length
       used by @racket[path-subpath-length]. When lengths tie, the earliest
       segment in traversal order is split.}
]

De Casteljau subdivision preserves the exact cubic curve. Splitting therefore
changes representation and correspondence, not the traced source or
destination figure. Both returned paths contain only cubic stored segments,
and @racket[path-geometry-morph-compatible?] returns @racket[#t] for them.
Point-only corresponding subpaths remain point-only.

The implicit closing edge of a closed subpath is not stored, converted, or
split. Closure remains represented by @racket[path-subpath-closed?]. Subpath
order and stored starting points are preserved.

This is deliberately limited normalization. It does not add or remove
subpaths, change closure, turn a point-only subpath into a drawn path, reverse
traversal, rotate the starting point of a closed path, reorder subpaths, or
choose a geometric best match. A difference requiring one of those operations
raises an exception that identifies the first unsupported subpath difference.
Reported indexes start at zero.

Example:

@racketblock[
(define triangle
  (polygon-path
   (list (vec2 -3 -1)
         (vec2 3 -1)
         (vec2 0 2))))

(define rectangle
  (polygon-path
   (list (vec2 -3 -2)
         (vec2 3 -2)
         (vec2 3 2)
         (vec2 -3 2))))

(define-values (normalized-triangle normalized-rectangle)
  (path-geometry-normalize-for-morph triangle rectangle))

(path-geometry-morph-compatible? normalized-triangle
                                 normalized-rectangle)
]
}

@defproc[(path-geometry-morph-compatible?
          [from path-geometry?]
          [to path-geometry?])
         boolean?]{

Returns @racket[#t] when @racket[from] and @racket[to] have corresponding
structure for pointwise path morphing.

Compatibility requires all of the following:

@itemlist[
 @item{The paths contain the same number of subpaths.}
 @item{Each corresponding subpath has the same @racket[closed?] value.}
 @item{Each corresponding subpath contains the same number of segments.}
 @item{Each corresponding segment has the same kind: line with line, or cubic
       Bézier with cubic Bézier.}
]

Subpaths and segments are paired by their stored order. Only stored segments
are counted. A closed subpath's implicit closing edge is represented by its
@racket[closed?] value, not by another stored line segment. Coordinates, path
lengths, and style do not affect compatibility. Empty geometry is compatible
with empty geometry. Point-only subpaths are compatible when their closure
values correspond.

The procedure remains strict. It does not insert segments, convert lines to
cubics, reverse a path, rotate a closed path's starting point, or reorder
subpaths. Use @racket[path-geometry-morph-normalizable?] and
@racket[path-geometry-normalize-for-morph] for the limited explicit
normalization provided by this version.
}

@defproc[(path-geometry-lerp [from path-geometry?]
                             [to path-geometry?]
                             [progress (real-in 0 1)])
         path-geometry?]{

Interpolates the stored points of two morph-compatible paths. The subpath
start points are interpolated pairwise. Line endpoints are interpolated
pairwise. For cubic segments, both control points and the endpoint are
interpolated pairwise. Subpath order, segment order, segment kind, and closure
are preserved.

@racket[progress] must be a finite real in the closed unit interval. A value of
@racket[0] returns @racket[from] itself. A value of @racket[1] returns
@racket[to] itself. An interior value returns new path geometry.

The interpolation uses local mathematical coordinates. It does not change a
Visual's identity, reference position, rotation, scale, fill, stroke, stroke
width, or drawing order. Use @racket[morph-to] to place this interpolation on a
timeline.

When the paths are incompatible, the procedure raises an exception describing
the first mismatch in deterministic traversal order. The diagnostic identifies
a subpath-count, closure, segment-count, or segment-kind mismatch. Reported
subpath and segment indexes start at zero. The procedure remains strict and
does not normalize incompatible paths automatically. Normalize explicitly or
use @racket[morph-to-normalized] for the limited supported cases.

Example:

@racketblock[
(define rectangle-path
  (polygon-path
   (list (vec2 -2 -1)
         (vec2 2 -1)
         (vec2 2 1)
         (vec2 -2 1))))

(define diamond-path
  (polygon-path
   (list (vec2 0 -2)
         (vec2 3 0)
         (vec2 0 2)
         (vec2 -3 0))))

(path-geometry-lerp rectangle-path diamond-path 1/2)
]
}

@defproc[(path-geometry-bounds [geometry path-geometry?])
         (values finite-real? finite-real? finite-real? finite-real?)]{

Returns four values: minimum x, minimum y, maximum x, and maximum y over the
visible path. Coordinates are local world units.

Line bounds come from their endpoints. Cubic bounds include their endpoints
and every interior parameter where the x or y derivative is zero. The result
therefore follows the curve itself instead of using the usually larger box of
its control points. The result is mathematically tight subject to the ordinary
numeric behavior of the supplied coordinates.

The implicit straight closing edge of a closed subpath is included. Empty
geometry has no bounds and raises an exception.
}

@defproc[(path-geometry-center [geometry path-geometry?]) vec2?]{

Returns the center of @racket[geometry]'s axis-aligned local bounding box. It
is the midpoint of the minimum and maximum x values and of the minimum and
maximum y values. Cubic extrema are included. Empty geometry raises an
exception.
}

@defproc[(path-subpath-length [subpath path-subpath?])
         (and/c real? (>=/c 0))]{

Returns the local arc length of @racket[subpath] in world units. A line
segment contributes the Euclidean distance from its start to its endpoint. A
cubic segment contributes a deterministic approximation of its curve length.
When the subpath is closed, the implicit straight edge from the final endpoint
back to @racket[(path-subpath-start subpath)] is included.

Cubic length is computed by repeatedly splitting the curve in half. For each
piece, the implementation compares the control-polygon length with the chord
length. Subdivision stops when their difference is at most the larger of
@racket[1e-10] world units and @racket[1e-8] times the original cubic's
control-polygon length, or after 20 subdivisions. The piece estimate is the
average of its chord and control-polygon lengths. These constants are part of
the current numeric behavior, but they are not a formal error guarantee.

A point-only subpath has length zero. Repeated adjacent points and completely
degenerate cubics contribute zero. The affine transform of a containing Visual
is not applied. The line distance calculation avoids unnecessary overflow,
but a true distance beyond the inexact number range can produce
@racket[+inf.0].
}

@defproc[(path-geometry-length [geometry path-geometry?])
         (and/c real? (>=/c 0))]{

Returns the sum of the local arc lengths of all subpaths in
@racket[geometry]. Empty geometry has length zero. Line portions use Euclidean
length, and cubic portions use the deterministic approximation described for
@racket[path-subpath-length].

This is a geometric model operation. A non-uniform scale on a path Visual can
change the displayed world-space length, but it does not change the value
returned here. The result can be @racket[+inf.0] when an inexact distance is
too large to represent. @racket[create], @racket[uncreate], and non-full
partial extraction require a finite result.
}

@defproc[(path-geometry-point-at [geometry path-geometry?]
                                 [fraction (real-in 0 1)])
         vec2?]{

Returns the point at @racket[fraction] of @racket[geometry]'s total ordered arc
length. @racket[fraction] must be a finite real in the closed unit interval, and
the computed total path length must be positive and finite.

Traversal uses the same significant edge order and length model as
@racket[path-geometry-partial]. Line portions use exact Euclidean distance. A
point inside a cubic uses the same deterministic adaptive arc-length table
described for @racket[path-subpath-length] to approximate the corresponding
curve parameter. The returned value is a semantic local point; no containing
Visual transform is applied.

Compound path geometry is traversed subpath by subpath in stored order.
Zero-length edges consume no positive fraction. The implicit closing edge of a
closed subpath is included. Exact @racket[0] returns the start of the first
positive-length edge, and exact @racket[1] returns the endpoint of the final
positive-length traversal edge. At an exact boundary between positive subpaths,
the endpoint of the preceding subpath is selected.

Empty geometry, zero-total-length geometry, or a non-finite computed total
length raises an exception. @racket[move-along-path] adds a stricter continuity
rule and accepts only one positive-length subpath as a motion route.
}

@defproc[(path-geometry-tangent-at [geometry path-geometry?]
                                   [fraction (real-in 0 1)])
         vec2?]{

Returns the forward unit tangent at @racket[fraction] of
@racket[geometry]'s total ordered arc length. The fraction, positive finite
length requirement, edge order, zero-length-edge handling, implicit closing
edge, and compound-subpath traversal rules match
@racket[path-geometry-point-at]. At an exact positive-length edge boundary, the
preceding traversal edge owns both the point and the tangent.

Line tangents are normalized directed edge vectors. Cubic tangents are computed
from the cubic derivative at the parameter selected by the same adaptive
arc-length table used for point lookup. When that derivative is zero at a
stationary endpoint or cusp, deterministic one-sided curve probes recover the
forward traversal direction when one exists. The result is semantic local
geometry; no containing Visual transform is applied.

Empty geometry, zero-total-length geometry, a non-finite computed total length,
or a selected positive-length cubic point with no recoverable traversal
direction raises an exception.
}

@defproc[(path-geometry-normal-at [geometry path-geometry?]
                                  [fraction (real-in 0 1)])
         vec2?]{

Returns the left unit normal corresponding to
@racket[path-geometry-tangent-at] at @racket[fraction]. For tangent
@racket[(vec2 tx ty)], the result is @racket[(vec2 (- ty) tx)]. The operation
therefore has the same domain and error behavior as tangent lookup.
}

@defproc[(path-geometry-offset
          [geometry path-geometry?]
          [distance finite-real?]
          [#:join join (or/c 'miter 'bevel 'round) 'miter]
          [#:miter-limit miter-limit (and/c finite-real? (>=/c 1)) 4])
         path-geometry?]{

Returns a continuous signed parallel offset of straight-segment subpaths in
@racket[geometry]. Positive @racket[distance] is to the left of stored traversal
direction; negative distance is to the right. A zero distance returns
@racket[geometry] unchanged. The result is ordinary immutable semantic path
geometry and can be passed directly to @racket[make-path-visual],
@racket[move-along-path], @racket[orient-along-path], and other path operations.

For an outside corner, @racket[join] selects how adjacent shifted edge lines are
connected. @racket['miter] extends them to their intersection. The distance from
the original vertex to that intersection is divided by the absolute offset
distance; when the ratio exceeds @racket[miter-limit], the outside corner falls
back to bevel. @racket['bevel] connects the shifted edge endpoints with one
straight segment. @racket['round] uses one or more cubic Bézier circular-arc
approximations centered at the original vertex, with no cubic spanning more than
a quarter turn.

Inside corners always use the natural intersection of the two shifted lines,
independent of @racket[join]. This keeps the offset path traversing forward along
both adjacent lines; the short centered arc on the inside would have the wrong
endpoint tangents. Collinear same-direction edges share their shifted point.

Open subpath endpoints are shifted by their endpoint edge normals. Closed
subpaths are joined cyclically, including the stored start vertex. Every edge
participating in a nonzero offset must be a positive-length
@racket[line-path-segment]. A zero-length edge, an exact 180-degree reversal, or
a cubic source segment raises an exception in this stage. Cubic segments may
still appear in the @emph{result} as round-join pieces.

The construction is geometric rather than renderer-dependent: camera scale,
stroke width, and output resolution do not affect the generated path. The result
has its own arc length, so @racket[move-along-path] with @racket[linear] easing
moves uniformly along the joined offset route itself.
}

@defproc[(path-geometry-partial [geometry path-geometry?]
                                [start (real-in 0 1)]
                                [end (real-in 0 1)])
         path-geometry?]{

Returns the interval from fraction @racket[start] through fraction @racket[end]
of @racket[geometry]'s total local arc length. Both fractions must be finite,
and @racket[start] must not be greater than @racket[end].

Fractions apply to the whole compound path. Traversal completes each subpath
before beginning the next. A cut inside a line is inserted by linear
interpolation. A cut inside a cubic uses the same deterministic adaptive
length table as @racket[path-subpath-length] to approximate the corresponding
curve parameter. The selected cubic interval is then extracted with de
Casteljau subdivision. The result remains a cubic segment; it is not replaced
by a polyline or a Pict command.

A partially selected closed subpath becomes open. Its implicit closing edge is
part of the traversal and may itself be returned as an open line segment. A
closed subpath keeps its closure only when its complete traversal is selected.
This rule prevents a partial prefix from being filled as if it were complete.

When @racket[start] and @racket[end] are equal, the result is
@racket[empty-path-geometry]. The exact interval from @racket[0] through
@racket[1] returns @racket[geometry] unchanged. This preserves segment types,
control points, point-only subpaths, and other zero-length structure. For a
zero-length path, every other interval returns empty geometry.

Zero-length edges and subpaths do not consume a positive portion of the arc
length. They can therefore disappear from a non-full partial result. Any
non-full partial extraction requires the computed total path length to be
finite. Extremely large inexact coordinates whose distance overflows raise an
exception here.

Examples:

@racketblock[
(define mixed-path
  (path-geometry
   (list
    (path-subpath
     origin
     (list (line-path-segment (vec2 2 0))
           (cubic-bezier-path-segment (vec2 3 2)
                                      (vec2 4 2)
                                      (vec2 5 0)))
     #f))))

(path-geometry-partial mixed-path 0 1/2)
]
}

@defproc[(path-geometry-cycle-start [geometry path-geometry?]
                                    [fraction (real-in 0 1)])
         path-geometry?]{

Moves the stored start of one closed loop to @racket[fraction] of that loop's
total arc length while preserving its forward traversal direction and traced
geometry. The fraction uses the same deterministic line/cubic length model as
@racket[path-geometry-point-at].

@racket[geometry] must contain exactly one closed subpath with positive finite
length. Exact @racket[0] and @racket[1] return @racket[geometry] unchanged. For
any other fraction, the selected point becomes both fraction zero and fraction
one of the returned closed loop.

When the selected point lies inside a line, the line is split by interpolation.
When it lies inside a cubic, the arc-length table chooses the deterministic
curve parameter and de Casteljau subdivision splits the curve. The tail from
the selected point through the original closing edge is followed by the old
prefix back to the selected point. The returned subpath remains closed; its
final synthetic closing edge has zero length.

The operation deliberately handles one closed subpath rather than assigning one
phase to every subpath of compound geometry. Automatic per-subpath phase
selection is a separate correspondence problem. The returned value is ordinary
path geometry and can be used directly by @racket[make-path-visual],
@racket[move-along-path], @racket[orient-along-path], camera following, partial
extraction, and normalized morph preparation.
}

@defproc[(polyline-path [points (listof vec2?)]) path-geometry?]{

Creates path geometry containing one open line-segment subpath. At least two
points are required. Points are stored in the supplied order and adjacent
points are connected by @racket[line-path-segment] values.

The points are local coordinates. Use @racket[make-path-visual] to choose the
reference position in the Visual's containing coordinate system. That system is
world space at the top level and group-local space for a child.
}

@defproc[(polygon-path [points (listof vec2?)]) path-geometry?]{

Creates path geometry containing one closed line-segment subpath. At least
three points are required. The closing edge from the final point to the first
point is represented by the subpath's @racket[closed?] field and is not stored
as a repeated endpoint.

Point order determines traversal direction and can affect later path
operations. The built-in renderer uses the odd-even fill rule, so clockwise
and counter-clockwise order produce the same simple fill in this version.
}

@defproc[(cubic-bezier-path
          [start vec2?]
          [segments (and/c pair?
                           (listof cubic-bezier-path-segment?))]
          [#:closed? closed? boolean? #f])
         path-geometry?]{

Creates path geometry containing one subpath made from one or more cubic
Bézier segments. The subpath begins at @racket[start]. Segment order is
significant, and each segment begins at the preceding segment's endpoint.

When @racket[closed?] is true, the subpath also has an implicit straight edge
from its final endpoint back to @racket[start]. A smooth closed cubic shape
normally includes a final cubic whose endpoint is @racket[start] and also sets
@racket[closed?] to true so that the built-in renderer fills it. In that case,
the implicit closing edge has length zero.

Example:

@racketblock[
(define arch
  (cubic-bezier-path
   (vec2 -2 0)
   (list
    (cubic-bezier-path-segment (vec2 -2 2)
                               (vec2 2 2)
                               (vec2 2 0)))))
]
}


@section[#:tag "affine-transforms"]{Affine Transforms}

Affine-transform values are created through @racket[make-affine-transform].
The raw structure constructor is not part of the public API.

@defproc[(affine-transform? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is an affine-transform value.
}

@defproc[(affine-transform-translation [transform affine-transform?]) vec2?]{

Returns the translation component of @racket[transform] in its containing
coordinate system. A top-level Visual normally uses world coordinates. A child
Visual normally uses coordinates local to its group.
}

@defproc[(affine-transform-rotation [transform affine-transform?])
         finite-real?]{

Returns the counter-clockwise rotation of @racket[transform] in radians.
}

@defproc[(affine-transform-scale [transform affine-transform?]) vec2?]{

Returns the positive x and y scale factors of @racket[transform]. A uniform
scale is stored with equal components.
}

@defproc[(scale-factor? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is either a positive finite real number
or a @racket[vec2] whose two components are positive. A number represents
uniform scale. A @racket[vec2] represents separate x and y scale.
}

@defproc[(scale-factor->vec2 [value scale-factor?]) vec2?]{

Converts a scale factor to two components. A numeric value @racket[s] becomes
@racket[(vec2 s s)]. A @racket[vec2] value is returned unchanged.
}

@defproc[(make-affine-transform
          [#:translation translation vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1])
         affine-transform?]{

Creates a validated decomposed transform. Translation is measured in the
coordinate system that contains the transformed value. Translation is applied
last, rotation is counter-clockwise, and scale is normalized with
@racket[scale-factor->vec2].
}

@defthing[identity-affine-transform affine-transform?]{

The transform with zero translation, zero rotation, and scale
@racket[(vec2 1 1)]. It leaves every point unchanged.
}

@defproc[(affine-transform-with-translation
          [transform affine-transform?]
          [translation vec2?])
         affine-transform?]{

Returns a new transform with @racket[translation] installed. Rotation and
scale are preserved.
}

@defproc[(affine-transform-with-rotation
          [transform affine-transform?]
          [rotation finite-real?])
         affine-transform?]{

Returns a new transform with @racket[rotation] installed. Translation and scale
are preserved.
}

@defproc[(affine-transform-with-scale
          [transform affine-transform?]
          [scale scale-factor?])
         affine-transform?]{

Returns a new transform with @racket[scale] installed. Translation and
rotation are preserved. Numeric scales are normalized to a @racket[vec2].
}

@defproc[(affine-transform-lerp
          [from affine-transform?]
          [to affine-transform?]
          [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         affine-transform?]{

Interpolates translation, rotation, and scale componentwise. Progress must be
between @racket[0] and @racket[1], inclusive.

Rotation is interpolated as an ordinary number. The procedure does not choose
the shortest path around a circle. For example, interpolation from
@racket[0] to @racket[(* 2 pi)] describes one full turn.
}

@defproc[(affine-transform-apply-vector
          [transform affine-transform?]
          [vector vec2?])
         vec2?]{

Applies scale and rotation to a displacement vector. Translation is ignored,
because a displacement has no fixed position.
}

@defproc[(affine-transform-apply-point
          [transform affine-transform?]
          [point vec2?])
         vec2?]{

Applies scale, rotation, and translation to a point, in that order.
}

@section[#:tag "cameras"]{Cameras}

A camera is an immutable orthographic view. Its pixel dimensions, visible
world width, center, and background are explicit values. The raw camera
constructor is not public; use @racket[make-camera]. A scene can store and
animate camera values without mutating them.

@defproc[(camera? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a camera value.
}

@defproc[(camera-width [camera camera?]) exact-positive-integer?]{

Returns the output width in pixels.
}

@defproc[(camera-height [camera camera?]) exact-positive-integer?]{

Returns the output height in pixels.
}

@defproc[(camera-world-width [camera camera?])
         (and/c finite-real? positive?)]{

Returns the visible width in world units.
}

@defproc[(camera-center [camera camera?]) vec2?]{

Returns the world point placed at the center of the output frame.
}

@defproc[(camera-background [camera camera?]) any/c]{

Returns the background style stored in the camera. The built-in Pict adapter
passes this value to Pict as a color. A color name string is the usual choice.
The value is not checked until an adapter uses it.
}

@defproc[(make-camera
          [#:width width exact-positive-integer? 1280]
          [#:height height exact-positive-integer? 720]
          [#:world-width world-width
                         (and/c finite-real? positive?)
                         14]
          [#:center center vec2? origin]
          [#:background background any/c "white"])
         camera?]{

Creates an immutable orthographic camera value. The aspect ratio comes from
@racket[width] and @racket[height]. The visible world height is derived from
that aspect ratio and @racket[world-width].
}

@defthing[default-camera camera?]{

The default camera: 1280 by 720 pixels, 14 world units wide, centered at
@racket[origin], with a white background.
}

@defproc[(camera-scale [camera camera?])
         (and/c real? positive?)]{

Returns the number of pixels per world unit. It is
@racket[(/ (camera-width camera) (camera-world-width camera))].
}

@defproc[(camera-world-height [camera camera?])
         (and/c real? positive?)]{

Returns the visible height in world units. It preserves the camera's pixel
aspect ratio.
}

@defproc[(camera-length->pixels [camera camera?]
                                [length finite-real?])
         real?]{

Converts a signed world-space length to pixels. The procedure multiplies by
@racket[camera-scale]. It does not take an absolute value.
}

@defproc[(camera-world->pixel [camera camera?]
                              [point vec2?])
         (values real? real?)]{

Returns two values: the pixel x coordinate and the pixel y coordinate of
@racket[point]. The camera center maps to the center of the output frame.
World y increases upward, while pixel y increases downward.
}

@defproc[(camera-pan-to [center vec2?]) camera-pan-to-request?]{

Creates an absolute camera-center request for @racket[scene-play]. At eased
progress one, @racket[center] is the world point in the middle of the frame.
The camera's pixel dimensions, visible width, aspect ratio, and background are
unchanged.
}

@defproc[(camera-pan-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-pan-to].
}

@defproc[(camera-pan-by [delta vec2?]) camera-pan-by-request?]{

Creates a relative camera-center request. When @racket[scene-play] compiles the
request, it adds @racket[delta] to the camera center at the beginning of that
clip. The request does not capture a camera when it is constructed.
}

@defproc[(camera-pan-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-pan-by].
}

@defproc[(camera-zoom-to
          [world-width (and/c finite-real? positive?)])
         camera-zoom-to-request?]{

Creates an absolute camera zoom request. @racket[world-width] is the requested
visible frame width in world units. A smaller width shows less of the world and
therefore appears more magnified. During a clip, visible world width is
interpolated linearly after easing; interpolation is not logarithmic. Pixel
width, pixel height, center, and background remain unchanged unless another
request changes the center.
}

@defproc[(camera-zoom-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-zoom-to].
}

@defproc[(camera-zoom-by [factor (and/c finite-real? positive?)])
         camera-zoom-by-request?]{

Creates a relative magnification request. The target visible width is the
clip-start camera width divided by @racket[factor]. Thus @racket[2] zooms in by
two, @racket[1] leaves magnification unchanged, and @racket[1/2] zooms out by
two. The resulting target width is interpolated linearly from the clip-start
width after easing.

Compilation raises an exception if the division produces a nonpositive or
non-finite visible width.
}

@defproc[(camera-zoom-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-zoom-by].
}

@defproc[(camera-follow [target (or/c visual? symbol?)])
         camera-follow-request?]{

Creates a clip-local request that keeps the reference position of
@racket[target] at its clip-start pixel position. The target is resolved as a
current top-level scene Visual when @racket[scene-play] compiles the request.
Nested group children are not searched.

Frame-space Visuals are not valid follow targets; camera following is defined
only for world-space top-level Visuals. A SCENE-AW derived target is resolved
against the same sampled scalar state before its world-space position is read.

At each scene sample, following reads the target's actual sampled
@racket[visual-position] at the same eased progress as its Visual animations.
The pre-removal motion state is retained for camera completion, so the request
can follow a Visual introduced by @racket[fade-in] or @racket[create], and it
can follow a Visual until a same-clip @racket[fade-out] or @racket[uncreate]
removes it at the structural endpoint. The sampled @racket[visual-position]
result must be a @racket[vec2].

Following preserves normalized horizontal and vertical frame position. When a
zoom request runs in the same clip, the camera adjusts its world-space offset
as the visible width changes, so the target remains at the same pixel
coordinates. Because the sampled Visual state supplies the position, the camera
also follows nonlinear motion such as @racket[move-along-path] through a bend or
curve rather than interpolating only between clip endpoints. The request changes
the camera-center component and may run with one zoom request. It conflicts with
pan, fitting, or another follow request.

Following tracks only @racket[visual-position], not the target's rendered box,
rotation, scale, or shape. It lasts for one play clip. It does not install a
persistent observer. Camera-only clips without following do not require scene
state sampling.
}

@defproc[(camera-follow-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-follow].
}

@defproc[(camera-fit-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a camera-fit request created
by @racket[camera-fit-layout-box], @racket[camera-fit-visuals], or
@racket[camera-fit-scene], including the @racket[camera-focus] specialization.
A fit request changes camera center and visible world width together. It
therefore reserves both camera components in one play clip.
}

@defproc[(camera-fit-layout-box
          [box layout-box?]
          [#:camera camera camera? default-camera]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a camera-fit request for @racket[box]. The target camera center is
@racket[(layout-box-center box)]. The target visible width is the larger of:

@itemlist[
 @item{the box width plus @racket[padding] on both horizontal sides; and}
 @item{the width needed to contain the padded box height while preserving the
       pixel aspect ratio of @racket[camera].}]

Padding is measured in world units and is applied equally on all four sides
before aspect-ratio correction. Pixel width, pixel height, and background are
preserved. A zero-size box with zero padding is rejected because it would
produce a nonpositive visible width.

The result is a snapshot request. It stores only the concrete target center and
visible width; it does not retain @racket[box] or recompute it during animation.
Use a camera with the same pixel aspect ratio as the scene camera that will run
the request. The stored fit is not recomputed for a different aspect ratio.
}

@defproc[(camera-fit-visuals
          [visuals (and/c (listof visual?) pair?)]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Measures the complete rendered union of @racket[visuals] with
@racket[visuals-layout-box], then creates the corresponding fit request.
The list must be nonempty, every Visual must use the same containing
coordinate system, and every supplied Visual must belong to world space.
Frame-space overlays and callouts are not camera-fit geometry.

Measurement uses @racket[camera] and the first-supporting renderer rule from
@racket[renderers]. Custom renderer padding therefore participates in fitting.
A standalone @racket[derived-visual?] cannot be measured here because this
function has no scene-state scalar context; use @racket[camera-fit-scene] for a
derived top-level target.
Measuring a nonempty formula through the built-in formula renderer can invoke
LaTeX and Poppler. Opacity does not change the measured Pict dimensions.

The values are measured when this function is called. Geometry or renderer
changes later in the same clip do not cause automatic remeasurement. The fit is
also not recomputed at its target zoom. A custom renderer whose Pict has a fixed
pixel size can therefore occupy a different world-space size at the endpoint.
To fit a planned endpoint in the same clip, supply Visual values and a
measurement camera that describe the intended view as closely as possible.
}

@defproc[(camera-fit-scene
          [scene scene?]
          [#:targets targets
                     (or/c false/c
                           (and/c pair?
                                  (listof (or/c visual? symbol? visual-path?))))
                     #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a fit request from @racket[scene]'s current endpoint state and current
camera. When @racket[targets] is @racket[#f], all current top-level
@emph{world-space} Visuals are measured in back-to-front order; frame-space
overlays and callouts are ignored. Otherwise, @racket[targets] must be a
nonempty list of Visual values, symbols, or explicit nonempty Visual paths, and
every resolved target must be a world-space Visual. A top-level target is
resolved by stable identity against @racket[(scene-current-state scene)], so a
stale constructor value still selects the current scene value. A nested path is
resolved with every enclosing group/formula transform and opacity composed into
an independently measurable world-space Visual. SCENE-AW derived definitions
are additionally evaluated against the current endpoint scalar values before
measurement.

A scene with no world-space Visuals, an empty target list, a missing target, or
an explicitly selected frame-space target raises an exception. The result is a
snapshot of the current endpoint state and does not follow later scene changes.
}

@defproc[(camera-focus
          [scene scene?]
          [focus (or/c visual? symbol? visual-path?)]
          [#:context context
                     (listof (or/c visual? symbol? visual-path?))
                     '()]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a renderer-aware fit around one explanatory subject and zero or more
explicit context Visuals. @racket[focus] and every value in @racket[context]
may be a current top-level Visual, its symbol identity, or an explicit nested
Visual path. The request is equivalent to a @racket[camera-fit-scene] selection
whose first target is the focus, but its named @racket[#:context] argument makes
the pedagogical framing decision clear at the call site.

All selected targets are measured in fully composed world coordinates. This
makes an imported SVG element or formula/group child a useful focus subject
without rebuilding its parent. Frame-space targets are rejected. The request is
a current-scene snapshot: it does not choose context automatically, remeasure
during the clip, or live-follow later subject/context motion.
}

@section[#:tag "frame-space"]{Frame-Space Overlays and Callouts}

Frame-space Visuals are semantic wrappers, not cached Picts. They remain
ordinary top-level Visuals with stable identity and can participate in
@racket[move-to], rotation, scale, opacity, structural fade, and ordinary scene
ordering. Their reference positions are interpreted in frame coordinates by
the adapter rather than world coordinates.

@defproc[(frame-space-visual? [value any/c]) boolean?]{

Returns @racket[#t] for the built-in @racket[fixed-in-frame] and
@racket[callout] wrapper values.
}

@defproc[(frame-space-visual-frame-width [visual frame-space-visual?])
         (and/c finite-real? positive?)]{

Returns the visible width of @racket[visual]'s captured frame coordinate
system. This is normally the @racket[camera-world-width] of the camera supplied
when the wrapper was constructed.
}

@defproc[(frame-space-camera
          [camera camera?]
          [frame-width (and/c finite-real? positive?)])
         camera?]{

Returns an origin-centered camera with the pixel width, pixel height, and
background of @racket[camera], but with visible world width
@racket[frame-width]. The Pict adapter uses this derived camera for frame-space
measurement, local rendering, and frame-coordinate placement. The input
camera's center and visible world width are deliberately ignored.
}

@defproc[(fixed-in-frame
          [content visual?]
          [#:camera camera camera? default-camera]
          [#:at position (or/c vec2? false/c) #f]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         fixed-in-frame-visual?]{

Wraps @racket[content] as a frame-space overlay. The wrapper preserves
@racket[(visual-id content)] as its top-level identity. The content remains
semantic model data and is rendered locally at the frame-space origin; its own
geometry, rotation, scale, style, and opacity remain significant. The wrapper's
rotation, scale, and opacity are additional outer transforms.

The wrapper snapshots @racket[(camera-world-width camera)]. If @racket[position]
is @racket[#f], its initial frame position is
@racket[(vec2- (visual-position content) (camera-center camera))]. Therefore a
Visual wrapped with the camera through which it is currently being viewed keeps
the same pixel position and size at the moment it becomes fixed. An explicit
@racket[position] is interpreted directly in the captured origin-centered frame
coordinate system.

Later world-camera pan and zoom do not change the overlay's frame position or
local rendering scale. Animated output pixel dimensions are not supported by
the camera model, but a static rendering override with different pixel
dimensions scales frame content with the output frame. Frame-space wrappers
cannot be nested inside one another and must remain top-level scene Visuals.
For a compound overlay, construct an ordinary @racket[group] first and wrap the
complete group.
}

@defproc[(fixed-in-frame-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a fixed-in-frame wrapper.
}

@defproc[(fixed-in-frame-visual-content
          [visual fixed-in-frame-visual?])
         visual?]{

Returns the semantic content stored by @racket[visual]. The returned content is
not a scene-state child and cannot be targeted directly while it is wrapped.
}

@defproc[(callout
          [content visual?]
          [target (or/c visual? symbol? visual-path? vec2?)]
          [#:camera camera camera? default-camera]
          [#:at position (or/c vec2? false/c) #f]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:target-anchor target-anchor
                           (or/c 'bottom-left 'bottom 'bottom-right
                                 'left 'center 'right
                                 'top-left 'top 'top-right)
                           'center]
          [#:connector-stroke connector-stroke any/c "black"]
          [#:connector-width connector-width
                             (and/c finite-real? (>=/c 0))
                             2])
         callout-visual?]{

Creates a fixed frame-space annotation with a leader line to a world-space
target. The frame placement and outer transform use the same semantics as
@racket[fixed-in-frame]. A Visual target is stored by stable identity. A symbol
is already a top-level target identity, and a nonempty @racket[visual-path?]
selects a built-in group/formula descendant. A @racket[vec2] is a fixed
world-space point.

Visual-path targets are resolved against each sampled scene state when a
complete scene is converted to a Pict. A nested result has every enclosing
group/formula transform and opacity composed before its world position is read.
This makes the connector follow ordinary movement of a target or its parent
without adding observer state to the timeline. SCENE-AW derived targets are
resolved from the same sampled scalar state. The resolved Visual must belong to
world space. A missing target or a frame-space target raises an exception at
scene rendering.

The connector is drawn beneath the annotation from the target's current world
pixel position to the edge of the complete annotation Pict box. For a Visual
target, @racket[target-anchor] selects the target's live renderer-box center,
edge, or corner; it is measured as each scene sample is rendered, so it follows
target size changes as well as movement. A literal @racket[vec2] target accepts
only the default @racket['center] anchor. Its width is a cosmetic pixel width.
A false @racket[connector-stroke] or a zero @racket[connector-width] suppresses
the line. The callout's outer opacity also applies to the connector.

@racket[visual->pict] on a callout returns only its local annotation Pict,
because resolving a symbolic connector target requires a complete sampled scene
state. @racket[scene-state->pict] and higher-level frame rendering include both
the leader and the annotation.
}

@defproc[(callout-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in callout Visual.
}

@defproc[(callout-visual-content [visual callout-visual?]) visual?]{

Returns the semantic annotation content stored by @racket[visual].
}

@defproc[(callout-visual-target [visual callout-visual?])
         (or/c symbol? visual-path? vec2?)]{

Returns the normalized callout target. Visual-valued constructor targets appear
here as their stable symbol identity; an explicit nested path is preserved;
fixed world points remain @racket[vec2] values.
}

@defproc[(callout-visual-target-anchor [visual callout-visual?]) symbol?]{

Returns the selected live renderer-box anchor for a Visual target.
}

@defproc[(callout-visual-connector-stroke [visual callout-visual?]) any/c]{

Returns the opaque connector stroke style stored by @racket[visual]. A false
value disables the connector during built-in scene rendering.
}

@defproc[(callout-visual-connector-width [visual callout-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the cosmetic connector width in output pixels.
}

Renderer-aware relative layout recognizes frame-space coordinates. Layout of a
single frame-space Visual uses its captured frame scale, so the result is
independent of later world-camera pan or zoom. Pair and list layout operations
may combine frame-space Visuals only when they have the same captured frame
width. Mixing world and frame coordinate domains in one relative-layout
calculation raises an exception. A callout layout box measures its fixed
annotation Pict only; the cross-space connector is deliberately not part of
frame-space layout.

World-camera operations deliberately exclude frame-space content:
@racket[camera-fit-visuals] rejects it, @racket[camera-fit-scene] ignores it for
implicit all-scene fitting and rejects it when explicitly selected, and
@racket[camera-follow] cannot follow a frame-space target.

@section[#:tag "semantic-colors"]{Semantic Colors}

SCENE-AT introduces a small renderer-independent color representation for style
interpolation. Existing Visual constructors still accept their historical color
strings; semantic RGBA values are needed only when an animation is sampled in
its interior or when callers choose to construct one explicitly.

@defstruct*[rgba-color ([red (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [green (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [blue (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [alpha opacity?])
  #:transparent]{

Represents one semantic sRGB color. Red, green, and blue are channel values from
zero through 255; alpha is in the closed unit interval. The constructor rejects
infinities, NaN values, and out-of-range components. The value has no dependency
on @racketmodname[racket/draw].
}

@defproc[(rgb-color [red (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [green (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [blue (and/c finite-real? (>=/c 0) (<=/c 255))])
         rgba-color?]{

Constructs an opaque @racket[rgba-color] whose alpha component is one.
}

@defproc[(color-spec? [value any/c]) boolean?]{

Returns @racket[#t] for an @racket[rgba-color] or a supported textual color.
Text accepts X11-style names from Racket's drawing color family case-insensitively
(common spaces, hyphens, and underscores are ignored), @tt{#RGB}, @tt{#RGBA}, @tt{#RRGGBB}, and
@tt{#RRGGBBAA}. @tt{transparent} is the zero-alpha black semantic color.
}

@defproc[(color-spec->rgba-color [value any/c]
                                 [who symbol? 'color-spec->rgba-color])
         rgba-color?]{

Resolves @racket[value] to semantic RGBA channels. An existing
@racket[rgba-color] is returned unchanged. Unsupported strings and other values
raise an argument error attributed to @racket[who].
}

@defproc[(rgba-color-lerp [from rgba-color?]
                          [to rgba-color?]
                          [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         rgba-color?]{

Interpolates red, green, blue, and alpha componentwise in sRGB value space.
This is intentionally a deterministic semantic interpolation rather than a
color-managed or perceptual color-space conversion.
}

@section[#:tag "visuals"]{Visuals}

@subsection{The Basic Visual Protocol}

@defproc[(visual-path? [value any/c]) boolean?]{

Returns @racket[#t] for a nonempty list of symbol identities used to address a
nested built-in group child, such as @racket['(scatter marker)]. The first
symbol identifies a top-level Visual and each remaining symbol names one child.
}

@defproc[(visual-target-path [target (or/c visual? symbol? visual-path?)])
         visual-path?]{

Converts a top-level Visual or symbol to its one-element path, and returns an
existing nested path unchanged.
}

@defthing[#:kind "generic interface" gen:visual any/c]{

The generic interface for semantic Visual values. A structure type implements
this interface with @racket[#:methods] in its @racket[struct] definition.
It must implement @racket[visual-id], @racket[visual-position], and
@racket[visual-with-position].
}

@defproc[(visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements @racket[gen:visual].
}

@defproc[(visual-id [visual visual?]) symbol?]{

Returns the stable identity of @racket[visual]. Scene lookup and animation
targeting use this symbol.

A custom Visual implementation must always return a symbol. Immutable update
methods must preserve the symbol.
}

@defproc[(visual-position [visual visual?]) vec2?]{

Returns the reference position of @racket[visual] in its containing coordinate
system. A top-level Visual uses world coordinates. A child of a group uses
coordinates local to that group. For the built-in affine Visuals, the result is
the translation component of the affine transform.
}

@defproc[(visual-with-position [visual visual?]
                               [position vec2?])
         visual?]{

Returns a new Visual with @racket[position] as its reference position in the
same containing coordinate system. The result must preserve identity. Built-in
Visuals also preserve geometry, style, rotation, scale, opacity, and child
order when applicable.
}

A minimal position-only Visual can be defined as follows:

@racketblock[
(struct marker (id position)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (marker-id value))
   (define (visual-position value)
     (marker-position value))
   (define (visual-with-position value position)
     (struct-copy marker value [position position]))])
]

Such a Visual can use @racket[move-to], but it cannot use rotation or scale
animations.

@subsection{The Affine-Visual Protocol}

@defthing[#:kind "generic interface" gen:affine-visual any/c]{

The optional generic interface for Visuals that support complete affine
transforms. A structure type implementing this interface must provide
@racket[visual-transform] and @racket[visual-with-transform]. It normally also
implements @racket[gen:visual].
}

@defproc[(affine-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:affine-visual].
}

@defproc[(visual-transform [visual affine-visual?]) affine-transform?]{

Returns the complete affine transform of @racket[visual]. Its translation must
agree with @racket[visual-position]. Custom implementations must return an
@racket[affine-transform?] value.
}

@defproc[(visual-with-transform [visual affine-visual?]
                                [transform affine-transform?])
         affine-visual?]{

Returns a new affine Visual with @racket[transform] installed. A correct
implementation preserves the Visual's identity, geometry, style, child order,
and opacity when those fields apply. The result's @racket[visual-position],
@racket[visual-rotation], and @racket[visual-scale] results must agree with the
installed transform.
}

@defproc[(visual-rotation [visual affine-visual?]) finite-real?]{

Returns the counter-clockwise rotation of @racket[visual] in radians.
}

@defproc[(visual-scale [visual affine-visual?]) vec2?]{

Returns the positive x and y scale factors of @racket[visual].
}

@defproc[(visual-with-rotation [visual affine-visual?]
                               [rotation finite-real?])
         affine-visual?]{

Returns a new affine Visual with @racket[rotation] installed. Position, scale,
geometry, style, and opacity are preserved.
}

@defproc[(visual-with-scale [visual affine-visual?]
                            [scale scale-factor?])
         affine-visual?]{

Returns a new affine Visual with @racket[scale] installed. Position, rotation,
geometry, style, child order, and opacity are preserved.

A built-in group or formula assembly accepts only a uniform scale, so its x
and y components must be equal. Other built-in affine Visuals, including arrows
and axes, accept non-uniform scale.
}

@subsection{The Opacity-Visual Protocol}

@defproc[(opacity? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real number in the closed
interval from @racket[0] through @racket[1]. Exact and inexact values are
accepted. Negative values, values greater than one, infinities, NaN values, and
non-real values are rejected.
}

@defthing[#:kind "generic interface" gen:opacity-visual any/c]{

The optional generic interface for Visuals that support global opacity. A
structure type implementing this interface must provide @racket[visual-opacity]
and @racket[visual-with-opacity]. It normally also implements
@racket[gen:visual].

Opacity is semantic model data. Renderers should draw the Visual normally. The
Pict adapter applies global opacity after it selects and runs a renderer.
}

@defproc[(opacity-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:opacity-visual]. Implementing this protocol does not require
implementing @racket[gen:affine-visual].
}

@defproc[(visual-opacity [visual opacity-visual?]) opacity?]{

Returns the global opacity of @racket[visual]. A custom implementation must
return a value accepted by @racket[opacity?]. Animation and rendering adapters
validate this result at their boundaries.
}

@defproc[(visual-with-opacity [visual opacity-visual?]
                              [opacity opacity?])
         opacity-visual?]{

Returns a new opacity Visual with @racket[opacity] installed. A correct
implementation preserves Visual identity, reference position, geometry, affine
transform, style, child order when applicable, and every other semantic field.
It must return the requested opacity exactly.

The built-in circle, rectangle, path, arrow, axes, plain-text, formula,
formula-assembly, and group Visuals implement this protocol.
}

A position-only custom Visual can implement opacity as follows:

@racketblock[
(struct marker (id position opacity)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (marker-id value))
   (define (visual-position value)
     (marker-position value))
   (define (visual-with-position value position)
     (struct-copy marker value [position position]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity value)
     (marker-opacity value))
   (define (visual-with-opacity value opacity)
     (struct-copy marker value [opacity opacity]))])
]

@subsection{The Stroke-Width-Visual Protocol}

@defproc[(stroke-width? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a nonnegative finite real number.
Exact and inexact values are accepted, including zero. Negative values,
infinities, NaN values, and non-real values are rejected. This semantic domain is
renderer-independent: alternate renderers may support widths outside the narrower
range accepted by the default Pict backend.
}

@defthing[#:kind "generic interface" gen:stroke-width-visual any/c]{

The optional generic interface for Visuals with one semantic cosmetic stroke
width. A structure type implementing this interface must provide
@racket[visual-stroke-width] and @racket[visual-with-stroke-width]. It normally
also implements @racket[gen:visual].

The protocol is renderer-independent model data. Built-in renderers read the
stored widths of the Visual types they support; third-party renderers decide how
to interpret the width exposed by their own Visual implementations.
}

@defproc[(stroke-width-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:stroke-width-visual]. Implementing this protocol does not require
implementing @racket[gen:affine-visual] or @racket[gen:opacity-visual].
}

@defproc[(visual-stroke-width [visual stroke-width-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the cosmetic stroke width of @racket[visual]. A custom implementation
must return a value accepted by @racket[stroke-width?]. Animation compilation
validates this result before constructing a stroke-width transition.
}

@defproc[(visual-with-stroke-width
          [visual stroke-width-visual?]
          [stroke-width (and/c finite-real? (>=/c 0))])
         stroke-width-visual?]{

Returns a new stroke-width Visual with @racket[stroke-width] installed. A
correct implementation preserves Visual identity and every semantic field other
than stroke width, returns a Visual that still implements the protocol, and
installs the requested width exactly, including exact/inexact numeric
representation.

The built-in circle, rectangle, path, arrow, axes, number-line, and point-marker
Visuals implement this protocol. Coordinate plots and filled areas that are
themselves path Visuals participate without a separate plot-animation mechanism.
A @racket[scatter-plot] result is instead a top-level group; its nested
point-marker children are not independent scene-state animation targets, so the
scatter group does not implement this protocol. A callout's
@racket[callout-visual-connector-width] is likewise separate frame-space connector
style and is not controlled by @racket[stroke-width-to].
}

A position-only custom Visual can opt in independently of affine transforms and
opacity:

@racketblock[
(struct width-marker (id position stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (width-marker-id value))
   (define (visual-position value)
     (width-marker-position value))
   (define (visual-with-position value position)
     (struct-copy width-marker value [position position]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width value)
     (width-marker-stroke-width value))
   (define (visual-with-stroke-width value stroke-width)
     (struct-copy width-marker value [stroke-width stroke-width]))])
]

@subsection{Fill-Color and Stroke-Color Visual Protocols}

@defthing[#:kind "generic interface" gen:fill-color-visual any/c]{

The optional interface for Visuals with a replaceable fill-color slot. A
structure type implementing it provides @racket[visual-fill-color] and
@racket[visual-with-fill-color]. A current slot value may be @racket[#f] to mean
no fill, but SCENE-AT color interpolation requires the current value to satisfy
@racket[color-spec?].
}

@defproc[(fill-color-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:fill-color-visual].
}

@defproc[(visual-fill-color [visual fill-color-visual?]) any/c]{

Returns the Visual's fill style slot. Built-ins normally return a textual color,
an @racket[rgba-color], or @racket[#f]. Animation compilation accepts a source
for @racket[fill-color-to] only when this result satisfies @racket[color-spec?].
}

@defproc[(visual-with-fill-color [visual fill-color-visual?]
                                 [color color-spec?])
         fill-color-visual?]{

Returns a Visual with @racket[color] installed as its fill color. Correct custom
implementations preserve Visual identity and all other semantic fields and
install the requested value exactly. For @racket[rgba-color] endpoints, exactness
includes the exact/inexact representation of every channel.
}

@defthing[#:kind "generic interface" gen:stroke-color-visual any/c]{

The corresponding optional interface for a replaceable stroke-color slot. It
provides @racket[visual-stroke-color] and @racket[visual-with-stroke-color]. A
current @racket[#f] stroke means no stroke and is not a SCENE-AT color
interpolation source.
}

@defproc[(stroke-color-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:stroke-color-visual].
}

@defproc[(visual-stroke-color [visual stroke-color-visual?]) any/c]{

Returns the Visual's stroke style slot. @racket[stroke-color-to] requires the
current result to satisfy @racket[color-spec?].
}

@defproc[(visual-with-stroke-color [visual stroke-color-visual?]
                                   [color color-spec?])
         stroke-color-visual?]{

Returns a Visual with @racket[color] installed as its stroke color while
preserving identity and every unrelated semantic field. The requested style must
be installed exactly, including exact/inexact channel representation for
@racket[rgba-color] values.
}

Circles, rectangles, paths, and point markers implement both protocols. Arrows,
axes, and number lines implement the stroke-color protocol. A @racket[scatter-plot]
result is a group whose nested marker children are not independent scene-state
targets, so the group itself implements neither color protocol. Callout
@racket[callout-visual-connector-stroke] is separate frame-space connector style
and is not controlled by @racket[stroke-color-to]. The protocols are independent
of affine transforms, opacity, and stroke width, so third-party Visuals may opt
into either one separately.

@subsection{Circle Visuals}

@defproc[(circle
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:radius radius (and/c finite-real? positive?) 1]
          [#:fill fill any/c "dodgerblue"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         circle-visual?]{

Creates a semantic circle. The @racket[id] argument is required and must be a
symbol. @racket[center], @racket[rotation], and @racket[scale] form its affine
transform. The center is in the Visual's containing coordinate system: world
coordinates at the top level and group-local coordinates for a child.
@racket[radius] is measured in local world units before scale is applied.

The built-in Pict renderer treats @racket[fill] and @racket[stroke] as color
values and @racket[stroke-width] as a Pict border width. These style values are
stored without adapter-specific validation.

Circle Visuals implement @racket[gen:visual],
@racket[gen:affine-visual], @racket[gen:opacity-visual], and
@racket[gen:stroke-width-visual]. The
@racket[opacity] value multiplies the complete rendered circle after renderer
dispatch.
}

@defproc[(circle-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in circle Visual.
}

@defproc[(circle-visual-radius [circle circle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local radius in world units.
}

@defproc[(circle-visual-fill [circle circle-visual?]) any/c]{

Returns the stored fill style.
}

@defproc[(circle-visual-stroke [circle circle-visual?]) any/c]{

Returns the stored stroke style.
}

@defproc[(circle-visual-stroke-width [circle circle-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored stroke width.
}

@subsection{Rectangle Visuals}

@defproc[(rectangle
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:width width (and/c finite-real? positive?) 2]
          [#:height height (and/c finite-real? positive?) 1]
          [#:fill fill any/c "goldenrod"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         rectangle-visual?]{

Creates a semantic rectangle. The untransformed rectangle is centered at its
reference position and is axis-aligned in local coordinates. The
@racket[center] value is in the Visual's containing coordinate system: world
coordinates at the top level and group-local coordinates for a child. Width and
height are measured before scale and rotation are applied.

The @racket[id] argument is required. Style values are stored for an adapter to
interpret. Rectangle Visuals implement the basic, affine, opacity, and
stroke-width Visual protocols. The @racket[opacity] value multiplies the complete rendered
rectangle.
}

@defproc[(rectangle-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in rectangle Visual.
}

@defproc[(rectangle-visual-width [rectangle rectangle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local width in world units.
}

@defproc[(rectangle-visual-height [rectangle rectangle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local height in world units.
}

@defproc[(rectangle-visual-fill [rectangle rectangle-visual?]) any/c]{

Returns the stored fill style.
}

@defproc[(rectangle-visual-stroke [rectangle rectangle-visual?]) any/c]{

Returns the stored stroke style.
}

@defproc[(rectangle-visual-stroke-width [rectangle rectangle-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored stroke width.
}

@subsection[#:tag "plain-text-visuals"]{Plain-Text Visuals}

A plain-text Visual stores one immutable line of Unicode text and explicit font
and anchor data. It implements @racket[gen:visual],
@racket[gen:affine-visual], and @racket[gen:opacity-visual]. Its raw structure
constructor and internal transform and opacity fields are not public.

The reference position is an anchor selected on the untransformed text box.
Horizontal alignment chooses its left edge, center, or right edge. Vertical
alignment chooses its top edge, center, font baseline, or bottom edge. Scale
and rotation are applied around that anchor.

@defproc[(text-font-family? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of the supported portable font
family symbols:

@racketblock[
'default
'decorative
'roman
'script
'swiss
'modern
'symbol
'system
]

A family is a portable request, not a promise of one particular installed font
face. The drawing backend chooses a suitable platform font.
}

@defproc[(text-font-style? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['normal], @racket['italic], or
@racket['slant]. These are the supported font slant styles.
}

@defproc[(text-font-weight? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['normal], @racket['bold], or
@racket['light].
}

@defproc[(text-horizontal-alignment? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['left], @racket['center], or
@racket['right]. The value identifies the horizontal part of the text box that
is placed at the Visual's reference position.
}

@defproc[(text-vertical-alignment? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['top], @racket['center],
@racket['baseline], or @racket['bottom]. The @racket['baseline] choice places
the font baseline at the Visual's reference position.
}

@defproc[(plain-text
          [content string?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1/2]
          [#:font-face font-face (or/c string? #f) #f]
          [#:font-family font-family text-font-family? 'default]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         text-visual?]{

Creates a semantic one-line text Visual. The required @racket[id] is its stable
Visual identity. @racket[center] is the selected text anchor in the containing
coordinate system. At the top level it is a world-space point; inside a group
it is local to that group.

@racket[content] may be empty and may contain arbitrary Unicode characters, but
it may not contain a carriage return or newline. The constructor copies the
string into immutable storage. A mutable @racket[font-face] string is copied in
the same way. A false @racket[font-face] asks the backend to select a face from
@racket[font-family]. When both are supplied, the face is preferred and the
family remains the fallback classification.

@racket[font-size] is measured in local world units before the Visual's
@racket[scale] is applied. The default is one half world unit. Non-uniform scale
may stretch the rendered text independently in x and y. Rotation is
counter-clockwise in radians.

@racket[color] is deliberately opaque model data. The built-in Pict renderer
passes it to Pict color handling. A different renderer may interpret it
differently. @racket[opacity] is semantic global opacity and is applied to the
complete rendered line after renderer dispatch.

The alignment arguments determine which point of the original text box is at
@racket[center]. Alignment is resolved before scale and rotation. This makes a
left-baseline label, for example, grow to the right and rotate around the start
of its baseline.
}

@defproc[(text-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in plain-text Visual.
}

@defproc[(text-visual-content [visual text-visual?]) string?]{

Returns the immutable single-line content string.
}

@defproc[(text-visual-font-size [visual text-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled font size in local world units.
}

@defproc[(text-visual-font-face [visual text-visual?])
         (or/c string? #f)]{

Returns the preferred immutable font-face string, or @racket[#f] when no face
was requested. Font availability and exact substitution are properties of the
rendering environment, not the semantic model.
}

@defproc[(text-visual-font-family [visual text-visual?])
         text-font-family?]{

Returns the portable fallback font-family symbol.
}

@defproc[(text-visual-font-style [visual text-visual?])
         text-font-style?]{

Returns the stored font slant style.
}

@defproc[(text-visual-font-weight [visual text-visual?])
         text-font-weight?]{

Returns the stored font weight.
}

@defproc[(text-visual-color [visual text-visual?]) any/c]{

Returns the stored adapter color value.
}

@defproc[(text-visual-horizontal-alignment [visual text-visual?])
         text-horizontal-alignment?]{

Returns the horizontal anchor alignment.
}

@defproc[(text-visual-vertical-alignment [visual text-visual?])
         text-vertical-alignment?]{

Returns the vertical anchor alignment.
}

@defproc[(text-visual-with-content [visual text-visual?]
                                   [content string?])
         text-visual?]{

Returns a new text Visual with @racket[content] installed as immutable
single-line text. Identity, affine transform, opacity, font data, color, and
alignment are preserved. The original Visual is unchanged. A carriage return
or newline is rejected.
}

@subsection[#:tag "formula-visuals"]{LaTeX Formula Visuals}

A formula Visual stores an immutable LaTeX mathematical snippet and explicit
typesetting data. It implements @racket[gen:visual],
@racket[gen:affine-visual], and @racket[gen:opacity-visual]. Its raw structure
constructor and internal transform and opacity fields are not public.

Formula model values are backend-independent. They do not contain Picts, PDF
pages, Poppler values, process handles, or cached TeX results. The built-in
adapter calls @racketmodname[latex-pict] only when a nonempty formula is
rendered.

@defproc[(formula-mode? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of the supported formula modes:

@racketblock[
'inline
'display
'display-environment
]

The @racket['inline] mode uses ordinary inline mathematics. The
@racket['display] mode uses display-style mathematics in a tight inline box.
The @racket['display-environment] mode uses a real LaTeX display environment,
which can include wider horizontal margins.
}

@defproc[(latex-option? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a symbol or string accepted as one
ordered LaTeX option. Mutable strings satisfy this predicate; constructors copy
them into immutable model storage.
}

@defproc[(latex-formula
          [source string?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:preview-options preview-options
                             (listof latex-option?)
                             '()]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         formula-visual?]{

Creates a semantic mathematical formula Visual. The required @racket[id] is
its stable Visual identity. @racket[center] is the selected formula anchor in
the containing coordinate system. At the top level it is a world-space point;
inside a group it is local to that group.

@racket[source] is a LaTeX mathematical snippet without surrounding dollar
signs, @litchar{\\( ... \\)}, or @litchar{\\[ ... \\]} delimiters. The selected
@racket[mode] supplies those delimiters. Formula source may contain carriage
returns and newlines. It may also be empty. The constructor copies it into an
immutable string.

The mode-to-typesetter mapping is:

@tabular[
 #:style 'boxed
 (list
  (list @bold{Mode} @bold{latex-pict operation})
  (list @racket['inline] @tt{tex-math})
  (list @racket['display] @tt{tex-display-math})
  (list @racket['display-environment] @tt{tex-real-display-math}))]

The @racket[font-size] value is measured in local world units before semantic
@racket[scale] is applied. The adapter asks @racketmodname[latex-pict] to typeset
at its natural scale and then maps the selected document base of 10pt, 11pt, or
12pt to the requested world-unit size. When no standard size option is present,
10pt is assumed. Supplying more than one distinct standard size option is an
error. Other document-class options and preamble commands may still change the
formula's visible metrics.

The complete visible height and width depend on the formula content. The
constructor does not automatically separate two independent formula Visuals,
so their rendered boxes can overlap when their anchors are placed too close
together. Use @racket[visual-layout-box], @racket[visual-place-above],
@racket[visual-place-below], or @racket[arrange-visuals-vertically] when spacing
must follow the actual rendered boxes.

@racket[preamble] is inserted into the generated LaTeX document. The
@racket[document-class-options] and @racket[preview-options] lists are passed in
stored order. Their strings and @racket[preamble] are copied into immutable
storage. Option order is significant because a LaTeX document class or package
may interpret options in order. The adapter passes these values and an extra
typesetter scale of one explicitly, so process-wide @racketmodname[latex-pict]
parameters do not silently change a formula Visual.

The alignment arguments select the left, center, or right horizontal point and
the top, center, baseline, or bottom vertical point of the untransformed
typeset Pict. That point is placed at @racket[center]. Scale and rotation are
then applied around the anchor.

The semantic model has no separate formula color field in this stage. Use
LaTeX source or preamble commands when colored mathematics is needed. This
avoids promising that a generic Pict recoloring operation can reliably recolor
arbitrary PDF-derived formula content.

Rendering a nonempty formula requires the @racketmodname[latex-pict] package,
a working @tt{pdflatex}, Poppler, the requested document class, and every
package named by the preamble. Model construction, scene sampling, and empty
formula rendering do not run TeX. Exact output depends on those external tools
and their installed versions. Formula source and preamble are trusted input;
this library does not sandbox the TeX process.
}

@subsubsection{Making @tt{latex-pict} Available}

Use the same Racket installation for this library and for @tt{latex-pict}. For
example, to install the catalog package with Racket 9.3.0.2 on macOS:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  latex-pict
}

For a local checkout, link the checkout with that same @tt{raco} executable:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  --link \
  "/Users/soegaard/Dropbox/GitHub/latex-pict"
}

A one-command alternative is to add the checkout root to @tt{PLTCOLLECTS}:

@verbatim{
PLTCOLLECTS="/Users/soegaard/Dropbox/GitHub/latex-pict:" \
  "/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/formula-visuals.rkt \
  frames/formula-visuals \
  formula-visuals.mp4
}

The trailing colon is significant. It keeps Racket's ordinary collection paths
after the added checkout. A package linked with one Racket installation is not
automatically visible to another installation, so use matching @tt{racket} and
@tt{raco} executables.

@defproc[(formula-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in LaTeX formula Visual.
}

@defproc[(formula-visual-source [visual formula-visual?]) string?]{

Returns the immutable LaTeX source string without surrounding mathematical
delimiters.
}

@defproc[(formula-visual-mode [visual formula-visual?]) formula-mode?]{

Returns the stored formula display mode.
}

@defproc[(formula-visual-font-size [visual formula-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled semantic formula font size in local world units.
}

@defproc[(formula-visual-preamble [visual formula-visual?]) string?]{

Returns the immutable additional LaTeX preamble string.
}

@defproc[(formula-visual-document-class-options
          [visual formula-visual?])
         (listof latex-option?)]{

Returns the ordered document-class options. String options are immutable.
Ordering is significant.
}

@defproc[(formula-visual-preview-options [visual formula-visual?])
         (listof latex-option?)]{

Returns the ordered options passed to the LaTeX Preview package by
@racketmodname[latex-pict]. String options are immutable. The mode-specific
option used by @racketmodname[latex-pict] is added by that package separately.
}

@defproc[(formula-visual-horizontal-alignment [visual formula-visual?])
         text-horizontal-alignment?]{

Returns the horizontal formula-anchor alignment.
}

@defproc[(formula-visual-vertical-alignment [visual formula-visual?])
         text-vertical-alignment?]{

Returns the vertical formula-anchor alignment.
}

@defproc[(formula-visual-with-source [visual formula-visual?]
                                     [source string?])
         formula-visual?]{

Returns a new formula Visual with @racket[source] copied into immutable model
storage. Identity, affine transform, opacity, mode, font size, preamble,
ordered option lists, and alignment are preserved. The original Visual is
unchanged. Multiline and empty source are accepted.
}


@subsection[#:tag "tagged-formulas"]{Tagged Formula Layouts}

@defstruct*[formula-fragment ([name symbol?]
                              [source string?])
  #:transparent]{

Represents one author-declared contiguous TeX fragment. @racket[name] is the
local part name in a @racket[tagged-formula]; @racket[source] must be a nonempty
string. Names must be unique within each tagged formula.

Fragments are deliberately explicit. Animate does not parse arbitrary TeX into
tokens, so a fragment must be a valid piece of the complete math expression and
must produce visible ink.
}

@defproc[(tagged-formula
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size (and/c finite-real? positive?) 1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [fragment formula-fragment?] ...)
         formula-assembly-visual?]{

Builds one full-layout formula from one or more @racket[formula-fragment]
values. Unlike @racket[formula-assembly], the fragments are typeset together.
Their positions, ordinary TeX spacing, kerning, scripts, and alignment come
from the complete formula rather than from manually supplied part positions.

Construction runs the external @tt{latex} and @tt{dvisvgm} executables once.
It wraps every fragment in a dvisvgm SVG group, measures the group, and returns
an ordinary formula assembly whose parts render as the resulting SVG fragments.
Those SVG fragments are renderer-cached, so sampling or rendering animation
frames does not run TeX again. Both executables must be available on
@tt{PATH} when this constructor is called.

All keyword options have the same validation and semantic meaning as for
@racket[latex-formula], except that Preview-package options and per-fragment
anchors are not applicable to a formula whose layout is computed as one unit.
The returned assembly can be moved, rotated, scaled, faded, addressed through
nested part paths, and used with the normal formula-correspondence operations.
}

@defproc[(glyph-tex
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size (and/c finite-real? positive?) 1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [source string?] ...)
         formula-assembly-visual?]{

Typesets one complete TeX expression and exposes each visible dvisvgm glyph
leaf as a formula part named @racket['glyph-0], @racket['glyph-1], and so on,
in painter order. The complete expression is still typeset as one unit, so its
ordinary TeX spacing, kerning, and script placement are retained. Construction
has the same external @tt{latex} and @tt{dvisvgm} requirements as
@racket[tagged-formula].

The generated glyph parts retain the complete author TeX source, but their
matching identity is the referenced dvisvgm path outline together with their
typesetting options. Consequently, exact unchanged glyphs can match between
two separately compiled expressions despite dvisvgm assigning different local
font-definition ids on each compilation. Use @racket[tagged-formula] or
@racket[math-tex] when several glyphs need one semantic identity: glyph leaves
are not TeX tokens, a superscript or accent can contain several leaves, and
repeated outlines match greedily in source order.
}

@defproc[(tagged-formula-fragment-visual? [value any/c]) boolean?]{

Returns @racket[#t] for a generated fragment Visual inside a tagged formula.
The subtype is also a @racket[formula-visual?].
}

@defproc[(tagged-formula-fragment-visual-svg-source
          [visual tagged-formula-fragment-visual?])
         string?]{

Returns the immutable SVG source used to render one generated tagged fragment.
This is provided for inspection and renderer integration; construct fragments
through @racket[tagged-formula], not by manufacturing this renderer detail.
}

@defproc[(transform-matching-formula
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:matches matches (listof formula-part-match?) '()])
         transform-formula-parts-request?]{

Builds a correspondence transform in the style of Manim's matching formula
transitions. Explicit @racket[matches] have priority. Animate then automatically
pairs every remaining source fragment with the first still-unmatched destination
fragment that has exactly the same formula source and typesetting options, in
source order.

Exact matches render as one rigid SVG group that moves with its local transform.
Changed explicit matches are moving cross-fades, and unmatched fragments use the
normal fade-out/fade-in behavior. This operation does not infer algebraic
equivalence, parse TeX tokens, choose paths/arcs for the movement, or morph
glyph outlines.
}

@defproc[(transform-matching-glyphs
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:matches matches (listof formula-part-match?) '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:changed-mode changed-mode (or/c 'fade 'morph) 'fade])
         transform-formula-parts-request?]{

Builds the glyph-level counterpart to @racket[transform-matching-formula]. Both
assemblies must have been produced by @racket[glyph-tex]. Exact dvisvgm path
outlines pair automatically in source order; use @racket[matches] for a
deliberate changed glyph, such as mapping the generated plus-sign part to the
destination minus-sign part. The remaining keywords have the same meanings as
for @racket[transform-matching-formula].

This matches and moves whole rendered glyph leaves. @racket['fade] is the
default: changed matches use the ordinary moving cross-fade. With
@racket[#:changed-mode 'morph], a changed matched pair instead interpolates its
outline only when both cropped dvisvgm SVG fragments expand to one identically
painted path whose positive-length contours are all closed and compatible in
count. Animate globally pairs those destination contours with the source,
phase-aligns them without reversing their traversal, normalizes the resulting
paths to compatible cubic segments, and uses that path geometry only for
interior frames; the ordinary tagged SVG fragments remain exact endpoints.
Glyphs with multiple independently painted paths, open contours, incompatible
contour topology, changed paint, or unsupported geometry safely fall back to
the moving cross-fade.

This operation does not derive a mathematical operation, identify TeX
characters or terms, perform semantic grouping, or infer which changed glyphs
should be paired.
}

@defproc[(rewrite-formula
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:anchor anchor (or/c symbol? formula-part-match?)]
          [#:matches matches (listof formula-part-match?) '()]
          [#:stationary stationary
                        (listof (or/c symbol? formula-part-match?))
                        '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade])
         transform-formula-parts-request?]{

Builds a matching formula transition with one fixed named anchor. Pass a symbol
such as @racket['equals] when the part has the same name at both endpoints, or
a @racket[formula-part-match] when its names differ. The anchor is made an
explicit match; a conflicting value in @racket[matches] raises an error.

When @racket[scene-play] compiles the request, Animate translates the complete
destination layout so the destination anchor coincides with the corresponding
part in the @italic{current} source formula. Consequently, a sequence of
rewrites keeps the anchor fixed even when the formula values passed as earlier
templates were constructed at their own default positions. The translation
preserves the target formula's TeX spacing and baselines.

Each @racket[stationary] entry names an additional matched pair: a symbol means
the same source and destination part name, while a @racket[formula-part-match]
permits different names. The pair is made explicit, and at clip compilation
the destination fragment receives the current source fragment's exact affine
transform. Thus several selected terms can remain fixed even if the rest of the
destination layout moves or reflows. This is an explicit presentation choice;
it does not infer which terms should remain still or maintain a general layout
constraint between them.

The remaining keywords have the same meaning as in
@racket[transform-matching-formula]: explicit matches take priority, routes and
copies select intentional term motion, and @racket['fade-transform] cross-fades
remaining unmatched parts while moving them. Like the lower-level operation,
this is whole-fragment correspondence rather than TeX parsing or glyph-outline
morphing.
}

@defproc[(formula-step
          [destination formula-assembly-visual?]
          [#:anchor anchor (or/c false/c symbol? formula-part-match?) #f]
          [#:stationary stationary
                        (listof (or/c symbol? formula-part-match?))
                        '()]
          [#:matches matches (listof formula-part-match?) '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:duration duration (and/c finite-real? positive?) 1]
          [#:pause pause (and/c finite-real? (>=/c 0)) 1/2]
          [#:explanation explanation (or/c false/c string?) #f])
         formula-derivation-step?]{

Describes one explicit rewrite endpoint for @racket[formula-derivation]. The
destination and rewrite keywords have the same meanings as @racket[rewrite-formula].
@racket[pause] is the amount of time to hold the optional explanation before
this step's transition begins. An explanation must be one line of plain text.

@racket[anchor] defaults to @racket[#f], which means that the derivation's
shared anchor is used. A step can override it with a same-name symbol or an
explicit @racket[formula-part-match]. @racket[stationary] has the same meaning
as in @racket[rewrite-formula] and makes additional matched parts fixed for
this one step. This data does not claim that the rewrite is algebraically valid;
it records the author's chosen presentation.
}

@defproc[(formula-derivation-step? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] was created by @racket[formula-step].
}

@defproc[(formula-derivation
          [scene scene?]
          [initial formula-assembly-visual?]
          [#:anchor anchor (or/c symbol? formula-part-match?)]
          [#:steps steps (listof formula-derivation-step?)]
          [#:explanation-position explanation-position
                                  (or/c false/c vec2?)
                                  #f]
          [#:explanation-id explanation-id symbol? 'derivation-note]
          [#:explanation-font-size explanation-font-size
                                    (and/c finite-real? positive?)
                                    1/4]
          [#:explanation-color explanation-color any/c "darkslategray"])
         scene?]{

Appends an ordered derivation to @racket[scene]. @racket[initial] must already
be present in the scene under its formula identity. For each @racket[steps]
entry, the builder first replaces its own optional explanation label, waits for
that step's @racket[pause], and then appends a @racket[rewrite-formula] clip
with the requested duration and correspondence options. The resulting endpoint
becomes the construction template for the next step, while every rewrite still
resolves its anchor from the current sampled scene formula.

When any step has an explanation, supply @racket[explanation-position]. The
builder creates plain text with @racket[explanation-id], which must be absent
from the initial scene. Later explanations replace only that generated Visual.
The final explanation remains visible unless a later step omits it.

This is immutable convenience syntax over existing scene and formula APIs. It
does not parse TeX, infer operations, prove a derivation, choose matches/routes,
or automatically lay out the explanation.
}

@subsection[#:tag "formula-parts"]{Named Formula Parts and Correspondence}

A formula assembly is a composite Visual made from independently typeset LaTeX
formula parts. Each part has a symbol name. That name is local to one assembly
and is also the identity of the part's formula Visual.

Part order is significant back-to-front drawing order. Part positions are local
to the assembly anchor. The library does not ask TeX to lay out several parts
as one document. The caller chooses each local position explicitly. Parts can
overlap when their local anchors are placed too close together.

@defstruct*[formula-part ([name symbol?]
                          [formula formula-visual?])
  #:transparent]{

Represents one named formula fragment.

The @racket[name] field is local to one formula assembly. The
@racket[formula] field contains the complete semantic formula Visual used to
render the fragment. The structure guard requires
@racket[(eq? name (visual-id formula))]. This rule gives each local name one
stable formula identity.

The formula transform and opacity are local to its containing assembly. The
structure is immutable and transparent.
}

@defproc[(latex-formula-part
          [source string?]
          [#:name name symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:preview-options preview-options
                             (listof latex-option?)
                             '()]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         formula-part?]{

Creates a @racket[formula-part] and its formula Visual in one step.
@racket[name] becomes both @racket[formula-part-name] and the formula Visual
identity. Every other argument has the same meaning and validation as the
corresponding argument to @racket[latex-formula].

The @racket[center] value is local to the formula assembly that will contain the
part. Formula source, preamble, and string options are copied into immutable
model storage.

Example:

@racketblock[
(latex-formula-part "n(n+1)"
                    #:name 'numerator
                    #:center (vec2 0 1/2)
                    #:mode 'inline
                    #:font-size 1/3)
]
}

@defproc[(formula-assembly
          [parts (listof formula-part?)]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         formula-assembly-visual?]{

Creates a semantic formula assembly. The @racket[parts] list is stored in
significant back-to-front order. An empty list creates a valid empty assembly.

Part names must be unique within the assembly. Because every part name is also
its formula Visual identity, @racket[id] must differ from every part name.
Part names are local: two different assemblies may use the same names.

The assembly @racket[center] is its reference position in the containing
coordinate system. The assembly rotation is measured counter-clockwise in
radians. Its own scale must be uniform after normalization. This is the same
restriction used by @racket[group]; a non-uniform parent scale followed by a
rotated part can require shear, which the current transform model cannot
represent. Individual formula parts may still use non-uniform local scales.

The assembly implements @racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual]. Existing movement, rotation, uniform scale,
opacity, @racket[fade-in], and @racket[fade-out] operations therefore work on
the complete assembly.

Every nonempty part is typeset separately. The caller is responsible for local
part spacing. The Pict adapter passes the same explicit renderer list to every
part. A custom renderer placed before the defaults may instead support and
replace the complete assembly. An empty assembly renders as stable transparent
one-pixel local geometry without running TeX.
}

@defproc[(formula-assembly-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in formula assembly Visual.
}

@defproc[(formula-assembly-visual-parts
          [assembly formula-assembly-visual?])
         (listof formula-part?)]{

Returns the assembly's parts in significant back-to-front order. The returned
list is immutable model data.
}

@defproc[(formula-assembly-visual-with-parts
          [assembly formula-assembly-visual?]
          [parts (listof formula-part?)])
         formula-assembly-visual?]{

Returns a new assembly with @racket[parts] as its significant ordered part
list. Assembly identity, reference position, rotation, uniform scale, and opacity
are preserved. The same name and identity checks as
@racket[formula-assembly] are performed. The original assembly is unchanged.
}

@defproc[(formula-assembly-visual-part-names
          [assembly formula-assembly-visual?])
         (listof symbol?)]{

Returns local part names in significant back-to-front order.
}

@defproc[(formula-assembly-visual-has-part?
          [assembly formula-assembly-visual?]
          [name symbol?])
         boolean?]{

Returns @racket[#t] when @racket[assembly] contains a part named
@racket[name]. This operation searches the local part namespace; it does not
search the top-level scene state.
}

@defproc[(formula-assembly-visual-ref
          [assembly formula-assembly-visual?]
          [name symbol?])
         formula-part?]{

Returns the part named @racket[name]. An exception is raised when the local name
is absent. The result is a @racket[formula-part], so use
@racket[formula-part-formula] to obtain its formula Visual.
}

@defstruct*[formula-part-match ([source-name symbol?]
                                [destination-name symbol?])
  #:transparent]{

Represents one manually chosen source-to-destination part match.

@racket[source-name] names a part in a source assembly.
@racket[destination-name] names a part in a destination assembly. The structure
itself checks only that both fields are symbols. A
@racket[formula-correspondence] checks that the names exist and are used
one-to-one.
}

@defstruct*[formula-correspondence
            ([source formula-assembly-visual?]
             [destination formula-assembly-visual?]
             [matches (listof formula-part-match?)])
  #:transparent]{

Represents a validated manual mapping between two formula assemblies.

The @racket[source] and @racket[destination] fields store the exact immutable
assembly values used when the correspondence is created. The @racket[matches]
field is stored in significant caller order.

Construction checks all of the following:

@itemlist[
 @item{Every source name exists in @racket[source].}
 @item{Every destination name exists in @racket[destination].}
 @item{A source name appears at most once.}
 @item{A destination name appears at most once.}
]

The match list may be empty. Equal names are not matched automatically. Parts
omitted from @racket[matches] remain explicitly unmatched. The list order is
also the order of matched transition layers created by
@racket[transform-formula-parts].
}

@defproc[(formula-correspondence-auto [source formula-assembly-visual?]
                                      [destination formula-assembly-visual?])
         formula-correspondence?]{

Builds a deterministic correspondence for unchanged formula parts. Each source
part is considered in source order and matches the first still-unmatched
destination part with the same LaTeX source and typesetting options. This allows
stable part names to change without losing unchanged semantic content. Parts
without a match remain unmatched and follow the ordinary fade-out/fade-in
transition behavior.
}

@defproc[(formula-correspondence-unmatched-source-names
          [correspondence formula-correspondence?])
         (listof symbol?)]{

Returns source part names that do not occur in any match. The result preserves
the source assembly's significant part order.
}

@defproc[(formula-correspondence-unmatched-destination-names
          [correspondence formula-correspondence?])
         (listof symbol?)]{

Returns destination part names that do not occur in any match. The result
preserves the destination assembly's significant part order.
}

A formula correspondence stores endpoint templates. It does not store sampled
transition layers. Those layers are compiled when
@racket[transform-formula-parts] is passed to @racket[scene-play], so the
operation can use the current formulas, local transforms, and local opacities
from the scene.

@subsection{Path Visuals}

A path Visual combines local @racket[path-geometry] with identity, affine
placement, fill, stroke, and cosmetic stroke width. Its geometry may contain
line segments, cubic Bézier segments, or both. It implements
@racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual].

The Visual's reference position is the translation component of its affine
transform. Its path points remain local model data. Scale and rotation are
applied around the local origin before the Visual is translated to its
reference position.

@defproc[(make-path-visual
          [path path-geometry?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:fill fill any/c #f]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         path-visual?]{

Creates a semantic path Visual from local @racket[path] geometry. The
@racket[id] argument is required. @racket[center] is the Visual's reference
position in its containing coordinate system. It is a world-space point at the
top level and a group-local point when the Visual is a child. Rotation is
measured counter-clockwise in radians, and scale is applied to local x and y
coordinates before rotation.
@racket[opacity] is global and is applied to the complete rendered path after
renderer dispatch.

The built-in Pict renderer interprets a false @racket[fill] as transparent and
a false @racket[stroke] as no outline. Other style values are passed to the
Racket drawing backend as color values. Stroke width is cosmetic and measured
in output pixels; semantic scale does not multiply it.

Empty path geometry is accepted and produces a transparent one-pixel Pict in
the built-in renderer.
}

@defproc[(path-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in path Visual.
}

@defproc[(path-visual-path [visual path-visual?]) path-geometry?]{

Returns @racket[visual]'s local semantic path geometry. The returned geometry
has not been translated, rotated, scaled, or converted to pixels.
}

@defproc[(path-visual-fill [visual path-visual?]) any/c]{

Returns the stored fill style. The built-in renderer uses it only for closed
subpaths. A false value disables filling.
}

@defproc[(path-visual-stroke [visual path-visual?]) any/c]{

Returns the stored stroke style. A false value disables stroking in the
built-in renderer.
}

@defproc[(path-visual-stroke-width [visual path-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(path-visual-with-path [visual path-visual?]
                                [path path-geometry?])
         path-visual?]{

Returns a new path Visual with its local geometry replaced by @racket[path].
Identity, affine transform, opacity, fill, stroke, and stroke width are
preserved. The original Visual is unchanged.
}

@defproc[(line [start vec2?]
               [end vec2?]
               [#:id id symbol?]
               [#:rotation rotation finite-real? 0]
               [#:scale scale scale-factor? 1]
               [#:opacity opacity opacity? 1]
               [#:stroke stroke any/c "black"]
               [#:stroke-width stroke-width
                               (and/c finite-real? (>=/c 0))
                               2])
         path-visual?]{

Creates an open path Visual between two points in one containing coordinate
system. The points are world-space values when the result is top level and
local values when the result is placed in a group. @racket[start] and
@racket[end] must differ.

The constructor uses the midpoint of the two points as the Visual's reference
position and subtracts that midpoint from both stored path points. The local
line is therefore centered at the origin. Rotation and scale are applied around
that midpoint. The fill style is always @racket[#f]. The optional
@racket[opacity] value is preserved as semantic global opacity.

For example:

@racketblock[
(line (vec2 -2 0)
      (vec2 2 0)
      #:id 'axis
      #:stroke "navy"
      #:stroke-width 3)
]
}

@defproc[(polygon [vertices (listof vec2?)]
                  [#:id id symbol?]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale scale-factor? 1]
                  [#:opacity opacity opacity? 1]
                  [#:fill fill any/c "cornflowerblue"]
                  [#:stroke stroke any/c "black"]
                  [#:stroke-width stroke-width
                                  (and/c finite-real? (>=/c 0))
                                  2])
         path-visual?]{

Creates a closed path Visual through at least three @racket[vertices] in one
containing coordinate system. The vertices are world-space values at the top
level and local values when the result is placed in a group. Vertex order is
significant.

The constructor computes the center of the vertices' axis-aligned bounding box
and uses it as the Visual's reference position. It subtracts that center from
every stored path point, so scale and rotation occur around the bounding-box
center. The constructor does not calculate a polygon centroid.

The closing edge from the last vertex to the first is implicit. Do not repeat
the first vertex merely to close the polygon; repeating it adds a zero-length
segment before the implicit closing edge. The optional @racket[opacity] value is
stored as semantic global opacity.
}

@subsection{Bitmap Images}

@defproc[(image [source path-string?]
                [#:id id symbol?]
                [#:center center vec2? origin]
                [#:rotation rotation finite-real? 0]
                [#:scale scale scale-factor? 1]
                [#:opacity opacity opacity? 1]
                [#:width width (and/c finite-real? positive?)]
                [#:height height (and/c finite-real? positive?)])
         image-visual?]{

Creates an immutable bitmap-image Visual. @racket[source] is copied as a path
string but is not opened during construction, scene sampling, or timeline
compilation. @racket[width] and @racket[height] specify the unscaled local
world dimensions, independently of the bitmap's source-pixel dimensions.

The built-in renderer loads the source lazily, scales it to the requested world
size at the current camera scale, then applies the normal Visual scale and
rotation. A missing or unreadable source therefore raises a renderer-time error.
Its renderer-local bitmap cache is bounded and does not affect scene semantics.
Image Visuals implement affine and opacity protocols, so standard movement,
scaling, rotation, fading, grouping, layout, camera placement, and frame
rendering work without a special timeline request.
}

@defproc[(image-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in bitmap image Visual.
}

@defproc[(image-visual-source [visual image-visual?]) immutable-string?]{

Returns the copied renderer-resolved source pathname.
}

@defproc[(image-visual-width [visual image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world width.
}

@defproc[(image-visual-height [visual image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world height.
}

@subsection{Full-Fidelity SVG Images}

@defproc[(svg-image [source path-string?]
                    [#:id id symbol?]
                    [#:center center vec2? origin]
                    [#:rotation rotation finite-real? 0]
                    [#:scale scale scale-factor? 1]
                    [#:opacity opacity opacity? 1]
                    [#:width width (and/c finite-real? positive?)]
                    [#:height height (and/c finite-real? positive?)])
         svg-image-visual?]{

Creates an immutable full-fidelity static SVG Visual. @racket[source] is not
opened until rendering; the default renderer delegates then to the catalog
@racketmodname[svg/svg] package. That renderer supports substantially more SVG
than the semantic importer, including transforms, gradients, clipping, masks,
text, local image references, CSS, and many static filters.

@racket[width] and @racket[height] specify unscaled local world dimensions,
independently of the SVG document's viewport. The Visual otherwise behaves like
@racket[image]: standard movement, scaling, rotation, opacity animation,
groups, layout, camera placement, and frame rendering work normally. The
renderer has a bounded local source-Pict cache. Use @racket[svg->visual] rather
than this constructor when individual SVG elements must be directly addressed
or animated.
}

@defproc[(svg-image-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in full-fidelity SVG Visual.
}

@defproc[(svg-image-visual-source [visual svg-image-visual?]) immutable-string?]{

Returns the copied renderer-resolved SVG source pathname.
}

@defproc[(svg-image-visual-width [visual svg-image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world width.
}

@defproc[(svg-image-visual-height [visual svg-image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world height.
}

@subsection{Semantic SVG Import}

@defproc[(svg->visual [source path-string?]
                      [#:id id symbol?]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale scale-factor? 1]
                      [#:opacity opacity opacity? 1])
         group-visual?]{

Reads an SVG XML file once and converts supported geometry into an immutable
semantic group. SVG @tt{path}, @tt{line}, @tt{polyline}, @tt{polygon},
@tt{rect}, @tt{circle}, @tt{ellipse}, and nested @tt{g} elements are supported.
The path importer accepts absolute and relative @tt{M}, @tt{L}, @tt{H}, @tt{V},
@tt{C}, @tt{Q}, and @tt{Z} commands; quadratic segments are converted exactly
to cubic semantic segments. Unsupported graphical tags are ignored.

The root takes @racket[id]. An SVG element's nonempty @tt{id} becomes its stable
child identity; missing IDs receive deterministic generated symbols. Nested
@tt{g} elements become nested built-in groups, so imported IDs participate in
@racket[scene-ref], @racket[scene-visual-at], derived-context lookup, and all
nested style and transform requests. The constructor rejects duplicate IDs using
the existing built-in group-tree invariant.

SVG's screen-down y coordinate is converted to the semantic world-up y
coordinate. Unitless @tt{translate(x[, y])} transforms are supported. Other
SVG transforms must be flattened before import. Inherited @tt{fill}, @tt{stroke},
@tt{stroke-width}, and @tt{opacity} attributes (including simple inline
@tt{style} declarations) are preserved. CSS stylesheets, clipping, text, use
elements, arcs, and paint servers are outside this deliberately semantic subset.
}


@subsection[#:tag "arrows-and-axes"]{Arrow and Cartesian Axes Visuals}

Arrow and axes values are semantic affine Visuals. They implement
@racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual]. Their raw structure constructors and internal local
geometry fields are not public.

@subsubsection{Arrows}

@defproc[(arrow
          [start vec2?]
          [end vec2?]
          [#:id id symbol?]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2]
          [#:tip-length tip-length
                        (and/c finite-real? positive?)
                        3/10]
          [#:tip-width tip-width
                       (and/c finite-real? positive?)
                       1/4]
          [#:start-tip? start-tip? boolean? #f]
          [#:end-tip? end-tip? boolean? #t])
         arrow-visual?]{

Creates a semantic arrow whose untransformed shaft begins at @racket[start] and
ends at @racket[end]. Both points are in one containing coordinate system. They
are world coordinates for a top-level Visual and local coordinates when the
arrow is later placed in a group.

The points must be distinct and their distance must be finite. The constructor
uses their midpoint as the Visual's reference position and stores the two
endpoints relative to that midpoint. The optional @racket[rotation] and
@racket[scale] therefore act around the midpoint.

@racket[start-tip?] and @racket[end-tip?] independently select closed triangular
tips. The default is one tip at the end. Both flags may be false, or both may be
true. @racket[tip-length] measures the distance from an apex to the center of its
base. @racket[tip-width] measures the full base width. Both are local world-unit
geometry and are affected by semantic scale. A tip is allowed to be longer than
the shaft.

@racket[stroke] is adapter-specific style data. The built-in Pict renderer uses
it for the shaft, tip fill, and tip outline. @racket[stroke-width] is a cosmetic
output width and is not multiplied by semantic scale. @racket[opacity] is
applied to the complete rendered arrow after renderer dispatch.
}

@defproc[(arrow-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in arrow Visual.
}

@defproc[(arrow-visual-length [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled length of the stored local shaft. Translation, rotation,
and semantic scale do not change this result.
}

@defproc[(arrow-visual-stroke [arrow arrow-visual?]) any/c]{

Returns the stored adapter-specific stroke style.
}

@defproc[(arrow-visual-stroke-width [arrow arrow-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(arrow-visual-tip-length [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length of each enabled triangular tip.
}

@defproc[(arrow-visual-tip-width [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local base width of each enabled triangular tip.
}

@defproc[(arrow-visual-start-tip? [arrow arrow-visual?]) boolean?]{

Reports whether the start endpoint has a triangular tip.
}

@defproc[(arrow-visual-end-tip? [arrow arrow-visual?]) boolean?]{

Reports whether the end endpoint has a triangular tip.
}

@defproc[(arrow-visual-start [arrow arrow-visual?]) vec2?]{

Returns the current start point in the arrow's containing coordinate system.
The complete affine transform has been applied.
}

@defproc[(arrow-visual-end [arrow arrow-visual?]) vec2?]{

Returns the current end point in the arrow's containing coordinate system. The
complete affine transform has been applied.
}

@defproc[(arrow-visual-point-at
          [arrow arrow-visual?]
          [progress (real-in 0 1)])
         vec2?]{

Returns the current shaft point at @racket[progress]. A value of @racket[0]
returns the transformed start, @racket[1] returns the transformed end, and
@racket[1/2] returns the transformed midpoint. The procedure follows the shaft
only; tip geometry does not affect the result.
}

@subsubsection{Axis Ranges}

@defstruct*[axis-range ([minimum finite-real?]
                        [maximum finite-real?]
                        [tick-step
                         (and/c finite-real? positive?)])
  #:transparent]{

Represents one closed numeric interval and the spacing of its regular ticks.
The fields have these meanings:

@itemlist[
 @item{@racket[minimum] is the smallest represented coordinate.}
 @item{@racket[maximum] is the largest represented coordinate.}
 @item{@racket[tick-step] is the positive distance between regular tick
       coordinates.}
]

@racket[minimum] must be less than @racket[maximum]. The computed difference
@racket[(- maximum minimum)] must also remain a positive finite real; this
rejects an inexact endpoint pair whose subtraction overflows. The structure is immutable and
transparent. Linear axes require their ranges to contain zero; logarithmic axes
require strictly-positive ranges. Its public bindings include @racket[axis-range],
@racket[axis-range?], the three field accessors, and
@racket[struct:axis-range].
}

@defproc[(axis-range-contains? [range axis-range?] [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real in the closed interval
from @racket[(axis-range-minimum range)] through
@racket[(axis-range-maximum range)]. Non-real values, infinities, and NaN return
@racket[#f].
}

@defproc[(axis-range-tick-values [range axis-range?])
         (listof finite-real?)]{

Returns the nonzero integer multiples of @racket[(axis-range-tick-step range)]
that lie in the closed interval. The values are in increasing numeric order.
An interval endpoint is included when it is such a multiple. Zero is omitted
because the two Cartesian shafts already intersect there.

For example:

@racketblock[
(axis-range-tick-values (axis-range -3 5 2))
]

returns @racket['(-2 2 4)]. The procedure does not choose ticks from camera
pixels or available label space.

Exact endpoint quotients are handled exactly. For inexact quotients, the
procedure uses a fixed relative tolerance of @racket[1e-12] when choosing the
first and last integer indexes. This prevents ordinary decimal input such as
@racket[-0.3], @racket[0.3], and @racket[0.1] from losing endpoint ticks because
of binary floating-point rounding. It raises an exception when dividing a range
endpoint by the step produces an infinite or NaN index.
}

@defproc[(axis-scale? [value any/c]) boolean?]{

Returns @racket[#t] for the supported scale symbols @racket['linear] and
@racket['log].
}

@subsubsection{Cartesian Axes}

@defproc[(axes
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:x-range x-range axis-range? (axis-range -6 6 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:x-scale x-scale axis-scale? 'linear]
          [#:y-scale y-scale axis-scale? 'linear]
          [#:x-log-base x-log-base
                        (and/c finite-real? (>/c 1))
                        10]
          [#:y-log-base y-log-base
                        (and/c finite-real? (>/c 1))
                        10]
          [#:x-length x-length
                      (and/c finite-real? positive?)
                      12]
          [#:y-length y-length
                      (and/c finite-real? positive?)
                      6]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2]
          [#:tick-size tick-size
                       (and/c finite-real? (>=/c 0))
                       3/20]
          [#:tip-length tip-length
                        (and/c finite-real? positive?)
                        3/10]
          [#:tip-width tip-width
                       (and/c finite-real? positive?)
                       1/4]
          [#:x-tip? x-tip? boolean? #t]
          [#:y-tip? y-tip? boolean? #t])
         axes-visual?]{

Creates semantic two-dimensional Cartesian axes. On the default linear scales,
numeric coordinate @tt{(0, 0)} is the Visual's local origin and reference point
before @racket[center], @racket[rotation], and @racket[scale] are applied.

The full interval from @racket[(axis-range-minimum x-range)] to
@racket[(axis-range-maximum x-range)] is mapped to @racket[x-length] local world
units. The y interval is mapped independently to @racket[y-length]. The x and y
unit lengths can therefore differ. Each resulting length-per-display-unit must
remain a positive finite real.

With @racket['log] for @racket[x-scale] or @racket[y-scale], that axis accepts
only a strictly-positive @racket[axis-range]. Numeric coordinates are converted
through @racket[(log value)] in the configured base before they are placed. A
log axis uses numeric one as its shaft reference when it is visible (otherwise
the minimum range value); coordinate zero is invalid. @racket[x-log-base] and
@racket[y-log-base] must be finite and greater than one. The
@racket[tick-step] of a log range is a step in base-logarithm exponent space, so
the usual value of one produces ticks at successive powers of the base.

The x shaft is drawn at numeric y coordinate zero on a linear y axis, and at
numeric one (or the visible minimum) on a log y axis; the y shaft follows the
same rule for its x coordinate. Regular ticks come from
@racket[axis-range-tick-values] on linear axes and powers of the configured base
on log axes. @racket[tick-size] is the full local length of
each tick. A value of zero hides all ticks while preserving the ranges and
coordinate conversion.

@racket[x-tip?] and @racket[y-tip?] select triangular tips at the maximum-x and
maximum-y endpoints, respectively. @racket[tip-length] and @racket[tip-width]
are local world-unit geometry. @racket[stroke-width] is cosmetic. The built-in
renderer uses @racket[stroke] for shafts, ticks, tip fill, and tip outlines.

The constructor does not create numeric labels, axis-name labels, grid lines,
or sampled plots. They can be added as separate Visuals. Renderer-aware layout
can place labels around the complete axes render box.
}

@defproc[(axes-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in Cartesian-axes Visual.
}

@defproc[(axes-visual-x-range [axes axes-visual?]) axis-range?]{

Returns the stored horizontal numeric range.
}

@defproc[(axes-visual-y-range [axes axes-visual?]) axis-range?]{

Returns the stored vertical numeric range.
}

@defproc[(axes-visual-x-scale [axes axes-visual?]) axis-scale?]{

Returns the stored horizontal coordinate scale.
}

@defproc[(axes-visual-y-scale [axes axes-visual?]) axis-scale?]{

Returns the stored vertical coordinate scale.
}

@defproc[(axes-visual-x-log-base [axes axes-visual?])
         (and/c finite-real? (>/c 1))]{

Returns the stored horizontal logarithm base. It affects coordinate conversion
only when @racket[(axes-visual-x-scale axes)] is @racket['log].
}

@defproc[(axes-visual-y-log-base [axes axes-visual?])
         (and/c finite-real? (>/c 1))]{

Returns the stored vertical logarithm base. It affects coordinate conversion
only when @racket[(axes-visual-y-scale axes)] is @racket['log].
}

@defproc[(axes-visual-x-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing the full x range.
}

@defproc[(axes-visual-y-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing the full y range.
}

@defproc[(axes-visual-stroke [axes axes-visual?]) any/c]{

Returns the stored adapter-specific line and tip style.
}

@defproc[(axes-visual-stroke-width [axes axes-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(axes-visual-tick-size [axes axes-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the unscaled full local length of each tick.
}

@defproc[(axes-visual-tip-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length of each enabled maximum-end tip.
}

@defproc[(axes-visual-tip-width [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local base width of each enabled maximum-end tip.
}

@defproc[(axes-visual-x-tip? [axes axes-visual?]) boolean?]{

Reports whether the maximum-x endpoint has a triangular tip.
}

@defproc[(axes-visual-y-tip? [axes axes-visual?]) boolean?]{

Reports whether the maximum-y endpoint has a triangular tip.
}

@defproc[(axes-x-unit-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing one x display-space unit. On a
linear axis it is
@racket[(/ (axes-visual-x-length axes)
           (- (axis-range-maximum (axes-visual-x-range axes))
              (axis-range-minimum (axes-visual-x-range axes))))]. On a log
axis the denominator is the corresponding base-logarithm span.
}

@defproc[(axes-y-unit-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing one y display-space unit. On a
linear axis it is
@racket[(/ (axes-visual-y-length axes)
           (- (axis-range-maximum (axes-visual-y-range axes))
              (axis-range-minimum (axes-visual-y-range axes))))]. On a log
axis the denominator is the corresponding base-logarithm span.
}

@defproc[(axes-coordinates->point
          [axes axes-visual?]
          [x finite-real?]
          [y finite-real?])
         vec2?]{

Converts numeric coordinate @tt{(x, y)} to a point in the axes' containing
coordinate system. The procedure first maps each coordinate through its linear
or logarithmic display scale, multiplies by the independent local unit lengths,
then applies semantic scale, rotation, and translation.

The numeric coordinates are not required to lie inside the displayed ranges.
This permits extrapolation and placement just outside the visible axes. A value
on a logarithmic axis must nevertheless be a positive finite real.
}

@defproc[(axes-point->coordinates [axes axes-visual?] [point vec2?]) vec2?]{

Converts @racket[point] from the axes' containing coordinate system to numeric
axis coordinates. The procedure removes translation, rotation, and positive
scale, then divides by the independent x and y unit lengths.

For finite inputs this is the inverse of @racket[axes-coordinates->point] up to
ordinary numeric precision. A nonzero rotation normally introduces inexact
trigonometric results.
}

@subsection[#:tag "coordinate-curves"]{Coordinate Curves and Plots}

The procedures in this section convert ordered numeric coordinates to semantic
path geometry. They use the local coordinate system of an @racket[axes] Visual.
They do not store a sampling procedure or a caller-owned point list in the
result.

@subsubsection{Interpolation Modes}

@defproc[(curve-interpolation? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of these symbols:

@itemlist[
 @item{@racket['linear] connects each accepted pair with a line segment.}
 @item{@racket['smooth] creates cubic Bézier segments that pass through all
       accepted samples in order.}
]

Every public coordinate-plot procedure uses @racket['linear] by default. An
unsupported symbol or another value returns @racket[#f].

Smooth interpolation is applied separately to every accepted run. Suppose one
run contains points @italic{P0} through @italic{Pn}. For a segment from
@italic{Pi} to @italic{Pi+1}, the usual interior control points are:

@centered{@italic{C1} = @italic{Pi} +
          (@italic{Pi+1} - @italic{Pi-1}) / 6}

@centered{@italic{C2} = @italic{Pi+1} +
          (@italic{Pi} - @italic{Pi+2}) / 6}

At an end of a run, the endpoint is repeated for the missing neighboring
point. A run containing exactly two points uses a line-equivalent cubic whose
controls are one third and two thirds of the way along the segment. The result
therefore follows the same traversal order and reaches every accepted sample.

When clipping is enabled, sample pairs are clipped as line segments before
smooth interpolation is calculated. Generated control points are then clamped
to the closed axes rectangle. A cubic Bézier curve lies inside the convex hull
of its endpoints and controls, so the resulting visible curve stays inside the
rectangle. Clamping may reduce smoothness where a run touches a boundary.
}

@subsubsection[#:tag "sampled-function-graphs"]{Sampled Curves and Fields}

@defproc[(sample-implicit-path [axes axes-visual?]
                               [field (procedure-arity-includes/c 2)]
                               [#:level level finite-real? 0]
                               [#:x-count x-count (and/c exact-integer? (>=/c 2)) 65]
                               [#:y-count y-count (and/c exact-integer? (>=/c 2)) 65])
         path-geometry?]{

Samples a two-argument scalar field with deterministic marching squares and
returns axes-local open contour segments where the field equals @racket[level].
Adjacent cell segments are stitched into deterministic open or closed
subpaths. Non-finite field samples create gaps. The result is immutable path
geometry and does not retain the callback.
}

@defproc[(implicit-curve [axes axes-visual?]
                          [field (procedure-arity-includes/c 2)]
                          [#:id id symbol?]
                          [#:level level finite-real? 0]
                          [#:x-count x-count (and/c exact-integer? (>=/c 2)) 65]
                          [#:y-count y-count (and/c exact-integer? (>=/c 2)) 65]
                          [#:opacity opacity opacity? 1]
                          [#:stroke stroke any/c "darkorange"]
                          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         path-visual?]{

Constructs a styled path Visual from @racket[sample-implicit-path], copying the
current axes transform as a semantic snapshot.
}

@defproc[(vector-field [axes axes-visual?]
                       [field (procedure-arity-includes/c 2)]
                       [#:id id symbol?]
                       [#:x-count x-count (and/c exact-integer? (>=/c 1)) 9]
                       [#:y-count y-count (and/c exact-integer? (>=/c 1)) 7]
                       [#:scale scale finite-real? 1/4]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "seagreen"]
                       [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
                       [#:tip-length tip-length (and/c finite-real? (>/c 0)) 3/20]
                       [#:tip-width tip-width (and/c finite-real? (>/c 0)) 1/8])
         group-visual?]{

Samples @racket[field] over a closed numeric axes grid. The procedure receives
numeric x/y coordinates and must return exactly one @racket[vec2] vector.
Each nonzero result becomes an arrow; zero vectors are omitted. The returned
immutable group has stable child identities and can therefore use nested paths
for lookup and animation. Sampling and axes transforms are captured at
construction time; the group retains no procedure or renderer state.
}

@defproc[(sample-function-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{

Samples @racket[function] at @racket[sample-count] uniformly spaced x values in
increasing order. The closed interval includes both endpoints. When
@racket[x-min] or @racket[x-max] is @racket[#f], the corresponding bound comes
from @racket[(axes-visual-x-range axes)]. The resolved minimum must be less than
the resolved maximum. Their difference must remain a positive finite real.

For a logarithmic x axis, spacing is uniform in the selected base-logarithm
display coordinate instead. Thus a base-ten range from one through one thousand
samples successive decades evenly. Explicit @racket[x-min] and @racket[x-max]
bounds follow the same rule and must be strictly positive on a log axis.

All arguments are checked before @racket[function] is called. When sampling
completes without an error, the function is called exactly once for each sample
x value. Sampling stops at the first invalid result or exception. Each call
must return exactly one value. That value has these meanings:

@itemlist[
 @item{A finite real is one numeric y sample.}
 @item{@racket[#f] is an explicit gap and breaks the current run.}
 @item{Positive infinity, negative infinity, and NaN also create a gap.}
 @item{Any other result raises an exception that reports the x value and the
       returned value.}
]

Returning zero values or more than one value raises an exception that reports
the x value and result count. An exception raised by @racket[function] is not
converted to a gap. It is reported together with the sample x value and the
original exception message. This keeps programming errors separate from
explicit discontinuities.

When @racket[max-jump] is a number, two adjacent finite samples are connected
only when the absolute difference between their numeric y values is no greater
than that number. The threshold is applied before axes scaling and before
clipping. The default @racket[#f] performs no jump rejection. Use an explicit
@racket[#f] result when the location of a discontinuity is known.

When @racket[clip?] is true, every accepted sample pair is clipped to the closed
rectangle described by the axes x and y ranges. Clipping is performed on
segments, so an intersection with a boundary becomes an exact path endpoint
when exact arithmetic permits it. When an inexact coordinate difference would
overflow, clipping temporarily uses the exact represented input values. When
@racket[clip?] is false, finite out-of-range samples remain in the path.
Clipping does not decide whether a segment crossing the rectangle is a true
discontinuity.

The @racket[interpolation] argument controls the path segment kind as described
by @racket[curve-interpolation?]. Linear interpolation stores line segments.
Smooth interpolation stores cubic Bézier segments through each accepted run.
Breaks from non-finite values, explicit @racket[#f] results, maximum-jump
rejection, or clipping keep the runs separate.

When @racket[detect-discontinuities?] is true, two adjacent samples that lie
beyond opposite sides of the visible numeric y interval are treated as the
hidden sides of a vertical asymptote and are not connected. This opt-in rule
prevents clipping from drawing a false segment through the plot window while
preserving the historical default behavior for steep continuous graphs.

The result contains zero or more open subpaths in sampling order. An isolated
finite sample with no accepted adjacent pair does not create a point-only
subpath. Every stored point uses the untransformed local coordinate system of
@racket[axes]. Numeric x is multiplied by @racket[axes-x-unit-length], and
numeric y is multiplied by @racket[axes-y-unit-length]. The axes translation,
rotation, and scale are not applied to the returned geometry.

The sampling grid is deterministic. Exact bounds produce exact rational
intermediate x values when ordinary exact arithmetic permits it. The result
contains only immutable path geometry. Rendering it later does not call
@racket[function] again.
}

@defproc[(function-graph
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[sample-function-path] with the same axes, function, interval,
sample count, clipping, jump, discontinuity detection, and interpolation arguments. It wraps the result
in a built-in path Visual.

The graph copies the current translation, rotation, and scale of @racket[axes].
Its local geometry already uses the axes x and y unit lengths, so the graph and
axes coincide at construction time even when the axes are translated, rotated,
or non-uniformly scaled. This is a snapshot. Updating either immutable Visual
later does not update the other. Put both in a group or apply matching animation
requests when they should continue to move together.

The graph has no fill. The identity, opacity, and stroke width are checked
before the numeric function is called. @racket[stroke] and
@racket[stroke-width] are used by the ordinary path renderer. The result works
with @racket[create], @racket[uncreate], path replacement, movement, rotation,
non-uniform scaling, fading, groups, layout, and custom path renderers. There is
no graph-specific renderer or timeline request.
}

@defproc[(derived-function-graph
          [axes axes-visual?]
          [field (procedure-arity-includes/c 2)]
          [#:id id symbol?]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         derived-visual?]{

Creates a pure derived function graph. @racket[field] receives the sampled
@racket[derived-context?] first and one numeric x coordinate second. It must
return the same one-value result accepted by @racket[function-graph]. The
ordinary graph options have the same meanings as in @racket[function-graph].

For each resolved scene state, the field is sampled anew and produces one
concrete path Visual with the requested identity, style, and axes transform.
This permits an immutable @racket[parameter] or another resolved Visual to drive
a plot without a mutable updater. As with any @racket[derived-visual?], animate
its source values or dependencies rather than applying a direct Visual animation
to the derived graph.
}

@subsubsection{Parametric Curves}

@defstruct*[parameter-range ([start finite-real?]
                             [end finite-real?])
  #:transparent]{

Represents one ordered closed parameter domain. The fields have these meanings:

@itemlist[
 @item{@racket[start] is the first parameter passed to a sampling procedure.}
 @item{@racket[end] is the last parameter passed to a sampling procedure.}
]

The values must be distinct finite reals. The computed difference
@racket[(- end start)] must also remain a nonzero finite real. The order is
significant. When @racket[start] is greater than @racket[end], sampling proceeds
in decreasing order.

The structure is immutable and transparent. Its public bindings include
@racket[parameter-range], @racket[parameter-range?], both field accessors, and
@racket[struct:parameter-range].
}

@defproc[(sample-parametric-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:parameter-range domain parameter-range? (parameter-range 0 1)]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{

Samples @racket[function] at @racket[sample-count] uniformly spaced parameter
values from @racket[(parameter-range-start domain)] through
@racket[(parameter-range-end domain)]. Both endpoints are included exactly as
stored. Intermediate values follow the same increasing or decreasing order.
Exact endpoints produce exact rational intermediate values when ordinary exact
arithmetic permits it.

All arguments are checked before @racket[function] is called. Each sampling call
must return exactly one value:

@itemlist[
 @item{A @racket[vec2] is one finite numeric coordinate.}
 @item{@racket[#f] is an explicit gap.}
]

Another value, zero values, or multiple values raise an exception that reports
the parameter value. An exception from @racket[function] is reported with the
same parameter and the original exception message. Sampling stops at the first
error.

When @racket[max-distance] is a number, two adjacent coordinates are connected
only when their Euclidean distance in numeric-coordinate units is no greater
than that number. The distance is measured before independent axes scaling.
The default @racket[#f] applies no distance rejection.

Clipping and interpolation follow the common rules described above. The result
contains axes-local open subpaths and does not retain @racket[function] or
@racket[domain]. Empty runs and isolated finite coordinates produce no drawn
segment.
}

@defproc[(parametric-curve
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:parameter-range domain parameter-range? (parameter-range 0 1)]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[sample-parametric-path] with the same sampling arguments and wraps
the result in an ordinary path Visual. Identity, opacity, and stroke width are
checked before the sampling procedure is called.

The returned path has no fill and copies the current axes translation, rotation,
and scale. This is a construction-time snapshot, not a live link. The result
can use every operation available to an ordinary path Visual, including
@racket[create], @racket[uncreate], morphing, affine animation, opacity, groups,
and renderer-aware layout.
}

@subsubsection{Ordered Data Plots}

@defproc[(data-series-path
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{

Converts @racket[points] to axes-local path geometry. The input must be a proper
list containing only @racket[vec2] values and @racket[#f]. A @racket[vec2] is
one numeric coordinate. @racket[#f] is an explicit gap.

List order is traversal order. The procedure does not sort by x, infer time
order, remove repeated coordinates, or retain the input list. An empty list, a
one-point list, or a finite coordinate isolated by gaps produces no drawn
segment.

The @racket[max-distance], @racket[clip?], and @racket[interpolation] arguments
have the same meanings as for @racket[sample-parametric-path]. Distance is
Euclidean in numeric-coordinate units. The result contains only immutable path
geometry.
}

@defproc[(data-plot
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:id id symbol?]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "seagreen"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[data-series-path] with the same point, clipping, distance, and
interpolation arguments and wraps the result in an ordinary path Visual.
Identity, opacity, and stroke width are checked before the point series is
converted.

The returned path has no fill and copies the axes translation, rotation, and
scale at construction time. It works with ordinary path rendering, creation,
removal, morphing, movement, rotation, non-uniform scaling, fading, groups, and
relative layout.
}


@subsection{Group Visuals}

A group is a semantic composite. Its children are stored as ordinary Visual
values, not as Picts. The child list is significant back-to-front order. Child
positions are local to the group anchor.

All children must implement both @racket[gen:visual] and
@racket[gen:affine-visual]. Circles, rectangles, paths, function graphs,
parametric curves, data plots, arrows, axes, plain text, formulas, and groups all
satisfy this requirement. A child may itself be a group. Every
identity in the complete built-in group tree must be unique and must differ
from the group's own identity. A custom affine Visual is treated as one leaf
because there is no public protocol for inspecting children hidden inside it.

@defproc[(group
          [children (listof (and/c visual? affine-visual?))]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         group-visual?]{

Creates a semantic group with @racket[children] in significant back-to-front
order. An empty list creates a valid empty group.

The @racket[center] value places the group anchor in its containing coordinate
system. At the top level this is a world-space point. In a parent group it is a
local point. Each child's existing reference position is interpreted in the
group's local coordinates.

The group @racket[scale] may be a positive finite scalar or a positive
@racket[vec2], but its normalized x and y components must be equal. This
uniform-scale restriction lets parent transforms compose exactly with rotated
children without introducing shear. The group may be rotated by any finite
angle.

The group @racket[opacity] is applied to the complete composed result. Child
opacity is applied first, so opacity is inherited multiplicatively through
nested groups.

The constructor rejects a non-affine child, a nonsymbol child identity, a
repeated identity anywhere in the built-in group tree, or a descendant whose
identity equals @racket[id]. For a custom affine child, its reported position
must agree with the translation in its reported affine transform.

Nested children are addressed by nonempty paths such as @racket['(parent child)]
for scene-state lookup and compatible animation requests. Their identity remains
local to the containing group, so a bare child symbol is not a top-level scene
identity.
}

@defproc[(group-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in group Visual.
}

@defproc[(group-visual-children [group group-visual?])
         (listof (and/c visual? affine-visual?))]{

Returns the group's children in significant back-to-front order. The returned
Visuals use coordinates local to the group. The list is immutable model data.
}

@defproc[(group-visual-with-children
          [group group-visual?]
          [children (listof (and/c visual? affine-visual?))])
         group-visual?]{

Returns a new group with @racket[children] as its significant back-to-front
child list. Identity, group transform, and opacity are preserved. The same
child and identity validation as @racket[group] is performed. The original
group is unchanged.
}


@section[#:tag "derived-visuals"]{Pure Derived Visuals}

SCENE-AW introduced persistent top-level derived Visual definitions driven by
immutable sampled scene values. SCENE-AX extends the same pure resolver model
with recursively resolved top-level Visual dependencies. No previous frame is
required. Concrete dependency results may be memoized within one resolution
traversal, but are never persisted into scene state or reused by a later sample.

@defproc[(derived-visual
          [template visual?]
          [resolver (-> derived-context? visual? visual?)])
         derived-visual?]{

Creates a derived Visual definition from concrete @racket[template]. The
template supplies the stable top-level identity and ordinary
@racket[gen:visual] reference position for the persistent definition. The
@racket[resolver] receives one read-only @racket[derived-context?] plus that
immutable template whenever concrete scene-aware geometry is needed. The
context exposes named semantic values and, through SCENE-AX, top-level Visual
presence and recursively resolved Visual lookup.

The template itself must be concrete rather than derived. The resolver must be
pure, must return a non-derived @racket[visual?], and the returned Visual's
@racket[visual-id] must be exactly the template ID. These requirements are
checked when the definition is resolved. Missing named inputs therefore fail
at resolution/render time rather than at construction.

The persistent definition still satisfies @racket[gen:visual] by delegating
@racket[visual-id], @racket[visual-position], and
@racket[visual-with-position] to its template. Scene-aware geometry comes from
@racket[scene-state-resolved-ref]. Direct Visual animation requests targeting a
derived definition remain rejected; animate its named scalar sources or the
ordinary scene inputs it depends on instead.
}

@defproc[(derived-visual? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a SCENE-AW derived Visual
definition.
}

@defproc[(derived-context? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is the read-only context supplied to a
derived resolver.
}

@defproc[(derived-context-value-has? [context derived-context?]
                                     [id (or/c symbol? scene-parameter?)])
         boolean?]{
Reports whether the sampled state contains the named semantic value @racket[id].
}

@defproc[(derived-context-value-ref [context derived-context?]
                                    [id (or/c symbol? scene-parameter?)])
         any/c]{
Returns named interpolable semantic value @racket[id] from the sampled immutable state. An absent
value raises an exception.
}

@defproc[(derived-context-visual-has? [context derived-context?]
                                      [id (or/c symbol? visual-path?)])
         boolean?]{
Reports whether the sampled scene state contains the addressed Visual.
@racket[id] may be a top-level symbol or a nonempty nested symbol path.
Presence lookup does not force a derived dependency to resolve.
}

@defproc[(derived-context-visual-ref [context derived-context?]
                                     [id (or/c symbol? visual-path?)])
         visual?]{
Returns the concrete Visual identified by @racket[id] in the same sampled
immutable state. @racket[id] may be a top-level symbol or a nested path.
Ordinary top-level Visuals return directly. A nested result composes every
enclosing built-in group/formula transform and opacity into world coordinates,
so its @racket[visual-position] is suitable for a separate top-level dependent.
Derived Visuals resolve recursively and may themselves read scalar or Visual
dependencies. Lookup is independent of drawing order.

Self-dependencies and longer cycles raise an exception identifying a derived
Visual dependency cycle. Successfully resolved dependencies are memoized only
within the current resolution traversal; no concrete result replaces the
persistent derived definition in scene state.
}

@defproc[(attach-to
          [content visual?]
          [target (or/c visual? symbol? visual-path?)]
          [#:offset offset vec2? origin])
         derived-visual?]{

Creates one world-space derived Visual whose reference position is the sampled
world-space reference position of @racket[target] plus @racket[offset].
@racket[target] may be a top-level Visual, its symbol identity, or a nested
built-in group/formula path. It is looked up anew at every scene sample, so the
attachment follows target motion and enclosing parent transforms.

The content must be a concrete, non-frame-space Visual. The result is a derived
Visual and therefore cannot be animated directly; animate the target or the
ordinary inputs that drive it. This API follows only a reference point. It does
not measure render-box edges, rotate content with the target, avoid collisions,
or create an automatic constraint solver.
}

@section[#:tag "scene-state"]{Scene States}

Scene-state values are immutable. Their raw constructor and fields are not
part of the public API.

@defproc[(scene-state? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a scene-state value.
}

@defthing[empty-scene-state scene-state?]{

An empty scene state with no top-level Visuals, no named semantic values, and an empty drawing order.
}

@defproc[(scene-state-count [state scene-state?])
         exact-nonnegative-integer?]{

Returns the number of top-level Visuals in @racket[state]. A group counts as
one top-level Visual regardless of the number of descendants it contains. A
derived definition likewise counts as one top-level Visual.
}

@defproc[(scene-state-has? [state scene-state?]
                           [target (or/c visual? symbol? visual-path?)])
         boolean?]{

Returns @racket[#t] when @racket[state] contains the addressed Visual. A Visual
argument is resolved through @racket[visual-id]; a @racket[visual-path?] follows
built-in group children. Frame-space Visuals are not valid @racket[camera-follow]
targets.
}

@defproc[(scene-state-ref [state scene-state?]
                          [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the stored Visual identified by @racket[target]. A nested path returns
its locally stored child, without inheriting parent transforms. Raises an
exception when the identity is not present. For a derived Visual this returns the persistent
@racket[derived-visual?] definition rather than evaluating its resolver; use
@racket[scene-state-resolved-ref] when concrete geometry is required.
}

@defproc[(scene-state-visuals-in-drawing-order [state scene-state?])
         (listof visual?)]{

Returns the stored top-level Visuals in back-to-front drawing order. The first
Visual is painted first. The last Visual is painted on top. A group's separate
child order is available through @racket[group-visual-children]. Derived entries
remain persistent @racket[derived-visual?] definitions in this raw list; use
@racket[scene-state-resolved-visuals-in-drawing-order] for concrete rendering
values.
}

@defproc[(scene-state-resolved-ref
          [state scene-state?]
          [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the concrete addressed Visual for @racket[target] in @racket[state].
Ordinary Visuals are returned unchanged. A @racket[derived-visual?] is evaluated
against a read-only context built from this exact immutable state. SCENE-AX
allows that resolver to recursively request other top-level Visuals. Dependency
cycles are rejected, and each result is validated for concrete-Visual type and
identity preservation.
}

@defproc[(scene-state-resolved-visuals-in-drawing-order
          [state scene-state?])
         (listof visual?)]{

Returns concrete top-level Visuals in significant back-to-front order,
resolving every derived definition against @racket[state]. All entries share one
local dependency-resolution traversal, so shared dependencies resolve
consistently even when the dependent appears before its dependency in drawing
order. The Pict scene adapter uses this operation without mutating stored state.
}

@defproc[(scene-state-value-has? [state scene-state?]
                                 [id (or/c symbol? scene-parameter?)]) boolean?]{
Returns @racket[#t] when @racket[state] contains the named semantic value
identified by @racket[id]. Named values are semantic state and are not rendered.
Value and Visual identifiers share one global scene namespace.
}

@defproc[(scene-state-value-ref [state scene-state?]
                                 [id (or/c symbol? scene-parameter?)]) any/c]{
Returns the named interpolable semantic value identified by @racket[id]. Raises an exception
when the value is absent.
}

@section[#:tag "animations"]{Animation Requests}

Animation constructor procedures return immutable request values. A request
stores a target identity and a requested endpoint or relative change. The
request is compiled against the scene's current state when @racket[scene-play]
is called.

A target can be a Visual value, its top-level symbol identity, or a nonempty
@racket[visual-path?]. A path follows built-in group children and is a direct
animation target; child transforms remain local to their containing group.

@defproc[(value-to [id (or/c symbol? scene-parameter?)] [destination any/c]) value-to-request?]{
Creates an absolute animation request for one named interpolable semantic value.
The value must already be present in the scene when the request is compiled, and
its kind must match @racket[destination]. Interior samples use
@racket[interpolate-value], while exact interval boundaries preserve the original
source and requested destination representations. Named values use the
same scheduler, easing, timing compositions, and conflict detection as Visual
requests. They are not painted directly; SCENE-AW derived Visual resolvers may
consume them and thereby change concrete rendered geometry.

An immutable @racket[scene-parameter?] may be used in place of @racket[id].
}

@defproc[(value-to-request? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a request created by @racket[value-to].
}

@defproc[(move-to [target (or/c visual? symbol?)]
                  [destination vec2?])
         move-to-request?]{

Creates an absolute translation request. At the end of its play clip, the
target's reference position is @racket[destination]. Identity, geometry, style,
rotation, scale, opacity, drawing order, and group child order are preserved.
}

@defproc[(move-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[move-to].
}

@defproc[(move-along-path
          [target (or/c visual? symbol?)]
          [path (or/c path-geometry? path-visual? derived-visual? symbol?)]
          [#:start start (real-in 0 1) 0]
          [#:end end (real-in 0 1) 1]
          [#:normal-offset normal-offset finite-real? 0])
         move-along-path-request?]{

Creates a translation request that places @racket[target] on @racket[path] by
total arc length. @racket[start] and @racket[end] are independent finite
fractions in the closed unit interval. The default traverses from the beginning
to the end; a larger @racket[start] than @racket[end] traverses the same route
in reverse. Other easing procedures remap this arc-length fraction in the same
way that they remap ordinary translation progress. Under @racket[linear], equal
time intervals cover equal total arc length.

@racket[normal-offset] adds a signed displacement perpendicular to the selected
route point. A positive value lies to the left of the @emph{actual traversal
direction}; reverse traversal therefore reverses the normal. Zero preserves the
SCENE-Y route point exactly and does not require tangent sampling. On a sharp
polyline corner the offset is segment-local, so the offset trajectory can jump
between the adjacent offset edge lines. Smooth cubic routes give smooth normal
motion wherever their tangent is continuous.

When @racket[path] is a @racket[path-geometry?] value, its points are interpreted
directly in @racket[target]'s containing coordinate system. When it is a path Visual, derived Visual definition, or symbol identity,
@racket[scene-play] resolves the current top-level Visual from the prepared
clip-start state by stable identity. A derived definition is evaluated against
that exact state first; the concrete result must be a path Visual. The path
Visual's current affine transform is then applied to its local path points before
the resulting world-space route is measured. Passing an earlier Visual value
therefore selects the current scene value rather than capturing stale
coordinates.

The compiled route is a snapshot for that play clip. Simultaneously moving,
scaling, rotating, or morphing the path Visual does not dynamically deform the
motion route. A path Visual route is world-space after resolution and cannot be
used to drive a frame-space target. Raw path geometry may drive a frame-space
target because it is already interpreted in that target's containing coordinate
system.

Motion requires a positive finite route with exactly one positive-length
subpath. Compound drawings with multiple positive-length subpaths are valid path
geometry but are rejected here so the target cannot silently teleport across a
gap. Closed single-subpath routes are allowed, including their implicit closing
edge.

The request changes the ordinary translation animation component. It conflicts
with same-target @racket[move-to] or another @racket[move-along-path], but may
run with disjoint rotation, scale, opacity, path-geometry, formula-part, and
camera components. Sampling places the target at the selected route point plus
any requested normal offset even when its prior reference position differs; put
the target at that complete @racket[start] position before the clip when a
continuous clip boundary is required.
}

@defproc[(move-along-path-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[move-along-path].
}

@defproc[(orient-along-path
          [target (or/c visual? symbol?)]
          [path (or/c path-geometry? path-visual? derived-visual? symbol?)]
          [#:start start (real-in 0 1) 0]
          [#:end end (real-in 0 1) 1]
          [#:rotation-offset rotation-offset finite-real? 0])
         orient-along-path-request?]{

Creates a rotation request that points @racket[target]'s local positive x axis
along the tangent of @racket[path] at the current total-arc-length fraction.
The target must implement @racket[gen:affine-visual]. @racket[start] and
@racket[end] use the same partial and reverse traversal semantics as
@racket[move-along-path]. Reverse traversal negates the stored forward tangent,
so the Visual points in the actual direction of motion. @racket[rotation-offset]
is a constant angle in radians added after tangent alignment.

Path source resolution, clip-start snapshot semantics, transformed path Visual
handling, frame/world coordinate rules, positive finite length requirements,
and single-positive-subpath continuity requirements are the same as for
@racket[move-along-path]. Tangents are provided by
@racket[path-geometry-tangent-at].

The request changes only the ordinary rotation animation component. It may run
simultaneously with same-target @racket[move-along-path], scale, opacity, and
disjoint components, but conflicts with same-target @racket[rotate-to],
@racket[rotate-by], or another @racket[orient-along-path]. The rotation at a
sample is derived directly from the sampled tangent rather than interpolated
between endpoint angles, so bends and curved routes are followed geometrically.
}

@defproc[(orient-along-path-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[orient-along-path].
}

@defproc[(rotate-to [target (or/c visual? symbol?)]
                    [angle finite-real?])
         rotate-to-request?]{

Creates an absolute rotation request. @racket[angle] is the requested final
counter-clockwise rotation in radians. The target must implement
@racket[gen:affine-visual]. Identity, geometry, style, position, scale, opacity,
drawing order, and group child order are preserved.
}

@defproc[(rotate-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[rotate-to].
}

@defproc[(rotate-by [target (or/c visual? symbol?)]
                    [delta finite-real?])
         rotate-by-request?]{

Creates a relative rotation request. The final rotation is the rotation at the
start of the clip plus @racket[delta]. Positive values rotate
counter-clockwise. The target must be an affine Visual. Identity, geometry,
style, position, scale, opacity, drawing order, and group child order are
preserved.
}

@defproc[(rotate-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[rotate-by].
}

@defproc[(scale-to [target (or/c visual? symbol?)]
                   [scale scale-factor?])
         scale-to-request?]{

Creates an absolute scale request. The final x and y scale factors are the
normalized form of @racket[scale]. The target must be an affine Visual.
Identity, geometry, style, position, rotation, opacity, drawing order, and group
child order are preserved.

A built-in group accepts only a uniform endpoint. @racket[scene-play] rejects a
request whose normalized x and y factors differ. For every affine target,
compilation also checks that @racket[visual-with-scale] returns an affine
Visual, preserves identity, and installs the requested endpoint exactly. These
checks occur before timeline sampling.
}

@defproc[(scale-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[scale-to].
}

@defproc[(scale-by [target (or/c visual? symbol?)]
                   [factor scale-factor?])
         scale-by-request?]{

Creates a relative scale request. The start scale is multiplied
componentwise by @racket[factor]. The target must be an affine Visual.
Identity, geometry, style, position, rotation, opacity, drawing order, and group
child order are preserved.

For a built-in group, the computed endpoint must remain uniform.
@racket[scene-play] rejects a relative factor that produces unequal x and y
components. For every affine target, compilation checks the resulting endpoint
through the same @racket[visual-with-scale] protocol rules as
@racket[scale-to].
}

@defproc[(scale-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[scale-by].
}

@defproc[(stroke-width-to
          [target (or/c symbol? (and/c visual? stroke-width-visual?))]
          [stroke-width (and/c finite-real? (>=/c 0))])
         stroke-width-to-request?]{

Creates an absolute cosmetic stroke-width request for a Visual already present
in the scene. The request interpolates from the target's semantic width at the
leaf start to @racket[stroke-width]. Zero is a valid endpoint.

When @racket[target] is a Visual value it must implement both @racket[gen:visual]
and @racket[gen:stroke-width-visual]. When it is a symbol, @racket[scene-play]
checks the resolved Visual while compiling the request. Compilation validates
the getter value, calls @racket[visual-with-stroke-width] with the requested
endpoint, requires the result to remain a stroke-width Visual with the same
identity, and checks that the endpoint was installed exactly.

Stroke width is its own animation component. It may run simultaneously with
translation, rotation, scale, opacity, or path-geometry changes for the same
identity. Two overlapping same-target stroke-width requests conflict after
AN--AR schedule expansion; touching requests may chain through a succession or
other nonoverlapping schedule.

The numeric interpolation follows the leaf easing like movement and ordinary
opacity animation. With an easing whose endpoint is one, the exact requested
numeric width is installed at the leaf endpoint even when the starting width or
schedule arithmetic is inexact. For custom Visuals, compilation also rejects a
setter that changes the exact/inexact representation of that requested endpoint.

The semantic width domain is renderer-independent. The default Pict/racket/draw
backend accepts cosmetic pen widths from 0 through 255 pixels and reports a
renderer error for larger values. Within that backend, width zero is a
device-dependent hairline rather than an instruction to remove the stroke.
}

@defproc[(stroke-width-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[stroke-width-to].
}

@defproc[(fill-color-to
          [target (or/c symbol? (and/c visual? fill-color-visual?))]
          [color color-spec?])
         fill-color-to-request?]{

Creates an absolute semantic fill-color request. The source fill at the leaf
start and @racket[color] must both satisfy @racket[color-spec?]. A slot whose
current value is @racket[#f] therefore cannot be animated by this operation.

Interior progress is resolved to @racket[rgba-color] endpoints and interpolated
componentwise in sRGB value space. At exact progress zero and one, the exact
source and destination style specifications are installed instead of normalized
copies. This preserves textual endpoints and exact sequential chaining.

Fill color owns the @racket['fill-color] animation component. It may overlap
same-target movement, rotation, scaling, opacity, stroke width, stroke color, and
path geometry. Overlapping same-target fill-color leaves conflict after schedule
expansion; touching leaves are legal.
}

@defproc[(fill-color-to-request? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] was created by @racket[fill-color-to].
}

@defproc[(stroke-color-to
          [target (or/c symbol? (and/c visual? stroke-color-visual?))]
          [color color-spec?])
         stroke-color-to-request?]{

Creates the corresponding absolute semantic stroke-color request. Source
validation, exact endpoints, sRGB interpolation, and custom protocol validation
follow @racket[fill-color-to]. Stroke color owns a distinct
@racket['stroke-color] component, so fill and stroke colors may animate together.
}

@defproc[(stroke-color-to-request? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] was created by @racket[stroke-color-to].
}

@defproc[(fade-to
          [target (or/c symbol? (and/c visual? opacity-visual?))]
          [opacity opacity?])
         fade-to-request?]{

Creates an absolute global-opacity request for a Visual that is already
present in the scene. The request interpolates from the target's opacity at the
start of the play clip to @racket[opacity].

When @racket[target] is a Visual value, it must implement both
@racket[gen:visual] and @racket[gen:opacity-visual]. When it is a symbol,
@racket[scene-play] checks the current Visual with that identity while compiling
the request. A missing target or a Visual without valid semantic opacity raises
an exception.

The request changes only the opacity component. It preserves identity,
position, affine transform, geometry, style, drawing order, and group child
order. It may run at
the same time as movement, rotation, scaling, or path morphing for the same
identity. It conflicts with another same-target request that changes opacity,
including @racket[fade-in] and @racket[fade-out].

@racket[fade-to] does not add or remove the target. Its endpoint follows the
easing result, like movement and morphing. An unusual easing procedure that
returns zero at the end therefore leaves the starting opacity in place.
}

@defproc[(fade-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[fade-to].
}

@defproc[(fade-in [visual (and/c visual? opacity-visual?)])
         fade-in-request?]{

Creates a request that introduces the complete supplied @racket[visual] by
increasing global opacity from zero to the Visual's own semantic opacity.

The Visual's identity must be absent from the scene before the play clip.
@racket[scene-play] adds a placeholder with the same identity, position,
geometry, affine transform, style, and drawing position, but with opacity zero.
Several fade-in requests add their placeholders in request order, in front of
Visuals already present. When the supplied Visual is a group, the complete child
tree is introduced as one top-level Visual.

All requests in the play clip compile against the prepared shared start state.
Movement, rotation, scaling, and path morphing can therefore target a Visual
introduced by @racket[fade-in], even when those requests appear before the
fade-in request. These operations change different components.

At interior samples, opacity is interpolated from zero to the opacity stored in
@racket[visual]. At the structural endpoint, the supplied opacity is installed
regardless of the easing result. This guarantees that the complete Visual is
present after the clip. An unusual easing procedure can therefore cause a jump
at the exact clip boundary. A Visual whose supplied opacity is zero is
introduced structurally but remains invisible.

A fade-in changes both opacity and scene presence. It conflicts with another
same-target opacity request and with another same-target introduction or
removal request. In particular, @racket[fade-in] cannot be combined with
same-target @racket[create], @racket[uncreate], or @racket[fade-out].
}

@defproc[(fade-in-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[fade-in].
}

@defproc[(fade-out
          [target (or/c symbol? (and/c visual? opacity-visual?))])
         fade-out-request?]{

Creates a request that lowers a present Visual's global opacity from its current
value to zero and then removes the Visual from the scene.

When @racket[target] is a symbol, @racket[scene-play] checks that the current
Visual implements the opacity protocol and returns a valid opacity. A missing
target or a Visual without semantic opacity raises an exception.

Movement, rotation, scaling, and path morphing may run at the same time for the
same identity. The Visual remains present at interior samples, so those
components continue to update while it fades. At the structural endpoint, the
Visual is removed regardless of the easing result. A group and its complete
child tree are removed as one top-level Visual. An unusual easing procedure can
therefore leave it visibly opaque just before the boundary and absent at
the boundary.

A fade-out changes both opacity and scene presence. It conflicts with another
same-target opacity request and with another same-target introduction or
removal request. In particular, it cannot be combined with same-target
@racket[fade-in], @racket[create], @racket[uncreate], or @racket[fade-to].
}

@defproc[(fade-out-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[fade-out].
}

@defproc[(morph-to [target (or/c path-visual? symbol?)]
                             [destination path-geometry?])
         morph-to-request?]{

Creates a request that interpolates the present path Visual identified by
@racket[target] to @racket[destination]. The destination is local semantic path
geometry, not a destination Visual and not a rendered Pict.

The target must be present when @racket[scene-play] compiles the request. When
@racket[target] is a symbol, the built-in path-Visual requirement is checked at
that time. The target's current path at the beginning of the clip must be
compatible with @racket[destination] according to
@racket[path-geometry-morph-compatible?]. Incompatible structure raises an
exception before the clip is added.

At each sample, @racket[morph-to] uses @racket[path-geometry-lerp] with the
clip's eased progress. It interpolates subpath starts, line endpoints, cubic
control points, and cubic endpoints. It preserves the target's identity,
affine transform, opacity, fill, stroke, stroke width, and drawing position. It
does not copy style or placement from another Visual.

A morph can run at the same time as movement, rotation, scaling, or opacity
fading for the same identity because those requests change different
components. This includes morphing a Visual introduced by @racket[fade-in] or
removed by @racket[fade-out]. A second strict, normalized, or aligned morph,
@racket[create], or @racket[uncreate] for the same identity conflicts because
all of them change the path-geometry component.

Like translation, rotation, and scale, morphing follows the easing result at
the clip endpoint. It has no special structural completion rule. An unusual
easing function that does not map one to one can therefore leave the final
path between the source and destination, or at the source.
}

@defproc[(morph-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to].
}

@defproc[(morph-to-normalized
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?])
         morph-to-normalized-request?]{

Creates a request that morphs a present path Visual to @racket[destination]
after applying the limited deterministic normalization described by
@racket[path-geometry-normalize-for-morph]. The destination is local semantic
path geometry, not another Visual and not a Pict.

When @racket[scene-play] compiles the request, it reads the target's current
path and normalizes that path together with @racket[destination]. Compilation
requires the pair to satisfy @racket[path-geometry-morph-normalizable?]. A
subpath-count, closure, or point-only/nonempty mismatch raises an exception
before the clip is added.

At eased progress zero, the exact original source path is used. At eased
progress one, the exact requested @racket[destination] is used. At interior
progress values, the normalized cubic source and destination are interpolated
with @racket[path-geometry-lerp]. This preserves the visible source and
destination figures while allowing stored line-versus-cubic and segment-count
differences supported by the normalizer.

The operation preserves Visual identity, reference position, rotation, scale,
opacity, fill, stroke, stroke width, and drawing order. Movement, rotation,
scaling, and opacity fading may run simultaneously for the same identity. A
strict morph, another normalized or aligned morph, @racket[create], or
@racket[uncreate] conflicts because all of them change path geometry.

Like @racket[morph-to], this request follows the easing result and has no
structural endpoint override. An easing function that returns zero at the clip
endpoint therefore leaves the exact source path. An easing function that
returns one produces the exact requested destination.

This request does not reverse a path, rotate a closed path's starting point,
reorder subpaths, add or remove subpaths, change closure, or invent drawn
segments for a point-only subpath.
}

@defproc[(morph-to-normalized-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-normalized].
}

@defproc[(morph-to-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-aligned-request?]{

Creates a closed-loop path morph that first calls
@racket[path-geometry-align-for-morph] on the target's current path and
@racket[destination], then applies the existing
@racket[path-geometry-normalize-for-morph] preparation to the aligned pair.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Both source and destination must each contain exactly one
positive finite closed subpath. @racket[allow-reverse?] and
@racket[sample-count] have the same meaning as for
@racket[path-geometry-align-for-morph].

At interior eased progress values, interpolation uses the automatically aligned
and normalized destination. At eased progress zero, the exact original source
path is used. At eased progress one, the exact @emph{requested}
@racket[destination] object is used, not the phase-shifted or reversed internal
working representation. The endpoint therefore preserves caller-requested
semantic storage while the visible closed loop has the correspondence selected
for the interior morph.

The request changes the path-geometry component. It may run simultaneously
with movement, rotation, scaling, or opacity changes, and conflicts with strict,
normalized, or another aligned morph plus @racket[create] and
@racket[uncreate] on the same target. Like the other morph requests, it follows
the easing result and has no structural endpoint override.
}

@defproc[(morph-to-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-aligned].
}

@defproc[(morph-to-open-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-open-aligned-request?]{

Creates an open-path morph that first calls
@racket[path-geometry-align-open-for-morph] on the target's current path and
@racket[destination], then applies @racket[path-geometry-normalize-for-morph]
to the direction-aligned pair.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must each contain exactly one
positive finite open subpath. @racket[allow-reverse?] and @racket[sample-count]
have the same meanings as for @racket[path-geometry-align-open-for-morph].

Interior eased progress uses the selected endpoint direction and normalized
geometry. Eased progress zero uses the exact clip-start source path. Eased
progress one installs the exact caller-requested @racket[destination] object,
including its original stored direction. Direction selection is therefore an
interior correspondence choice rather than an endpoint rewrite.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, closed-loop aligned, compound-aligned, another open-aligned morph,
@racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-open-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-open-aligned].
}

@defproc[(morph-to-open-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-open-compound-aligned-request?]{

Creates an equal-count open-compound morph that first calls
@racket[path-geometry-align-open-compound-for-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the globally paired and
direction-aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must contain the same nonzero number
of positive finite open subpaths. @racket[allow-reverse?] and
@racket[sample-count] have the same meanings as for
@racket[path-geometry-align-open-compound-for-morph].

Interior eased progress uses global subpath pairing, per-pair endpoint direction,
and normalized geometry. Eased progress zero uses the exact clip-start source
path. Eased progress one installs the exact caller-requested
@racket[destination] object, including its original subpath order and stored
traversal directions. Pairing and reversal are therefore interior correspondence
choices rather than endpoint rewrites.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, closed-compound aligned, another open-compound
aligned morph, @racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-open-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-open-compound-aligned].
}

@defproc[(morph-to-mixed-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-mixed-compound-aligned-request?]{

Creates a topology-aware compound morph that first calls
@racket[path-geometry-align-mixed-compound-for-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the reordered/aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must be nonempty positive-finite
compound paths with matching counts of open subpaths and matching counts of
closed subpaths. @racket[allow-reverse?] and @racket[sample-count] have the same
meaning as for @racket[path-geometry-align-mixed-compound-for-morph].

Interior eased progress uses topology-class global pairing, per-open endpoint
direction, per-closed phase/direction, and normalized geometry. Eased progress
zero uses the exact clip-start source. Eased progress one installs the exact
caller-requested @racket[destination] object, including its original interleaving,
subpath order, and stored traversal representations.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, open-compound aligned, closed-compound aligned,
another mixed-compound aligned morph, @racket[create], or @racket[uncreate] on
the same target.
}

@defproc[(morph-to-mixed-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-mixed-compound-aligned].
}

@defproc[(morph-to-topology-changing
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64]
          [#:birth-anchor birth-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:death-anchor death-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:birth-anchor-map birth-anchor-map hash? #hash()]
          [#:death-anchor-map death-anchor-map hash? #hash()]
          [#:birth-penalty birth-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:death-penalty death-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:birth-penalty-map birth-penalty-map hash? #hash()]
          [#:death-penalty-map death-penalty-map hash? #hash()]
          [#:match-penalty-map match-penalty-map hash? #hash()])
         morph-to-topology-changing-request?]{

Creates a topology-aware normalized morph that permits open/closed subpath count
changes. When @racket[scene-play] compiles the request, it calls
@racket[path-geometry-prepare-topology-changing-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the two prepared equal-count
paths.

Matched real open/closed subpaths use the same correspondence rules as SCENE-AG.
Unmatched destination subpaths grow from deterministic degenerate bounds-center
seeds by default, while unmatched source subpaths collapse to their own
bounds-center seeds. @racket[birth-anchor] and @racket[death-anchor] may instead
be explicit finite local @racket[vec2] values shared by all unmatched subpaths on
the corresponding side. SCENE-AK's @racket[birth-anchor-map] and
@racket[death-anchor-map] may sparsely override those shared values by original
destination/source subpath index. Missing keys inherit the shared anchor and an
explicit @racket['bounds-center] entry opts that subpath back into its own center.
The request snapshots both hashes immutably; index range is checked against the
actual clip-start source and caller destination when the request is compiled. By
default @racket[birth-penalty] and @racket[death-penalty] are both
@racket['forced], preserving SCENE-AH/AI matching. Supplying both as finite
nonnegative real costs enables SCENE-AJ voluntary death+birth replacement when
that lowers the global correspondence cost; exact cost ties prefer fewer topology
changes. SCENE-AL's @racket[birth-penalty-map] and
@racket[death-penalty-map] may sparsely override those shared numeric costs by
original destination/source subpath index. Missing keys inherit the shared cost.
The request snapshots both endpoint penalty maps immutably, and nonempty endpoint
maps require numeric shared penalty mode. SCENE-AM's @racket[match-penalty-map]
may be used in either forced or numeric mode. Its keys are
@racket[(cons source-index destination-index)] pairs in original caller storage
order and its finite nonnegative values add to real-edge geometric scores only.
The request snapshots this map immutably as well. Pair-key range and topology
validation occurs when the request is compiled against the clip-start source and
stored destination. Empty source or destination geometry is legal; any real
subpath that is present must have positive finite arc length.

Interior eased progress uses the prepared/normalized geometry. Eased progress
zero uses the exact clip-start source path, with no synthetic birth slots
present. Eased progress one installs the exact caller-requested
@racket[destination], with no synthetic death slots present. Birth/death seeds,
reordering, reversal, and closed-loop phase are therefore interior
correspondence only.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation and conflicts with strict,
normalized, aligned, compound-aligned, another topology-changing morph,
@racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-topology-changing-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-topology-changing].
}

@defproc[(morph-to-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-compound-aligned-request?]{

Creates a compound closed-path morph that first calls
@racket[path-geometry-align-compound-for-morph] on the target's current path and
@racket[destination], then applies @racket[path-geometry-normalize-for-morph]
to the paired/aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must have the same nonzero number
of positive finite closed subpaths. @racket[allow-reverse?] and
@racket[sample-count] have the same meaning as for
@racket[path-geometry-align-compound-for-morph].

Interior eased progress uses globally paired, phase/direction-aligned, normalized
geometry. Eased progress zero uses the exact clip-start source path. Eased
progress one uses the exact caller-requested @racket[destination] object,
including its original subpath order and storage representation. Pairing is
therefore an interior correspondence choice rather than an endpoint rewrite.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, another compound-aligned morph, @racket[create],
or @racket[uncreate] on the same target.
}

@defproc[(morph-to-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-compound-aligned].
}

@defproc[(transform-shape
          [source (or/c visual? symbol?)]
          [destination (and/c visual? affine-visual? opacity-visual?)]
          [#:mode mode (or/c 'auto 'morph 'cross-fade) 'auto]
          [#:correspondence correspondence (or/c 'auto 'perimeter 'path) 'auto]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         transform-shape-request?]{

Replaces the present top-level Visual named by @racket[source] with the fresh
top-level @racket[destination]. The source and destination identities must be
distinct; the source must be present, and the destination identity must be
absent, when @racket[scene-play] compiles the request. Both endpoints require
affine placement and global opacity. A nested @racket[visual-path?] is not
accepted because this operation removes the source structural identity at the
clip boundary.

The default @racket['auto] first tries a geometric transition when each endpoint
is one built-in @racket[path-visual?], @racket[circle-visual?], or
@racket[rectangle-visual?]. Circle/rectangle pairs use a canonical
eight-segment perimeter: both start at their right midpoint and correspond at
the cardinal and diagonal positions. This produces an evenly rounded
square-to-circle interior. Pass @racket['perimeter] to require that primitive
correspondence, or @racket['path] to use only the general stored-path policy.
Other geometric pairs use automatic topology-class pairing, including
closed-loop phase/direction and open-path direction; when counts differ, they
try deterministic birth/death preparation. The source and destination styles
are alpha layers over the same intermediate outline, so a fill/stroke change
fades naturally while the geometry moves. Their transforms are interpolated too.

If either endpoint is a group, image, text, formula, SVG tree, custom Visual,
or atomic geometry that cannot be prepared safely, @racket['auto] keeps the
exact endpoint trees and cross-fades them at their own positions. This is a
deliberate graceful fallback: it does not flatten a group or manufacture a
semantic mapping between its children. @racket['morph] requires the geometric
case and raises an exception otherwise. @racket['cross-fade] always selects the
fallback and ignores the correspondence controls.

At exact start, the source is unchanged. At interior samples it is hidden and a
temporary frontmost layer is drawn. At structural completion, regardless of the
easing result, the source is removed and the exact caller-supplied destination
Visual is installed. Temporary path conversions and normalized outlines are
therefore never retained in later clips.

The operation reserves all ordinary Visual components and presence for both
source and destination identities. It cannot be combined in one play clip with
another animation of either endpoint.
}

@defproc[(transform-shape-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[transform-shape].
}

@defproc[(transform-formula-parts
          [correspondence formula-correspondence?])
         transform-formula-parts-request?]{

Creates a request that transforms the named parts described by
@racket[correspondence].

The identity of @racket[(formula-correspondence-source correspondence)] is the
top-level scene target. That identity must already name a
@racket[formula-assembly-visual] when @racket[scene-play] compiles the request.
The current assembly must have exactly the same local part names, in the same
order, as the correspondence source. The actual current formulas, local
transforms, and local opacities are used as the source values. This allows an
earlier clip to change those values before this request is compiled.

The correspondence destination is a part-layout template. Its exact ordered
part list becomes the structural endpoint. Its top-level identity, reference
position, rotation, scale, and opacity are not copied. The current source
assembly keeps those outer values unless simultaneous requests change them.

For every explicit match, the local translation, rotation, and x/y scale are
interpolated from the current source formula to the destination formula. The
part opacity is also interpolated.

A matched pair uses one moving layer when these typesetting values are equal:

@itemlist[
 @item{LaTeX source;}
 @item{formula mode and semantic font size;}
 @item{preamble;}
 @item{ordered document-class options and Preview-package options;}
 @item{horizontal and vertical anchor choices.}
]

Identity, local transform, and local opacity are not part of that equality
test. When one of the listed typesetting values differs, two layers move along
the same transform interpolation: the current source layer fades to zero, and
the destination layer fades in from zero. This is a moving cross-fade. The
library does not morph glyph outlines or TeX boxes.

An unmatched source part remains at its current local transform and fades to
zero. An unmatched destination part remains at its destination local transform
and fades in from zero.

Interior drawing order is deterministic:

@itemlist[#:style 'ordered
 @item{unmatched source parts in source part order;}
 @item{matched layers in explicit correspondence-match order;}
 @item{unmatched destination parts in destination part order.}
]

A changed matched pair contributes its source layer immediately before its
destination layer. Interior layers receive deterministic temporary local names
beginning with @tt{__formula-transition-}. The allocator avoids the top-level
assembly identity and every source and destination part name. Exact endpoint
samples use the original endpoint names, not the temporary names.

At eased progress zero, the exact current source part list is used. At interior
progress, the temporary layers are used. At structural completion, the exact
destination part list is installed even when the easing procedure does not map
one to one. Such an easing procedure can therefore cause a discontinuity at the
clip boundary.

The request may run simultaneously with @racket[move-to], rotation, scale, and
@racket[fade-to] requests for the same assembly because those operations change
separate components. It conflicts with another formula-part transformation.
It also reserves the presence component, so it conflicts with same-target
@racket[fade-in], @racket[fade-out], @racket[create], and @racket[uncreate].
Those operations add or remove the top-level identity, and combining their
structural endpoints would otherwise make completion order significant.

An empty source assembly, empty destination assembly, and empty match list form
a valid transformation.
}

@defproc[(transform-formula-parts-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[transform-formula-parts].
}

@defproc[(create [visual path-visual?]) create-request?]{

Creates a request that introduces @racket[visual] by revealing a prefix of its
local path from fraction zero through fraction one.

The Visual's identity must be absent from the scene before the play clip. Its
computed local path length must be finite. Line portions use Euclidean length,
and cubic portions use the deterministic approximation documented by
@racket[path-subpath-length]. @racket[scene-play] prepares an
empty-path placeholder with the same identity, style, affine transform, and
opacity at clip start. The complete supplied path is stored at the structural
endpoint.

A @racket[create] request can run with movement, rotation, scaling, and
@racket[fade-to] requests for the same identity because those requests change
different animation components. It conflicts with @racket[morph-to],
@racket[morph-to-normalized], @racket[morph-to-aligned],
@racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], @racket[morph-to-compound-aligned], and @racket[uncreate] because they change path
geometry. It also conflicts with @racket[fade-in] and @racket[fade-out] because
all three operations change scene presence. The complete Visual carried by
@racket[create] supplies the shared start position, rotation, scale, opacity,
style, and path.

Several creation requests in one play clip introduce their Visuals in request
order, in front of Visuals already in the scene.

A zero-length path has no positive interior prefix. It therefore remains empty
at interior samples and is restored to its complete semantic structure at the
structural endpoint. This matters for point-only and explicitly empty paths.
}

@defproc[(create-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[create].
}

@defproc[(uncreate [target (or/c path-visual? symbol?)]) uncreate-request?]{

Creates a request that retracts the visible prefix of a present path Visual
from fraction one toward fraction zero. The target is removed from the scene's
structural endpoint after the play clip completes.

When @racket[target] is a symbol, its path-Visual requirement is checked when
the request is compiled by @racket[scene-play]. A missing target or a target
that is not a built-in path Visual raises an exception. The current path must
also have a finite computed local length. Cubic portions use the same
deterministic approximate length and partial extraction as @racket[create].

Movement, rotation, scaling, and @racket[fade-to] may run at the same time for
the same target. A second @racket[uncreate], @racket[morph-to],
@racket[morph-to-normalized], @racket[morph-to-aligned],
@racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], @racket[morph-to-compound-aligned], or same-target @racket[create] conflicts because
all of them change the path-geometry component. Same-target @racket[fade-in] or
@racket[fade-out] also conflicts because those requests change scene presence.

A zero-length path has no positive interior prefix, so it is empty at interior
samples and is removed at the structural endpoint.
}

@defproc[(uncreate-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[uncreate].
}

@defproc[(write-in
          [visual visual?]
          [#:order order (or/c 'document 'left-to-right) 'document]
          [#:lag-ratio lag-ratio (or/c #f nonnegative-real?) #f]
          [#:outline-stroke-width outline-stroke-width nonnegative-real? 2]
          [#:reveal reveal (or/c 'bezier 'arc-length) 'bezier]
          [#:reverse? reverse? boolean? #f]
          [#:rate-func rate-func (-> finite-real? finite-real?) linear])
         write-in-request?]{

Creates a Manim-like vector introduction for @racket[visual]. Every writable
path leaf first appears as a progressively traced outline. In the second half
of its local interval, the full outline transitions to the leaf's final fill,
stroke, and cosmetic stroke width. Path leaves overlap by a small default
stagger, @racket[(min 1/5 (/ 4 N))] for @racket[N] leaves. Pass
@racket[#:lag-ratio] to select another nonnegative overlap ratio.

The default @racket['bezier] reveal gives every ordered line or Bézier segment
equal writing time, matching Manim's partial-@tt{VMobject} behavior.
@racket['arc-length] retains constant-speed geometric progress as an explicit
alternative. @racket[#:reverse? #t] writes both leaves and their path traversal
in reverse. The scene easing and @racket[#:rate-func] are applied to each leaf
after its stagger offset, so nonlinear easing does not delay the start of later
leaves.

@racket['document] follows group/SVG path order. @racket['left-to-right] sorts
the path leaves by their resolved horizontal position before calculating the
same stagger. The supplied Visual must be absent from the scene at the clip
start. The endpoint is installed exactly as supplied, so semantic SVG circles
and rectangles, and tagged formula fragments rendered through their normal SVG
renderer, are restored without a proxy representation at completion.

Built-in path Visuals, groups whose leaves are writable, circles, rectangles,
and @racket[tagged-formula] assemblies are supported. Tagged formulas expand
dvisvgm's local glyph-path @tt{<defs>} and @tt{<use>} references only while the
request is constructed; sampling and rendering the clip never invoke TeX.
Arbitrary renderer Visuals, gradients, masks, filters, and SVG text are not
writable. The request reserves all target Visual components, so it cannot run
simultaneously with another same-target Visual animation.

The name is @racket[write-in], rather than @racket[write], so requiring the
library does not shadow Racket's ordinary output procedure.
}

@defproc[(unwrite
          [target (or/c visual? symbol? visual-path?)]
          [#:order order (or/c 'document 'left-to-right) 'document]
          [#:lag-ratio lag-ratio (or/c #f nonnegative-real?) #f]
          [#:outline-stroke-width outline-stroke-width nonnegative-real? 2]
          [#:rate-func rate-func (-> finite-real? finite-real?) linear])
         unwrite-request?]{

Removes a writable Visual already present in the scene. Its leaves and path
traversal are processed in reverse order; the endpoint structurally removes the
target. The current scene Visual supplies the writing proxy, so an @racket[unwrite]
uses the current geometry and style rather than a stale caller copy.
}

@defproc[(write-in-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[write-in].
}

@defproc[(unwrite-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[unwrite].
}

@defproc[(linear [progress finite-real?]) finite-real?]{

Returns @racket[progress] unchanged. This is the default easing procedure. The
scene machinery supplies a clamped finite input and validates the easing result.
}

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
                         uncreate-request?)]
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
endpoint, its exact semantic endpoint is held. SCENE-AR permits timed wrappers
inside Visual/scalar compositions and permits a composition itself to be wrapped. Camera
requests and another @racket[timed] wrapper are not valid @racket[request] values.
Ordinary camera requests remain top-level/full-clip.
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
                         uncreate-request?)] ...)
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
place of separate arguments. Ordinary Visual requests, unified style transitions, timed Visual/composition
wrappers, and nested successions, animation groups, or lagged starts are valid
children. Camera animation requests remain invalid inside compositions.
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
                         uncreate-request?)] ...)
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
place of separate arguments. Unified style transitions and timed Visual/composition wrappers are valid group
children; camera requests remain top-level only.
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
                         uncreate-request?)] ...
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
place of separate arguments. Unified style transitions and timed Visual/scalar composition wrappers are valid lagged
children; camera requests remain top-level only.
}

@defproc[(lagged-start-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a composition created by
@racket[lagged-start].
}

@defproc[(style-to
          [target (or/c symbol? visual?)]
          [#:fill fill (or/c false/c color-spec?) #f]
          [#:stroke stroke (or/c false/c color-spec?) #f]
          [#:stroke-width stroke-width (or/c false/c stroke-width?) #f]
          [#:opacity opacity (or/c false/c opacity?) #f])
         style-to-animation-request?]{

Creates one unified style composition for @racket[target]. Any non-@racket[#f]
subset of fill color, stroke color, stroke width, and opacity may be supplied;
at least one property is required. The keyword names mirror the corresponding
Visual constructor style fields.

This operation is composition syntax rather than a new interpolation primitive.
It expands to @racket[fill-color-to], @racket[stroke-color-to],
@racket[stroke-width-to], and @racket[fade-to] leaves for exactly the properties
that were supplied. Those leaves share one assigned interval and preserve their
existing semantic protocol validation, exact endpoints, easing, and renderer
behavior.

Because expansion occurs before scheduler conflict checking, the properties do
not collapse into one coarse @racket['style] component. For example, a
fill-only @racket[style-to] may overlap a same-target @racket[stroke-width-to] or
@racket[fade-to], while an overlapping @racket[fill-color-to] conflicts normally
on @racket['fill-color].

When @racket[target] is a direct Visual, each supplied property's primitive
constructor validates the required optional Visual protocol immediately. A
symbolic target defers those same checks until @racket[scene-play] resolves the
target. A @racket[#f] keyword value means omitted; it is not a request to remove
paint. The SCENE-AT rule that a current @racket[#f] fill or stroke cannot be
color-interpolated therefore remains unchanged.

@racket[style-to] counts as one direct child for parent composition timing and
then expands its primitive leaves in parallel inside the interval it receives.
It may be used directly by @racket[scene-play], wrapped with @racket[timed], or
nested inside @racket[succession], @racket[animation-group], and
@racket[lagged-start].
}

@defproc[(style-to-animation-request? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a unified style composition created
by @racket[style-to].
}

@section[#:tag "scenes"]{Scene Timelines}

@defproc[(scene? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a scene timeline.
}

@defproc[(make-scene
          [initial-state scene-state? empty-scene-state]
          [#:camera camera camera? default-camera])
         scene?]{

Creates a zero-duration scene whose current semantic state is
@racket[initial-state] and whose current camera is @racket[camera]. The new
scene contains no clips.
}

@defproc[(scene-add [scene scene?] [visual visual?] ...) scene?]{

Returns a scene with each supplied Visual added instantaneously at the current
scene time. No clip is appended and duration does not change.

Visuals are added in argument order. Each later argument is placed in front of
earlier Visuals. Adding a top-level identity already present as a Visual or named scalar in the current
state raises an exception. A group is added as one top-level Visual; its child
order remains internal to the group. A @racket[derived-visual?] is likewise
stored as one top-level identity and is resolved only when concrete geometry is
requested.

An instantaneous addition at the exact end of a scene is not normally included
in frame sampling. Follow it with @racket[scene-wait] or @racket[scene-play]
when it must be visible in rendered output. Supplying no Visuals returns an
equivalent scene.
}

@defproc[(scene-remove [scene scene?]
                       [target (or/c visual? symbol? visual-path?)] ...)
         scene?]{

Returns a scene with each addressed target removed instantaneously from the
current state. No clip is appended and duration does not change. Removing a
nested path rebuilds only its ancestor groups; top-level drawing order is
preserved. Removing an absent target raises an exception. Supplying no targets
returns an equivalent scene.
}

@defproc[(scene-ref [scene scene?]
                    [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the concrete addressed Visual from the scene's current endpoint state.
}

@defproc[(scene-visual-at [scene scene?]
                          [target (or/c visual? symbol? visual-path?)]
                          [time (and/c finite-real? (>=/c 0))])
         visual?]{

Samples @racket[scene] at @racket[time] and returns the concrete addressed
Visual. Nested child transforms remain local to their containing group.
}

@defproc[(scene-set-value [scene scene?]
                          [id (or/c symbol? scene-parameter?)]
                          [value any/c]) scene?]{
Adds or replaces one named interpolable semantic value instantaneously at the
current scene time. No clip is appended and duration does not change. A value ID
may not collide with a top-level Visual ID. Earlier clips retain their stored
value snapshots.

The two-argument shorthand @racket[(scene-set-value scene parameter)] accepts
a @racket[scene-parameter?] and installs its declared initial value.
}

@defproc[(scene-remove-value [scene scene?]
                             [id (or/c symbol? scene-parameter?)]) scene?]{
Removes one named semantic value instantaneously. Removing an absent value raises an
exception and does not append a timeline clip.
}

@defproc[(scene-current-value [scene scene?]
                              [id (or/c symbol? scene-parameter?)]) any/c]{
Returns one named interpolable semantic value from the scene's stored endpoint state.
}

@defproc[(scene-value-at [scene scene?]
                          [id (or/c symbol? scene-parameter?)]
                          [time (and/c finite-real? (>=/c 0))]) any/c]{
Samples one named interpolable semantic value directly at absolute scene @racket[time]. The same
closed timeline bounds as @racket[scene-sample] apply.
}

@defproc[(scene-set-camera [scene scene?]
                            [camera camera?])
         scene?]{

Returns a scene whose current camera is @racket[camera]. The replacement is
instantaneous: no clip is appended and duration does not change. Earlier clips
keep their stored cameras.

An instantaneous replacement at the exact end of a scene is not normally
included in frame sampling. Follow it with @racket[scene-wait] or
@racket[scene-play] when the replacement must appear in rendered output.
}

@defproc[(scene-play
          [scene scene?]
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
                         write-in-request?
                         unwrite-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...
          [#:duration duration
                      (or/c false/c (and/c finite-real? positive?))
                      #f]
          [#:easing easing (procedure-arity-includes/c 1) linear])
         scene?]{

Appends one play clip. When no @racket[timed], @racket[succession],
@racket[animation-group], or @racket[lagged-start] value is present, Visual/scalar and
camera @racket[request] values retain the historical behavior: they run
simultaneously and share @racket[duration] and @racket[easing]. The exact
pre-SCENE-AN compilation path is used unchanged.

When @racket[#:duration] is omitted, ordinary requests retain the historical
one-second default. A direct @racket[write-in] uses Manim's default instead:
one second for fewer than fifteen writable leaves and two seconds for fifteen
or more. An explicit positive duration always takes precedence.

When at least one timing/composition value is present, every Visual or scalar request
resolves to one or more concrete local intervals. A top-level @racket[timed]
value uses literal second-based start and duration and may wrap either one Visual
leaf or one composition. An ordinary unwrapped top-level Visual request spans the
complete enclosing clip.

Inside compositions, unwrapped direct children contribute one timing unit and a
timed direct child contributes @racket[(+ start duration)] units. A succession
places those spans consecutively, an animation group starts them together and
scales against the longest span, and a lagged start offsets raw starts by its lag
ratio before scaling the complete envelope. Bare nested compositions remain
one-unit direct children unless explicitly wrapped by @racket[timed]. All three
composition forms may nest arbitrarily with timed Visual/composition children.

Equal-start Visual leaves are compiled together against one prepared local start
state. A later start batch is compiled against the exact semantic state sampled
at that local boundary, so a touching relative request starts from the previous
request's exact endpoint rather than the enclosing clip start. Sampling remains
direct and does not depend on rendering prior frames.

Structural introduction requests are installed only at their local start. A
@racket[create] request adds an empty-path placeholder and @racket[fade-in] adds
the complete Visual at opacity zero. Requests beginning at that same local time
share the prepared state, so movement, rotation, scaling, opacity, and compatible
geometry changes can still compose with an introduction exactly as in the
historical simultaneous model. A @racket[fade-out] or @racket[uncreate] removal
may not end while another animation of that target remains active; reintroduction
at the exact removal boundary is allowed.

Positive-measure overlap on the same Visual component is rejected. Touching
intervals are not overlap and are legal. Requests for disjoint components may
overlap freely.

Camera requests remain full-clip through SCENE-AW and are compiled
against the current camera at the clip start.
@racket[camera-pan-by] adds to that start center, while
@racket[camera-zoom-by] divides that start world width by its magnification
factor. A @racket[camera-follow] request reads the Visual state at local time zero to
capture the target's initial frame offset; scene sampling later supplies the
target's actual sampled Visual position, including delayed, early-ending,
duration-scaled sequential, parallel, and lagged SCENE-AR motion. A camera-fit request already contains a
concrete center and visible width measured when the request was constructed.
Camera and Visual requests may appear in any order.

A single list of requests can be supplied in place of separate request
arguments:

@racketblock[
(scene-play scene
            (list (move-to 'a (vec2 2 0))
                  (rotate-by 'a 1)
                  (camera-pan-to (vec2 1 0))
                  (camera-zoom-by 2))
            #:duration 2)
]

At least one request is required. Each composition value itself also requires
at least one child. In the historical full-clip case, two
simultaneous requests may target the same Visual when every component they
change is disjoint. With local timing, the same rule applies only where the
request intervals overlap. The components in
this version are translation, rotation, scale, opacity, path geometry, formula
parts, and scene presence. Both @racket[move-to] and
@racket[move-along-path] reserve translation. @racket[orient-along-path],
@racket[rotate-to], and @racket[rotate-by] reserve rotation. A request can
change more than one component:
@racket[fade-in] and @racket[fade-out] change opacity and presence,
@racket[create] and @racket[uncreate] change path geometry and presence, and
@racket[transform-formula-parts] changes formula parts and reserves presence.

Two overlapping requests may not change the same component for the same
identity. Exact endpoint touching is allowed. Thus overlapping opacity requests
conflict. Strict morphing, normalized morphing, creation, and
uncreation conflict on path geometry. Two formula-part transformations conflict
on formula parts. A formula-part transformation also conflicts with a
same-target structural introduction or removal because both reserve presence.
Requests for different identities do not conflict.

The camera center and visible world width are separate camera components. Pan
and follow requests change the center. Zoom requests change visible width. A fit
request changes both. One follow request and one zoom request may run together.
Two requests that reserve the same camera component raise an exception, so fit
conflicts with pan, follow, zoom, or another fit. Camera components do not
conflict with Visual components.

Before easing is called, progress is clamped to the closed unit interval. The
easing result must be a finite real and is also clamped to that interval. A
normal easing procedure should map @racket[0] to @racket[0] and @racket[1] to
@racket[1]. Transform component endpoints follow the easing result, as in
earlier versions.

Introduction, removal, and formula-part transformation requests have
structural endpoint rules. For an untimed request the structural endpoint is the
play-clip boundary; for a timed request it is the local interval endpoint. At
that endpoint, a completed
@racket[create] contains the complete original path, a completed
@racket[fade-in] contains the supplied final opacity, and a completed
@racket[transform-formula-parts] contains the exact destination part list. A
completed @racket[uncreate] or @racket[fade-out] removes its target. These rules
apply even when easing does not map one to one. Such an easing procedure can
therefore cause a discontinuity at the request endpoint.

A @racket[fade-to], @racket[morph-to], @racket[morph-to-normalized],
@racket[morph-to-aligned], @racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], or @racket[morph-to-compound-aligned] request has no
structural endpoint override. Like
movement, rotation, scale, camera pan, camera zoom, camera fit, and camera
follow, its final sampled value follows the easing result. A normalized morph
preserves the exact source at eased progress zero and the exact requested
destination at eased progress one. Camera animation preserves pixel dimensions
and background throughout the clip.
}

@defproc[(scene-wait [scene scene?]
                     [duration (and/c finite-real? positive?)])
         scene?]{

Appends a wait clip that holds the current Visual state and current camera
unchanged for @racket[duration] seconds.
}

@defproc[(scene-sample [scene scene?]
                       [time (and/c finite-real? (>=/c 0))])
         scene-state?]{

Returns the complete scene state at absolute @racket[time]. Time must lie in
the closed interval from @racket[0] through @racket[(scene-duration scene)].

Clip intervals are half-open. Sampling the exact total duration returns
@racket[scene-current-state]. This procedure samples only the Visual state; it
does not apply camera animations. Camera values are sampled separately with
@racket[scene-camera-at].
}

@defproc[(scene-camera-at [scene scene?]
                          [time (and/c finite-real? (>=/c 0))])
         camera?]{

Returns the complete camera at absolute @racket[time]. Time must lie in the
same closed interval accepted by @racket[scene-sample]. Clip intervals are
half-open. Sampling the exact total duration returns
@racket[scene-current-camera]. This procedure samples only the camera. For a
follow request, the timeline internally samples the followed target's semantic
Visual state at the same absolute time, including SCENE-AR local timing and
sequential/parallel/lagged composition. It
never depends on earlier rendered frames.
}

@defproc[(scene-duration [scene scene?])
         (and/c finite-real? (>=/c 0))]{

Returns the total duration in seconds.
}

@defproc[(scene-current-state [scene scene?]) scene-state?]{

Returns the state after all operations currently in the timeline. This is also
the state returned by sampling the exact scene duration. A completed
@racket[create] or @racket[fade-in] contributes its complete Visual. A completed
@racket[uncreate] or @racket[fade-out] contributes no Visual for its target
identity.
}

@defproc[(scene-current-camera [scene scene?]) camera?]{

Returns the camera after all operations currently in the timeline. This is also
the camera returned by @racket[scene-camera-at] at the exact scene duration.
An unusual easing procedure can leave the current camera before a requested pan,
zoom, fit, or follow endpoint, just as it can leave a moved Visual before its
destination.
}

@defproc[(scene-clip-count [scene scene?]) exact-nonnegative-integer?]{

Returns the number of play and wait clips. Instantaneous Visual additions,
Visual removals, and camera replacements do not increase this count.
}

@section[#:tag "pict-renderers"]{Pict Renderer Protocol}

A Pict renderer converts one kind of semantic Visual into centered local Pict
geometry. Renderer selection uses an explicit ordered list. The first renderer
that reports support is selected. There is no mutable global registry.

@defthing[#:kind "generic interface" gen:pict-renderer any/c]{

The generic interface for Pict renderer values. A renderer structure must
implement @racket[pict-renderer-supports?] and
@racket[pict-renderer-render].
}

@defproc[(pict-renderer? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:pict-renderer].
}

@defproc[(pict-renderer-supports? [renderer pict-renderer?]
                                  [visual visual?])
         boolean?]{

Reports whether @racket[renderer] can render @racket[visual]. The high-level
renderer dispatcher checks that a custom implementation returns a Boolean.
}

@defproc[(pict-renderer-render [renderer pict-renderer?]
                               [visual visual?]
                               [camera camera?])
         pict?]{

Renders centered local geometry for a supported Visual. The result must not
apply translation in the Visual's containing coordinate system. A renderer is
responsible for interpreting any local geometry, scale, and rotation that its
Visual type supports. It should render at full local strength and should not
apply semantic global opacity. The high-level adapter applies opacity after
renderer dispatch, then a scene or group adapter places the result at the
Visual's reference position.

The high-level renderer dispatcher checks that the result is a Pict. Calling
@racket[pict-renderer-render] directly does not apply semantic opacity.

A renderer that explicitly supports a group or formula assembly replaces the
built-in recursive compositor for that Visual. It receives the semantic
composite value and camera, but not the surrounding renderer list. It is
responsible for interpreting the children or parts, their significant order,
their opacity, nested composites, and the complete Visual's scale and rotation.
It must not apply the Visual's containing-system translation or global opacity.
The high-level adapter applies global opacity afterward and the parent adapter
places the result.
}

@defproc[(pict-renderer-list? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a list containing only Pict renderer
values. The empty list is valid. It can compose an empty built-in group or an
empty formula assembly, but a nonempty leaf needs an explicit supporting
renderer.
}

@defthing[default-pict-renderers (listof pict-renderer?)]{

The ordered built-in renderer list. It contains circle, rectangle, path,
arrow, axes, bitmap-image, full-fidelity SVG, and plain-text renderers, followed
by the LaTeX formula renderer. Groups are composed by the high-level Pict adapter when no explicit renderer supports them.
Formula assemblies use the same recursive compositor through their internal
ordered formula parts. Prepend a custom renderer when it should override a
built-in leaf or complete composite.
}

@subsection{Built-in Rendering}

The built-in circle renderer multiplies the local diameter by the Visual's x
and y scale factors. Non-uniform scale therefore produces an ellipse. Rotation
is applied when that ellipse is not rotationally symmetric.

The built-in rectangle renderer multiplies local width and height by the scale
factors and then rotates the resulting Pict.

The built-in arrow renderer derives one open shaft and zero, one, or two
closed triangular tip subpaths from the semantic arrow. The built-in axes
renderer derives the two open shafts, ordered open ticks, and optional closed
maximum-end tips. Both then use the ordinary path renderer. Tip dimensions and
tick sizes are transformed as local geometry. Stroke width remains cosmetic.

Closed tips use the same odd-even fill, miter join, and butt-cap policy as other
closed path geometry. Open shafts and ticks use round endpoint caps and miter
joins. The adapter uses the stored stroke style for shaft and tick lines and for
tip fill and outline.

The built-in plain-text renderer converts the semantic font size from world
units to camera pixels and constructs a platform font from the requested face,
family, style, and weight. It renders the one-line string with Pict, applies the
stored color, places the chosen anchor at the center of a symmetric local Pict,
and then applies semantic scale and rotation around that anchor. Direct font
sizes are kept within the drawing backend's supported range; a final Pict scale
preserves the requested world-space size outside that range.

Since version @tt{0.50.1}, the completed nonempty local text appearance is
rasterized to an alpha bitmap before scene placement. Moving the Visual or
panning the camera therefore translates an already-rasterized glyph run instead
of asking the platform font backend to rerasterize it at changing device-space
origins. This prevents subtle apparent inter-letter spacing changes during smooth
motion. The default renderer keeps a bounded renderer-local cache for common
immutable text appearances. The cache key excludes position, Visual identity,
opacity, and camera center, but includes text/font/color/alignment data, semantic
scale and rotation, and camera pixel scale. Camera zoom and appearance transforms
therefore rerasterize at their sampled resolution. Unknown adapter-native color
objects bypass the cache while retaining stable local-origin rasterization.
The same bounded renderer-resource mechanism caches complete formula
appearances. Formula position, identity, opacity, and camera center do not
invalidate an appearance, while formula source/options, semantic scale/rotation,
and camera pixel scale do.

An empty text string produces a transparent one-pixel Pict. Left and right
anchors reserve symmetric space on the opposite side of the anchor, and top
and bottom anchors do the same vertically. Baseline alignment uses the Pict's
font ascent and descent. These symmetric boxes keep the semantic anchor at the
local Pict center, which is the placement convention used by groups and scene
states.

The built-in formula renderer chooses one of @tt{tex-math},
@tt{tex-display-math}, and @tt{tex-real-display-math} from the semantic mode.
It passes the immutable source, preamble, document-class options, and Preview
options to @racketmodname[latex-pict] with that package's extra scale set to
one. It then maps the selected 10pt, 11pt, or 12pt document base to the
formula's semantic world-unit font size.

Formula anchoring, non-uniform semantic scale, rotation, and opacity follow the
same order as plain text. Empty formula source produces a transparent
one-pixel Pict without loading @racketmodname[latex-pict] or running TeX.
Nonempty formula rendering can perform external process and native-library
work. @racketmodname[latex-pict] is loaded at that adapter boundary instead of
from the pure formula model. That package caches repeated complete TeX
documents; source, preamble, or option changes produce a different document.

A formula assembly is composed from its parts in significant back-to-front
order. Each part is rendered as an ordinary formula Visual at its stored local
position. The same explicit renderer list is passed to every part. An empty
assembly produces a transparent one-pixel Pict and does not invoke TeX. The
assembly's uniform scale and rotation are inherited through its part model
transforms before rendering, and its global opacity is applied after the parts
have been composed.

The built-in path renderer transforms every stored local point by scale and
rotation, converts world units to pixels, and draws the result through
@racket[dc-path%]. Sampled function graphs reach this renderer as ordinary path
Visuals; no separate graph renderer is used. Line segments become drawing-path
line operations. Cubic segments become drawing-path curve operations and remain
true cubic curves.
Closed subpaths are filled together with the odd-even rule. Open subpaths are
stroked without implicit filling. A false fill or stroke selects a transparent
brush or pen.

Closed outlines use miter joins and butt caps, which keeps polygon corners
sharp. Open paths use round endpoint caps and miter joins between segments.

A partial piece returned by @racket[path-geometry-partial] is open unless it
contains a complete original closed subpath. During @racket[create], a closed
shape is therefore stroked as it grows and becomes filled when its subpath is
complete. In a compound path, one completed closed subpath can be filled while
a later subpath is still partial. @racket[uncreate] performs the same sequence
in reverse.

For all built-in Visuals, stroke width is cosmetic: semantic scale does not
multiply it. A group is composed recursively from its ordered children. Its
uniform scale and rotation are inherited by child model transforms before each
child is rendered, so cosmetic stroke widths are not enlarged by scaling a
finished composite Pict. The same explicit renderer list is passed to every
descendant. Group translation places the complete composite in its containing
coordinate system.

The built-in compositor uses a symmetric Pict box around the group anchor. Its
half-width and half-height are the largest absolute child extents on each axis.
This keeps the anchor at the center even when all children lie on one side. An
empty group produces a transparent one-pixel Pict.

Global opacity is applied to the complete local Pict after renderer selection
or group composition. It affects fill and stroke together and does not change
Pict bounds. World translation is applied later by
@racket[scene-state->pict]. Path reveal
is measured in untransformed local arc length. Cubic reveal uses
the deterministic approximation described by @racket[path-subpath-length]. A
non-uniform Visual scale can therefore change displayed speed along differently
oriented or curved portions.

@subsection{Defining a Custom Renderer}

Here is a complete custom Visual and renderer:

@racketblock[
(require pict
         animate)

(struct cross-visual (id position)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (cross-visual-id value))
   (define (visual-position value)
     (cross-visual-position value))
   (define (visual-with-position value position)
     (struct-copy cross-visual value [position position]))])

(struct cross-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (cross-visual? visual))
   (define (pict-renderer-render _renderer _visual camera)
     (define arm
       (camera-length->pixels camera 1))
     (cc-superimpose
      (filled-rectangle arm (/ arm 5))
      (filled-rectangle (/ arm 5) arm)))])

(define renderers
  (cons (cross-renderer) default-pict-renderers))
]

The example's renderer uses Pict operations, so its module must also require
@racketmodname[pict].

@section[#:tag "relative-layout"]{Relative Layout}

Relative layout measures the Pict that a Visual would produce and converts its
pixel dimensions back into world units. Arrow tips, axis ticks, tip outlines,
and cosmetic stroke padding are therefore included in the measured box. It
then returns new Visual values with updated reference positions. The source Visuals are not mutated.

Layout is renderer-aware. Text, formulas, custom Visuals, and composites can
have dimensions that are known only after renderer selection. Every measurement
and placement procedure therefore accepts the same @racket[#:camera] and
@racket[#:renderers] arguments as the Pict adapter. Use the same values for
layout and final rendering.

A layout box is the complete symmetric render box of the local Pict. It is not
a tight ink box. Transparent padding, text anchor padding, formula anchor
padding, group composition extents, and any padding returned by a custom
renderer are included. Semantic opacity does not change the box because opacity
does not change Pict dimensions.

Measuring a nonempty LaTeX formula with the built-in formula renderer can invoke
LaTeX and Poppler. A custom formula renderer can provide deterministic metrics
without launching TeX.

@defstruct*[layout-box ([left finite-real?]
                        [bottom finite-real?]
                        [right finite-real?]
                        [top finite-real?])
  #:transparent]{

Represents an axis-aligned rendered box in the containing coordinate system.
Coordinates use the library's mathematical convention: x increases to the
right and y increases upward.

The fields have these meanings:

@itemlist[
 @item{@racket[left] is the smallest horizontal coordinate.}
 @item{@racket[bottom] is the smallest vertical coordinate.}
 @item{@racket[right] is the largest horizontal coordinate.}
 @item{@racket[top] is the largest vertical coordinate.}
]

All four fields must be finite real numbers. @racket[left] must not exceed
@racket[right], and @racket[bottom] must not exceed @racket[top]. Zero-width
and zero-height boxes are valid.

The structure is immutable and transparent. Its public bindings include
@racket[layout-box], @racket[layout-box?], the four field accessors, and
@racket[struct:layout-box].
}

@defproc[(layout-horizontal-alignment? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of:

@racketblock[
'left
'center
'right
]

These symbols select a horizontal coordinate of a layout box.
}

@defproc[(layout-vertical-alignment? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of:

@racketblock[
'bottom
'center
'top
]

These symbols select a vertical coordinate of a layout box. Baseline alignment
is not part of this layout protocol. A text or formula Visual may still use a
baseline as its own semantic anchor before its complete render box is measured.
}

@defproc[(layout-box-width [box layout-box?])
         (and/c finite-real? (>=/c 0))]{

Returns @racket[(- (layout-box-right box) (layout-box-left box))].
}

@defproc[(layout-box-height [box layout-box?])
         (and/c finite-real? (>=/c 0))]{

Returns @racket[(- (layout-box-top box) (layout-box-bottom box))].
}

@defproc[(layout-box-center [box layout-box?]) vec2?]{

Returns the midpoint of @racket[box].
}

@defproc[(layout-box-anchor? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of the nine canonical
render-box anchors:

@racketblock[
'bottom-left  'bottom  'bottom-right
'left         'center  'right
'top-left     'top     'top-right
]

These names select both coordinates at once. They are distinct from the
one-axis alignment predicates and intentionally do not infer a baseline from a
renderer.
}

@defproc[(layout-box-anchor [box layout-box?]
                            [anchor layout-box-anchor?])
         vec2?]{

Returns the point selected by @racket[anchor] in @racket[box]'s containing
coordinate system. For example, @racket['top-right] gives
@racket[(vec2 (layout-box-right box) (layout-box-top box))].
}

@defproc[(visual-layout-box
          [visual visual?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         layout-box?]{

Renders @racket[visual] as local Pict geometry with @racket[camera] and
@racket[renderers], then returns its complete symmetric box in the Visual's
containing coordinate system.

If the local Pict has pixel width @italic{w}, pixel height @italic{h}, camera
scale @italic{s}, and Visual position @italic{(x,y)}, the result is:

@centered{
 @tt{layout-box(x - w/(2s), y - h/(2s), x + w/(2s), y + h/(2s))}}

The selected renderer must follow the Pict-renderer protocol and return centered
local geometry. The procedure checks that the Visual position is a
@racket[vec2], that its identity is a symbol, and that the Pict dimensions are
finite and nonnegative.

This procedure can perform adapter effects. In particular, measuring a nonempty
formula through the built-in formula renderer can run TeX.
}

@defproc[(visual-layout-anchor
          [visual visual?]
          [anchor layout-box-anchor?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         vec2?]{

Measures @racket[visual] as @racket[visual-layout-box] would and returns the
selected canonical anchor. The result is in the Visual's containing world or
frame coordinate system.
}

@defproc[(visuals-layout-box
          [visuals (listof visual?)]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         (or/c layout-box? false/c)]{

Returns the smallest axis-aligned box containing the measured boxes of all
@racket[visuals]. List order does not change the union. Returns @racket[#f] for
an empty list.

The camera and renderer list are validated even for an empty list. Every
nonempty Visual is measured with @racket[visual-layout-box] using the supplied
context.
}

@defproc[(visual-place-at
          [visual visual?]
          [position vec2?]
          [#:anchor anchor layout-box-anchor? 'center]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns an immutable copy of @racket[visual] whose measured @racket[anchor] is
exactly @racket[position]. The default moves its render-box center. Identity,
appearance, and all transform components other than translation are preserved.
}

@defproc[(visual-align-to
          [visual visual?]
          [reference visual?]
          [#:anchor anchor layout-box-anchor? 'center]
          [#:reference-anchor reference-anchor layout-box-anchor? anchor]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns an immutable copy of @racket[visual] whose selected @racket[anchor]
equals @racket[reference]'s selected @racket[reference-anchor]. The default
aligns centers. Both Visuals must be measured in compatible world or frame
coordinate systems. This is a compile-time layout calculation, not a live
constraint: later animation of either Visual does not update the returned one.
}

@defproc[(visual-align-horizontal
          [visual visual?]
          [reference visual?]
          [alignment layout-horizontal-alignment?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] whose selected horizontal box coordinate is
equal to the same coordinate of @racket[reference]. The symbols @racket['left],
@racket['center], and @racket['right] select the coordinate.

Only the x component of the Visual position changes. Its y component, identity,
geometry, style, transform components other than translation, opacity, and
children remain as supplied by its @racket[visual-with-position]
implementation. @racket[reference] is unchanged.
}

@defproc[(visual-align-vertical
          [visual visual?]
          [reference visual?]
          [alignment layout-vertical-alignment?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] whose selected vertical box coordinate is
equal to the same coordinate of @racket[reference]. The symbols
@racket['bottom], @racket['center], and @racket['top] select the coordinate.

Only the y component of the Visual position changes. The x component and the
reference Visual remain unchanged.
}

@defproc[(visual-place-above
          [visual visual?]
          [reference visual?]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:horizontal-alignment horizontal-alignment
                                  layout-horizontal-alignment?
                                  'center]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] placed above @racket[reference]. The bottom
edge of the returned Visual's box is exactly @racket[gap] world units above the
top edge of the reference box.

The selected horizontal coordinates are aligned. The default aligns box
centers; @racket['left] and @racket['right] align the corresponding edges.
}

@defproc[(visual-place-below
          [visual visual?]
          [reference visual?]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:horizontal-alignment horizontal-alignment
                                  layout-horizontal-alignment?
                                  'center]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] placed below @racket[reference]. The top edge
of the returned Visual's box is exactly @racket[gap] world units below the
bottom edge of the reference box. The requested horizontal box coordinates are
aligned.
}

@defproc[(visual-place-left-of
          [visual visual?]
          [reference visual?]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:vertical-alignment vertical-alignment
                                layout-vertical-alignment?
                                'center]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] placed to the left of @racket[reference]. The
right edge of the returned Visual's box is exactly @racket[gap] world units to
the left of the reference box. The requested vertical box coordinates are
aligned.
}

@defproc[(visual-place-right-of
          [visual visual?]
          [reference visual?]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:vertical-alignment vertical-alignment
                                layout-vertical-alignment?
                                'center]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         visual?]{

Returns a copy of @racket[visual] placed to the right of @racket[reference]. The
left edge of the returned Visual's box is exactly @racket[gap] world units to
the right of the reference box. The requested vertical box coordinates are
aligned.
}

@defproc[(visuals-center-at
          [visuals (listof visual?)]
          [center vec2?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         (listof visual?)]{

Translates every Visual by the same displacement so that the center of their
union layout box is @racket[center]. Input order and Visual identities are
preserved. The input values are unchanged.

Returns an empty list when @racket[visuals] is empty. The camera, renderer list,
and center are still validated.
}

@defproc[(arrange-visuals-horizontally
          [visuals (listof visual?)]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:vertical-alignment vertical-alignment
                                layout-vertical-alignment?
                                'center]
          [#:center center (or/c vec2? false/c) #f]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         (listof visual?)]{

Arranges @racket[visuals] from left to right in their existing list order.
Without @racket[#:center], the first Visual keeps its original position. Each
later Visual is placed to the right of the previously arranged Visual with the
requested gap and vertical alignment.

When @racket[center] is a @racket[vec2], the complete arranged list is translated
as one unit so that its union layout box has that center. @racket[#f] leaves the
first Visual fixed. An empty input list returns an empty list.

The procedure returns a new list and does not reorder identities. Arrangement
uses adjacent measured boxes; it is not a constraint solver and does not
recompute automatically after later content, renderer, camera, or transform
changes.
}

@defproc[(arrange-visuals-vertically
          [visuals (listof visual?)]
          [#:gap gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:horizontal-alignment horizontal-alignment
                                  layout-horizontal-alignment?
                                  'center]
          [#:center center (or/c vec2? false/c) #f]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         (listof visual?)]{

Arranges @racket[visuals] from top to bottom in their existing list order.
Without @racket[#:center], the first Visual keeps its original position. Each
later Visual is placed below the previously arranged Visual with the requested
gap and horizontal alignment.

When @racket[center] is a @racket[vec2], the complete arranged list is translated
as one unit so that its union layout box has that center. @racket[#f] leaves the
first Visual fixed. An empty input list returns an empty list.

The returned list preserves order and identities. Layout is a one-time immutable
calculation. It does not maintain a live relationship between the arranged
Visuals.
}

@subsection{Fitting a Background}

A background can be fitted around measured content by adding padding to the
union box:

@racketblock[
(define arranged
  (arrange-visuals-vertically
   (list title formula explanation)
   #:gap 1/3
   #:center origin
   #:camera default-camera
   #:renderers default-pict-renderers))

(define content-box
  (visuals-layout-box arranged
                      #:camera default-camera
                      #:renderers default-pict-renderers))

(define background
  (rectangle #:id 'background
             #:center (layout-box-center content-box)
             #:width (+ (layout-box-width content-box) 3/2)
             #:height (+ (layout-box-height content-box) 3/2)))

(define card
  (group (cons background arranged)
         #:id 'card))
]

The example adds three quarters of a world unit on every side. The background
is first in the group child list, so it is painted behind the content.


@section[#:tag "attention"]{Temporary Attention Effects}

@defproc[(circumscribe
          [target (or/c visual? symbol? visual-path?)]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/5]
          [#:color color any/c "gold"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         circumscribe-request?]{

Creates a temporary rounded outline that draws, holds, and erases over one
play clip. @racket[target] may be a top-level Visual/id or an explicit nested
built-in group/formula path. At every interior sample, its resolved world-space
Visual is measured through the ordinary renderer; the outline consequently
follows simultaneous target translation, rotation, scale, and formula-layout
changes regardless of request order in the play clip.

The outline does not mutate the target and is absent at both structural clip
endpoints. It measures a renderer box rather than visible glyph contours, and
does not respond to camera or renderer changes within the same clip.
}

@defproc[(circumscribe-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[circumscribe].
}

@defproc[(indicate
          [target (or/c visual? symbol? visual-path?)]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/5]
          [#:color color any/c "gold"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         indicate-request?]{

Creates a temporary rounded outline that pulses once over one play clip. Target
resolution, renderer-aware nested live measurement, and endpoint behavior are
the same as @racket[circumscribe].
}

@defproc[(indicate-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[indicate].
}

@section[#:tag "rendering"]{Pict, Bitmap, and Frame Conversion}

@defproc[(visual->pict [visual visual?]
                       [camera camera?]
                       [#:renderers renderers
                                    pict-renderer-list?
                                    default-pict-renderers])
         pict?]{

Selects the first explicit supporting renderer and validates its local Pict.
When no explicit renderer supports a built-in group or formula assembly, the
adapter recursively composes its ordered children or parts and passes the same
@racket[renderers] list to every descendant. An explicit renderer that reports
support for the complete composite therefore overrides the built-in compositor.

The dispatcher does not apply translation in the Visual's containing
coordinate system. It also does not interpret an affine transform on behalf of
a custom renderer. The built-in circle, rectangle, path, plain-text, and
formula renderers apply their Visuals' scale and rotation themselves. The
built-in group compositor inherits the group's uniform scale and rotation
through its children before rendering. A formula assembly delegates the same
composition rule to its ordered formula parts.

When @racket[visual] implements @racket[gen:opacity-visual], its
@racket[visual-opacity] result must satisfy @racket[opacity?]. Opacity one
returns the rendered or composed Pict unchanged. Lower values use Pict alpha
without changing the Pict's width, height, or reference placement. A custom
renderer therefore receives opacity behavior without handling it itself. Group
opacity is applied after its children have been composed.

A @racket[derived-visual?] cannot be rendered by @racket[visual->pict] directly
because no scene-state scalar context is available. Resolve it first with
@racket[scene-state-resolved-ref], or render through @racket[scene-state->pict]
or @racket[scene->pict].

If no renderer supports the concrete Visual, an exception is raised. Invalid
custom support, render, or opacity-protocol results also raise exceptions.
}

@defproc[(scene-state->pict
          [state scene-state?]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         pict?]{

Creates a fixed-size Pict for @racket[state]. It fills the background, resolves
any top-level @racket[derived-visual?] definitions against this exact state's
named scalars, renders the resulting concrete Visuals in back-to-front order,
and places each Visual so its reference position maps through @racket[camera].
A group occupies one top-level drawing
position and recursively applies its own child order. A formula assembly also
occupies one top-level position and applies its separate local part order. A
zero-opacity Visual remains in semantic order but contributes no visible
pixels.
}

@defproc[(scene->pict
          [scene scene?]
          [time (and/c finite-real? (>=/c 0))]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         pict?]{

Samples @racket[scene] at @racket[time] and converts the resulting scene state
to a Pict. The same time range rules as @racket[scene-sample] apply.

When @racket[camera] is @racket[#f], the Visual state and scene camera are
sampled together using one easing evaluation. Supplying a camera is a static
override: the supplied camera is used instead of the scene-camera timeline for
this conversion.
}

@defproc[(scene-frame-count [scene scene?]
                            [#:fps fps exact-positive-integer? 30])
         exact-nonnegative-integer?]{

Returns @racket[(ceiling (* (scene-duration scene) fps))]. A zero-duration
scene has zero frames.
}

@defproc[(frame-index->time
          [frame-index exact-nonnegative-integer?]
          [#:fps fps exact-positive-integer? 30])
         (and/c rational? (>=/c 0))]{

Converts a zero-based frame index to the exact time
@racket[(/ frame-index fps)]. This procedure does not know a scene and does not
check whether the index is in range for one.
}

@defproc[(scene-frame->bitmap
          [scene scene?]
          [frame-index exact-nonnegative-integer?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers])
         (is-a?/c bitmap%)]{

Renders one in-range scene frame to an aligned bitmap. Valid frame indices run
from @racket[0] through one less than @racket[(scene-frame-count scene)]. An
out-of-range index raises an exception.

When @racket[camera] is @racket[#f], the camera is sampled from the scene at the
frame time. A supplied camera is used as one fixed override for the frame.
}

@section[#:tag "output"]{PNG and MP4 Output}

The procedures in this section perform external effects. Their names end in
@litchar{!} according to the project house style.

@defproc[(render-frames!
          [scene scene?]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1])
         (listof path?)]{

Creates @racket[output-directory] when needed and writes every sampled frame as
a PNG file. The returned paths are in frame order. A zero-duration scene writes
no frames and returns an empty list, but directory creation and optional cleanup
still occur.

When @racket[camera] is @racket[#f], each frame samples the camera stored in the
scene timeline. Supplying a camera uses that one static view for every frame and
ignores camera pan or zoom requests during rendering. Pixel dimensions remain
fixed either way.

When a sampled scene contains a nonempty formula, including a nonempty part of
a formula assembly, and the built-in formula renderer is selected, frame
rendering can invoke LaTeX and Poppler through @racketmodname[latex-pict]. A
custom renderer placed before the defaults can replace that behavior for a
formula leaf or for the complete assembly.

Names use at least six decimal digits:

@itemlist[
 @item{@filepath{frame-000000.png}}
 @item{@filepath{frame-000001.png}}
 @item{@filepath{frame-000002.png}}
]

When @racket[clean?] is true, the procedure first deletes files in the output
directory whose names match @tt{frame-} followed by at least six digits and
@tt{.png}. Other files are preserved. When @racket[clean?] is false, no cleanup
is performed.

@racket[workers] is a bounded thread-pool size. Its default, one, retains
sequential output. With more workers, independent frames render and write
concurrently, but the returned paths remain in frame-index order and each frame
keeps its deterministic filename. The built-in renderers synchronize their
shared resources. A custom renderer used with more than one worker must itself
be safe for concurrent calls.
}

@defproc[(render-frames/report!
          [scene scene?]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1])
         render-diagnostics?]{

Writes frames with the same behavior as @racket[render-frames!], but returns a
@racket[render-diagnostics] value. Cache counts are deltas collected while this
call runs from the built-in image, SVG, text, and formula resource caches;
custom renderer caches are intentionally not inspected.
}

@defstruct*[render-diagnostics
             ([paths (listof path?)]
              [frame-count exact-nonnegative-integer?]
              [workers exact-nonnegative-integer?]
              [elapsed-milliseconds (and/c real? (>=/c 0))]
              [frame-milliseconds (listof (and/c real? (>=/c 0)))]
              [cache-hits exact-nonnegative-integer?]
              [cache-misses exact-nonnegative-integer?]
              [cache-evictions exact-nonnegative-integer?])] {

The report returned by @racket[render-frames/report!]. @racket[paths] and
@racket[frame-milliseconds] are both ordered by frame index, not completion
order. @racket[workers] is the active worker count, so a zero-frame render
reports zero workers. The elapsed and per-frame durations include sampling,
Pict/bitmap conversion, and PNG writing. Cache fields are performance telemetry
only; they never affect the sampled scene or output pixels.
}

@defproc[(encode-mp4! [frames-directory path-string?]
                      [output-file path-string?]
                      [#:fps fps exact-positive-integer? 30])
         path-string?]{

Runs the @tt{ffmpeg} executable found on @tt{PATH}. It reads
@filepath{frame-%06d.png} from @racket[frames-directory] and writes an H.264 MP4
file with @tt{yuv420p} pixel format. An existing output file is overwritten.

The input sequence should start at @filepath{frame-000000.png} and be
contiguous. @racket[render-frames!] produces the expected sequence.

The procedure returns @racket[output-file] after FFmpeg succeeds. It raises an
exception when FFmpeg is not found or the process fails.
}


@section[#:tag "errors"]{Errors and Validation}

Most public constructors and operations check their arguments and raise
contract exceptions for invalid input. Important checks include:

@itemlist[
 @item{World coordinates, rotations, times, dimensions, and path fractions must
       be finite.}
 @item{Path fractions must lie from zero through one, with start no greater
       than end.}
 @item{A non-full partial path needs a finite computed total length.}
 @item{Path interpolation progress must lie from zero through one.}
 @item{Strictly morphing paths must have corresponding subpath counts, closure
       values, segment counts, and segment kinds.}
 @item{Normalized morphing still requires equal subpath counts, corresponding
       closure values, and corresponding point-only or nonempty status.}
 @item{Limited normalization does not reverse traversal, rotate a closed
       starting point, reorder subpaths, change closure, or add drawn geometry
       to a point-only subpath.}
 @item{Shape dimensions, text font sizes, and scale factors must be positive.}
 @item{An arrow needs distinct finite endpoints. Tip length and tip width must
       be positive finite values; stroke width must be nonnegative.}
 @item{An axis range needs finite bounds with minimum less than maximum, a
       positive finite computed span, zero in the interval, and a positive
       finite tick step.}
 @item{Axes x and y lengths, resulting unit lengths, and tip dimensions must be
       positive finite values.
       Tick size and stroke width must be nonnegative, and tip flags must be
       Boolean.}
 @item{Arrow point-at progress must lie from zero through one. Axes coordinate
       inputs and inverse-conversion points must be finite.}
 @item{Function sampling requires an axes Visual, a procedure accepting one
       argument, a finite increasing x interval, an exact sample count of at
       least two, a Boolean clipping flag, either @racket[#f] or a nonnegative
       finite maximum jump, and a documented interpolation symbol.}
 @item{A sampled function result must be a real number or @racket[#f].
       Non-finite real results and @racket[#f] create gaps. Another result, or
       an exception from the procedure, is reported with the sample x value.}
 @item{A parameter range needs distinct finite endpoints whose ordered
       difference remains a nonzero finite real. Increasing and decreasing
       endpoint order are both valid.}
 @item{Parametric sampling requires an axes Visual, a procedure accepting one
       argument, a parameter range, an exact sample count of at least two, a
       Boolean clipping flag, an optional nonnegative finite maximum distance,
       and a documented interpolation symbol.}
 @item{A parametric sample must be one @racket[vec2] or @racket[#f]. Another
       result, an invalid result count, or an exception is reported with the
       corresponding parameter value.}
 @item{A data series must be a proper ordered list of @racket[vec2] values and
       @racket[#f] gaps. Its maximum-distance option must be @racket[#f] or a
       nonnegative finite real.}
 @item{Coordinate-curve interpolation must be @racket['linear] or
       @racket['smooth].}
 @item{Plain-text content must be a string without carriage returns or newline
       characters. An empty string is allowed.}
 @item{A text font face must be a string or @racket[#f]. Font family, style,
       weight, and horizontal and vertical alignments must use the documented
       symbols.}
 @item{Formula source and preamble must be strings. Formula mode and anchor
       alignment must use the documented symbols. Multiline and empty formula
       source are valid.}
 @item{Formula document-class and Preview options must be ordered lists of
       symbols or strings. The document-class options may select at most one
       distinct standard size among 10pt, 11pt, and 12pt.}
 @item{A formula-part name must be a symbol and must equal the identity of its
       formula Visual.}
 @item{Formula-part names must be unique within one formula assembly, and the
       assembly identity must differ from every local part name. A formula
       assembly's own scale must be uniform.}
 @item{A formula correspondence requires source and destination formula
       assemblies. Every match must name an existing part on both sides, and
       no source or destination name may be reused.}
 @item{@racket[transform-formula-parts] requires the correspondence source
       identity to name a present formula assembly. Its current ordered local
       names must equal the correspondence source names exactly.}
 @item{The correspondence destination parts must be valid under the current
       source assembly identity. In particular, no destination part may reuse
       that top-level identity.}
 @item{Rendering a nonempty formula can fail when @racketmodname[latex-pict],
       LaTeX, Poppler, a requested document class, or a requested LaTeX package
       is unavailable, or when the source is invalid LaTeX.}
 @item{Formula source and preamble are passed to an external TeX process. The
       library does not sandbox untrusted LaTeX input.}
 @item{A group accepts only affine children. Its own scale must be uniform.}
 @item{Every identity in a built-in group tree must be a symbol, must be unique
       within that tree, and must differ from the group identity. Custom affine
       Visuals are treated as leaves.}
 @item{A custom affine child used in a group must return an affine transform,
       keep its reference position consistent with the transform translation,
       preserve identity during transform replacement, and install the exact
       requested transform.}
 @item{Global opacity must be a finite real from zero through one.}
 @item{Stroke widths must be nonnegative.}
 @item{Path subpaths and segments must use supported semantic path values.}
 @item{Cubic segment controls and endpoints must be @racket[vec2] values.}
 @item{Polyline paths need at least two points; polygon paths need at least
       three; @racket[cubic-bezier-path] needs at least one cubic segment.}
 @item{A line Visual needs two distinct endpoints in one containing coordinate
       system.}
 @item{Empty path geometry has no bounds or center.}
 @item{Top-level Visual identities must be symbols and unique within a scene
       state. Each built-in group tree separately requires unique identities.
       A custom affine Visual is treated as one leaf.}
 @item{A @racket[create] or @racket[fade-in] identity must be absent before
       its play clip.}
 @item{Other animation targets must be present in the prepared clip start
       state.}
 @item{@racket[create] and @racket[uncreate] require built-in path Visuals
       with finite computed local lengths.}
 @item{@racket[morph-to] requires a present built-in path Visual and strictly
       compatible destination geometry.}
 @item{@racket[morph-to-normalized] requires a present built-in path Visual and
       a destination supported by limited normalization.}
 @item{@racket[morph-to-aligned] requires a present built-in path Visual and one
       positive finite closed source/destination loop for automatic
       correspondence before normalization.}
 @item{@racket[morph-to-open-aligned] requires a present built-in path Visual and
       one positive finite open source/destination subpath for automatic
       endpoint-direction correspondence before normalization.}
 @item{@racket[morph-to-open-compound-aligned] requires a present built-in path
       Visual, equal nonzero source/destination subpath counts, and positive
       finite open subpaths throughout before global pairing and normalization.}
 @item{@racket[morph-to-compound-aligned] requires a present built-in path Visual,
       equal nonzero source/destination subpath counts, and positive finite
       closed loops throughout before global pairing and normalization.}
 @item{Rotation and scale requests require an affine Visual. A built-in group
       accepts only a uniform scale endpoint.}
 @item{Opacity requests require a Visual implementing
       @racket[gen:opacity-visual]. Its opacity must satisfy @racket[opacity?].}
 @item{A custom @racket[visual-with-opacity] result must remain a Visual,
       preserve identity, implement the opacity protocol, and install the
       requested numeric opacity.}
 @item{Two simultaneous requests cannot change the same target component.
       Presence conflicts are checked as well as value-component conflicts.}
 @item{Camera pan centers and deltas must be @racket[vec2] values. Camera zoom
       targets and factors must be positive finite reals. A relative zoom must
       also produce a positive finite visible world width.}
 @item{One pan and one zoom may share a play clip. Two pan requests or two zoom
       requests in one clip are rejected as duplicate camera components.}
 @item{A renderer support result must be Boolean.}
 @item{A Pict renderer result must be a Pict.}
 @item{A layout box needs finite coordinates with left no greater than right
       and bottom no greater than top. Layout gaps must be finite and
       nonnegative.}
 @item{Layout operations require a valid camera, an ordered renderer list, and
       Visuals whose position updates preserve identity and install the exact
       requested @racket[vec2] position.}
 @item{Layout alignment symbols must be @racket['left], @racket['center], or
       @racket['right] horizontally and @racket['bottom], @racket['center], or
       @racket['top] vertically.}
 @item{Scene sample times and frame indices must be in range.}
]

Style values such as fill, stroke, and camera background are deliberately
opaque at the model boundary. A rendering adapter may reject them later.

@section[#:tag "determinism"]{Determinism and Immutability}

The built-in coordinate, path, transform, camera, Visual, arrow, axis-range,
axes, parameter-range, sampled-graph, parametric-curve, data-plot, plain-text,
formula, formula-part, formula-assembly, formula-correspondence, group,
layout-box, scene-state, visual animation request, camera-animation request, and
scene values are immutable.
Group child
order, formula part and match order, opacity interpolation, formula-part
transition planning, path interpolation, path length, partial extraction, and
morph normalization depend only on explicit model values and significant
stored order.

Cubic length approximation uses fixed tolerances, fixed midpoint subdivision,
and a fixed maximum depth. Morph normalization always converts lines with the
same one-third and two-thirds controls. It then splits the longest current
cubic at parameter one half. Equal approximate lengths are resolved by taking
the earliest segment in traversal order. The same numeric inputs therefore
produce the same normalized model values.

Plain-text content, font requests, color, alignment, and transforms are explicit
immutable values. Repeated text rendering is deterministic within one fixed
Racket, operating-system, font-installation, and rendering environment. Exact
font substitution, glyph metrics, hinting, and rasterized pixels can differ
between platforms or when installed fonts change. The semantic text value does
not hide that platform dependency.

Formula source, mode, size, preamble, ordered options, alignment, and
transforms are explicit immutable values. Repeated formula rendering is
deterministic only within one fixed Racket, @racketmodname[latex-pict], LaTeX,
Poppler, document-class, package, font, and rendering environment. Different
tool versions can change spacing, glyph outlines, metrics, or rasterized
pixels. The semantic formula value does not hide those external dependencies.

Formula assemblies keep an explicit local part order and perform no automatic
spacing or token matching. Formula correspondences keep an explicit ordered
one-to-one match list and perform no same-name inference. Unmatched-name queries
therefore depend only on the two stored part orders and the stored match list.

Formula-part transition layer order is fixed: unmatched source parts, explicit
matches, then unmatched destination parts. Temporary names are allocated from a
fixed prefix and deterministic numeric sequence while avoiding endpoint names.
A changed match always places its moving source layer before its moving
destination layer. The same current source assembly and correspondence therefore
produce the same sampled semantic part values.

Arrow endpoint order, midpoint anchoring, tip flags, and tip dimensions are
explicit immutable values. Axis bounds, tick steps, tick order, local interval
lengths, and coordinate conversion are likewise explicit. The same range and
step always produce the same ordered nonzero tick values. Coordinate conversion
uses only the stored transform and lengths; rotated inverse conversions may be
inexact because they use trigonometric operations.

Coordinate-curve sampling uses explicit closed domains, exact sample counts,
clipping flags, distance rules, and interpolation symbols. Function samples are
processed in increasing x order. Parametric samples follow the stored parameter
order, which may increase or decrease. Data samples follow their explicit list
order. Sampling procedures are called only during construction and are not
retained. The same deterministic procedures, point values, and options therefore
produce the same semantic path geometry; a procedure that depends on hidden
mutable state is outside that guarantee.

Linear interpolation stores accepted line segments directly. Smooth
interpolation uses fixed Catmull-Rom-to-cubic formulas, a fixed two-point rule,
and deterministic control clamping after clipping. The same accepted coordinate
runs therefore produce the same line or cubic model values.

Relative layout is deterministic when the selected camera, renderer list, and
Visual implementations are deterministic. It measures complete local Pict
extents, not hidden ink bounds, and computes all displacements from explicit
world-coordinate boxes. Different fonts, TeX installations, custom renderer
metrics, or camera-dependent renderers can produce different boxes. Use the
same rendering environment for layout and final output.

Sampling is deterministic when custom Visual methods, easing procedures, and
renderers are deterministic. Fade introduction and removal use explicit
structural endpoint rules; they do not depend on hidden clocks or renderer
state. The library cannot force a third-party Visual or renderer implementation
to be immutable or deterministic. Custom implementations should return fresh
values from update methods and should not depend on hidden mutable state.

Nested group transforms are resolved from explicit parent and child values in
significant tree order. The same renderer list is propagated recursively. The
library does not use a process-global Visual identity counter or a mutable
renderer registry. Renderer order, top-level drawing order, and group child
order are explicit values.

Every scene clip stores complete Visual and camera start states. Camera pan and
zoom are sampled only from those explicit values, clip progress, and easing.
Rendering with no camera override samples that timeline; rendering with an
override uses one explicit fixed camera. Neither mode depends on an earlier
rendered frame.

Filesystem output and FFmpeg invocation are isolated in procedures ending in
@litchar{!}.



@section[#:tag "number-lines-and-coordinate-decorations"]{
  Number Lines and Coordinate Decorations}

SCENE-T adds a semantic number-line Visual and constructors that derive grid
lines and upright numeric labels from an existing coordinate object. These
constructors produce immutable snapshots. Changing the source axes or number
line later does not update an already constructed grid or label list.

@defproc[(number-line [range axis-range?]
                      [#:id identifier symbol?]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale any/c 1]
                      [#:opacity opacity opacity? 1]
                      [#:length length positive-real? 10]
                      [#:stroke stroke string? "black"]
                      [#:stroke-width stroke-width
                       nonnegative-real? 2]
                      [#:tick-size tick-size
                       nonnegative-real? 1/5]
                      [#:tip-length tip-length
                       nonnegative-real? 2/5]
                      [#:tip-width tip-width
                       nonnegative-real? 3/10]
                      [#:start-tip? start-tip? boolean? #f]
                      [#:end-tip? end-tip? boolean? #f])
         number-line-visual?]{

Constructs a horizontal semantic number line. @racket[range] must contain zero.
The Visual's reference position is the point representing numeric zero, not
necessarily the geometric midpoint of the shaft. @racket[length] is the local
world-unit length of the complete interval.

The regular ticks come from @racket[axis-range-tick-values], with zero inserted
for the number-line representation. Stroke width is cosmetic. Tick and tip
sizes are semantic local geometry and therefore follow affine scale.
}

@defproc[(number-line-visual? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a number-line Visual.}

@defproc[(number-line-visual-range [visual number-line-visual?]) axis-range?]{
Returns the numeric range and regular tick step.}

@defproc[(number-line-visual-length [visual number-line-visual?])
         positive-real?]{
Returns the local shaft length for the complete numeric interval.}

@defproc[(number-line-visual-stroke [visual number-line-visual?]) string?]{
Returns the shaft, tick, and tip color name.}

@defproc[(number-line-visual-stroke-width [visual number-line-visual?])
         nonnegative-real?]{
Returns the cosmetic stroke width.}

@defproc[(number-line-visual-tick-size [visual number-line-visual?])
         nonnegative-real?]{
Returns the full local length of every regular tick.}

@defproc[(number-line-visual-tip-length [visual number-line-visual?])
         nonnegative-real?]{
Returns the local length of each enabled triangular tip.}

@defproc[(number-line-visual-tip-width [visual number-line-visual?])
         nonnegative-real?]{
Returns the full local width of each enabled triangular tip.}

@defproc[(number-line-visual-start-tip? [visual number-line-visual?])
         boolean?]{
Reports whether the minimum endpoint has a tip.}

@defproc[(number-line-visual-end-tip? [visual number-line-visual?])
         boolean?]{
Reports whether the maximum endpoint has a tip.}

@defproc[(number-line-unit-length [visual number-line-visual?])
         positive-real?]{
Returns the local world-unit distance representing one numeric unit.}

@defproc[(number-line-tick-values
          [visual number-line-visual?]
          [#:include-zero? include-zero? boolean? #t])
         (listof finite-real?)]{
Returns regular tick values in increasing numeric order. Zero is included by
default and can be omitted explicitly.}

@defproc[(number-line-number->point
          [visual number-line-visual?]
          [number finite-real?])
         vec2?]{
Maps @racket[number] to the containing coordinate system. The result includes
the number line's complete translation, rotation, and scale. Values outside the
visible range are extrapolated.}

@defproc[(number-line-point->number
          [visual number-line-visual?]
          [point vec2?])
         real?]{
Projects @racket[point] onto the transformed number line and returns the
corresponding numeric value. A point need not lie exactly on the line.}

@defproc[(number-line-visual-start [visual number-line-visual?]) vec2?]{
Returns the transformed point at the numeric minimum.}

@defproc[(number-line-visual-end [visual number-line-visual?]) vec2?]{
Returns the transformed point at the numeric maximum.}

@defproc[(axes-grid-lines
          [axes axes-visual?]
          [#:id identifier symbol?]
          [#:x-grid? x-grid? boolean? #t]
          [#:y-grid? y-grid? boolean? #t]
          [#:include-zero? include-zero? boolean? #f]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke string? "lightgray"]
          [#:stroke-width stroke-width nonnegative-real? 1])
         path-visual?]{
Constructs an ordinary path Visual containing vertical grid lines at x ticks
and horizontal grid lines at y ticks. X lines precede y lines in traversal
order. Zero is omitted by default because the axes already draw the coordinate
axes there. The returned path copies the current axes transform.}

@defproc[(axes-number-labels
          [axes axes-visual?]
          [#:id-prefix identifier-prefix symbol?]
          [#:include-zero? include-zero? boolean? #f]
          [#:font-size font-size positive-real? 3/10]
          [#:color color string? "black"]
          [#:x-gap x-gap nonnegative-real? 1/10]
          [#:y-gap y-gap nonnegative-real? 1/10]
          [#:number->string number->string procedure?
           number->string])
         (listof text-visual?)]{
Constructs upright plain-text labels at the current tick positions. X labels
come first in increasing value order, followed by y labels. When zero is
included, it appears once among the x labels; it is not duplicated on the y
axis. The x gap and y gap are semantic distances from the corresponding tick
extent to the label anchor.

The formatter is called once per label with the numeric value. It must accept
one argument and return exactly one string. It is not retained in the returned
Visuals. Child identities have the forms
@tt{prefix-x-index} and @tt{prefix-y-index}, where each index starts at zero.
}

@defproc[(number-line-number-labels
          [number-line number-line-visual?]
          [#:id-prefix identifier-prefix symbol?]
          [#:include-zero? include-zero? boolean? #t]
          [#:font-size font-size positive-real? 3/10]
          [#:color color string? "black"]
          [#:gap gap nonnegative-real? 1/10]
          [#:number->string number->string procedure?
           number->string])
         (listof text-visual?)]{
Constructs upright plain-text labels below the current number-line ticks.
Values and result order are those of @racket[number-line-tick-values]. Child
identities have the form @tt{prefix-number-index}. The formatter contract is the
same as for @racket[axes-number-labels].
}

Number-line rendering is implemented by converting the model to ordinary
semantic path geometry after explicit renderer selection. A custom renderer can
therefore override the complete number line. Semantic opacity is applied once
after either custom rendering or fallback conversion. Grid lines use the normal
path renderer, while labels use the normal plain-text renderer.


@section[#:tag "animated-camera"]{Animated Camera Views}

Every scene and timeline clip stores one immutable camera. The camera can be
sampled independently from the Visual state, and both tracks are rendered at
the same absolute time.

A scene may begin with an explicit camera:

@racketblock[
(define initial-camera
  (make-camera #:world-width 14
               #:center origin))

(define scene
  (make-scene #:camera initial-camera))
]

Camera and Visual requests can share one play clip:

@racketblock[
(scene-play scene
            (move-to 'marker (vec2 3 1))
            (camera-pan-to (vec2 2 1))
            (camera-zoom-by 2)
            #:duration 2)
]

The camera center and visible world width are independent components. Pan and
follow requests change the center. Zoom requests change visible width. A fit
request changes both components. Requests for disjoint components may run
together; requests that reserve the same component raise an exception.
Relative pan and zoom requests compile from the camera at the beginning of the
clip.

@racket[camera-zoom-by] uses magnification rather than a width multiplier. A
factor of two divides the visible world width by two and zooms in. A factor of
one half doubles the visible width and zooms out. Visible world width is
interpolated linearly between the clip-start and target widths.

@racket[scene-camera-at] samples arbitrary times using the same half-open clip
selection and closed total-duration interval as @racket[scene-sample]. A wait
clip holds both state and camera. @racket[scene-set-camera] replaces only the
current endpoint camera and appends no clip.

@racket[scene->pict], @racket[scene-frame->bitmap], and
@racket[render-frames!] use the sampled scene camera when their
@racket[#:camera] argument is @racket[#f]. Supplying a camera is a deliberate
static override and ignores every camera request for that render.

The camera's pixel dimensions, aspect ratio, and background stay fixed while
its center or visible width changes. Renderer-aware layout continues to accept
a static camera value. To measure for one sampled view, pass
@racket[(scene-camera-at scene time)] explicitly. Layout does not reflow
automatically on every frame.

This version does not animate camera rotation, pixel dimensions, or background
style.

Render the SCENE-U pan-and-zoom example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-pan-and-zoom.rkt \
  frames/camera-pan-and-zoom \
  camera-pan-and-zoom.mp4

open camera-pan-and-zoom.mp4
}


@section[#:tag "camera-framing-following"]{
  Automatic Camera Framing and Following}

SCENE-W adds renderer-aware fit requests and clip-local following. Both are
ordinary camera requests accepted by @racket[scene-play].

@subsection{Fitting a Rendered Box}

A fit request can be built from a world-coordinate layout box:

@racketblock[
(define fit-request
  (camera-fit-layout-box box
                         #:camera (scene-current-camera scene)
                         #:padding 1/2))

(scene-play scene fit-request #:duration 1)
]

The target center is the center of @racket[box]. Padding is added equally on all
four sides in world units. The target visible width is then enlarged when
needed so the padded height fits the camera's pixel aspect ratio. Pixel width,
pixel height, and background are preserved.

The @racket[#:camera] value supplies the aspect ratio used to compute the fit.
Use the same camera, or at least the same pixel aspect ratio, as the scene in
which the request will run. A fit request stores only the resulting center and
visible width. It does not retain the box or recompute it later.

@subsection{Fitting Visuals and Scene Targets}

Fit a nonempty list of Visuals with the renderer list used for final output:

@racketblock[
(camera-fit-visuals (list diagram title)
                    #:camera (scene-current-camera scene)
                    #:renderers default-pict-renderers
                    #:padding 1/2)
]

This operation measures complete renderer boxes, not tight visible-ink bounds.
Transparent padding, semantic anchors, group extents, cosmetic stroke padding,
and custom-renderer padding can therefore affect the result. Measuring a
nonempty formula with the built-in formula renderer can invoke LaTeX and
Poppler. The Visuals must use one containing coordinate system.

The current scene can be fitted directly:

@racketblock[
(camera-fit-scene scene #:padding 1/2)

(camera-fit-scene scene
                  #:targets (list 'marker 'label)
                  #:padding 1)
]

With no @racket[#:targets], every current top-level world-space Visual is
included and frame-space overlays are ignored. Otherwise, each Visual value or
symbol is resolved by stable identity against @racket[(scene-current-state
scene)]. An explicit nested @racket[visual-path?] is also accepted and measured
after every enclosing transform/opacity is composed. An empty world scene, empty
target list, missing target, or explicitly selected frame-space target raises an
exception. For a focused explanation, @racket[camera-focus] names one nested or
top-level subject and its chosen context directly.

Both operations are snapshots. Geometry, transforms, text metrics, renderer
results, or scene membership changed later in the same play clip are not
remeasured. To fit a planned endpoint, construct and measure Visual values that
already describe that endpoint.

A fit request changes center and visible world width together. It conflicts
with pan, zoom, follow, or another fit request in the same clip. It may run with
any disjoint Visual animation.

@subsection{Following a Moving Visual}

Follow one top-level Visual while it moves:

@racketblock[
(scene-play scene
            (move-to marker destination)
            (camera-follow marker)
            (camera-zoom-by 2)
            #:duration 2)
]

At clip compilation, the request records the target's prepared start position
and normalized horizontal and vertical frame offset. At each sample it reads the
target's actual sampled @racket[visual-position] at the same eased progress as
the Visual motion. The camera center is chosen so that sampled reference
position remains at the same pixel coordinates. When zoom runs simultaneously,
the world-space offset shrinks or grows with the sampled visible width and
height. This sampled-state rule lets following trace @racket[move-along-path]
through a polyline elbow or Bézier curve instead of interpolating only between
the target's clip endpoints.

Following tracks @racket[visual-position], not a rendered bounding box. It is
clip-local and does not install a persistent observer. Clips without a follow
request keep the ordinary camera-only sampling path; scene-state sampling is
needed only when following depends on it. Repeat @racket[camera-follow] in each
later clip that should continue tracking.

The target must be a top-level world-space Visual in the prepared clip state;
frame-space overlays cannot be camera-follow targets. It may be introduced by
@racket[fade-in] or @racket[create] in the same clip. It may also be followed
through @racket[fade-out] or @racket[uncreate], because the pre-removal sampled
motion state is retained for camera completion before the structural endpoint is
stored.

A follow request changes only the center component. It may run with one zoom
request, but it conflicts with pan, fit, or another follow request. Follow and
fit endpoints obey the easing result; neither has a structural endpoint
override.

Render the canonical SCENE-W example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/camera-framing-and-following.rkt \
  frames/camera-framing-and-following \
  camera-framing-and-following.mp4

open camera-framing-and-following.mp4
}



@section[#:tag "unified-style-animation"]{Unified Style Transitions}

SCENE-AU adds @racket[style-to] as compact composition syntax for the style
components established by SCENE-AS and SCENE-AT.

@racketblock[
(scene-play
 scene
 (animation-group
  (move-to 'shape (vec2 4 0))
  (style-to 'shape
            #:fill "cornflowerblue"
            #:stroke "navy"
            #:stroke-width 8
            #:opacity 3/4))
 #:duration 3)
]

Only supplied properties participate. Internally the unified transition expands
to the ordinary fill-color, stroke-color, stroke-width, and opacity leaves, so
their independent scheduler components remain visible to overlap validation.
There is no style-specific compiled animation, sampler, or renderer branch.

The keywords default to @racket[#f], which means omitted. At least one property
must be supplied. In particular, @racket[#f] does not become a destination for
fill/stroke paint; missing paint remains outside color interpolation.

A @racket[style-to] is one direct parent-timing child, then its selected style
leaves run in parallel in that child's assigned interval. It therefore composes
with @racket[timed], @racket[succession], @racket[animation-group], and
@racket[lagged-start] without introducing new timing rules.

Render the canonical SCENE-AU example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/unified-style-transitions.rkt \
  frames/unified-style-transitions \
  unified-style-transitions.mp4

open unified-style-transitions.mp4
}


@section[#:tag "color-animation"]{Fill and Stroke Color Animation}

SCENE-AT extends semantic style animation with independent fill and stroke color
components. Existing color strings remain exact style values. During an interior
sample the animation engine resolves source and destination specifications to
renderer-independent @racket[rgba-color] values and interpolates their sRGB and
alpha components.

@racketblock[
(scene-play
 scene
 (animation-group
  (move-to 'disk (vec2 4 0))
  (fill-color-to 'disk "tomato")
  (stroke-color-to 'disk "darkred")
  (stroke-width-to 'disk 10))
 #:duration 3)
]

The four requests above are mutually compatible because they own different
animation components. Same-target overlap conflicts are checked independently
for fill color and stroke color after AN--AR composition expansion. Touching
sequential changes compile from the exact prior color specification.

The semantic layer does not import @racketmodname[racket/draw]. The built-in Pict
adapter converts @racket[rgba-color] values to drawing colors only immediately
before rendering. This preserves deterministic arbitrary-time sampling and keeps
third-party semantic Visuals independent of a particular renderer.

A current @racket[#f] fill or stroke means paint is absent rather than a color;
SCENE-AT deliberately does not turn paint presence into an interpolated style
component. Use an actual color such as @tt{transparent} when alpha interpolation
is desired while retaining a color endpoint. Scatter-plot marker children remain
nested inside their group and are not individually targetable, and callout
connector paint remains separate frame-space style. Custom color setters are
validated for exact endpoint installation, including exact/inexact channel
representation inside @racket[rgba-color].

Render the canonical SCENE-AT example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/animating-colors.rkt \
  frames/animating-colors \
  animating-colors.mp4

open animating-colors.mp4
}

@section[#:tag "stroke-width-animation"]{Stroke-Width Animation}

SCENE-AS begins the style-animation track with one renderer-independent semantic
component. Built-in stroke-bearing Visuals implement
@racket[gen:stroke-width-visual], and @racket[stroke-width-to] animates the
component through the same request compiler and schedule tree used by movement,
opacity, path morphing, and AN--AR composition.

@racketblock[
(scene-play
 scene
 (animation-group
  (move-to 'ring (vec2 4 0))
  (stroke-width-to 'ring 12))
 #:duration 3)
]

The two requests above are compatible because translation and stroke width are
different animation components. Two overlapping same-target
@racket[stroke-width-to] leaves conflict; touching leaves are legal and compile
the later transition from the exact semantic state at their shared boundary.

The built-in circle, rectangle, path, arrow, axes, number-line, and point-marker
Visuals implement the protocol. Plot curves and filled areas that are path Visuals
therefore inherit the capability from their ordinary semantic representation. A
@racket[scatter-plot] is different: it returns a group, and its nested marker
children are not independent scene-state animation targets. The scatter group
therefore cannot be passed to @racket[stroke-width-to]. Callout connector width is
also intentionally separate from the Visual stroke-width component.

Stroke width may be zero and remains ordinary semantic style data. It does not
remove a Visual or disable its stroke style value. Numeric interpolation follows
the leaf easing. When the eased endpoint is one, the exact requested width is
installed even when the source width or scheduling arithmetic is inexact. The
default Pict/racket/draw backend renders width zero as a device-dependent hairline
and accepts pen widths only through 255 pixels; the semantic protocol remains
open to larger values for other renderers.

The protocol also provides an extension point for third-party Visuals. Scene
compilation validates a custom getter and setter before timeline sampling: the
getter must produce a value accepted by @racket[stroke-width?], the setter must
return a Visual that still implements the protocol, Visual identity must be
preserved, and the requested endpoint must be installed exactly, including its
exact/inexact numeric representation.

No renderer-specific animation path is introduced. Existing built-in renderers
already read the sampled Visual's stored width. This keeps arbitrary-time scene
sampling and deterministic frame rendering unchanged.

Render the canonical SCENE-AS example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/animating-stroke-width.rkt \
  frames/animating-stroke-width \
  animating-stroke-width.mp4

open animating-stroke-width.mp4
}

@section[#:tag "duration-scaled-animation-composition"]{Duration-Scaled Visual Animation Composition}

SCENE-AR makes @racket[timed] compositional. A timed wrapper may now appear as a
direct child of @racket[succession], @racket[animation-group], or
@racket[lagged-start], and it may wrap any one of those composition values in
addition to an ordinary Visual animation request.

Inside a composition, every unwrapped direct child contributes one intrinsic
timing unit. A timed direct child contributes @racket[(+ start duration)] units.
The parent maps those intrinsic spans into the concrete interval assigned by its
own parent or by @racket[scene-play]. This keeps every AO--AQ tree unchanged when
no nested timing is present.

For a succession, direct spans are consecutive. The following spans are one,
two, and one:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'a (vec2 4 2))
  (timed (move-to 'b (vec2 4 0)) #:duration 2)
  (move-to 'c (vec2 4 -2)))
 #:duration 8)
]

The concrete child durations are therefore two, four, and two seconds. A timed
child's @racket[start] is part of its intrinsic span: for example
@racket[(timed request #:start 1 #:duration 1)] has span two. If that child is
allocated four seconds, it contributes two seconds of delay followed by two
seconds of active animation.

For an animation group, all direct children start at the group start and their
spans are scaled against the longest direct span. Thus in a four-second group a
plain one-unit child beside @racket[(timed request #:duration 2)] runs for two
seconds while the timed two-unit child runs for all four seconds; the shorter
child then holds its endpoint.

For a lagged start, let a direct child's intrinsic span be @italic{s}. The first
raw start is zero, and each following raw start is the previous raw start plus
@italic{r} times the previous child's span, where @italic{r} is the lag ratio.
The complete raw envelope is then scaled to the assigned concrete duration. With
all spans equal to one this is exactly the SCENE-AQ schedule. With unequal spans,
lag ratio zero still equals duration-scaled parallel timing, while lag ratio one
still equals duration-scaled succession timing.

A bare nested composition remains one direct parent-level unit regardless of
its internal child count. This preserves the earlier rule that a nested
composition is one child. Wrap the nested composition itself with @racket[timed]
when it should reserve an explicit larger, smaller, or delayed parent-level span:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'a origin)
  (timed
   (succession
    (rotate-by 'b 1)
    (scale-by 'b 2))
   #:duration 2)
  (fade-to 'c 0))
 #:duration 8)
]

The outer direct spans are one, two, and one, so the timed nested succession
receives four seconds and divides those four seconds according to its own direct
children.

At top level, @racket[timed] retains its original literal-second meaning. It may
now wrap a whole composition:

@racketblock[
(scene-play
 scene
 (timed
  (succession
   (move-to 'dot (vec2 4 0))
   (rotate-by 'dot 2))
  #:start 1
  #:duration 4)
 #:duration 6)
]

The wrapped succession is inactive before local second one, fills seconds one
through five, and then holds its exact semantic endpoint through second six. A
@racket[#:easing] supplied by the timed composite becomes the inherited easing
for its descendant leaves. A nested timed child may override that easing; timing
allocation itself is never eased.

AR does not add a new clip or sampling engine. All timing trees still expand to
SCENE-AN scheduled Visual leaves before conflict and structural-removal
validation, then compile against exact local boundary states. Exact endpoint
sampling, same-component overlap rules, structural event ordering,
@racket[camera-follow], and arbitrary-time reconstruction therefore continue to
use the existing scheduler.

Camera requests remain top-level/full-clip in SCENE-AR, and @racket[timed] does
not wrap another timed wrapper.

Render the canonical SCENE-AR example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/duration-scaled-compositions.rkt \
  frames/duration-scaled-compositions \
  duration-scaled-compositions.mp4

open duration-scaled-compositions.mp4
}

@section[#:tag "lagged-animation-composition"]{Lagged Visual Animation Composition}

SCENE-AQ adds staggered composition through @racket[lagged-start]. For an
assigned interval of duration @italic{D}, @italic{n} direct children, and lag
ratio @italic{r}, each child receives
@racket[(/ D (+ 1 (* (sub1 n) r)))], and consecutive starts are separated by
@italic{r} child durations. For example:

@racketblock[
(scene-play
 scene
 (lagged-start
  (move-to 'a (vec2 4 2))
  (move-to 'b (vec2 4 0))
  (move-to 'c (vec2 4 -2))
  #:lag-ratio 1/2)
 #:duration 4)
]

The three children last two seconds each and start at local seconds zero, one,
and two. The first two overlap from one through two; the last two overlap from
two through three. The final child ends exactly at local second four.

The ratio connects the earlier composition forms cleanly. A zero lag ratio gives
every child the complete interval, matching @racket[animation-group] timing. A
unit lag ratio gives equal touching intervals, matching @racket[succession]
timing. Ratios greater than one insert gaps while preserving the assigned outer
duration. The default ratio is @racket[1/4].

Lagged starts may contain successions, animation groups, or nested lagged starts,
and those composition forms may contain lagged starts in return. Every direct
child receives one computed lagged interval; the child then recursively expands
inside that interval according to its own rule. No lag-specific clip or renderer
exists. The final leaves are the same scheduled requests used by SCENE-AN through
SCENE-AP.

Because validation runs after expansion, overlapping same-component leaves are
rejected according to their concrete intervals. A unit lag ratio therefore makes
touching relative requests legal, while a half lag ratio for two moves of the
same Visual is a conflict. Different components and different targets may overlap
normally. Structural introduction/removal and @racket[camera-follow] likewise
consume the expanded staggered schedule directly.

SCENE-AQ originally kept timed wrappers and camera requests outside nested
compositions. SCENE-AR now permits timed Visual/composition children while camera
requests remain top-level/full-clip.

Render the canonical SCENE-AQ example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/lagged-start-animations.rkt \
  frames/lagged-start-animations \
  lagged-start-animations.mp4

open lagged-start-animations.mp4
}

@section[#:tag "parallel-animation-composition"]{Parallel Visual Animation Composition}

SCENE-AP adds first-class parallel composition through @racket[animation-group].
A group occupies the interval assigned by its enclosing @racket[scene-play] or
parent composition, and every direct child receives that same interval:

@racketblock[
(scene-play
 scene
 (animation-group
  (move-to 'card origin)
  (rotate-by 'card 1)
  (fade-to 'label 0))
 #:duration 3)
]

All three children run from local second zero through three. Ordinary leaves see
normalized progress from zero to one across that common interval, with the
enclosing easing applied independently to each leaf. Existing component rules
apply after expansion, so the move and rotation may target one Visual while two
parallel movement requests for that identity remain a conflict.

Parallel groups and successions can nest in either direction. A group can occupy
one child slice of a succession:

@racketblock[
(scene-play
 scene
 (succession
  (animation-group
   (move-to 'card origin)
   (rotate-by 'card 1))
  (animation-group
   (scale-by 'card 2)
   (fade-to 'label 0)))
 #:duration 4)
]

Each group receives two seconds; every leaf inside that group receives the same
two seconds. Conversely, a succession inside an animation group receives the
group's complete interval and subdivides that interval among its own children:

@racketblock[
(scene-play
 scene
 (animation-group
  (succession
   (move-to 'a origin)
   (rotate-by 'a 1))
  (succession
   (move-to 'b origin)
   (scale-by 'b 2)))
 #:duration 4)
]

Both successions run in parallel for four seconds, while each branch performs
its own two-second children sequentially. Nested groups simply reuse their
assigned interval recursively.

The implementation does not introduce a group-specific clip or sampling path.
Composition trees expand to the SCENE-AN scheduled Visual-leaf representation.
Equal-start leaves are compiled together against one exact prepared state; later
starts compile against exact semantic boundary states. SCENE-AN structural event
ordering, AO sequence boundaries, overlap validation, easing, and direct
arbitrary-time sampling therefore compose without frame-by-frame accumulation.

Camera requests remain top-level and full-clip. @racket[camera-follow] samples
the actual Visual motion produced by the mixed composition tree. SCENE-AP/AQ
originally kept @racket[timed] outside nested compositions; SCENE-AR now permits
timed Visual/composition children while cameras remain top-level.

Render the canonical SCENE-AP example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/parallel-animation-groups.rkt \
  frames/parallel-animation-groups \
  parallel-animation-groups.mp4

open parallel-animation-groups.mp4
}

@section[#:tag "successive-animation-composition"]{Successive Visual Animation Composition}

SCENE-AO adds first-class sequential composition through @racket[succession]. A
succession occupies the interval assigned by its enclosing @racket[scene-play],
then divides that interval equally among its direct children:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'card origin)
  (rotate-by 'card 1)
  (scale-by 'card 2))
 #:duration 3)
]

The move runs during local seconds zero through one, the rotation during one
through two, and the scale during two through three. Each leaf sees normalized
progress from zero to one inside its own interval, and the enclosing easing is
applied independently to each leaf.

Compilation occurs at the same semantic event boundaries introduced for
@racket[timed]. The rotation above is compiled from the exact state after the
move, and the scale is compiled from the exact state after rotation. This also
makes repeated relative requests deterministic:

@racketblock[
(scene-play
 scene
 (succession
  (rotate-by 'marker 1)
  (rotate-by 'marker 1))
 #:duration 2)
]

The final rotation is exactly two radians relative to the clip-start value,
because the second @racket[rotate-by] starts from the first child's exact
endpoint rather than recompiling from clip start.

Nested successions receive one direct-child share and recursively subdivide it:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'marker origin)
  (succession
   (rotate-by 'marker 1)
   (scale-by 'marker 2)))
 #:duration 4)
]

The move receives the first two seconds. The nested succession receives the
second two seconds and assigns one second to each of its children.

Top-level ordinary Visual requests still span the complete enclosing clip, and
top-level @racket[timed] leaves keep their explicit intervals. Conflict checking
runs after succession expansion, so a full-clip sibling that changes the same
component as a succession leaf conflicts only because their concrete intervals
overlap. Different components and different targets compose normally.

SCENE-AN structural semantics also apply unchanged. A @racket[fade-in] or
@racket[create] child may introduce a target for a later child, while an exact
boundary may remove and reintroduce the same identity deterministically. Camera
requests remain full-clip; @racket[camera-follow] samples the actual target state
through every succession child.

SCENE-AO intentionally gave unwrapped direct children equal shares. SCENE-AP
added @racket[animation-group], SCENE-AQ added @racket[lagged-start], and SCENE-AR
adds timed Visual/composition children while preserving one-unit shares for every
unwrapped direct child. Camera requests remain invalid composition children.

@section[#:tag "local-animation-timing"]{Local Visual Animation Timing}

SCENE-AN begins the animation-composition track without changing the immutable
scene model. @racket[timed] attaches a local interval to one existing Visual
animation request:

@racketblock[
(scene-play
 scene
 (timed (move-to 'a (vec2 4 1))
        #:start 0
        #:duration 2)
 (timed (move-to 'b (vec2 4 -1))
        #:start 1
        #:duration 2)
 #:duration 3)
]

Local times are seconds from the enclosing clip start. A leaf has no effect
before its start, uses its own normalized progress while active, and holds its
compiled endpoint afterward. Omitting local easing inherits the enclosing
@racket[scene-play] easing.

Compilation is performed at semantic event boundaries. Requests with the same
start share one prepared state, preserving @racket[fade-in] and @racket[create]
placeholder semantics. Later requests compile against the exact state at their
local start, which makes touching relative requests deterministic:

@racketblock[
(scene-play
 scene
 (timed (rotate-by 'marker 1) #:start 0 #:duration 1)
 (timed (rotate-by 'marker 1) #:start 1 #:duration 1)
 #:duration 2)
]

The second rotation is compiled from the first rotation's boundary state. Two
requests that change the same target component may touch at an endpoint but may
not overlap with positive duration. Different components may overlap.

Structural endpoint ordering is explicit. At one event time, previously active
component values are sampled first, then completed removals/introductions are
resolved, then same-time new requests begin. This permits deterministic same-ID
reintroduction and prevents request-order-dependent failures when, for example,
movement and @racket[fade-out] end together.

Camera requests remain full-clip requests. In particular,
@racket[camera-follow] receives the actual locally timed sampled Visual state,
so it holds during a delayed target start and follows only when that target
moves. SCENE-AR extends the same scheduler with timed Visual/composition children
and composite duration scaling; timed camera requests remain a later stage.

@section[#:tag "per-pair-topology-match-penalties"]{Per-Pair Real-Match Penalties}

SCENE-AM adds sparse, deterministic semantic costs to individual real assignment
edges while retaining the existing geometric correspondence score:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:match-penalty-map
             (hash (cons 0 0) 20
                   (cons 1 1) 5))
            #:duration 3)
]

Each key is @racket[(cons source-index destination-index)] in the original caller
subpath order. The value is a finite nonnegative additive cost. Missing pairs add
zero. Topology partitioning, global assignment, destination reordering, open-path
reversal, and closed-loop phase selection never renumber the indexes.

The map affects real source/destination edges only. In forced mode it can change
which same-topology real subpaths pair without enabling optional birth/death. In
numeric SCENE-AJ mode the increased real-edge score also competes with the
resolved SCENE-AL death and birth costs. Exact primary-cost ties retain AJ's
secondary preference for fewer topology changes.

Direct geometry preparation rejects out-of-range and open-to-closed keys. Timeline
requests validate key shape/value at construction, snapshot the hash immutably,
and validate range/topology at clip compilation. AK anchor maps and AL endpoint
penalty maps remain independent.

Render the canonical comparison with:

@verbatim{
racket examples/per-pair-match-penalties.rkt \
  frames/per-pair-match-penalties \
  per-pair-match-penalties.mp4

open per-pair-match-penalties.mp4
}

The upper panel uses geometry alone and both curves visibly morph locally. The
lower panel penalizes original pair @racket[(cons 0 0)], so the global assignment
swaps the two real destination identities and the curves cross.


@section[#:tag "per-subpath-topology-morph-penalties"]{Per-Subpath Birth/Death Penalties}

SCENE-AL keeps SCENE-AJ's shared numeric costs as fallbacks and adds sparse
original-index overrides:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-penalty 2
             #:death-penalty 2
             #:birth-penalty-map (hash 1 20)
             #:death-penalty-map (hash 0 20))
            #:duration 3)
]

@racket[birth-penalty-map] keys address the caller destination's original
subpath indexes. @racket[death-penalty-map] keys address the clip-start source's
original subpath indexes. Topology partitioning, global assignment, destination
reordering, open-path reversal, and closed-loop phase selection do not renumber
these keys.

Every map value is a finite nonnegative real cost. A missing key inherits the
corresponding shared @racket[birth-penalty] or @racket[death-penalty]. Sparse
values change only source-to-dummy death costs and dummy-to-destination birth
costs in SCENE-AJ's augmented assignment. Real-pair geometric scores and the
lexicographic exact-tie preference for fewer topology changes are unchanged.

Nonempty maps require numeric shared penalty mode; they are rejected when both
shared penalties are @racket['forced]. Anchor policy remains independent:
SCENE-AI/AK still decides where any unmatched subpath selected by the cost policy
collapses or grows. Timeline requests copy penalty maps into immutable hashes so
later mutation of caller hashes has no effect. Direct preparation validates map
ranges immediately; request compilation validates them against the clip-start
source and stored destination.

Render the canonical comparison with:

@verbatim{
racket examples/per-subpath-topology-penalties.rkt \
  frames/per-subpath-topology-penalties \
  per-subpath-topology-penalties.mp4

open per-subpath-topology-penalties.mp4
}

The upper panel uses shared low costs and replaces both distant pairs. The lower
panel raises the death cost of original source index 0 and the birth cost of
original destination index 1; that upper pair remains a real morph while the
lower pair still collapses and regrows.


@section[#:tag "per-subpath-topology-morph-anchors"]{Per-Subpath Birth/Death Anchors}

SCENE-AK keeps SCENE-AI's shared anchors as fallbacks and adds sparse overrides
for individual endpoint subpaths:

@racketblock[
(define left-hub (vec2 -5 -1))
(define right-hub (vec2 5 -1))

(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-anchor origin
             #:death-anchor origin
             #:birth-anchor-map (hash 1 left-hub 2 right-hub)
             #:death-anchor-map (hash 1 left-hub 2 right-hub))
            #:duration 3)
]

A birth-map key names the exact original subpath index in the caller's
@racket[destination]. A death-map key names the exact original subpath index in
the clip-start source path. Topology partitioning, global assignment, source-order
reconstruction, destination reversal, and closed-loop phase alignment do not
change those key meanings.

Each map value is either @racket['bounds-center] or a finite local @racket[vec2].
If a key is absent, the corresponding shared @racket[birth-anchor] or
@racket[death-anchor] is used. An explicit @racket['bounds-center] entry therefore
lets one subpath use its own center even when the shared fallback is a custom hub.
Matched real subpaths ignore anchor maps.

The same lookup applies to voluntary unmatched slots selected by SCENE-AJ
numeric penalties. Anchor maps never alter real-pair costs or assignment policy.
Timeline requests copy the maps into immutable hashes when the request is
constructed, so later mutation of the caller's input hash has no effect. Direct
geometry preparation validates key ranges immediately; request compilation checks
them against the clip-start source and stored destination.

Render the canonical example with:

@verbatim{
racket examples/per-subpath-topology-anchors.rkt \
  frames/per-subpath-topology-anchors \
  per-subpath-topology-anchors.mp4

open per-subpath-topology-anchors.mp4
}

The two lower source paths collapse into separate marked hubs while two new
closed loops grow from those corresponding hubs. A surviving upper curve morphs
at the same time.


@section[#:tag "penalized-topology-morph-correspondence"]{Penalized Topology-Changing Correspondence}

SCENE-AJ makes forced real correspondence optional when the caller supplies an
explicit cost for both sides of a replacement. The default remains unchanged:

@racketblock[
(path-geometry-prepare-topology-changing-morph
 source destination
 #:birth-penalty 'forced
 #:death-penalty 'forced)
]

To let the global matcher reject a poor source/destination pair, provide finite
nonnegative local path-unit costs:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-penalty 2
             #:death-penalty 2)
            #:duration 3)
]

A real edge keeps the existing SCENE-AC/AE geometric correspondence score. A
death costs @racket[death-penalty], and a birth costs @racket[birth-penalty].
The assignment is solved globally within each open/closed topology class. Thus a
good nearby pair can remain matched while a distant pair is represented by one
local collapse and one local regrowth. This is not a greedy threshold applied
independently to each candidate.

SCENE-AJ minimizes two objectives lexicographically. First it minimizes total
geometric/penalty cost. If that primary cost ties exactly, it minimizes the total
number of birth/death edges. A real correspondence whose score equals death plus
birth cost is therefore retained. Remaining exact ties use the same deterministic
index ordering as the existing assignment machinery.

Both penalty keywords must use one mode: either both are the exact symbol
@racket['forced], or both are finite nonnegative real numbers. Anchor selection is
independent. Every unmatched slot---whether forced by a count difference or
selected voluntarily by numeric penalties---uses the SCENE-AI birth/death anchor
policy. Synthetic slots remain interior correspondence only; exact source and
caller destination representations are preserved at the clip endpoints.

Render the canonical comparison with:

@verbatim{
racket examples/penalized-topology-changing-morphs.rkt \
  frames/penalized-topology-changing-morphs \
  penalized-topology-changing-morphs.mp4

open penalized-topology-changing-morphs.mp4
}

The upper path uses forced correspondence and sweeps between distant locations.
The lower path uses numeric penalties and instead collapses locally on the left
while its destination grows locally on the right.


@section[#:tag "explicit-topology-morph-anchors"]{Explicit Birth/Death Anchors}

SCENE-AI makes SCENE-AH seed placement configurable while leaving correspondence
policy unchanged. Bounds-center behavior remains the default. To use one local
hub for both sides:

@racketblock[
(define hub (vec2 0 0))

(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-anchor hub
             #:death-anchor hub)
            #:duration 3)
]

An explicit anchor is a point in the path Visual's local coordinate system. The
Visual's translation, rotation, and scale apply afterward. The anchor is used
only for unmatched subpaths; matched real correspondence remains governed by
SCENE-AC/AE scoring and the existing topology-class assignments.

The only symbolic value accepted by either keyword is @racket['bounds-center].
SCENE-AI uses one shared point per side. SCENE-AJ may create additional
voluntary unmatched slots through numeric penalties. SCENE-AK adds sparse
per-subpath overrides for those same seed positions. SCENE-AL independently adds
sparse numeric cost overrides for deciding which subpaths become unmatched.

Render the canonical example with:

@verbatim{
racket examples/anchored-topology-changing-morphs.rkt \
  frames/anchored-topology-changing-morphs \
  anchored-topology-changing-morphs.mp4

open anchored-topology-changing-morphs.mp4
}

The movie marks the explicit hub with a red diamond. One lower curve collapses
into that hub while a new lower loop grows from it; a surviving upper curve
visibly morphs at the same time.


@section[#:tag "topology-changing-morphs"]{Topology-Changing Morphs and Subpath Birth/Death}

SCENE-AH extends topology-aware correspondence to compounds whose open or
closed subpath counts differ. Prepare explicit interior geometry with:

@racketblock[
(define-values (prepared-source prepared-destination)
  (path-geometry-prepare-topology-changing-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph
   prepared-source prepared-destination))
]

Real open and closed subpaths are matched independently with the correspondence
rules from SCENE-AE/AF and SCENE-AC/AD. Under the default forced-only policy, if
one class has extra real subpaths, only the forced count difference is unmatched.
A born subpath grows from a one-segment degenerate seed at its destination bounds
center; a dying subpath collapses to an analogous seed at its source bounds
center. SCENE-AI additionally allows explicit local anchor points without
changing this default, and SCENE-AJ optionally permits additional voluntary
unmatched slots through numeric penalties.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-topology-changing panel destination)
            #:duration 3)
]

Prepared birth/death slots exist only in interior normalized geometry. Eased
progress zero is the exact source object and eased progress one is the exact
caller destination, so endpoint subpath counts and ordering remain exact.

Render the canonical example with:

@verbatim{
racket examples/topology-changing-morphs.rkt \
  frames/topology-changing-morphs \
  topology-changing-morphs.mp4

open topology-changing-morphs.mp4
}

The surviving open and closed paths visibly change shape, one unmatched open
curve collapses, and one unmatched closed loop grows. Destination storage also
scrambles surviving direction/phase so automatic correspondence remains visible
in the same movie.


@section[#:tag "mixed-compound-morph-correspondence"]{Automatic Mixed-Topology Compound Morph Correspondence}

SCENE-AG composes the existing open and closed correspondence rules for one
compound path that may contain both topology classes. Prepare explicit geometry
with:

@racketblock[
(define aligned-destination
  (path-geometry-align-mixed-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The source and destination must be nonempty and every subpath must have positive
finite arc length. Open counts must match independently from closed counts. Open
candidate pairs use SCENE-AE forward/reverse endpoint correspondence and closed
candidate pairs use SCENE-AC cyclic phase/direction correspondence. The same
deterministic global assignment policy is solved separately inside both classes,
then the selected destination subpaths are restored to source order.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-mixed-compound-aligned panel destination)
            #:duration 3)
]

Topology pairing/reordering and per-pair alignment are interior correspondence
only. Eased progress zero uses the exact clip-start source, and eased progress
one installs the exact caller-requested destination, including its original
interleaving and storage order.

Render the canonical comparison example with:

@verbatim{
racket examples/mixed-compound-morph-correspondence.rkt \
  frames/mixed-compound-morph-correspondence \
  mixed-compound-morph-correspondence.mp4

open mixed-compound-morph-correspondence.mp4
}

Every intended destination counterpart also changes geometry. The upper panel
uses normalized stored-order correspondence and sweeps identities across the
scene. The lower panel solves open and closed identities independently, so the
green paths visibly morph while staying with their spatially sensible
counterparts.


@section[#:tag "open-compound-morph-correspondence"]{Automatic Open-Compound Morph Correspondence}

SCENE-AF extends SCENE-AE endpoint-direction correspondence to equal-count
compound figures whose subpaths are all open. Prepare explicit geometry with:

@racketblock[
(define aligned-destination
  (path-geometry-align-open-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

Every source/destination open-subpath pair is scored with SCENE-AE's inclusive
total-arc-length forward/reverse correspondence. SCENE-AF then chooses a global
minimum-total-cost assignment using the deterministic assignment policy already
used by SCENE-AD. A locally attractive early match therefore cannot force a
worse total correspondence.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-open-compound-aligned panel destination)
            #:duration 3)
]

Pairing and per-pair reversal are interior correspondence only. Eased progress
zero uses the exact clip-start source path, and eased progress one installs the
exact caller-requested destination, including its original subpath order and
stored directions.

Render the canonical comparison example with:

@verbatim{
racket examples/open-compound-morph-correspondence.rkt \
  frames/open-compound-morph-correspondence \
  open-compound-morph-correspondence.mp4

open open-compound-morph-correspondence.mp4
}

The upper panel uses stored-order normalized correspondence and cross-pairs the
open curves. The lower panel pairs subpaths globally and chooses each endpoint
direction independently.


@section[#:tag "open-morph-correspondence"]{Automatic Open-Path Morph Correspondence}

SCENE-AE handles the endpoint-direction ambiguity of one open path. Prepare an
explicit destination traversal with:

@racketblock[
(define aligned-destination
  (path-geometry-align-open-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The two paths must each contain exactly one positive finite open subpath. The
algorithm samples corresponding total-arc-length fractions from both endpoints
and compares the stored destination traversal with its semantic reversal. A
strictly lower reverse score selects reversed correspondence; an exact tie keeps
the stored destination direction. There is no cyclic phase search because open
endpoints remain distinct.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-open-aligned panel destination)
            #:duration 3)
]

The aligned/reversed representation is interior correspondence only. Eased
progress zero uses the exact clip-start source path, and eased progress one
installs the exact destination object originally requested by the caller.

Render the canonical comparison example with:

@verbatim{
racket examples/open-morph-correspondence.rkt \
  frames/open-morph-correspondence \
  open-morph-correspondence.mp4

open open-morph-correspondence.mp4
}


@section[#:tag "compound-morph-correspondence"]{Automatic Compound-Path Morph Correspondence}

SCENE-AD extends closed-loop alignment to compound paths whose subpath storage
order differs. Prepare explicit geometry with:

@racketblock[
(define aligned-destination
  (path-geometry-align-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

Every source/destination loop pair is scored with SCENE-AC phase/direction
correspondence. SCENE-AD then chooses one global minimum-total-cost assignment,
so a locally attractive early match cannot force a worse overall pairing.
Pairing is deterministic and independent of rendering, camera state, frame
rate, wall-clock time, or randomness.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-compound-aligned panel destination)
            #:duration 3)
]

The source and destination must contain equal nonzero counts of positive finite
closed subpaths. The exact requested destination representation, including its
original subpath order, is installed at eased progress one. Reordering and
per-loop alignment are interior correspondence only.

Render the canonical comparison example with:

@verbatim{
racket examples/compound-morph-correspondence.rkt \
  frames/compound-morph-correspondence \
  compound-morph-correspondence.mp4

open compound-morph-correspondence.mp4
}


@section[#:tag "automatic-morph-correspondence"]{Automatic Closed-Loop Morph Correspondence}

SCENE-AC composes SCENE-AB reversal and cyclic starts with the existing
normalized morph engine. Given two single closed loops, align the destination
explicitly with:

@racketblock[
(define aligned-destination
  (path-geometry-align-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The alignment search uses total-arc-length point samples. It considers both
traversal directions by default, scores cyclic phases deterministically, and
prefers forward traversal on exact ties. Set @racket[#:allow-reverse? #f] when
orientation is semantically significant and only a cyclic phase may change.

For ordinary animation, the combined request is shorter:

@racketblock[
(scene-play scene
            (morph-to-aligned panel destination)
            #:duration 3)
]

The exact requested destination representation is still installed at eased
progress one. Automatic alignment is an interior correspondence choice; it does
not rewrite the caller's endpoint object permanently.

SCENE-AC deliberately stops at one positive finite closed subpath per side.
SCENE-AD adds equal-count compound pairing, while SCENE-AH adds controlled
subpath birth/death when topology-class counts differ.

Render the canonical comparison example with:

@verbatim{
racket examples/automatic-morph-correspondence.rkt \
  frames/automatic-morph-correspondence \
  automatic-morph-correspondence.mp4

open automatic-morph-correspondence.mp4
}


@section[#:tag "reversed-cyclic-paths"]{Path Reversal and Cyclic Starts}

SCENE-AB adds traversal-order operations to semantic path geometry. Reverse an
open or closed route with:

@racketblock[
(define reverse-route
  (path-geometry-reverse route))
]

Open routes begin at their former endpoint. Closed routes keep the same stored
start and traverse the loop in the opposite direction. This is useful when two
objects should start together and move around the same loop in opposite
directions:

@racketblock[
(scene-play scene
            (move-along-path forward-pointer route)
            (orient-along-path forward-pointer route)
            (move-along-path reverse-pointer reverse-route)
            (orient-along-path reverse-pointer reverse-route)
            #:duration 4)
]

A closed loop can instead keep its direction while changing phase:

@racketblock[
(define phased-route
  (path-geometry-cycle-start route 3/10))
]

The selected fraction is measured by total arc length and need not coincide
with a stored vertex. SCENE-AB splits a line or cubic when necessary, so the new
route begins exactly at the selected semantic path point under the existing
deterministic arc-length model. Fractions zero and one preserve the original
immutable object.

Cyclic start adjustment accepts exactly one positive-length closed subpath.
This keeps compound-path correspondence explicit. A phase-shifted path can be
passed to @racket[path-geometry-normalize-for-morph] or
@racket[morph-to-normalized] when the caller knows the desired closed-loop
correspondence. SCENE-AC adds @racket[path-geometry-align-for-morph] and
@racket[morph-to-aligned] when the phase or direction should be selected
automatically. SCENE-AD adds @racket[path-geometry-align-compound-for-morph]
and @racket[morph-to-compound-aligned] when multiple equal-count closed subpaths
must also be paired automatically. SCENE-AE adds
@racket[path-geometry-align-open-for-morph] and @racket[morph-to-open-aligned]
when one open path should choose its endpoint direction automatically. SCENE-AF
adds @racket[path-geometry-align-open-compound-for-morph] and
@racket[morph-to-open-compound-aligned] when multiple equal-count open subpaths
must also be globally paired.

Render the canonical SCENE-AB example with:

@verbatim{
racket examples/reversed-and-cyclic-paths.rkt \
  frames/reversed-and-cyclic-paths \
  reversed-and-cyclic-paths.mp4

open reversed-and-cyclic-paths.mp4
}


@section[#:tag "joined-offset-paths"]{Continuous Joined Offset Paths}

SCENE-AA turns the segment-local normal idea from SCENE-Z into reusable semantic
geometry for straight paths. Construct a signed parallel route with an explicit
outside-corner policy:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 -2))))

(define lane
  (path-geometry-offset route 1 #:join 'round))
]

Positive offset is left of the stored path direction. In this right-turn example
that side is outside the corner, so the round policy inserts a cubic quarter
circle between the two shifted lines. Miter and bevel policies are selected the
same way:

@racketblock[
(path-geometry-offset route 1 #:join 'miter)
(path-geometry-offset route 1 #:join 'bevel)
]

Inside corners use the natural shifted-line intersection for every policy. This
is not merely an implementation shortcut: the short centered arc on the inside
would leave the incoming offset edge with the opposite tangent.

Outside miters use a default limit of four times the absolute offset distance. A
longer miter falls back to bevel; choose another finite limit of at least one with
@racket[#:miter-limit]. Round joins are stored as deterministic cubic Bézier arc
pieces, subdivided so each piece spans at most 90 degrees.

The output is ordinary path geometry, so no new animation request is needed:

@racketblock[
(scene-play scene
            (move-along-path pointer lane)
            (orient-along-path pointer lane)
            #:duration 3)
]

The rider now traverses the joined route continuously and tangent orientation
uses the line/cubic geometry of that route. Camera following likewise sees the
actual sampled rider position. Under @racket[linear] easing the speed is constant
in the joined route's own total arc length.

Nonzero SCENE-AA offsets deliberately accept straight source segments only. A
zero-length edge, 180-degree reversal, or cubic source segment is rejected. A
zero offset is an identity operation. Exact cubic-source parallel curves and
self-intersection cleanup remain future work.

SCENE-Z's @racket[#:normal-offset] remains segment-local. It is useful for smooth
routes or when that exact normal rule is intended; use
@racket[path-geometry-offset] when a polyline corner must be continuous.

Render the canonical SCENE-AA example with:

@verbatim{
racket examples/joined-offset-paths.rkt \
  frames/joined-offset-paths \
  joined-offset-paths.mp4

open joined-offset-paths.mp4
}


@section[#:tag "path-orientation-offsets"]{
  Path Tangents, Orientation, and Normal Offsets}

SCENE-Z extends arc-length traversal with semantic direction information.
Tangent and normal lookup use the same measured route fractions as
@racket[path-geometry-point-at].

For an unequal polyline:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 4))))

(path-geometry-tangent-at route 1/7) ; (vec2 1 0)
(path-geometry-normal-at route 1/7)  ; (vec2 0 1)
(path-geometry-tangent-at route 1/2) ; (vec2 0 1)
(path-geometry-normal-at route 1/2)  ; (vec2 -1 0)
]

At an exact edge boundary, the preceding positive edge owns the tangent. This
matches the point boundary rule. Cubic paths use the derivative at the
arc-length-selected parameter. A stationary endpoint or cusp uses a
deterministic one-sided fallback when the geometric direction remains
recoverable.

Offset a target to the left of its actual traversal direction with
@racket[#:normal-offset]:

@racketblock[
(move-along-path marker route #:normal-offset 1)
]

The sign is relative to motion, not merely the stored path direction. Reversing
the path therefore reverses the normal:

@racketblock[
(move-along-path marker route
                 #:start 1
                 #:end 0
                 #:normal-offset 1)
]

Normal offset is segment-local. A sharp polyline corner can jump between the
two adjacent offset edge lines. Use smooth cubic geometry when a continuous
offset trajectory is required.

Tangent orientation is a separate rotation request:

@racketblock[
(scene-play scene
            (move-along-path pointer route)
            (orient-along-path pointer route)
            #:duration 3)
]

The translation and rotation components remain independent. This lets the two
requests compose on one target while preserving ordinary component conflict
rules. Same-target @racket[rotate-to], @racket[rotate-by], or another
@racket[orient-along-path] conflicts with the orientation request.

@racket[#:rotation-offset] accommodates a Visual whose natural forward axis is
not local positive x:

@racketblock[
(orient-along-path pointer route #:rotation-offset (/ pi 2))
]

Reverse orientation points in the reverse traversal direction. A path Visual
route is resolved by stable identity from the prepared clip-start scene and
transformed into world coordinates before arc length or tangent evaluation.
Raw path geometry remains in the target's containing coordinate system. As in
SCENE-Y, route geometry is a clip-start snapshot rather than a live deforming
constraint.

Camera following sees the final sampled Visual position, including any normal
offset, so a followed offset rider remains fixed at its captured frame offset.

Render the canonical SCENE-Z example with:

@verbatim{
racket examples/path-orientation-and-offsets.rkt \
  frames/path-orientation-and-offsets \
  path-orientation-and-offsets.mp4

open path-orientation-and-offsets.mp4
}

@section[#:tag "path-following"]{Arc-Length Path Following}

SCENE-Y promotes semantic path traversal to a first-class translation request.
The new point lookup operation and timeline request use the same deterministic
arc-length model as path reveal and partial extraction.

Sample a route by total ordered arc length:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 4))))

(path-geometry-point-at route 3/7) ; (vec2 3 0)
(path-geometry-point-at route 1/2) ; (vec2 3 1/2)
]

The unequal three-unit and four-unit edges demonstrate that fractions describe
arc length, not segment indexes. Under @racket[linear] easing,
@racket[move-along-path] therefore gives constant speed in route units:

@racketblock[
(scene-play scene
            (move-along-path marker route)
            #:duration 7)
]

Use @racket[#:start] and @racket[#:end] for partial or reverse traversal:

@racketblock[
(move-along-path marker route #:start 1/4 #:end 3/4)
(move-along-path marker route #:start 1 #:end 0)
]

A path Visual route is resolved by stable identity from the prepared clip-start
state and transformed to world coordinates before its arc length is measured.
Raw path geometry is instead interpreted directly in the target's containing
coordinate system. In both forms the route is a clip-start snapshot rather than
a live observer of later path deformation.

Motion routes require exactly one positive-length continuous subpath. This is
stricter than @racket[path-geometry-point-at], which can traverse general
compound geometry in stored order. The stricter timeline rule prevents an
animated Visual from teleporting across a gap between drawn subpaths.

Camera following now samples that actual path-motion state:

@racketblock[
(scene-play scene
            (move-along-path marker route)
            (camera-follow marker)
            (camera-zoom-by 3/2)
            #:duration 3)
]

The followed marker keeps its clip-start frame position even when the route
bends. This also corrects the old endpoint-only assumption for any future
nonlinear translation animation.

Render the canonical SCENE-Y example with:

@verbatim{
racket examples/path-following.rkt \
  frames/path-following \
  path-following.mp4

open path-following.mp4
}

@section[#:tag "fixed-overlays-callouts"]{
  Fixed-in-Frame Overlays and Callouts}

SCENE-X introduces an origin-centered frame coordinate domain for presentation
content that must remain stable while the world camera moves. The semantic
wrapper snapshots only a visible frame width; Pict rendering remains in the
adapter.

Freeze a title at an explicit frame position:

@racketblock[
(define title
  (fixed-in-frame
   (plain-text "Fixed title"
               #:id 'title
               #:font-size 1/2)
   #:camera initial-camera
   #:at (vec2 0 3)))
]

Frame-space Visuals remain ordinary affine and opacity animation targets. Later
world pan and zoom do not alter their screen position or local render scale. A
compound overlay is made by grouping ordinary content first and wrapping the
complete group; frame-space wrappers themselves remain top-level.

Add a fixed annotation whose leader tracks a moving world Visual:

@racketblock[
(define note
  (callout
   (plain-text "moving point" #:id 'note #:font-size 2/5)
   marker
   #:camera initial-camera
   #:at (vec2 4 2)
   #:connector-stroke "navy"
   #:connector-width 2))

(scene-play
 (scene-add (make-scene #:camera initial-camera) marker title note)
 (move-to marker destination)
 (camera-pan-by (vec2 2 1))
 (camera-zoom-by 2)
 #:duration 2)
]

The callout stores a Visual target as its stable identity. Complete scene
rendering resolves that identity against each sampled top-level state, draws the
leader from the target's current world pixel position to the fixed annotation
box, and then places the annotation. A literal @racket[vec2] target instead
represents one fixed world point.

Renderer-aware relative layout measures frame-space Visuals with their captured
frame scale. World and frame domains cannot be mixed in one layout calculation,
and frame Visuals combined together must share the same captured frame width.
Camera fit and follow remain world-only.

The canonical movie moves its marker along the same piecewise-linear sample
edges that define the displayed quadratic graph. SCENE-Y now expresses that
traversal as one @racket[move-along-path] clip while the camera keeps the
original continuous linear pan and zoom trajectory over the three seconds.

Render the canonical SCENE-X example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/fixed-overlays-and-callouts.rkt \
  frames/fixed-overlays-and-callouts \
  fixed-overlays-and-callouts.mp4

open fixed-overlays-and-callouts.mp4
}


@section[#:tag "point-markers-scatter-areas"]{
  Point Markers, Scatter Plots, and Filled Areas}

SCENE-V adds small semantic marker Visuals, ordered scatter-plot groups, and
closed areas derived from sampled function graphs or ordered data series.
These values remain ordinary immutable Visuals. They use the existing affine,
opacity, group, path, timeline, camera, and renderer protocols.

@defproc[(point-marker-shape? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is one of:

@racketblock[
'circle
'square
'diamond
'triangle-up
'triangle-down
]

The set is explicit. Other symbols are rejected.
}

@defproc[(point-marker [#:id identifier symbol?]
                       [#:center center vec2? origin]
                       [#:rotation rotation finite-real? 0]
                       [#:scale scale any/c 1]
                       [#:opacity opacity opacity? 1]
                       [#:shape shape point-marker-shape? 'circle]
                       [#:size size positive-real? 1/5]
                       [#:fill fill any/c "royalblue"]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width
                        nonnegative-real? 1])
         point-marker-visual?]{
Constructs one semantic point marker. @racket[size] is a local world-unit
extent before affine scale. It is the circle diameter, square side, diamond
width and height, or triangle width and height. Stroke width is cosmetic and is
not multiplied by semantic scale.

The marker implements the basic Visual, affine-Visual, and opacity-Visual
protocols. It can therefore be moved, rotated, scaled, faded, grouped, and used
with renderer-aware layout.

The constructor rejects a non-symbol identity, non-finite position or rotation,
nonpositive scale or size, opacity outside the closed unit interval, an unknown
shape, and a negative or non-finite stroke width. Fill and stroke values are
passed to the selected rendering backend in the same way as for the existing
circle, rectangle, and path Visuals.
}

@defproc[(point-marker-visual? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a point-marker Visual.}

@defproc[(point-marker-visual-shape [visual point-marker-visual?])
         point-marker-shape?]{
Returns the marker shape.}

@defproc[(point-marker-visual-size [visual point-marker-visual?])
         positive-real?]{
Returns the full local marker extent before affine scale.}

@defproc[(point-marker-visual-fill [visual point-marker-visual?]) any/c]{
Returns the adapter-specific fill style.}

@defproc[(point-marker-visual-stroke [visual point-marker-visual?]) any/c]{
Returns the adapter-specific stroke style.}

@defproc[(point-marker-visual-stroke-width [visual point-marker-visual?])
         nonnegative-real?]{
Returns the cosmetic stroke width.}

The default Pict adapter converts marker shapes to existing semantic circle,
rectangle, or path primitives after explicit renderer selection. A custom
renderer placed before the defaults can override the complete marker. Semantic
opacity is applied once after either custom rendering or fallback conversion.

@defproc[(scatter-plot [axes axes-visual?]
                       [points (listof (or/c vec2? false/c))]
                       [#:id identifier symbol?]
                       [#:clip? clip? boolean? #t]
                       [#:shape shape point-marker-shape? 'circle]
                       [#:size size positive-real? 1/5]
                       [#:opacity opacity opacity? 1]
                       [#:fill fill any/c "royalblue"]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width
                        nonnegative-real? 1])
         group-visual?]{
Constructs an ordered group of point markers from numeric coordinates.
@racket[#f] entries are omitted. When @racket[clip?] is true, points whose
centers lie outside either closed axes range are also omitted. Marker geometry
is not clipped at an axes boundary.

Visible markers preserve input order. Their identities are derived from the
plot identity and original zero-based list index:

@verbatim{plot-id-marker-index}

Indexes are not renumbered when a @racket[#f] value or clipped point is omitted.
The returned group copies the current axes center and rotation. Numeric marker
positions include the current x and y axes scale, while the markers themselves
start upright and keep the requested world-unit size. This is a
construction-time snapshot. Later changes to the axes do not update the
scatter plot.

The @racket[opacity] argument belongs to the complete returned group. Individual
marker children start with opacity one. The returned group can be transformed
or faded through the ordinary timeline requests.

The constructor rejects anything other than a proper list of @racket[vec2]
values and @racket[#f] gaps. It also validates the identity, clipping flag,
shape, positive finite size, opacity, and nonnegative finite stroke width before
creating any marker child.
}

@defproc[(sample-function-area-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:baseline baseline finite-real? 0]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count exact-integer? 201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{
Samples @racket[function] with the same endpoint, gap, jump, clipping, and
interpolation rules as @racket[sample-function-path]. Every accepted open graph
run becomes one closed subpath. A straight edge is added from the horizontal
baseline to the first graph point, and another from the last graph point back
to the baseline. The implicit closing edge joins the two baseline points.

When clipping is enabled, @racket[baseline] is clamped to the displayed y range.
The graph segments are clipped first, and only the visible accepted runs are
closed. Therefore this operation fills beneath the visible sampled graph path;
it does not reconstruct a region whose complete graph lies outside the display.
Each discontinuous run becomes a separate closed region. Smooth cubic graph
segments remain cubic inside the area.

The baseline must be finite. All other domain, sample-count, callback-result,
exception, clipping, jump, and interpolation errors are the same as for
@racket[sample-function-path]. Sampling stops at the first reported error.
}

@defproc[(function-area
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id identifier symbol?]
          [#:baseline baseline finite-real? 0]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count exact-integer? 201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1/2]
          [#:fill fill any/c "cornflowerblue"]
          [#:stroke stroke any/c #f]
          [#:stroke-width stroke-width nonnegative-real? 0])
         path-visual?]{
Creates a styled path Visual from @racket[sample-function-area-path]. The
returned Visual copies the current axes translation, rotation, and scale. The
procedure is used only during construction and is not retained. The default
style is a half-opacity fill with no visible outline.

The identity must be a symbol, opacity must be in the closed unit interval, and
stroke width must be a nonnegative finite real. Sampling and baseline errors are
reported by @racket[sample-function-area-path].
}

@defproc[(data-series-area-path
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:baseline baseline finite-real? 0]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{
Converts an ordered data series to closed area subpaths. Data order, explicit
@racket[#f] gaps, clipping, maximum-distance breaks, and interpolation follow
@racket[data-series-path]. Each accepted run is closed to the horizontal
baseline using the same rules as a function area.

The baseline must be finite. Point-list, clipping, distance, and interpolation
errors are the same as for @racket[data-series-path].
}

@defproc[(data-area
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:id identifier symbol?]
          [#:baseline baseline finite-real? 0]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1/2]
          [#:fill fill any/c "lightgreen"]
          [#:stroke stroke any/c #f]
          [#:stroke-width stroke-width nonnegative-real? 0])
         path-visual?]{
Creates a styled path Visual from @racket[data-series-area-path]. The returned
Visual copies the current axes transform and stores no reference to the input
list. It uses the ordinary path renderer and therefore supports opacity,
groups, @racket[create], @racket[uncreate], path morphing, affine animation, and
animated cameras.

The identity, opacity, and stroke width are validated before the path Visual is
created. Geometry-construction errors are reported by
@racket[data-series-area-path].
}

The following example places a filled function area behind its graph and adds
ordered observations as diamond markers:

@racketblock[
(define area
  (function-area coordinate-axes
                 function
                 #:id 'area
                 #:interpolation 'smooth))

(define graph
  (function-graph coordinate-axes
                  function
                  #:id 'graph
                  #:interpolation 'smooth))

(define observations
  (scatter-plot coordinate-axes
                (list (vec2 -2 1)
                      (vec2 0 0)
                      (vec2 2 1))
                #:id 'observations
                #:shape 'diamond))
]

Render the canonical stage example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/markers-scatter-areas.rkt \
  frames/markers-scatter-areas \
  markers-scatter-areas.mp4

open markers-scatter-areas.mp4
}


@section[#:tag "version-history"]{Version History}

@itemlist[
 @item{@bold{0.86.0 — SCENE-CL.} Added @racket[#:stationary] to
       @racket[rewrite-formula] and @racket[formula-step]. Extra explicit
       matches retain their current transforms, supplementing the primary
       anchored destination translation in a narrated derivation.}
 @item{@bold{0.85.0 — SCENE-CK.} Made @racket[circumscribe] and
       @racket[indicate] measure their target from the sampled scene state.
       Added @racket[#:target-anchor] to @racket[callout] for live rendered-box
       edge and corner leaders.}
 @item{@bold{0.84.0 — SCENE-CJ.} Added canonical eight-segment perimeter
       correspondence for circle/rectangle @racket[transform-shape] pairs,
       producing symmetric square-to-circle interiors.}
 @item{@bold{0.83.0 — SCENE-CI.} Added source-package omission metadata, so
       @tt{raco pkg create --source} excludes generated renders, local
       experiments, compiled artifacts, and Finder metadata while retaining the
       compile-omitted Rhombus examples as source.}
 @item{@bold{0.82.0 — SCENE-CH.} Added @racket[camera-focus] for a nested or
       top-level explanatory subject plus explicit contextual targets. Extended
       @racket[camera-fit-scene] target selection to nested Visual paths using
       fully composed world-space renderer measurement.}
 @item{@bold{0.81.0 — SCENE-CG.} Added @racket[transform-shape], a safe
       top-level Visual replacement transition. Atomic path/circle/rectangle
       pairs use automatic outline correspondence and exact destination
       restoration; unsupported or composite endpoints deliberately cross-fade.}
 @item{@bold{0.80.0 — SCENE-CF.} Added explicit @racket[formula-step] values
       and @racket[formula-derivation], which sequence anchored formula
       rewrites with optional explanatory pre-transition pauses. The author
       still supplies all algebra, endpoints, and matching choices.}
 @item{@bold{0.79.0 — SCENE-CE.} Extended @racket[circumscribe] and
       @racket[indicate] to nested Visual paths. SCENE-CK later made their
       renderer-measured outlines live within the same play clip.}
 @item{@bold{0.78.0 — SCENE-CD.} Added @racket[attach-to] for sampled
       world-space following of a top-level or nested Visual path. Nested
       derived dependencies now compose enclosing transforms, and
       @racket[callout] leaders accept the same paths.}
 @item{@bold{0.77.0 — SCENE-CC.} Added the common nine-point render-box anchor
       vocabulary with @racket[layout-box-anchor], @racket[visual-layout-anchor],
       @racket[visual-place-at], and @racket[visual-align-to]. These are
       renderer-aware, immutable layout calculations rather than live
       constraints.}
 @item{@bold{0.76.0 — SCENE-CB.} Extended
       @racket[transform-from-copy] to accept a nested Visual path through
       built-in groups/formula assemblies. The selected source is frozen with
       every enclosing transform and opacity composed into an independent
       temporary layer; the original child remains in place.}
 @item{@bold{0.75.0 — SCENE-CA.} Extended opt-in
       @racket[#:changed-mode 'morph] to one identically painted dvisvgm glyph
       path composed of compatible closed contours. Destination contours are
       globally paired and phase-aligned without reversal, so outer/counter
       glyphs can morph while incompatible geometry retains the moving
       cross-fade.}
 @item{@bold{0.74.0 — SCENE-BZ.} Added opt-in
       @racket[#:changed-mode 'morph] to
       @racket[transform-matching-glyphs]. A deliberately conservative
       one-contour, identically painted dvisvgm changed-glyph pair now morphs
       through normalized cubic outline geometry while retaining exact SVG
       endpoint artifacts; all other changed glyphs retain the moving
       cross-fade.}
 @item{@bold{0.73.0 — SCENE-BY.} Added @racket[glyph-tex] and
       @racket[transform-matching-glyphs]. One complete TeX expression now
       exposes its visible dvisvgm glyph leaves as positional formula parts;
       exact SVG path outlines match automatically across separate TeX
       compilations. Changed glyphs remain explicit moving cross-fades rather
       than outline morphs.}
 @item{@bold{0.72.0 — SCENE-BX.} Added @racket[rewrite-formula], an anchored
       formula-transition convenience operation. Its anchor is resolved from
       the current scene formula when a clip compiles, so staged algebra keeps
       a named term such as @racket['equals] fixed without pre-translating each
       construction template. Semantically unchanged tagged fragments also
       retain their source SVG crop at the destination transform, preventing a
       final-frame renderer-resource swap.}
 @item{@bold{0.71.0 — SCENE-BW.} Added source-preserving
       @racket[transform-from-copy], renderer-measured @racket[circumscribe]
       and @racket[indicate], formula-part copies, and arbitrary normalized
       formula routes.}
 @item{@bold{0.70.0 — SCENE-BU.} Refined @racket[write-in] to reveal ordered
       Bézier-curve slots by default, apply easing after each leaf's stagger
       offset, and support reversed writing. Added @racket[unwrite] for
       reverse-order vector removal; arc-length writing remains opt-in.}
 @item{@bold{0.69.0 — SCENE-BT.} Added @racket[write-in], a two-phase
       outline-then-fill vector introduction for paths, groups, common semantic
       SVG shapes, and tagged dvisvgm formula glyphs. Endpoints retain their
       exact original Visuals after the write interval.}
 @item{@bold{0.68.0 — SCENE-BS.} Added @racket[formula-fragment],
       @racket[tagged-formula], and @racket[transform-matching-formula]. Tagged
       formulas use one @tt{latex} to @tt{dvisvgm} compilation for complete TeX
       layout, expose author-declared fragments as cached SVG groups, and
       automatically move rendering-equivalent fragments while changed pieces
       retain cross-fade behavior.}
 @item{@bold{0.67.0 — SCENE-BQ/BR.} Added deterministic bounded-worker PNG
       output through @racket[render-frames!]'s @racket[#:workers] argument,
       plus @racket[render-frames/report!] and @racket[render-diagnostics] for
       per-frame timing and built-in renderer-cache telemetry.}
 @item{@bold{0.66.0 — SCENE-BO/BP.} Added @racket[svg-image], a full-fidelity
       static SVG Visual rendered through the catalog @racketmodname[svg/svg]
       package, with ordinary affine and opacity behavior. Added a bounded,
       thread-safe renderer-resource cache shared by bitmap, text, and formula
       renderers; repeated formula appearances now avoid redundant typesetting.}
 @item{@bold{0.65.0 — SCENE-BG/BI.} Added @racket[svg->visual], importing a
       practical SVG geometry subset into nested semantic groups and preserving
       SVG element identities as stable paths for ordinary lookup and animation.}
 @item{@bold{0.64.0 — SCENE-BH.} Added immutable @racket[image] Visuals with
       explicit world dimensions, normal affine/opacity behavior, lazy default
       bitmap rendering, and a bounded renderer-local bitmap cache.}
 @item{@bold{0.63.0 — SCENE-BJ.} Added linear/log coordinate-scale selection,
       configurable log bases, positive log ranges, logarithmic ticks and
       coordinate conversion, and log-uniform function/vector/implicit sampling.
       Also corrected vector-field's finite grid traversal.}
 @item{@bold{0.62.0 — SCENE-BN.} Added @racket[derived-function-graph], a pure
       context-derived function graph whose two-argument field is sampled from
       each immutable scene state. Parameter-driven plots now need no mutable
       updater or imperative reconstruction.}
 @item{@bold{0.61.0 — SCENE-BL.} Added @racket[sample-implicit-path] and
       @racket[implicit-curve] for deterministic marching-squares contours,
       stitched into stable open or closed semantic path subpaths.}
 @item{@bold{0.60.0 — SCENE-BM.} Added @racket[vector-field], an immutable
       group of stable arrow children sampled from a two-argument vector field.}
 @item{@bold{0.59.0 — SCENE-BK.} Added opt-in discontinuity-aware sampling for
       function graphs, avoiding false clipped segments across asymptotes.}
 @item{@bold{0.58.0 — SCENE-BF.} Added @racket[formula-correspondence-auto],
       deterministic appearance-based matching of unchanged formula parts.}
 @item{@bold{0.57.0 — SCENE-BE.} Documented the existing explicit
       @racket[formula-correspondence] and @racket[formula-part-match] mapping
       workflow as the deliberate matching-transform API.}
 @item{@bold{0.56.0 — SCENE-BD.} Extended stable nested Visual paths through
       formula assemblies, making their named formula parts direct lookup and
       compatible animation targets while preserving immutable assembly state.}
 @item{@bold{0.55.0 — SCENE-BC.} Enabled motion, transform, style, opacity,
       and removal animation requests for nested Visual paths. Ancestor groups
       rebuild immutably and scheduler conflicts compare paths structurally.}
 @item{@bold{0.54.0 — SCENE-BB.} Added stable nonempty symbol paths for nested
       built-in group children, path-aware scene/state and derived-context
       lookup, and @racket[scene-ref]/@racket[scene-visual-at].}
 @item{@bold{0.53.0 — SCENE-BA.} Established derived groups as stable
       top-level @racket[derived-visual] identities whose concrete child
       collections may vary per immutable sampled state.}
 @item{@bold{0.52.0 — SCENE-AZ.} Added immutable @racket[parameter] handles
       for ergonomic reusable scene-value identities and initial values. Handles
       work with value installation, animation, state/scene lookup, removal,
       and derived-context lookup without introducing mutable updater state.}
 @item{@bold{0.51.0 — SCENE-AY.} Generalized named scene values from finite
       reals to interpolable semantic values. Added @racket[interpolable?] and
       @racket[interpolate-value]; finite reals, @racket[vec2], and
       @racket[rgba-color] now share immutable value state, @racket[value-to],
       and derived-context lookup with exact endpoints and compile-time kind
       compatibility checks.}
 @item{@bold{0.50.1 — SCENE-AX text-raster correction.} Kept the @tt{0.50.0}
       public API and dependency semantics unchanged while rasterizing nonempty
       plain-text appearances at a stable local origin before scene placement.
       Added a bounded renderer-local raster cache whose key excludes position
       and camera center but invalidates on appearance changes and camera zoom,
       preventing moving glyph runs from exhibiting apparent spacing drift.}
 @item{@bold{0.50.0 — SCENE-AX.} Extended @racket[derived-context?] with
       @racket[derived-context-visual-has?] and
       @racket[derived-context-visual-ref], allowing pure derived Visuals to
       depend recursively on other top-level Visuals in the same immutable
       sampled scene state. Resolution is drawing-order independent, uses
       traversal-local memoization, rejects self and multi-Visual dependency
       cycles explicitly, and remains nonpersistent across scene samples. Added
       semantic/render regressions and Racket examples.}
 @item{@bold{0.49.0 — SCENE-AW.} Added pure @racket[derived-visual]
definitions driven by immutable sampled scalar values, together with
@racket[derived-context?], scalar context lookup, and resolved scene-state
lookup in drawing order. Rendering, callout targeting, camera follow, scene
camera fitting, and named path-source lookup now resolve derived targets
automatically. Resolver output is never persisted into scene state,
preserves top-level identity, and direct Visual animation of derived definitions
is rejected in favor of animating their scalar sources. Added semantic/render
regressions and Racket examples.}
 @item{@bold{0.48.0 — SCENE-AV.} Added immutable named finite-real scene values,
       @racket[value-to], @racket[scene-set-value], @racket[scene-remove-value],
       @racket[scene-value-at], @racket[scene-current-value], and scene-state value
       lookup. Scalar transitions reuse the existing compiled-animation and
       AN--AR schedule-tree machinery, preserve exact boundaries, compose with
       Visual requests, and remain deliberately non-rendering in preparation for
       derived reactive Visuals.}
 @item{@bold{0.47.1 — SCENE-AU compatibility correction.} Replaced the
       accidental use of the unavailable @racket[false?] predicate in
       @racket[style-to] with an explicit @racket[eq?] check against @racket[#f],
       restoring compatibility with supported Racket releases such as 8.12.}
 @item{@bold{0.47.0 — SCENE-AU.} Added @racket[style-to] and
       @racket[style-to-animation-request?]. Unified style transitions expand to
       the existing fill-color, stroke-color, stroke-width, and opacity leaves,
       retaining exact endpoints, optional Visual protocol validation, fine-grained
       scheduler conflict components, and AN--AR timing semantics. Added semantic
       and renderer regressions plus Racket examples.}
 @item{@bold{0.46.2 — SCENE-AT (test correction).} Corrected the expected midpoint of black-to-gold interpolation and changed the transparent-endpoint renderer regression to sample exact scene time rather than an out-of-range frame index.}
 @item{@bold{0.46.1 — SCENE-AT (rebased).} Added renderer-independent
       @racket[rgba-color] values, X11-style/hex @racket[color-spec?] parsing, fill and
       stroke color Visual protocols, and @racket[fill-color-to] /
       @racket[stroke-color-to] as independent animation components. Exact style
       endpoints are preserved while interior samples use semantic sRGB/alpha
       interpolation; Pict converts semantic RGBA values only at the rendering
       boundary. Built on the corrected SCENE-AS v0.45.1 baseline and supersedes
       the earlier 0.46.0 archive. Added exactness-coercion and scatter/callout
       exclusion tests plus independent rendered checks for every built-in color
       protocol path, alongside Racket examples.}

 @item{@bold{0.45.1 — SCENE-AS correction.} Tightened custom
       @racket[visual-with-stroke-width] validation so exact requested endpoints
       cannot be silently coerced to inexact equal values. Corrected the plot
       coverage documentation: path-valued curves/areas inherit the protocol,
       while scatter groups and callout connector widths do not. Documented and
       tested the default Pict/racket/draw 0--255 pixel pen-width constraint and
       width-zero hairline behavior. Strengthened rendered regression coverage so
       every built-in stroke-width Visual is checked independently.}

 @item{@bold{0.45.0 — SCENE-AS.} Added the optional
       @racket[gen:stroke-width-visual] protocol,
       @racket[stroke-width?], @racket[visual-stroke-width], and
       @racket[visual-with-stroke-width], implemented by built-in circles,
       rectangles, paths, arrows, axes, number lines, and point markers. Added
       @racket[stroke-width-to] as a distinct animation component that composes
       with AN--AR local timing, succession, parallel groups, and lagged starts.
       Custom protocol endpoints are validated during scene compilation. Added
       Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.44.0 — SCENE-AR.} Extended @racket[timed] to wrap
       sequential, parallel, and lagged Visual compositions and allowed timed
       Visual/composition wrappers inside all three composition forms. Untimed
       direct children retain one intrinsic unit; timed children contribute
       @racket[(+ start duration)] units that are scaled by the parent.
       Succession now supports proportional child spans, animation groups scale
       against the longest span, and lagged starts use previous-child spans while
       preserving ratio-zero/group and ratio-one/succession equivalence. Bare
       nested compositions remain one parent-level unit for AO--AQ compatibility.
       Added Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.43.1 — SCENE-AQ maintenance.} Scheduled Visual sampling now
       uses exact progress @racket[0] and @racket[1] at local start/end
       boundaries, preventing inexact schedule arithmetic from contaminating
       otherwise exact endpoint coordinates. Corrected the AQ default-lag
       regression expectation for a rectangle moving horizontally at
       y-coordinate @racket[-2].}

 @item{@bold{0.43.0 — SCENE-AQ.} Added @racket[lagged-start] as a first-class
       staggered visual animation composition with nonnegative
       @racket[#:lag-ratio]. Direct-child duration is scaled so the final child
       ends exactly at the assigned endpoint; ratio zero matches parallel-group
       timing, ratio one matches equal-slice succession, intermediate ratios
       overlap, and larger ratios create gaps. Lagged starts nest freely with
       successions and animation groups and expand to the existing SCENE-AN
       scheduled-leaf representation. Added Racket examples and
       semantic/rendered regression coverage.}

 @item{@bold{0.42.0 — SCENE-AP.} Added @racket[animation-group] as a first-class
       parallel visual animation composition. Every direct child receives the
       group's complete assigned interval; groups and @racket[succession]
       compositions may nest in either direction. Mixed trees expand to the
       existing SCENE-AN scheduled-leaf representation, preserving exact boundary
       compilation, component-conflict rules, structural event ordering,
       camera-follow behavior, and arbitrary-time sampling. Timed/camera nested
       children remain deferred until explicit composite-duration semantics are
       introduced. Added Racket examples and semantic/rendered regression
       coverage.}

 @item{@bold{0.41.0 — SCENE-AO.} Added @racket[succession] as a first-class
       sequential visual animation composition. Direct children receive equal
       consecutive shares of the enclosing interval; nested successions
       recursively subdivide their assigned share. Leaves compile against exact
       semantic boundary states and reuse SCENE-AN overlap, structural, and
       camera-follow behavior. Ordinary and timed top-level siblings remain
       composable, while timed/camera succession children are deferred until
       explicit composite-duration semantics are introduced. Added
       Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.40.0 — SCENE-AN.} Started the animation-composition track with
       @racket[timed] Visual requests carrying local start times, durations, and
       optional local easing inside one @racket[scene-play]. Later start batches
       compile against exact semantic boundary states; touching same-component
       intervals are legal while positive overlap conflicts. Structural
       introductions occur at local start, removals cannot invalidate an active
       same-target animation, untimed requests retain full-clip behavior, and
       camera-follow tracks actual locally timed motion. Added Racket
       examples and semantic/rendered regression coverage.}

 @item{@bold{0.39.0 — SCENE-AM.} Extended topology-changing morph preparation
       and timeline requests with sparse @racket[#:match-penalty-map] additions
       keyed by original @racket[(cons source-index destination-index)] pairs.
       Pair costs are finite nonnegative additions to real geometric assignment
       edges, work in both forced and numeric policy modes, preserve AJ exact-tie
       semantics, and remain independent of AL dummy-edge costs and AK anchors.
       Requests snapshot maps immutably; geometry preparation validates range and
       topology. Added Racket examples and semantic/rendered regression
       coverage.}

 @item{@bold{0.38.0 — SCENE-AL.} Extended topology-changing morph preparation
       and timeline requests with sparse @racket[#:birth-penalty-map] and
       @racket[#:death-penalty-map] overrides keyed by original destination/source
       subpath indexes. Missing entries retain SCENE-AJ shared numeric costs;
       nonempty maps require numeric mode. Cost overrides affect dummy edges only,
       while real geometric scores, AJ tie semantics, AI/AK anchor placement, and
       exact endpoint storage remain unchanged. Timeline requests snapshot maps
       immutably. Added Racket examples and semantic/rendered regression
       coverage.}

 @item{@bold{0.37.0 — SCENE-AK.} Extended topology-changing morph preparation
       and timeline requests with sparse @racket[#:birth-anchor-map] and
       @racket[#:death-anchor-map] overrides keyed by original destination/source
       subpath indexes. Missing entries retain SCENE-AI shared-anchor fallback,
       explicit @racket['bounds-center] entries may override a shared hub, and
       timeline requests snapshot maps immutably. SCENE-AJ penalty assignment is
       unchanged and uses the same indexed anchor policy for voluntary slots.
       Added Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.36.0 — SCENE-AJ.} Extended topology-changing morph preparation
       and timeline requests with paired @racket[#:birth-penalty] and
       @racket[#:death-penalty] policy options. The default @racket['forced]
       behavior is unchanged; finite nonnegative costs enable global voluntary
       death+birth replacement of poor real correspondences. Exact primary-cost
       ties prefer fewer topology changes. Added Racket examples and
       semantic/rendered regression coverage.}

 @item{@bold{0.35.0 — SCENE-AI.} Extended
       @racket[path-geometry-prepare-topology-changing-morph] and
       @racket[morph-to-topology-changing] with declarative
       @racket[#:birth-anchor] and @racket[#:death-anchor] options. Bounds-center
       placement remains the exact default; explicit finite local @racket[vec2]
       anchors may be shared by all unmatched subpaths on either side. Added
       Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.34.0 — SCENE-AH.} Added topology-changing automatic compound
       morph preparation through @racket[path-geometry-prepare-topology-changing-morph]:
       open and closed classes use rectangular global assignment, unmatched
       destinations grow from deterministic bounds-center seeds, and unmatched
       sources collapse to analogous seeds; added
       @racket[morph-to-topology-changing] with normalized interior interpolation
       and exact endpoint preservation, plus Racket examples and
       semantic/rendered regression coverage.}

 @item{@bold{0.33.0 — SCENE-AG.} Added topology-aware automatic compound
       correspondence through @racket[path-geometry-align-mixed-compound-for-morph]:
       open and closed subpaths are globally assigned independently with the
       existing SCENE-AE/AF and SCENE-AC/AD scoring rules, then restored to source
       order; added @racket[morph-to-mixed-compound-aligned] with normalized
       interior interpolation and exact source/destination endpoint preservation,
       plus Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.32.0 — SCENE-AF.} Added deterministic global pairing for
       equal-count positive finite open compound paths through
       @racket[path-geometry-align-open-compound-for-morph], reusing SCENE-AE
       endpoint-direction scores and SCENE-AD minimum-total-cost assignment;
       added @racket[morph-to-open-compound-aligned] with normalized interior
       interpolation and exact source/destination endpoint preservation, plus
       Racket examples and semantic/rendered regression coverage.}

 @item{@bold{0.31.0 — SCENE-AE.} Added deterministic automatic endpoint-direction
       correspondence for one positive finite open source/destination path through
       @racket[path-geometry-align-open-for-morph], including total-arc-length
       forward/reverse scoring and forward tie preference; added
       @racket[morph-to-open-aligned] with normalized interior interpolation and
       exact source/destination endpoint preservation, plus Racket
       examples and semantic/rendered regression coverage.}

 @item{@bold{0.30.0 — SCENE-AD.} Added deterministic global pairing for
       equal-count positive finite closed compound paths through
       @racket[path-geometry-align-compound-for-morph], reusing SCENE-AC
       phase/direction scores within every pair and solving a minimum-total-cost
       assignment; added @racket[morph-to-compound-aligned] with exact endpoint
       preservation, plus Racket examples and semantic/rendered
       regression coverage.}

 @item{@bold{0.29.1 — SCENE-AC fix1.} Kept the SCENE-AC public API and animation semantics unchanged while correcting the renderer regression test to use frame indices with @racket[scene-frame->bitmap] and the public @racket[render-frames!] output API for deterministic PNG checks.}

 @item{@bold{0.29.0 — SCENE-AC.} Added deterministic automatic closed-loop
       morph correspondence through @racket[path-geometry-align-for-morph],
       including cyclic phase search, optional reverse traversal, stored-edge
       boundary candidates, fixed-round refinement, and forward tie preference;
       added @racket[morph-to-aligned] as an additive timeline request that
       reuses normalized cubic morphing while preserving the exact requested
       endpoint; and added Racket examples plus semantic/rendered
       regression coverage.}

 @item{@bold{0.28.1 — SCENE-AB fix1.} Kept the SCENE-AB public API
       unchanged while making cyclic-start reconstruction preserve every
       untouched semantic segment exactly; only the phase-containing edge is
       split, and a final straight prefix is represented by the closed-path
       edge. This avoids renderer-visible floating drift in equivalent cycled
       polygon geometry.}

 @item{@bold{0.28.0 — SCENE-AB.} Added semantic
       @racket[path-geometry-reverse] traversal reversal for line/cubic open
       and closed paths; same-start reversal for closed loops; arbitrary
       arc-length @racket[path-geometry-cycle-start] phase changes with
       deterministic line/cubic splitting; direct reuse by motion, tangent
       orientation, camera following, and normalized morph preparation; and
       Racket examples with semantic/rendered regression coverage.}

 @item{@bold{0.27.0 — SCENE-AA.} Added semantic
       @racket[path-geometry-offset] construction for continuous signed
       straight-path offsets; miter, bevel, and cubic round outside joins;
       inside-corner intersections; miter-limit fallback; open/closed path
       support; direct reuse by path motion/orientation and camera following;
       and Racket examples with semantic/rendered regression coverage.}

 @item{@bold{0.26.0 — SCENE-Z.} Added total-arc-length unit tangent and left
       normal lookup; signed left-of-traversal normal offsets for
       @racket[move-along-path]; independent tangent-derived
       @racket[orient-along-path] rotation with reverse traversal and additive
       rotation offsets; transformed route handling shared with SCENE-Y;
       camera-follow coverage for offset motion; and Racket examples.}

 @item{@bold{0.25.0 — SCENE-Y.} Added total-arc-length point lookup and
       first-class @racket[move-along-path] translation with forward, reverse,
       and partial traversal; clip-start transformed path-Visual route
       resolution; explicit discontinuity rejection; sampled-state camera
       following for nonlinear target motion; Racket examples; and a
       one-clip replacement for the SCENE-X graph-traversal workaround.}

 @item{@bold{0.24.1 — SCENE-X fix1.} Corrected the canonical fixed-overlay
       example so its marker traverses the same piecewise-linear samples as the
       displayed quadratic while preserving the original simultaneous linear
       camera pan and zoom. Added a frame-by-frame regression test for the
       traversal.}

 @item{@bold{0.24.0 — SCENE-X.} Added pure fixed-in-frame Visual wrappers, an
       origin-centered captured frame coordinate system, callouts with sampled
       world-space leader targets, frame-aware relative layout, explicit
       separation from world-camera fit/follow semantics, and Racket
       examples.}

 @item{@bold{0.23.0 — SCENE-W.} Added renderer-aware camera fitting from
       layout boxes, Visual lists, or current scene targets; clip-local camera
       following that preserves a target's frame position during simultaneous
       motion and zoom; deterministic camera-component conflicts; and
       Racket examples.}

 @item{@bold{0.22.0 — SCENE-V.} Added semantic point markers,
       deterministic ordered scatter-plot groups, sampled function and data
       areas closed to horizontal baselines, renderer fallback through existing
       primitives, and Racket examples. Also corrected fallback opacity
       so number-line opacity is applied once.}

 @item{@bold{0.21.0 — SCENE-U.} Added immutable scene-camera state, absolute
       and relative camera pan and zoom requests, simultaneous Visual and camera
       animation, arbitrary-time camera sampling, instantaneous camera
       replacement, scene-camera rendering by default, static camera overrides,
       and Racket examples.}

 @item{@bold{0.20.0 — SCENE-T.} Added semantic number-line Visuals,
       numeric coordinate conversion, automatic axes grid lines, and ordered
       upright numeric labels for axes and number lines.}

 @item{@bold{0.19.0 — SCENE-S.} Added ordered parameter ranges,
       coordinate-valued parametric sampling, ordered data-series plots,
       explicit linear and smooth interpolation, shared clipping and run
       construction, Euclidean distance rejection, and Racket examples.
       Function graphs gained the same interpolation option, and an accidental
       printed value was removed from a SCENE-R test.}
 @item{@bold{0.18.0 — SCENE-R.} Added deterministic coordinate-aware sampling
       of one-variable functions, explicit and non-finite gaps, optional jump
       rejection, rectangular segment clipping, axes-local path geometry,
       transform-snapshot graph Visuals, and Racket examples. Also
       corrected a nonportable rotated-group height assertion in SCENE-Q.}
 @item{@bold{0.17.0 — SCENE-Q.} Added semantic arrows with optional endpoint
       tips, validated Cartesian axis ranges, ordered regular ticks, semantic
       axes, affine coordinate conversion and inversion, shared path-backed
       rendering, renderer-aware label placement, and Racket examples.}
 @item{@bold{0.16.0 — SCENE-P.} Added renderer-aware world-coordinate layout
       boxes, edge and center alignment, relative placement with measured gaps,
       ordered horizontal and vertical arrangement, union centering, fitted-card
       examples, and deterministic custom-renderer layout tests.}
 @item{@bold{0.15.0 — SCENE-O.} Added timeline transformations driven by
       explicit formula correspondence, deterministic matched-part movement,
       changed-formula cross-fades, unmatched-part fades, exact structural
       endpoints, and simultaneous outer assembly transforms.}
 @item{@bold{0.14.0 — SCENE-N.} Added named LaTeX formula parts, semantic
       formula assemblies with significant local part order, explicit
       one-to-one formula correspondence, unmatched-part queries, and recursive
       formula-part rendering. The SCENE-M formula-card example was also
       corrected to avoid unintended overlap, and local @tt{latex-pict}
       checkout workflows were documented.}
 @item{@bold{0.13.0 — SCENE-M.} Added semantic LaTeX formula Visuals,
       immutable source, preamble, mode, ordered option and anchor data, and a
       separate @racketmodname[latex-pict] rendering adapter.}
 @item{@bold{0.12.0 — SCENE-L.} Added semantic one-line plain-text Visuals,
       immutable font and anchor data, built-in Pict text rendering, group
       participation, and ordinary transform, opacity, and fade behavior.}
 @item{@bold{0.11.0 — SCENE-K.} Added semantic groups, significant nested child
       order, inherited uniform transforms and opacity, recursive Pict
       composition, and custom group-renderer overrides.}
 @item{@bold{0.10.0 — SCENE-J.} Added semantic global opacity, the optional
       opacity-Visual protocol, renderer-independent Pict opacity, and
       @racket[fade-to], @racket[fade-in], and @racket[fade-out] requests.}
 @item{@bold{0.9.0 — SCENE-I.} Added deterministic limited path normalization,
       explicit line-to-cubic conversion, longest-segment subdivision, and
       timeline @racket[morph-to-normalized] requests.}
 @item{@bold{0.8.0 — SCENE-H.} Added structural path compatibility, pointwise
       line and cubic interpolation, and timeline @racket[morph-to] requests.}
 @item{@bold{0.7.0 — SCENE-G.} Added semantic cubic Bézier segments, tight
       curve bounds, deterministic approximate curve length, cubic partial
       extraction, curve rendering, and sharp closed-path joins.}
 @item{@bold{0.6.0 — SCENE-F.} Added local path length, partial-path extraction,
       semantic @racket[create] introduction, and @racket[uncreate] removal.}
 @item{@bold{0.5.0 — SCENE-E.} Added semantic path geometry, open and closed
       subpaths, path Visuals, line and polygon constructors, and Pict path
       rendering.}
 @item{@bold{0.4.0 — SCENE-D.} Added the complete Scribble reference manual and
       documentation-coverage requirements. The public runtime API is unchanged
       from 0.3.0.}
 @item{@bold{0.3.0 — SCENE-C.} Added affine transforms, rotation, scale, and
       component animation.}
 @item{@bold{0.2.0 — SCENE-B.} Added rectangles and the ordered Pict renderer
       protocol.}
 @item{@bold{0.1.0 — SCENE-A.} Added Visual identity, scene states, movement,
       timeline sampling, PNG frames, and optional MP4 encoding.}
]
