#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-clipping-sections-ae6e276"]{3D: Clipping, sections, and transparency}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Render clipping and geometric slicing are distinct operations.
@racket[clip3d] keeps its source subtree intact and clips only the triangles
submitted to a @racket[view3d] renderer. @racket[slice-mesh3d] instead returns
new half-space mesh geometry; it deliberately does not invent a cap. Use
@racket[section-by-plane3d] for the actual plane intersection and
@racket[section-curve3d] to draw every loop or open chain as ordinary spatial
curves.

@defproc[(clip-plane3d [plane plane3?]
                        [#:keep keep (or/c 'positive 'negative) 'positive])
         clip-plane3d?]{Describes the retained half-space of a clipping plane.}
@defproc[(clip-plane3d? [value any/c]) boolean?]{Recognizes a clipping-plane
description.}
@defproc[(clip3d [content spatial-visual?]
                  [clip (or/c plane3? clip-plane3d?)]
                  [#:id id symbol?])
         clip3d?]{Wraps one spatial subtree with local render-only clipping.}
@defproc[(clip3d? [value any/c]) boolean?]{Recognizes a render-clip wrapper.}
@defproc[(slice-mesh3d [mesh mesh3d?]
                        [clip (or/c plane3? clip-plane3d?)])
         mesh3d?]{Returns actual, deterministically triangulated clipped mesh
geometry in the source mesh's local coordinates. Generated cut vertices reuse
one source-edge registry and therefore interpolate the supported per-vertex
normal and RGBA colour attributes consistently across neighbouring triangles.}
@defproc[(vertex-color-lerp [first color-spec?] [second color-spec?]
                            [amount finite-real?])
         color-spec?]{Interpolates one mesh colour attribute in encoded-sRGB
components with straight alpha. It is the spatial-attribute convention used by
mesh slicing and deliberately differs from @racket[color-mix]'s default
linear-light, premultiplied authoring blend. Tokens remain unresolved until a
render context is selected.}
@defproc[(slice-mesh-by-planes3d [mesh mesh3d?]
                                  [clips (listof (or/c plane3? clip-plane3d?))])
         mesh3d?]{Applies plane cuts in declaration order to produce actual
geometry. This is not @racket[clip-planes3d], which remains render-only.}
@defproc[(section-by-plane3d [mesh mesh3d?]
                              [clip (or/c plane3? clip-plane3d?)])
         section3d?]{Returns deterministic @racket[section3d] topology. Its
@racket[section3d-loops] and @racket[section3d-chains] accessors distinguish
closed components from open ones.}
@defproc[(section3d? [value any/c]) boolean?]{Recognizes plane-section
topology.}
@defproc[(section3d-loops [section section3d?]) (listof (listof vec3?))]{Returns
its closed components in deterministic plane orientation.}
@defproc[(section3d-chains [section section3d?]) (listof (listof vec3?))]{Returns
its open components in deterministic endpoint order.}
@defproc[(section-curve3d [mesh mesh3d?]
                           [clip (or/c plane3? clip-plane3d?)]
                           [#:id id symbol?])
         group3d?]{Builds a group of physical-radius tube curves for every
section component.}

@racket[material3d] accepts an alpha-bearing semantic colour. In an opaque
@racket[view3d], fully opaque geometry writes the depth buffer first; transparent
geometry is then rendered far-to-near with @racket['object-sorted] or
@racket['triangle-sorted] @racket[#:transparency-mode]. Transparent triangles
depth-test against opaque geometry but do not write depth. A
@racket[projected-label] accepts @racket[#:occlusion 'always-visible],
@racket['hide], or @racket['fade]; its occlusion test uses that opaque depth
target, preserving the label as a crisp 2D Visual.

