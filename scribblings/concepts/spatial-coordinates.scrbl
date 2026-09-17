#lang scribble/manual
@(require (for-label racket/base racket/math animate/3d))

@title[#:tag "spatial-coordinates"]{Three-dimensional coordinates}

A 3D object has local coordinates, just as a 2D object does. A spatial transform
places it in the 3D world. A 3D camera projects that world into a 2D viewport.

A @racket[view3d] is an ordinary 2D Visual containing that viewport. It can appear
beside text or inside a larger Scene. You do not need a second video timeline.

@section{The axes}

The coordinate system is right-handed. The named unit vectors are
@racket[x-axis3], @racket[y-axis3], and @racket[z-axis3]. Their orientation is
specified by @racket[(vec3-cross x-axis3 y-axis3)], which is @racket[z-axis3].
The origin is @racket[origin3]. A point from the 2D xy plane becomes
@racket[(vec3 x y 0)].

What appears left, right, near, or far in the picture also depends on the camera.
The world axes do not change when the camera moves.

@section{Scale, rotate, then move}

An author-facing transform applies its scale first, then its rotation, then its
translation:

@racketblock[
(define placement
  (make-transform3
   #:translation (vec3 4 0 0)
   #:rotation (axis-angle z-axis3 (/ pi 2))
   #:scale (vec3 2 2 2)))
(transform3-apply-point placement (vec3 1 0 0))]

Here the point is doubled, rotated a quarter-turn, and moved four units in x.
Composing nonuniform scales and rotations can also produce shear. That is why
@racket[transform3-compose] returns an @racket[affine3] map instead of discarding
that part of the result.

@section{Geometry and drawing are separate}

Meshes, spatial trees, cameras, and transforms are data. The renderer draws them
at a requested time. The software renderer is the default. The optional OpenGL
backend has its own environment requirements and rendering limits.

Do not use a chapter about coordinates as a capability checklist. The 3D API
entries in @secref["part-reference"] describe supported geometry, lighting,
transparency, picking, prepared trajectories, and backend restrictions. Changes
to those features do not change the coordinate conventions above.
