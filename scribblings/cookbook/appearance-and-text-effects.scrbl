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


@title[#:tag "cookbook-appearance-and-text-effects"]{Combining Appearance and Text Effects}

Combine entrance, exit, text, and style effects without mixing their animation components.

API reference: @secref["reference-animation-enter-leave"], @secref["reference-animation-appearance"].

@local-table-of-contents[]

@; recipe-redistribution begin: effects-cookbook
@section[#:tag "effects-cookbook"]{Composing Exact Enter/Leave and Text Effects}

The effects vocabulary is ordinary scene composition, so it has no playback
history: sampling a frame directly has the same result as reaching it through
Play. Use @racket[enter] to install a new affine Visual from a relative
appearance, and @racket[leave] to remove a resolved Visual through the paired
relative appearance. The final endpoints are exact: @racket[enter] retains the
author's original Visual, while the default @racket[leave] removes its target.

@racketblock[
(define card
  (rectangle #:id 'card #:width 3 #:height 2 #:fill "gold" #:stroke "sienna"))

(scene-play
 (scene-add (make-scene) card)
 (succession
  (pulse 'card #:scale-factor 6/5)
  (leave 'card #:translation-offset (vec2 0 1) #:opacity-factor 0))
 #:duration 2)
]

For text, @racket[typewrite] accepts a complete @racket[rich-text] Visual and
reveals its final measured layout by grapheme, word, line, or span. Rich spans
and wrapped paragraphs therefore keep their final line breaks while the effect
advances. The current Pict renderer rejects interior samples for rotated or
non-unit-scale text instead of reflowing a transformed prefix. See
@filepath{examples/typewriter-and-decorations.rkt} for a complete renderable
example, and @filepath{tools/benchmark-fx.rkt} for the non-gating rich-text
preparation measurement.


@; recipe-redistribution end: effects-cookbook

@; recipe-redistribution begin: stroke-width-animation
@section[#:tag "stroke-width-animation"]{Stroke-Width Animation}

Stroke width is a renderer-independent semantic animation component. Built-in stroke-bearing Visuals implement
@racket[gen:stroke-width-visual], and @racket[stroke-width-to] animates the
component through the same request compiler and schedule tree used by movement,
opacity, path morphing, and animation composition.

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

Render the canonical stroke-width example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/animating-stroke-width.rkt \
  frames/animating-stroke-width \
  animating-stroke-width.mp4

open animating-stroke-width.mp4
}


@; recipe-redistribution end: stroke-width-animation

@; recipe-redistribution begin: color-animation
@section[#:tag "color-animation"]{Fill and Stroke Color Animation}

Fill and stroke color are independent semantic style-animation components. Existing color strings remain exact style values. During an interior
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
for fill color and stroke color after composition expansion. Touching
sequential changes compile from the exact prior color specification.

The semantic layer does not import @racketmodname[racket/draw]. The built-in Pict
adapter converts @racket[rgba-color] values to drawing colors only immediately
before rendering. This preserves deterministic arbitrary-time sampling and keeps
third-party semantic Visuals independent of a particular renderer.

A current @racket[#f] fill or stroke means paint is absent rather than a color;
The color-animation API deliberately does not turn paint presence into an
interpolated style component. Use an actual color such as @tt{transparent} when alpha interpolation
is desired while retaining a color endpoint. Scatter-plot marker children remain
nested inside their group and are not individually targetable, and callout
connector paint remains separate frame-space style. Custom color setters are
validated for exact endpoint installation, including exact/inexact channel
representation inside @racket[rgba-color].

Render the canonical color-animation example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/animating-colors.rkt \
  frames/animating-colors \
  animating-colors.mp4

open animating-colors.mp4
}


@; recipe-redistribution end: color-animation

@; recipe-redistribution begin: unified-style-animation
@section[#:tag "unified-style-animation"]{Unified Style Transitions}

@racket[style-to] is compact composition syntax for the fill color, stroke
color, stroke width, and opacity animation components.

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

Render the canonical unified-style example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/unified-style-transitions.rkt \
  frames/unified-style-transitions \
  unified-style-transitions.mp4

open unified-style-transitions.mp4
}



@; recipe-redistribution end: unified-style-animation
