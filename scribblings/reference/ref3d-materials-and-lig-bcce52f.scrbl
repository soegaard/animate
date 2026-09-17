#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lig-bcce52f"]{3D: Finite-light animation}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-V4 keeps authored lights in the same immutable, random-access
timeline as spatial objects and cameras. A light request names the owning
view and the stable light ID separately; it captures the exact field value at
the start of its local clip. It therefore works as a leaf of @racket[timed],
@racket[succession], @racket[animation-group], @racket[lagged-start], and a
@racket[change-speed] timing curve without a frame-by-frame updater.

@racketblock[
(scene-play
 (scene-add (make-scene) world)
 #:duration 2
 (animation-group
  (point-light3d-move-by 'world 'lamp (vec3 2 0 0))
  (spot-light3d-aim-at 'world 'spot origin3)
  (light3d-intensity-to 'world 'key 3)))
]

@defproc[(light3d-intensity-to [view-id symbol?] [light-id symbol?]
                               [intensity nonnegative-real?]) any/c]{
Interpolates one light's nonnegative intensity from its clip-start value.}
@defproc[(light3d-color-to [view-id symbol?] [light-id symbol?]
                           [color any/c]) any/c]{Interpolates one opaque light
colour in linear light, then encodes the sampled colour back to sRGB.}
@defproc[(point-light3d-move-to [view-id symbol?] [light-id symbol?]
                                [position vec3?]) any/c]{Moves a point light
to an absolute position.}
@defproc[(point-light3d-move-by [view-id symbol?] [light-id symbol?]
                                [delta vec3?]) any/c]{Moves a point light by
@racket[delta] from its clip-start position.}
@defproc[(spot-light3d-move-to [view-id symbol?] [light-id symbol?]
                               [position vec3?]) any/c]{Moves a spot light to
an absolute position.}
@defproc[(spot-light3d-aim-at [view-id symbol?] [light-id symbol?]
                              [target vec3?]) any/c]{Interpolates a spot
direction toward the clip-start position's direction to @racket[target].
Direction vectors use normalized vector interpolation; near a half-turn, a
deterministic quaternion interpolation avoids the zero-vector singularity.}
@defproc[(spot-light3d-cone-to [view-id symbol?] [light-id symbol?]
                               [inner-angle nonnegative-real?]
                               [outer-angle positive-real?]) any/c]{
Interpolates a spot's inner and outer cone angles while retaining the required
@math{0 <= inner <= outer <= pi} invariant.}

@bold{Current limitation.} V4 defines and samples the exposed light values.
Both V5's software renderer and V6's OpenGL renderer make finite illumination
visible, but attenuation, range, and the reserved shadow descriptor are not
animatable in this stage.

