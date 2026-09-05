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

@section[#:tag "pict-renderers"]{Pict Renderer Protocol}

@declare-exporting[animate #:use-sources (animate/main)]

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

@declare-exporting[animate #:use-sources (animate/main)]

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

@defproc[(align-baselines
          [visuals (listof visual?)]
          [#:baseline baseline (or/c finite-real? false/c) #f]
          [#:camera camera camera? default-camera]
          [#:renderers renderers pict-renderer-list? default-pict-renderers])
         (listof visual?)]{

Returns one immutable positioned copy per input Visual, in input order. Their
reference y coordinates are all set to @racket[baseline], or to the first
Visual's reference y coordinate when it is @racket[#f]. In particular, this
aligns the true baselines of text made with @racket[#:vertical-alignment
'baseline]. Other Visual kinds use their ordinary reference position; no hidden
font baseline is inferred for them.
}

@defproc[(keep-inside-frame
          [visual visual?]
          [#:margin margin (and/c finite-real? (>=/c 0)) 0]
          [#:camera camera camera? default-camera]
          [#:renderers renderers pict-renderer-list? default-pict-renderers])
         visual?]{

Returns an immutable copy translated minimally so its complete measured render
box is inside @racket[camera]'s viewport after the requested margin. A Visual
larger than the available viewport is centred on that axis. The operation is a
construction-time correction, not a live camera or viewport constraint.
}

@defproc[(avoid-overlap
          [visuals (listof visual?)]
          [#:direction direction (or/c 'right 'up) 'right]
          [#:gap gap (and/c finite-real? (>=/c 0)) 0]
          [#:camera camera camera? default-camera]
          [#:renderers renderers pict-renderer-list? default-pict-renderers])
         (listof visual?)]{

Returns ordered immutable copies separated by a deterministic greedy pass.
@racket['right] moves later Visuals rightward until their measured boxes leave
at least @racket[gap] horizontal space; @racket['up] does the analogous
vertical pass. It is intentionally not a general two-dimensional packing or
constraint solver.
}

@defproc[(distribute-within
          [visuals (listof visual?)]
          [start finite-real?]
          [end finite-real?]
          [#:axis axis (or/c 'horizontal 'vertical) 'horizontal])
         (listof visual?)]{

Returns ordered immutable copies whose reference x or y coordinates are evenly
spaced, including @racket[start] and @racket[end]. An empty list returns empty;
a singleton is placed at their midpoint. The unselected coordinate and all other
Visual properties are preserved.
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

@declare-exporting[animate #:use-sources (animate/main)]

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

@defproc[(flash [target (or/c visual? symbol? visual-path?)]
                [#:radius radius (and/c finite-real? (>=/c 0)) 1/2]
                [#:color color any/c "gold"]
                [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3])
         flash-request?]{
Draws a short eight-ray burst around the target's live rendered-box centre.
The transient overlay is absent at both clip endpoints.
}

@defproc[(flash-request? [value any/c]) boolean?]{Recognizes a @racket[flash] request.}

@defproc[(focus-on [target (or/c visual? symbol? visual-path?)]
                   [#:radius radius (and/c finite-real? (>=/c 0)) 1/2]
                   [#:color color any/c "gold"]
                   [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3])
         focus-on-request?]{
Expands and fades a circular live-target focus ring over one play clip.
}

@defproc[(focus-on-request? [value any/c]) boolean?]{Recognizes a @racket[focus-on] request.}

@defproc[(show-passing-flash
          [target (or/c path-visual? symbol? visual-path?)]
          [#:time-width time-width (real-in 0 1) 1/5]
          [#:color color any/c "gold"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 4])
         show-passing-flash-request?]{
Renders only a moving arc-length sliver of a path Visual. A symbol/path target
is checked when the play clip is compiled.
}

@defproc[(show-passing-flash-request? [value any/c]) boolean?]{
Recognizes a @racket[show-passing-flash] request.
}

@defproc[(wiggle [target (or/c visual? symbol? visual-path?)]
                 [#:angle angle finite-real? 1/12]
                 [#:cycles cycles exact-positive-integer? 2])
         succession-animation-request?]{
Returns an ordinary reversible rotation succession. It ends at exactly the
initial rotation and follows normal composition timing.
}

@defproc[(grow-from-center [visual (and/c visual? affine-visual? opacity-visual?)])
         grow-from-center-request?]{
Introduces an absent Visual from an invisible, centre-scaled source and
restores the exact supplied endpoint at completion.
}

@defproc[(grow-from-center-request? [value any/c]) boolean?]{
Recognizes a @racket[grow-from-center] request.
}

@defproc[(grow-arrow [visual arrow-visual?]) grow-arrow-request?]{
Introduces an absent arrow from its start endpoint, including its arrowhead.
}

@defproc[(grow-arrow-request? [value any/c]) boolean?]{Recognizes a @racket[grow-arrow] request.}

@defproc[(draw-border-then-fill [visual path-visual?])
         draw-border-then-fill-request?]{
Introduces an absent path Visual by tracing its outline with arc-length timing,
then fading in its original fill and final stroke style.
}

@defproc[(draw-border-then-fill-request? [value any/c]) boolean?]{
Recognizes a @racket[draw-border-then-fill] request.
}

@defproc[(transform-from-copy
          [source (or/c visual? symbol? visual-path?)]
          [destination (and/c visual? affine-visual? opacity-visual?)]
          [#:path-arc path-arc finite-real? 0]
          [#:route route (or/c #f formula-route?) #f])
         transform-from-copy-request?]{

Keeps the source in place while a transient copy moves to the initially absent
destination.  A supplied route overrides the default circular @racket[path-arc].
}

@defproc[(transform-from-copy-request? [value any/c]) boolean?]{
Recognizes a @racket[transform-from-copy] animation request.
}

@section[#:tag "rendering"]{Pict, Bitmap, and Frame Conversion}

@declare-exporting[animate #:use-sources (animate/main)]

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

@declare-exporting[animate/render #:use-sources (animate/render)]

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

@racket[workers] is a bounded worker-pool size. Its default, one, retains
sequential output. On Racket 8.18 or later with parallelism enabled, more than
one worker builds independent frame bitmaps through a parallel thread pool;
one ordinary thread then encodes their PNG files, because Racket's PNG encoder
uses callbacks that cannot run in a parallel thread. On the package's Racket
8.12 baseline, the same argument uses the compatible coroutine-thread
implementation. In every case, returned paths remain in frame-index order and
each frame keeps its deterministic filename. The built-in renderers synchronize
their shared resources. A custom renderer used with more than one worker must
itself be safe for concurrent calls.
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

@subsection{Authored timelines and selected sections}

@declare-exporting[animate/authoring #:use-sources (animate/authoring)]

@defproc[(section [name symbol?]
                  [start finite-real?]
                  [end finite-real?])
         authoring-section?]{

Constructs a named half-open authoring interval @litchar{[start, end)}. The name
is stable metadata; it does not become a scene Visual or change scene sampling.
Both times must be finite and nonnegative, and @racket[end] must be strictly
greater than @racket[start]. The enclosing timeline checks that the interval is
inside its scene and does not overlap another section.
}

@defproc[(cue [name symbol?] [time finite-real?]) cue?]{

Constructs a named point marker in scene seconds. A cue is metadata only: it
does not draw a marker or affect sampling. @racket[make-authored-timeline]
checks that it lies in the scene timeline.
}

@defproc[(audio-cue [source path-string?]
                    [#:start start finite-real? 0]
                    [#:source-start source-start finite-real? 0]
                    [#:duration duration (or/c false/c finite-real?) #f]
                    [#:gain gain finite-real? 1]
                    [#:fade-in fade-in finite-real? 0]
                    [#:fade-out fade-out finite-real? 0])
         audio-cue?]{

Constructs immutable audio-placement metadata. @racket[source] is deliberately
not opened or decoded, so construction and scene rendering remain independent
of external codecs and files. @racket[start] and @racket[source-start] are
nonnegative; when supplied, @racket[duration] is positive. @racket[gain] is a
nonnegative linear multiplier. Fade lengths are nonnegative; a fade-out needs
an explicit duration and neither fade may exceed it. During
@racket[assemble-authored-mp4!] or @racket[mux-authored-video!], FFmpeg trims
the source, applies gain/fades, delays it to @racket[start], mixes all cues,
and encodes AAC.
}

@defproc[(subtitle [start finite-real?] [end finite-real?] [text string?])
         subtitle?]{

Constructs one audience-facing half-open caption interval. Both bounds must be
inside the owning scene and @racket[end] must be greater than @racket[start].
The text is kept verbatim apart from CR/LF normalization when it is written to
SRT or WebVTT.
}

@defproc[(authoring-section? [value any/c]) boolean?]{
Recognizes an immutable named half-open authoring interval.
}

@defproc[(cue? [value any/c]) boolean?]{
Recognizes immutable cue metadata.
}

@defproc[(audio-cue? [value any/c]) boolean?]{
Recognizes immutable audio-placement metadata.
}

@defproc[(subtitle? [value any/c]) boolean?]{
Recognizes immutable caption metadata.
}

@defproc[(make-authored-timeline
          [scene scene?]
          [#:sections sections (listof authoring-section?) null]
          [#:cues cues (listof cue?) null]
          [#:audio-cues audio-cues (listof audio-cue?) null]
          [#:subtitles subtitles (listof subtitle?) null])
         authored-timeline?]{

Associates immutable authoring metadata with an ordinary scene. Section names
and cue names must be unique. Sections must lie wholly within the scene,
non-overlap, and retain their declared order in returned metadata. Cues and
audio placements must start no later than the scene endpoint; subtitle ends
must also lie inside it. The wrapped scene itself is unchanged and is available
through @racket[authored-timeline-scene].
}

@defproc[(timeline-section [timeline authored-timeline?]
                           [section-or-name (or/c symbol? authoring-section?)])
         authoring-section?]{

Resolves a named section, or checks that a supplied section is one of the exact
section values owned by @racket[timeline]. An unknown name and a section taken
from another timeline raise an exception.
}

@defproc[(timeline-section-names [timeline authored-timeline?])
         (listof symbol?)]{

Returns section names in declared authoring order.
}

@defproc[(timeline-section-frame-indices
          [timeline authored-timeline?]
          [section-or-name (or/c symbol? authoring-section?)]
          [#:fps fps exact-positive-integer? 30])
         (listof exact-nonnegative-integer?)]{

Returns the global scene-frame indices whose timestamps lie in the selected
section's half-open interval. At @racket[fps], the result begins at
@racket[(ceiling (* start fps))] and ends before
@racket[(ceiling (* end fps))], clipped to the scene's available output frames.
This is the same grid as a full render, not a new section-relative sampling
grid.
}

@defproc[(timeline-section-frame-count
          [timeline authored-timeline?]
          [section-or-name (or/c symbol? authoring-section?)]
          [#:fps fps exact-positive-integer? 30])
         exact-nonnegative-integer?]{

Returns the length of @racket[timeline-section-frame-indices].
}

@defproc[(timeline-section-cues
          [timeline authored-timeline?]
          [section-or-name (or/c symbol? authoring-section?)])
         (listof cue?)]{

Returns the timeline's cues that lie in the selected section's half-open
interval, in their declared order.
}

@defproc[(authored-timeline-metadata [timeline authored-timeline?])
         immutable?]{

Returns a renderer-independent immutable hash containing the scene duration and
portable section, cue, audio-cue, and subtitle data. The hash intentionally
excludes the scene structure, procedures, renderer caches, and decoded audio.
}

@defproc[(authored-timeline? [value any/c]) boolean?]{
Recognizes an immutable scene together with its authoring metadata.
}

@defproc[(authored-timeline-scene [timeline authored-timeline?]) scene?]{
Returns the ordinary immutable Scene wrapped by @racket[timeline].
}

@subsubsection{Rendering selected frames and authored sections}

@declare-exporting[animate/render #:use-sources (animate/render)]

@defproc[(write-subtitles! [timeline authored-timeline?]
                           [output-file path-string?]
                           [#:format format (or/c 'srt 'webvtt) 'srt])
         path-string?]{

Writes the timeline's subtitles as SRT or WebVTT. It preserves internal caption
line breaks and returns @racket[output-file]. The resulting file can be passed
to either MP4 assembly procedure; FFmpeg muxes it as an MP4 @tt{mov_text}
subtitle stream rather than drawing it into the video pixels.
}

@defproc[(render-frame-indices!
          [scene scene?]
          [frame-indices (listof exact-nonnegative-integer?)]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers pict-renderer-list? default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1])
         (listof path?)]{

Renders selected global frame indices in the supplied order. The output files
are locally numbered from @filepath{frame-000000.png}, which makes the result
directly suitable for @racket[encode-mp4!]. Indices are validated before the
output directory is changed. The camera, renderer, cleanup, worker, and
diagnostic behavior is otherwise the same as @racket[render-frames!].
}

@defproc[(render-frame-indices/report!
          [scene scene?]
          [frame-indices (listof exact-nonnegative-integer?)]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers pict-renderer-list? default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1])
         render-diagnostics?]{

Like @racket[render-frame-indices!], returning normal rendering diagnostics.
The report's paths and per-frame times are ordered by the local output number.
}

@defproc[(render-timeline-section!
          [timeline authored-timeline?]
          [section-or-name (or/c symbol? authoring-section?)]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers pict-renderer-list? default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1]
          [#:cache-key cache-key (or/c false/c 'auto symbol? string?) 'auto]
          [#:asset-files asset-files (listof path-string?) null])
         (listof path?)]{

Renders one named section using its global indices and local output filenames.
The default @racket['auto] key fingerprints the serializable scene value,
section identity/bounds, FPS, camera/renderers, Racket version, and bytes of
the declared @racket[asset-files]. It reuses a matching
@filepath{.animate-section-cache.rktd} manifest only if every expected PNG is
still present. SCENE-DL built-in @racket[rate-function?] values remain
serializable; if an arbitrary procedure is present in the scene representation,
automatic caching is disabled conservatively. An explicit symbol/string remains
available for an author-managed key; @racket[#f] disables caching and removes
any existing section cache manifest. External dependencies are not discovered:
declare them in @racket[asset-files] or use a deliberate explicit key.
}

@defproc[(render-timeline-section/report!
          [timeline authored-timeline?]
          [section-or-name (or/c symbol? authoring-section?)]
          [output-directory path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers pict-renderer-list? default-pict-renderers]
          [#:clean? clean? boolean? #t]
          [#:workers workers exact-positive-integer? 1]
          [#:cache-key cache-key (or/c false/c 'auto symbol? string?) 'auto]
          [#:asset-files asset-files (listof path-string?) null])
         section-render-report?]{

Like @racket[render-timeline-section!], returning a
@racket[section-render-report]. A fresh render contains normal
@racket[render-diagnostics]; a validated cache hit has @racket[#f] diagnostics.
}

@defstruct*[section-render-report
             ([paths (listof path?)]
              [source-frame-indices (listof exact-nonnegative-integer?)]
              [cache-hit? boolean?]
              [diagnostics (or/c false/c render-diagnostics?)])] {

The report for one selected section. @racket[paths] are locally numbered output
paths; @racket[source-frame-indices] records their corresponding global scene
frames. The two lists have the same order and length.
}

@defproc[(automatic-section-cache-key
          [timeline authored-timeline?]
          [section authoring-section?]
          [#:fps fps exact-positive-integer?]
          [#:camera camera (or/c camera? false/c)]
          [#:renderers renderers pict-renderer-list?]
          [#:asset-files asset-files (listof path-string?)])
         (or/c false/c string?)]{

Computes the conservative automatic key used by selected rendering. It returns
@racket[#f] when the scene contains an arbitrary procedure, because its identity
and source cannot be made a reliable content hash. Built-in
@racket[rate-function?] values are represented semantically and remain
cacheable. The public rendering procedures
normally call it themselves; it is exposed for diagnostics or a custom partial
movie workflow.
}

@subsection{Mathematical graphs and networks}

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(graph-vertex [name symbol?]
                       [#:position position (or/c vec2? false/c) #f]
                       [#:label label (or/c string? false/c) #f]
                       [#:partition partition (or/c symbol? false/c) #f])
         graph-vertex?]{

Constructs immutable vertex specification data. A manual graph layout requires
a @racket[#:position] for every vertex. Circle, tree, spring, layered, and
planar layouts replace those positions deterministically. The partite layout
requires a @racket[#:partition] for every vertex. An optional string label
becomes the ordinary child at the vertex's @racket['label] path.
}

@defproc[(graph-vertex? [value any/c]) boolean?]{Recognizes a graph vertex specification.}

@defproc[(graph-edge [source symbol?]
                     [target symbol?]
                     [#:id id (or/c symbol? false/c) #f]
                     [#:label label (or/c string? false/c) #f]
                     [#:weight weight finite-real? 1]
                     [#:curvature curvature (or/c finite-real? false/c) #f]
                     [#:stroke stroke any/c #f]
                     [#:stroke-width stroke-width (or/c finite-real? false/c) #f])
         graph-edge?]{

Constructs one immutable edge specification. Source and target must later name
declared vertices; they may be equal to make a loop. When @racket[#:id] is
omitted, its stable nested identity is formed as @racket[source] followed by
@litchar{->} followed by @racket[target], such as @racket['A->B]. An optional
label follows the sampled straight, cubic, or loop route. @racket[weight] is a
positive finite multiplier for the graph's default stroke width. A nonfalse
@racket[curvature] explicitly selects a signed cubic bow; otherwise the graph
assigns lanes to parallel edges. @racket[stroke] and @racket[stroke-width]
override their graph-wide defaults for this edge.
}

@defproc[(graph-edge? [value any/c]) boolean?]{Recognizes a graph edge specification.}

@defproc[(graph-layout? [value any/c]) boolean?]{
Recognizes one of the supported layout modes: @racket['manual], @racket['circle],
@racket['tree], @racket['spring], @racket['layered], @racket['partite], or
@racket['planar].
}

@defproc[(graph [vertices (listof graph-vertex?)]
                [edges (listof graph-edge?)]
                [#:id id symbol?]
                [#:layout layout graph-layout? 'manual]
                [#:layout-center layout-center vec2? origin]
                [#:layout-radius layout-radius finite-real? 3]
                [#:tree-root tree-root (or/c symbol? false/c) #f]
                [#:tree-x-spacing tree-x-spacing finite-real? 3/2]
                [#:tree-y-spacing tree-y-spacing finite-real? 3/2]
                [#:partite-order partite-order (or/c (listof symbol?) false/c) #f]
                [#:spring-iterations spring-iterations exact-positive-integer? 60]
                [#:spring-attraction spring-attraction finite-real? 1]
                [#:spring-repulsion spring-repulsion finite-real? 1]
                [#:vertex-shape vertex-shape point-marker-shape? 'circle]
                [#:vertex-size vertex-size finite-real? 1/2]
                [#:vertex-fill vertex-fill any/c "aliceblue"]
                [#:vertex-stroke vertex-stroke any/c "navy"]
                [#:vertex-stroke-width vertex-stroke-width finite-real? 2]
                [#:vertex-label-offset vertex-label-offset vec2? (vec2 0 -2/5)]
                [#:vertex-label-size vertex-label-size finite-real? 1/5]
                [#:vertex-label-color vertex-label-color any/c "midnightblue"]
                [#:edge-stroke edge-stroke any/c "slategray"]
                [#:edge-stroke-width edge-stroke-width finite-real? 2]
                [#:edge-curvature edge-curvature finite-real? 0]
                [#:parallel-edge-separation parallel-edge-separation finite-real? 1/3]
                [#:self-loop-radius self-loop-radius finite-real? 4/5]
                [#:edge-label-offset edge-label-offset vec2? (vec2 0 1/5)]
                [#:edge-label-size edge-label-size finite-real? 1/5]
                [#:edge-label-color edge-label-color any/c "darkslategray"])
         group-visual?]{

Creates an undirected graph as one ordinary immutable group tree. It has named
top-level children @racket['edges] and @racket['vertices]. Each vertex is an
ordinary group with @racket['body] and optional @racket['label] children. Each
edge is a group with a derived @racket['line] child and optional derived label.
The normal nested-scene API can therefore target vertices, edges, and labels.

@racket['manual] requires positions in all vertex specifications.
@racket['circle] places declared vertices counter-clockwise from the positive
x axis in list order. @racket['tree] treats edge direction as parent to child:
it requires exactly one fewer edge than vertices, one root without an incoming
edge (or a matching @racket[#:tree-root]), one incoming edge for every other
vertex, and reachability from that root. Sibling order is declared edge order.

SCENE-DP adds deterministic construction-time layouts. @racket['spring] is a
fixed Jacobi force iteration with the supplied positive iteration, attraction,
and repulsion values. @racket['layered] is available only on @racket[digraph]
and requires an acyclic edge relation. @racket['partite] puts the declared
@racket[#:partition] columns in @racket[#:partite-order] or stable first-use
order. @racket['planar] searches for a crossing-free circular outerplanar
embedding, exhaustively through eight vertices.

All dimensions are positive finite reals except the two stroke widths, which
are nonnegative finite reals. @racket[#:edge-curvature],
@racket[#:parallel-edge-separation], and @racket[#:self-loop-radius] control
the derived routes. Vertex and edge labels use the ordinary Pict text backend.
Straight lines are shortened by half a vertex marker size at each endpoint;
this keeps markers and directed arrowheads legible. Distinct sampled endpoints
are required for nonloop edges.
}

@defproc[(digraph [vertices (listof graph-vertex?)]
                  [edges (listof graph-edge?)]
                  [#:id id symbol?]
                  [#:layout layout graph-layout? 'manual]
                  [#:layout-center layout-center vec2? origin]
                  [#:layout-radius layout-radius finite-real? 3]
                  [#:tree-root tree-root (or/c symbol? false/c) #f]
                  [#:tree-x-spacing tree-x-spacing finite-real? 3/2]
                  [#:tree-y-spacing tree-y-spacing finite-real? 3/2]
                  [#:partite-order partite-order (or/c (listof symbol?) false/c) #f]
                  [#:spring-iterations spring-iterations exact-positive-integer? 60]
                  [#:spring-attraction spring-attraction finite-real? 1]
                  [#:spring-repulsion spring-repulsion finite-real? 1]
                  [#:vertex-shape vertex-shape point-marker-shape? 'circle]
                  [#:vertex-size vertex-size finite-real? 1/2]
                  [#:vertex-fill vertex-fill any/c "aliceblue"]
                  [#:vertex-stroke vertex-stroke any/c "navy"]
                  [#:vertex-stroke-width vertex-stroke-width finite-real? 2]
                  [#:vertex-label-offset vertex-label-offset vec2? (vec2 0 -2/5)]
                  [#:vertex-label-size vertex-label-size finite-real? 1/5]
                  [#:vertex-label-color vertex-label-color any/c "midnightblue"]
                  [#:edge-stroke edge-stroke any/c "slategray"]
                  [#:edge-stroke-width edge-stroke-width finite-real? 2]
                  [#:edge-curvature edge-curvature finite-real? 0]
                  [#:parallel-edge-separation parallel-edge-separation finite-real? 1/3]
                  [#:self-loop-radius self-loop-radius finite-real? 4/5]
                  [#:edge-label-offset edge-label-offset vec2? (vec2 0 1/5)]
                  [#:edge-label-size edge-label-size finite-real? 1/5]
                  [#:edge-label-color edge-label-color any/c "darkslategray"])
         group-visual?]{

Like @racket[graph], but each derived line is an ordinary arrow whose direction
is the declared @racket[source] to @racket[target] order. The layout and style
keywords have the same meaning as for @racket[graph].
}

@defproc[(graph-vertex-partition [vertex graph-vertex?]) (or/c symbol? false/c)]{

Returns the vertex's optional partite-layout partition name.
}

@defproc[(graph-edge-weight [edge graph-edge?]) finite-real?]{

Returns the edge's positive stroke-weight multiplier.
}

@defproc[(graph-edge-curvature [edge graph-edge?]) (or/c finite-real? false/c)]{

Returns the optional explicit signed curvature. @racket[#f] selects automatic
parallel-edge routing.
}

@defproc[(graph-edge-stroke [edge graph-edge?]) any/c]{

Returns the optional per-edge stroke override.
}

@defproc[(graph-edge-stroke-width [edge graph-edge?]) any/c]{

Returns the optional per-edge cosmetic stroke-width override.
}

@defproc[(graph-vertices-path [graph-id symbol?]) visual-path?]{

Returns @racket[(list graph-id 'vertices)].
}

@defproc[(graph-edges-path [graph-id symbol?]) visual-path?]{

Returns @racket[(list graph-id 'edges)].
}

@defproc[(graph-vertex-path [graph-id symbol?] [vertex-id symbol?])
         visual-path?]{

Returns @racket[(list graph-id 'vertices vertex-id)], the ordinary target for
operations such as @racket[move-to].
}

@defproc[(graph-edge-path [graph-id symbol?]
                          [edge-or-id (or/c graph-edge? symbol?)])
         visual-path?]{

Returns @racket[(list graph-id 'edges edge-id)], using an edge specification's
stable identity when one is supplied.
}

@defproc[(graph-bfs [edges (listof graph-edge?)]
                    [source symbol?]
                    [#:directed? directed? boolean? #t])
         (listof symbol?)]{

Returns the stable breadth-first vertex visitation order from @racket[source].
The declared edge-list order breaks ties. With @racket[#:directed? #f], every
edge contributes both adjacency directions. This creates no mutation or
animation request.
}

@defproc[(graph-dfs [edges (listof graph-edge?)]
                    [source symbol?]
                    [#:directed? directed? boolean? #t])
         (listof symbol?)]{

Returns the stable depth-first vertex visitation order using declared edge-list
order for neighbours.
}

@defproc[(graph-shortest-path [edges (listof graph-edge?)]
                              [source symbol?]
                              [target symbol?]
                              [#:directed? directed? boolean? #t])
         (or/c (listof symbol?) false/c)]{

Returns one declaration-order tie-broken unweighted shortest path, including
its source and target, or @racket[#f] when no path exists.
}

Graph edge computation is a pure sampled dependency: it reads the current
world positions of its named vertex groups and reconstructs local straight,
cubic, or loop geometry. It therefore works at an arbitrary requested scene
time and does not depend on previously rendered frames. Whole-graph affine
transforms are composed once into both vertices and edges. A graph currently
must be a top-level scene Visual; an outer arbitrary group cannot yet rewrite
the graph's stored endpoint paths.
}

@subsection{MP4 encoding and media assembly}

@declare-exporting[animate/render #:use-sources (animate/render)]

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

@defproc[(assemble-authored-mp4! [timeline authored-timeline?]
                                 [frames-directory path-string?]
                                 [output-file path-string?]
                                 [#:fps fps exact-positive-integer? 30]
                                 [#:subtitle-file subtitle-file
                                                   (or/c false/c path-string?)
                                                   #f])
         path-string?]{

Encodes one locally numbered PNG sequence and applies the authored timeline's
audio cues in the same FFmpeg invocation. Each cue can select a source offset
and duration, apply gain/fades, and delay itself on the output timeline.
When a supplied SRT/WebVTT subtitle file is supplied, it becomes an MP4
@tt{mov_text} stream. The visual sequence must begin at
@filepath{frame-000000.png}; source audio and subtitle files are checked when
this external operation runs.
}

@defproc[(mux-authored-video! [timeline authored-timeline?]
                              [input-video path-string?]
                              [output-file path-string?]
                              [#:subtitle-file subtitle-file
                                                (or/c false/c path-string?)
                                                #f])
         path-string?]{

Applies the same authored audio and captions to an existing visual MP4 without
re-encoding its video stream. It maps the input's visual stream only: any
pre-existing audio in @racket[input-video] is intentionally replaced by the
timeline's mixed audio (or omitted when the timeline has no audio cues).
}

@defproc[(concatenate-mp4! [partial-movies (non-empty-listof path-string?)]
                            [output-file path-string?])
         path-string?]{

Uses FFmpeg's concat demuxer to stream-copy compatible partial MP4 files into
one visual movie. Partials must have matching codecs and stream layout; the
visual-only files made by @racket[encode-mp4!] meet that requirement.
}

@defproc[(render-authored-mp4!
          [timeline authored-timeline?]
          [work-directory path-string?]
          [output-file path-string?]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c camera? false/c) #f]
          [#:renderers renderers pict-renderer-list? default-pict-renderers]
          [#:workers workers exact-positive-integer? 1]
          [#:cache-key cache-key (or/c false/c 'auto symbol? string?) 'auto]
          [#:asset-files asset-files (listof path-string?) null]
          [#:subtitle-file subtitle-file
                            (or/c false/c 'auto path-string?) 'auto]
          [#:subtitle-format subtitle-format (or/c 'srt 'webvtt) 'srt])
         path-string?]{

Renders a complete authored production incrementally. The timeline must have
at least one named section; sorted sections must begin at zero, be contiguous,
and end at the scene duration. Each section is rendered into a stable local
subdirectory of @racket[work-directory]. A valid PNG cache plus matching
partial-MP4 manifest reuses that section's visual movie; an invalidated section
alone is rendered and encoded again. The visual partials are concatenated, then
the final movie receives all authored audio. With the default
@racket['auto] subtitle-file, nonempty timeline subtitles are written below the
work directory in the requested format and muxed automatically. Pass
@racket[#f] to omit captions or a path to use a prewritten file.

Automatic reuse deliberately shares the selected-section cache's conservative
boundary: it fingerprints declared assets but cannot discover arbitrary files,
font/TeX inputs, or an FFmpeg build, and cannot safely hash procedures. Use
@racket[#:asset-files], a versioned explicit key, or @racket[#f] according to
the production's dependency model.
}

@subsection{Project execution}

@declare-exporting[animate/render #:use-sources (animate/render)]

@defproc[(execute-prepared-project!
          [prepared prepared-project?]
          [#:protected-frame-roots protected-frame-roots (listof path?) '()]
          [#:open-after? open-after? boolean? #t])
         project-execution-report?]{

Executes a prepared project through its already normalized frame, cache,
encoder, media, and output plans. Directories are created lazily. The result
records rendered/reused frames and segments, media work, cache events, tools,
warnings, and the atomically installed artifact paths.
}

@defproc[(project-execution-report? [value any/c]) boolean?]{
Recognizes the immutable outcome of a completed project render.
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
 @item{Every identity in a built-in group tree must be a symbol. Direct
       siblings must be distinct, and a group identity must differ from every
       descendant. Equal local identities in separate branches are allowed;
       complete nested paths remain distinct. Custom affine Visuals are treated
       as leaves.}
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
       state. Each built-in group tree requires distinct direct siblings and no
       reuse of an ancestor identity. A custom affine Visual is treated as one
       leaf.}
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
