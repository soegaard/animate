#lang scribble/manual
@(require (for-label (except-in racket/base angle string-copy)
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

@section[#:tag "quick-start"]{Quick Start}

@declare-exporting[animate #:use-sources (animate/main)]

The following program builds Cartesian axes, samples a coordinate-valued
parametric procedure, plots one ordered data series, and animates the camera at
the same time. Both curves use smooth cubic interpolation and the ordinary path
@racket[create] animation.

@racketmod[
racket/base

(require animate)

;; Frame and media output is deliberately a separate effectful module.
(require animate/render)

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

@declare-exporting[animate #:use-sources (animate/main)]

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
state. Immutable updates must preserve identity. A group's direct children must
have distinct identities and no descendant may reuse that group's identity. The
same local child identity may occur in separate branches, since complete nested
paths remain distinct. A custom affine Visual is treated as one leaf.

Built-in group and formula children are addressable with a nonempty nested
Visual path such as @racket['(equation numerator)] or
@racket['(A row-1 col-2)]. Formula-part names form a local namespace inside one
formula assembly; a formula-part transformation still targets the containing
top-level assembly and updates its parts collectively.

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

@racket[transform-matching-visuals] extends that operation over the leaves of
ordinary group trees. It first honors explicit relative paths, then searches
stable leaf paths and conservative built-in shape correspondence. Formula and
glyph transitions retain their more specialized tagged-TeX matching API.

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

The established @racket[affine-transform] value stores translation, rotation,
and scale. Components are
applied in this fixed order:

@centered{@bold{scale, then rotate, then translate}}

Scale is stored as positive x and y factors. SCENE-CY-A adds separate
@racket[linear2] and @racket[affine2] values for a full matrix and translation.
@racket[apply-affine] and @racket[apply-matrix] map a world Visual through
those values. SCENE-DK extends the map layer to ordinary nested paths: a named
child can be mapped inside an already-mapped group without flattening the
group. The existing decomposed affine-Visual protocol remains available for
Visual implementations; the general-map wrapper supplies the bridge through a
nested group tree.

A group may be translated and rotated normally, but its own legacy scale must be
uniform. A uniform parent scale and rotation compose exactly with each child's
existing decomposed transform. Allowing a non-uniform parent scale followed by
a rotated child can create shear, which the legacy transform model cannot
represent. Use @racket[apply-affine] on the complete top-level group when that
is the intended mathematical operation.

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

@section[#:tag "scene-state"]{Scene States}

@declare-exporting[animate #:use-sources (animate/main)]

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

@declare-exporting[animate #:use-sources (animate/main)]

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

@defproc[(change-number-to [id (or/c symbol? scene-parameter?)]
                           [destination (or/c finite-real? finite-complex?)])
         change-number-to-request?]{

Creates an absolute numerical transition. Finite reals interpolate normally;
finite complex values interpolate their Cartesian components. It uses the same
immutable scalar-value animation as @racket[value-to], but its numerical
contract communicates that it is intended to drive a numeric display.
}

@defproc[(change-number-to-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[change-number-to].
}

@defproc[(count-to [id (or/c symbol? scene-parameter?)]
                    [destination finite-real?])
         count-to-request?]{

Counts from the named parameter's value at this play clip's start to
@racket[destination]. The initial named value must therefore be a compatible
finite real when the request is compiled.
}

@defproc[(count-to-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[count-to].
}

@defproc[(count-from [id (or/c symbol? scene-parameter?)]
                      [from finite-real?]
                      [to finite-real?])
         count-from-request?]{

Counts between explicit endpoints. In particular, @racket[from] is the value
at clip phase zero even if the preceding scene has a different value. This is
useful for independently reproducible counters and does not introduce a mutable
tracker.
}

@defproc[(count-from-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[count-from].
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

@defproc[(apply-affine [target (or/c visual? symbol? visual-path?)]
                       [map affine2?])
         apply-affine-request?]{

Creates a SCENE-DK general affine-map request. At each sampled interior time,
the identity-to-@racket[map] entry-wise interpolation is applied after
@racket[target]'s current outer affine map. The map therefore acts in world
coordinates; it can express shears, reflections, arbitrary linear maps, and
translation in one request.

The target may be a top-level world Visual or an ordinary nested
@racket[visual-path?]. A nested request is rebased through enclosing semantic
affine maps so its requested map still has world-coordinate meaning. The
enclosing map must be invertible; derived Visuals and frame-space overlays are
still rejected during scene compilation. The resulting endpoint is an
@racket[affine-map-visual?], so a later @racket[apply-affine] composes maps
without rasterizing the prior result. Existing movement, rotation, and scale
requests conflict with @racket[apply-affine] for the same target during an
overlapping interval.
}

@defproc[(apply-affine-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request made by
@racket[apply-affine].
}

@defproc[(apply-matrix [target (or/c visual? symbol? visual-path?)]
                       [matrix linear2?])
         apply-affine-request?]{

Convenience form of @racket[apply-affine] for a translation-free linear map
about the world origin.
}

@subsection[#:tag "pointwise-maps"]{Robust Pointwise Maps}

SCENE-DQ extends SCENE-CY-C's nonlinear companion to the affine-map layer.
It acts on world-space points and samples a path before mapping it, so a line
under a nonlinear map becomes a visible curve rather than a chord joining two
transformed endpoints. The exact caller Visual is retained at clip time zero.
Adaptive refinement checks the deviation of a mapped midpoint from its mapped
chord, while a failed map sample can split the result into separate subpaths.

@defproc[(apply-pointwise
          [target (or/c visual? symbol? visual-path?)]
          [map-point (procedure-arity-includes/c 1)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'split])
         apply-pointwise-request?]{

Creates a SCENE-DQ world-space point-map request. At each positive clip
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

Creates a SCENE-DW time-dependent world-space deformation request. At each
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
          [color paint?])
         fill-color-to-request?]{

Creates an absolute semantic fill-paint request. The source fill at the leaf
start and @racket[color] must both satisfy @racket[paint?]. A slot whose current
value is @racket[#f] therefore cannot be animated by this operation.

Compatible solid colours, linear gradients, radial gradients, and checker
patterns interpolate through @racket[paint-lerp]. At exact progress zero and
one, the exact source and destination paint objects are installed. Different
paint kinds (or gradients with unequal stop counts) are rejected during scene
compilation; use an explicit cross-fade of two Visuals for that change.

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
follow the solid-colour case of @racket[fill-color-to]. Stroke color owns a distinct
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

@defstruct*[visual-match ([source-path (listof symbol?)]
                          [destination-path (listof symbol?)])
                         #:transparent]{

An explicit correspondence between two leaf paths relative to the root Visuals
passed to @racket[transform-matching-visuals]. The empty path names an atomic
root. Every selected source and destination leaf may occur in at most one
explicit match.
}

@defproc[(transform-matching-visuals
          [source visual?]
          [destination (and/c visual? affine-visual? opacity-visual?)]
          [#:matches matches (listof visual-match?) '()]
          [#:mode mode (or/c 'auto 'morph 'cross-fade) 'auto]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count (and/c exact-integer? (>=/c 8)) 64])
         transform-matching-visuals-request?]{

Replaces the present top-level @racket[source] root with the fresh top-level
@racket[destination] root. The root identities must differ. At compilation, the
current source root is flattened through ordinary @racket[group] transforms
into leaf paths. The matching order is: explicit @racket[visual-match] pairs,
equal relative leaf paths, exact built-in path/circle/rectangle type and style,
identical local shape fingerprints, then nearest remaining compatible shape
geometry. This is deterministic and every leaf participates at most once.

For a matched path, circle, or rectangle that can use the existing
topology-aware outline preparation, @racket['auto] shares an intermediate
geometric morph. Other matched affine/opacity leaves move through an
interpolated affine transform while their source/destination content cross-fades.
Unmatched leaves fade in place; @racket['fade-transform] pairs the remaining
leaves by nearest position to give them the same moving cross-fade. Pass
@racket['morph] to require every matched pair to have geometric correspondence,
or @racket['cross-fade] to disable all geometric morphs.

This first general matcher is intentionally conservative. It does not infer
semantic matches for arbitrary SVG/text/custom leaves after renaming, preserve
one leaf through a split or merge, resolve occlusion/collisions, or replace the
formula APIs' TeX/glyph correspondence. At exact start the source is unchanged;
interior samples use a temporary frontmost overlay; at the clip boundary the
exact destination root is installed.
}

@defproc[(transform-matching-visuals-request? [value any/c]) boolean?]{

Recognizes a request created by @racket[transform-matching-visuals].
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

@subsection{Serializable Rate Functions}

SCENE-DL represents built-in easings as transparent callable values. A
@racket[rate-function?] can therefore be supplied anywhere the historical API
accepts a one-argument procedure, while its kind and parameters remain part of
the scene's serializable representation. Arbitrary one-argument procedures
remain supported; they are intentionally opaque to automatic authoring caches.

@defproc[(rate-function? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in callable semantic rate
function.
}

@defproc[(rate-function-name [value rate-function?]) symbol?]{

Returns the stable built-in kind, such as @racket['smooth].
}

@defproc[(rate-function-parameters [value rate-function?]) list?]{

Returns the validated constructor parameters in their stable order.
}

@defproc[(rate-function->datum [value rate-function?]) pair?]{

Returns a compact serializable description, for example
@racket['(smooth 10)].
}

@defproc[(rate-function-apply [value rate-function?]
                              [progress finite-real?]) finite-real?]{

Applies one semantic rate function. The scene machinery supplies clamped
progress; built-ins return exact 0 or 1 at the corresponding clip boundaries.
}

@defthing[linear rate-function?]{

The default rate function, callable as @racket[(linear progress)]. It returns
@racket[progress] unchanged.
}

@defproc[(smooth [#:inflection inflection positive-real? 10]) rate-function?]{

Returns a normalized logistic S curve. Greater @racket[inflection] makes its
departure from zero and arrival at one sharper.
}

@defproc[(smoothstep) rate-function?]{

Returns the cubic @math{3t^2-2t^3} curve with zero slope at both endpoints.
}

@defproc[(rush-into) rate-function?]{

Returns a smooth curve that starts slowly and accelerates into its endpoint.
}

@defproc[(rush-from) rate-function?]{

Returns a smooth curve that leaves quickly and decelerates toward its endpoint.
}

@defproc[(there-and-back) rate-function?]{

Returns a smooth excursion from zero to one and back to zero.
}

@defproc[(there-and-back-with-pause
          [#:pause-ratio pause-ratio (and/c finite-real? (>=/c 0) (</c 1)) 1/3])
         rate-function?]{

Returns an outward-and-returning curve that holds one for the specified fraction
of its unit interval.
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

@defproc[(reverse-rate [function rate-function?]) rate-function?]{

Returns the time reversal of a semantic rate function.
}

@defproc[(compose-rate [first rate-function?] [rest rate-function?] ...)
         rate-function?]{

Returns nested timing composition: @racket[(compose-rate outer inner)] evaluates
@racket[outer] after @racket[inner].
}

@defproc[(squish-rate [function rate-function?]
                      [#:from from (and/c finite-real? (>=/c 0) (<=/c 1)) 0]
                      [#:to to (and/c finite-real? (>=/c 0) (<=/c 1)) 1])
         rate-function?]{

Runs @racket[function] only over the strict interval from @racket[from] to
@racket[to], holding zero before it and one after it.
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
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)]
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
endpoint, its exact semantic endpoint is held. SCENE-CV permits timed wrappers
inside Visual/scalar and camera compositions and permits a composition itself to
be wrapped. Another @racket[timed] wrapper is not a valid @racket[request]
value. A timed @racket[camera-follow] samples its target only while its own
interval is active, then holds the resulting endpoint view.
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
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...)
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
place of separate arguments. Ordinary Visual and camera requests, unified style
transitions, timed Visual/camera composition wrappers, and nested successions,
animation groups, or lagged starts are valid children. Camera center and
world-width overlap rules apply after expansion.
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
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...)
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
place of separate arguments. Unified style transitions, camera requests, timed
Visual/camera composition wrappers, and nested compositions are valid group
children. Camera center and world-width overlap rules apply after expansion.
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
                         uncreate-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...
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
place of separate arguments. Unified style transitions, camera requests, timed
Visual/camera composition wrappers, and nested compositions are valid lagged
children. Camera center and world-width overlap rules apply after expansion.
}

@defproc[(lagged-start-animation-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a composition created by
@racket[lagged-start].
}

@defproc[(style-to
          [target (or/c symbol? visual?)]
          [#:fill fill (or/c false/c paint?) #f]
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

@declare-exporting[animate #:use-sources (animate/main)]

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

When at least one timing/composition value is present, every Visual, scalar, or
camera request resolves to one or more concrete local intervals. A top-level
@racket[timed] value uses literal second-based start and duration and may wrap
either one leaf or one composition. An ordinary unwrapped top-level Visual or
camera request spans the complete enclosing clip.

Inside compositions, unwrapped direct children contribute one timing unit and a
timed direct child contributes @racket[(+ start duration)] units. A succession
places those spans consecutively, an animation group starts them together and
scales against the longest span, and a lagged start offsets raw starts by its lag
ratio before scaling the complete envelope. Bare nested compositions remain
one-unit direct children unless explicitly wrapped by @racket[timed]. All three
composition forms may nest arbitrarily with timed Visual/camera composition
children.

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

SCENE-CV gives camera requests those same local intervals. A later pan, zoom,
fit, or follow compiles from the exact camera view at its local start.
@racket[camera-pan-by] therefore adds to that local center, and
@racket[camera-zoom-by] divides that local visible width by its magnification
factor. A @racket[camera-follow] captures its target's frame offset at the
start of its own interval, samples the target's actual local Visual state while
active, and holds the resulting endpoint view after it ends. A camera-fit
request remains a concrete center/width snapshot measured when it was
constructed. Camera and Visual requests may appear in any order.

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
Overlapping requests that reserve the same camera component raise an exception,
so fit conflicts with pan, follow, zoom, or another fit for the same local
interval. Touching camera intervals are legal and hand off exactly. Camera
components do not conflict with Visual components.

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
