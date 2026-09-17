#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lig-78e41df"]{3D: Software finite-light evaluation}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-V5 evaluates point and spot lights per software-rasterized fragment.
The rasterizer perspective-correctly interpolates camera-space positions and
normals, transforms authored finite lights into that camera space once per
prepared frame, and accumulates the authored light list in its declared order.
For a point source it applies the named attenuation and optional range. For a
spot it additionally applies the named smoothstep cone from the outward light
direction. These factors multiply both the Lambert diffuse and the
Blinn--Phong specular terms; material emission remains independent of lights.

Double-sided materials use their interpolated outward normal for a front face
and flip that normal toward the viewing side for a back face. This is a fixed
illustration policy, rather than an inferred rendering accident.

@bold{Current limitation.} The software path is the deterministic conformance
reference. The OpenGL path evaluates matching finite-light records and V9
directional/spot shadow maps, but it has fixed four-directional/eight-point/
four-spot light limits and no separate persistent finite-light buffer cache.
Point/spot attenuation, range, and cone values are fixed during a V4 animation
clip; only the exposed light fields are animated.

