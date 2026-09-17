#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-cameras-and-projection"]{3D: Cameras and projection}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


A camera's local @racket[x] axis is screen-right, local @racket[y] is
screen-up, and local negative @racket[z] is forward. A default camera is at
@racket[(vec3 0 0 8)] and looks at @racket[origin3]. The camera is reusable:
viewport aspect is supplied when projecting or rendering, rather than stored in
the camera.

@defstruct*[perspective-projection3d ([vertical-field-of-view finite-real?])
  #:transparent]{A perspective projection measured in radians.}
@defstruct*[orthographic-projection3d ([vertical-size positive-real?])
  #:transparent]{An orthographic projection with the stated visible vertical
size.}
@defproc[(perspective-camera3d [#:position position vec3? (vec3 0 0 8)]
                               [#:look-at target vec3? origin3]
                               [#:up up vec3? y-axis3]
                               [#:rotation rotation (or/c #f rotation3?) #f]
                               [#:near near positive-real? 1/10]
                               [#:far far positive-real? 100]
                               [#:vertical-field-of-view field-of-view finite-real? (/ pi 4)])
         camera3d?]{Creates a perspective camera. An explicit rotation wins
over the look-at fields.}
@defproc[(orthographic-camera3d [#:position position vec3? (vec3 0 0 8)]
                                [#:look-at target vec3? origin3]
                                [#:up up vec3? y-axis3]
                                [#:rotation rotation (or/c #f rotation3?) #f]
                                [#:near near positive-real? 1/10]
                                [#:far far positive-real? 100]
                                [#:vertical-size size positive-real? 6])
         camera3d?]{Creates a parallel orthographic camera.}
@defproc[(camera3d? [value any/c]) boolean?]{Recognizes an immutable camera.}
@defproc[(camera3d-position [camera camera3d?]) vec3?]{Returns its world position.}
@defproc[(camera3d-rotation [camera camera3d?]) rotation3?]{Returns camera-local axes in world coordinates.}
@defproc[(camera3d-near [camera camera3d?]) positive-real?]{Returns nearest visible forward depth.}
@defproc[(camera3d-far [camera camera3d?]) positive-real?]{Returns farthest visible forward depth.}
@defproc[(camera3d-projection [camera camera3d?]) (or/c perspective-projection3d? orthographic-projection3d?)]{Returns its lens.}
@defproc[(camera3d-forward [camera camera3d?]) vec3?]{Returns world-space local negative z.}
@defproc[(camera3d-right [camera camera3d?]) vec3?]{Returns world-space local positive x.}
@defproc[(camera3d-up [camera camera3d?]) vec3?]{Returns world-space local positive y.}
@defproc[(camera3d-look-at [camera camera3d?] [target vec3?]
                           [#:up up vec3? y-axis3]) camera3d?]{Returns an
immutable reorientation toward @racket[target].}
@defproc[(camera3d-world->view [camera camera3d?] [point vec3?]) vec3?]{
Converts a world point to camera coordinates; visible forward points have
negative z.}
@defproc[(camera3d-view-depth [camera camera3d?] [point vec3?]) finite-real?]{
Returns positive depth along the camera's forward axis.}
@defproc[(camera3d-project [camera camera3d?] [point vec3?]
                           [#:aspect aspect positive-real? 1])
         (or/c #f vec2?)]{
Projects to normalized viewport coordinates. It returns @racket[#f] behind the
camera or outside the inclusive near/far interval.
}
@defproc[(camera3d-pixel-ray [camera camera3d?] [pixel-x finite-real?]
                             [pixel-y finite-real?]
                             [#:width width exact-positive-integer?]
                             [#:height height exact-positive-integer?]) ray3?]{
Returns a world ray through a top-left-origin pixel coordinate.}
@defproc[(camera3d-frustum [camera camera3d?]
                           [#:aspect aspect positive-real? 1]) vector?]{
Returns immutable inward-facing near, far, left, right, bottom, and top planes.}

