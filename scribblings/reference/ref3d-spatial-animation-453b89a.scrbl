#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-animation-453b89a"]{3D: Animating 3D objects}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-D keeps three-dimensional motion in the ordinary immutable
@racket[scene] timeline. A spatial target is a path beginning with its owning
@racket[view3d] identifier, for example @racket['(world cube)]. A camera target
is the owning view identifier alone, for example @racket['world]. Every request
captures its endpoint from the clip-start state. Sampling at a time does not
depend on having sampled an earlier frame.

@racketblock[
(scene-play
 (scene-add (make-scene) world matrix)
 (rotate3d-by '(world cube) (axis-angle y-axis3 pi))
 (camera3d-orbit-by 'world #:azimuth (/ pi 2))
 #:duration 2)
]

@defproc[(move3d-to [path spatial-path?] [position vec3?]) any/c]{Moves one
spatial Visual to an absolute local translation.}
@defproc[(move3d-by [path spatial-path?] [delta vec3?]) any/c]{Moves one
spatial Visual by a local translation from its clip-start value.}
@defproc[(rotate3d-to [path spatial-path?] [rotation rotation3?]) any/c]{Sets
an absolute local orientation.}
@defproc[(rotate3d-by [path spatial-path?] [rotation rotation3?]) any/c]{Applies
a local rotation after the clip-start orientation.}
@defproc[(scale3d-to [path spatial-path?] [scale vec3?]) any/c]{Sets a
nonzero componentwise local scale.}
@defproc[(scale3d-by [path spatial-path?] [factor vec3?]) any/c]{Multiplies
the clip-start componentwise local scale.}
@defproc[(transform3d-to [path spatial-path?] [transform transform3?]) any/c]{
Sets translation, rotation, and scale together. A scale interpolation that
would pass through zero is rejected when the clip is compiled.}

