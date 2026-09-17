#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lig-836167a"]{3D: Colour space and final output}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Semantic @racket[rgba-color] values are sRGB: RGB channels use the ordinary
@racket[0] through @racket[255] display encoding and alpha is linear coverage.
Before interpolation, lighting, or source-over composition, an opaque 3D
renderer converts RGB into linear light. It keeps a separate
@racket[linear-rgba3d] value internally because material emission or specular
terms may exceed one without being clipped. At the final output boundary RGB is
tone-mapped, converted back to sRGB, and stored; alpha is preserved unchanged.

@defstruct*[linear-rgba3d ([red nonnegative-real?]
                           [green nonnegative-real?]
                           [blue nonnegative-real?]
                           [alpha (and/c real? (between/c 0 1))]) #:transparent]{
An internal-style straight-alpha linear-light colour. RGB is nonnegative and
may exceed @racket[1] before tone mapping.}
@defproc[(srgb-channel->linear [channel (and/c real? (between/c 0 1))]) real?]{
Applies the IEC 61966-2-1 sRGB transfer curve to one normalized channel.}
@defproc[(linear-channel->srgb [channel (and/c real? (between/c 0 1))]) real?]{
Applies the inverse IEC 61966-2-1 transfer curve to one normalized channel.}
@defproc[(rgba-srgb->linear [color rgba-color?]) linear-rgba3d?]{Converts a
semantic sRGB colour to straight linear light; alpha is unchanged.}
@defproc[(rgba-linear->srgb [color linear-rgba3d?]) rgba-color?]{Converts a
unit-range linear-light value to semantic sRGB. Values above one must first be
passed through @racket[tone-map3d-apply].}
@defproc[(linear-rgba3d-over [source linear-rgba3d?]
                              [destination linear-rgba3d?])
         linear-rgba3d?]{Performs straight-alpha source-over in linear light.}

@defstruct*[tone-map3d ([mode (or/c 'clamp 'reinhard)]
                        [exposure nonnegative-real?]
                        [white-point positive-real?]) #:transparent]{
The immutable final RGB output policy. Exposure multiplies linear RGB before
the selected operator. @racket['clamp] clamps the exposed value to one;
@racket['reinhard] maps an exposed channel @math{x} to
@math{x/(x + white-point)}. The white point is retained for @racket['clamp]
too, so a later mode switch preserves the authored policy.}
@defthing[default-tone-map3d tone-map3d?]{The default
@racket[(tone-map3d 'clamp 1 1)].}
@defproc[(tone-map3d-apply [policy tone-map3d?] [color linear-rgba3d?])
         linear-rgba3d?]{Applies @racket[policy] to RGB only and preserves
alpha exactly.}

@bold{Limitations.} The colour contract covers opaque 3D rendering and its
3D strokes, markers, and billboards. It does not provide ICC profiles,
wide-gamut or display-HDR export, texture colour-space metadata, or guaranteed
linear composition between a rendered @racket[view3d] and arbitrary outer
two-dimensional Picts. Transparency remains order-sorted rather than
order-independent.

The runnable comparison is @filepath{examples/3d/tone-map-emission.rkt}; it
uses strong emission to show the visible difference between the default clamp
policy and Reinhard output.

