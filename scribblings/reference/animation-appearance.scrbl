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

@title[#:tag "reference-animation-appearance"]{Changing color, width, and opacity}

Change appearance without changing the object’s identity.

@declare-exporting[animate #:use-sources (animate/main)]

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
