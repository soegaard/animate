#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-viewports"]{3D: Views inside a Scene}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defproc[(view3d [children (listof spatial-visual?)]
                  [#:id id symbol?]
                  [#:center center vec2? origin]
                  [#:width width positive-real? 12]
                  [#:height height positive-real? 27/4]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale (or/c positive-real? vec2?) 1]
                  [#:opacity opacity (and/c real? (between/c 0 1)) 1]
                  [#:camera camera camera3d? (perspective-camera3d)]
                  [#:lights lights (listof light3d?) null]
                  [#:background background any/c "white"]
                  [#:tone-map tone-map tone-map3d? default-tone-map3d]
                  [#:render-mode render-mode (or/c 'wireframe 'opaque) 'wireframe]
                  [#:transparency-mode transparency-mode
                   (or/c 'object-sorted 'triangle-sorted) 'triangle-sorted])
         view3d?]{
Creates the boundary between a normal two-dimensional Scene and a spatial tree.
Its position, rotation, scale, opacity, and placement act as they do for other
ordinary Visuals. @racket['wireframe] retains the initial clipped-edge adapter.
@racket['opaque] uses a deterministic software triangle renderer: six-plane
frustum clipping, CCW front-face culling (unless a material is double-sided),
pixel-centre rasterization, and a z-buffer. An empty @racket[lights] list uses
a deterministic ambient-plus-directional default. Every explicit light ID must
be distinct. Lights live in the view's immutable frame state, not in its
spatial tree.
When material or effective spatial opacity is below one, transparent triangles
are composited after the opaque depth-writing pass using the selected explicit
sorting mode.
}
@defproc[(view3d? [value any/c]) boolean?]{Recognizes a 2D viewport Visual
containing a spatial tree.}
@defproc[(view3d-children [view view3d?]) (listof spatial-visual?)]{Returns direct spatial children.}
@defproc[(view3d-width [view view3d?]) positive-real?]{Returns local 2D viewport width.}
@defproc[(view3d-height [view view3d?]) positive-real?]{Returns local 2D viewport height.}
@defproc[(view3d-camera [view view3d?]) camera3d?]{Returns the spatial camera.}
@defproc[(view3d-lights [view view3d?]) list?]{Returns immutable light declarations.}
@defproc[(view3d-light-ref [view view3d?] [id symbol?]) light3d?]{Returns the
unique authored light with @racket[id].}
@defproc[(view3d-light-replace [view view3d?] [id symbol?] [replacement light3d?]) view3d?]{
Returns a view with one light replaced. @racket[replacement] must retain
@racket[id].}
@defproc[(view3d-light-update [view view3d?] [id symbol?] [update procedure?]) view3d?]{
Applies an immutable same-ID update to one authored light.}
@defproc[(view3d-background [view view3d?]) any/c]{Returns the opaque viewport background.}
@defproc[(view3d-tone-map [view view3d?]) tone-map3d?]{Returns the immutable
linear-light final output policy.}
@defproc[(view3d-render-mode [view view3d?]) (or/c 'wireframe 'opaque)]{Returns the renderer mode.}
@defproc[(view3d-transparency-mode [view view3d?])
         (or/c 'object-sorted 'triangle-sorted)]{Returns its transparent-pass
ordering policy.}
@defproc[(view3d-spatial-ref [view view3d?] [path spatial-path?]) spatial-visual?]{
Resolves a path rooted with the outer view identity, such as
@racket['(world cube)].
}
@defproc[(view3d-spatial-has? [view view3d?] [path any/c]) boolean?]{Reports
whether a rooted spatial path exists.}
@defproc[(view3d-spatial-replace [view view3d?] [path spatial-path?]
                                  [replacement spatial-visual?]) view3d?]{
Returns a view with one same-identity descendant replaced.}
@defproc[(view3d-spatial-update [view view3d?] [path spatial-path?]
                                 [update procedure?]) view3d?]{
Applies an immutable same-identity update to a descendant.}

