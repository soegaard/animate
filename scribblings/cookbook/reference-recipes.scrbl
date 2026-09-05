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

@title[#:tag "number-lines-and-coordinate-decorations"]{
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

SCENE-CV also gives camera leaves the normal composition vocabulary:

@racketblock[
(scene-play scene
            (succession
             (camera-pan-to (vec2 -4 0))
             (animation-group
              (camera-follow 'marker)
              (camera-zoom-by 2)))
            #:duration 4)
]

Here pan occupies the first half. Follow and zoom occupy the second half in
parallel because they write separate camera components. A top-level
@racket[timed] camera request uses literal local seconds; inside a composition,
it follows the same duration-scaling rules as a timed Visual request. Each
camera leaf compiles from the exact view at its local start. A local
@racket[camera-follow] tracks the sampled world-space target only during its
own interval and then retains that endpoint view.

The camera center and visible world width are independent components. Pan and
follow requests change the center. Zoom requests change visible width. A fit
request changes both components. Requests for disjoint components may run
together; overlapping requests that reserve the same component raise an
exception. Relative pan and zoom requests compile from the camera at the start
of their own local interval.

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


@section[#:tag "probability-and-statistical-diagrams"]{
  Probability and Statistical Diagrams}

SCENE-DT provides small, immutable, addressable diagram groups for common
probability and statistics explanations. These constructors do not analyse data
or add a separate scene protocol: their bars, cells, tree branches, quartile
box, and error-bar elements are ordinary named children that work with existing
paths, colours, transforms, and attention effects.

@defproc[(bar-chart [values (and/c list? pair?)]
                    [#:id identifier symbol?]
                    [#:labels labels (or/c (listof string?) false/c) #f]
                    [#:center center vec2? origin]
                    [#:width width positive-real? 6]
                    [#:height height positive-real? 3]
                    [#:maximum maximum (or/c positive-real? false/c) #f]
                    [#:fill fill any/c "cornflowerblue"]
                    [#:stroke stroke any/c "navy"]
                    [#:stroke-width stroke-width nonnegative-real? 2]
                    [#:value-labels? value-labels? boolean? #t])
         group-visual?]{

Creates a baseline and one upward nonnegative bar per value. Values are scaled
against @racket[maximum], or the largest supplied value (at least one). Labels
and value labels are optional ordinary text children. The path of one bar is
@racket[(bar-chart-bar-path identifier index)], where indexes start at one.
}

@defproc[(histogram [samples (and/c list? pair?)]
                    [#:id identifier symbol?]
                    [#:bins bins exact-positive-integer? 8]
                    [#:range range (or/c pair? false/c) #f]
                    [#:center center vec2? origin]
                    [#:width width positive-real? 6]
                    [#:height height positive-real? 3])
         group-visual?]{

Counts finite numeric samples into equally wide bins, then returns the same
addressable bar-group shape as @racket[bar-chart]. A supplied range is an
increasing pair; samples outside it are omitted and a sample at the upper bound
belongs to the final bin.
}

@defproc[(stacked-bar-chart [rows (and/c list? pair?)]
                            [#:id identifier symbol?]
                            [#:center center vec2? origin]
                            [#:width width positive-real? 6]
                            [#:height height positive-real? 3]
                            [#:maximum maximum (or/c positive-real? false/c) #f]
                            [#:colors colors (and/c list? pair?) any/c]
                            [#:stroke stroke any/c "navy"]
                            [#:stroke-width stroke-width nonnegative-real? 1])
         group-visual?]{

Creates one bar per equal-length nonnegative row and stacks each row's values
from the common baseline. Use @racket[stacked-bar-path] and
@racket[stacked-bar-segment-path] for one bar or segment, with one-based
indexes.
}

@defproc[(sample-space [rows (and/c list? pair?)]
                       [#:id identifier symbol?]
                       [#:center center vec2? origin]
                       [#:width width positive-real? 5]
                       [#:height height positive-real? 3])
         group-visual?]{

Creates equally sized, coloured cells from a nonnegative rectangular matrix.
Each cell displays its supplied weight. Its path is
@racket[(sample-space-cell-path identifier row column)], with one-based row and
column indexes; the geometry remains equal even for unequal weights.
}

@defstruct*[probability-branch ([id symbol?]
                                [label string?]
                                [probability nonnegative-real?]
                                [children (listof probability-branch?)])
  #:transparent]{

Describes one immutable node in a finite probability tree. Branch identities
must be globally unique within one @racket[probability-tree] input.
}

@defproc[(probability-tree [branches (and/c list? pair?)]
                           [#:id identifier symbol?]
                           [#:center center vec2? origin]
                           [#:width width positive-real? 6]
                           [#:level-gap gap positive-real? 1]
                           [#:node-radius radius positive-real? 1/6])
         group-visual?]{

Lays out an explicit finite forest by leaf order. Child edge labels display the
child branch probability. A node can be addressed with
@racket[(probability-tree-node-path identifier branch-id)].
}

@defproc[(box-plot [values (listof finite-real?)]
                   [#:id identifier symbol?]
                   [#:center center vec2? origin]
                   [#:width width positive-real? 5]
                   [#:height height positive-real? 3/4])
         group-visual?]{

Creates whiskers, a quartile box, and a median line from at least two values.
Quartiles use deterministic linear interpolation between sorted observations;
outliers are not inferred or displayed. @racket[box-plot-summary] is the
transparent five-number summary structure used by the constructor.
}

@defstruct*[error-bar-point ([x finite-real?]
                             [y finite-real?]
                             [error nonnegative-real?])
  #:transparent]{

Describes a point with symmetric vertical error.}

@defproc[(error-bars [points (and/c list? pair?)]
                     [#:id identifier symbol?]
                     [#:center center vec2? origin]
                     [#:cap-width cap-width positive-real? 1/5])
         group-visual?]{

Creates addressable vertical stems, end caps, and point markers. The path for a
one-based point index is @racket[(error-bar-path identifier index)].
}

@defproc[(bar-chart-bar-path [identifier symbol?]
                             [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based bar.}

@defproc[(stacked-bar-path [identifier symbol?]
                           [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based stacked bar.}

@defproc[(stacked-bar-segment-path [identifier symbol?]
                                   [bar-index exact-positive-integer?]
                                   [segment-index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based stacked-bar segment.}

@defproc[(sample-space-cell-path [identifier symbol?]
                                 [row exact-positive-integer?]
                                 [column exact-positive-integer?])
         visual-path?]{Returns the path of one one-based sample-space cell.}

@defproc[(probability-tree-node-path [identifier symbol?] [branch-id symbol?])
         visual-path?]{Returns the path of one named probability-tree node.}

@defstruct*[box-plot-summary ([minimum finite-real?]
                               [lower-quartile finite-real?]
                               [median finite-real?]
                               [upper-quartile finite-real?]
                               [maximum finite-real?])
  #:transparent]{
The deterministic five-number summary used by @racket[box-plot].
}

@defproc[(error-bar-path [identifier symbol?]
                         [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based error-bar group.}

See @filepath{examples/probability-and-statistics.rkt} for one composition that
uses chart, finite-outcome, tree, distribution, and uncertainty views together.
}
