#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-textured-billboards"]{3D: Textured billboards}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@racket[billboard3d] is the depth-tested spatial counterpart to a projected
label. It is appropriate for a sprite, image annotation, or marker that must
exist in the 3D viewport rather than above it. A billboard image is immutable
straight-ARGB data, so it can be sampled by a render worker and uploaded by an
OpenGL renderer without retaining a GUI @tt{bitmap%} or a renderer-local
texture in the Scene.

@defproc[(billboard-image3d [width exact-positive-integer?]
                             [height exact-positive-integer?]
                             [argb bytes?])
         billboard-image3d?]{Creates an immutable source image. @racket[argb]
contains exactly four bytes per pixel in top-to-bottom straight ARGB order.
The constructor copies the bytes.}
@defproc[(billboard-image3d? [value any/c]) boolean?]{Recognizes a billboard
image source.}
@defproc[(billboard-style3d [#:width width positive? 32]
                             [#:height height (or/c #f positive?) #f]
                             [#:size-mode size-mode (or/c 'screen 'world) 'screen]
                             [#:facing facing (or/c 'camera 'axis) 'camera]
                             [#:axis axis vec3? y-axis3]
                             [#:opacity opacity (real-in 0 1) 1]
                             [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                             [#:depth-bias depth-bias nonnegative-real? 1e-5])
         billboard-style3d?]{Creates an immutable billboard policy. In
@racket['screen] mode, @racket[width] and @racket[height] are output pixels;
in @racket['world] mode they are physical plane dimensions. An omitted height
preserves image aspect ratio. @racket['camera] uses camera image-plane axes;
@racket['axis] keeps @racket[axis] upright and rotates around it toward the
camera. Axis-facing therefore requires world sizing. Depth modes have the same
meaning as @racket[stroke3d]: @racket['test] is normally occluded,
@racket['always] is an overlay, and @racket['hidden] paints only behind opaque
geometry.}
@defproc[(billboard3d [image billboard-image3d?] [position vec3?]
                      [#:id id symbol?]
                      [#:style style billboard-style3d? (billboard-style3d)]
                      [#:transform transform transform3? identity-transform3]
                      [#:opacity opacity (real-in 0 1) 1])
         spatial-visual?]{Creates one immutable spatial billboard. Its child
path is stable, its camera-dependent plane is resolved only during frame
preparation, and transparent texels do not write scene depth.}

The software renderer and the explicit Racket/OpenGL renderer consume the same
prepared corners, depth policy, and ARGB source. The executable probe is
@filepath{examples/3d/textured-billboards.rkt}.

@bold{Billboard limitations:} source images use nearest sampling; a billboard
whose world quad crosses the frustum boundary is conservatively omitted rather
than clipped; partial alpha does not write depth; and billboards do not yet
participate in exact spatial picking or cast/receive shadows. Use
@racket[projected-label] for source-mapped formulas and crisp vector text.

