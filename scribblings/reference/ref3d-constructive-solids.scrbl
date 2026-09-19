#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-constructive-solids"]{3D: Constructive solids}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Solid constructors create deterministic indexed meshes. The standard constructors
and regular-polyhedron constructors return ordinary @racket[mesh3d] values. Their tessellation parameters are
part of the authored immutable value, not a renderer decision.

@defproc[(cube3d [side finite-real?] [#:id id symbol?]) mesh3d?]{Creates a cube.}
@defproc[(box3d [width finite-real?] [height finite-real?] [depth finite-real?]
                 [#:id id symbol?]) mesh3d?]{Creates an axis-aligned box.}
@defproc[(prism3d [sides exact-positive-integer?] [#:id id symbol?]) mesh3d?]{Creates a regular prism.}
@defproc[(sphere3d [radius finite-real?] [#:id id symbol?]) mesh3d?]{Creates a latitude-longitude sphere.}
@defproc[(cylinder3d [radius finite-real?] [height finite-real?] [#:id id symbol?]) mesh3d?]{Creates a cylinder.}
@defproc[(cone3d [radius finite-real?] [height finite-real?] [#:id id symbol?]) mesh3d?]{Creates a cone.}
@defproc[(torus3d [major-radius finite-real?] [minor-radius finite-real?] [#:id id symbol?]) mesh3d?]{Creates a torus.}

@defproc[(extrude3d [contour (listof vec2?)] [#:id id symbol?]
                     [#:vector direction vec3?]) mesh3d?]{Extrudes one simple
closed xy-plane contour through a noncoplanar vector.  Caps use deterministic
ear clipping.}
@defproc[(revolve3d [profile (listof vec2?)] [#:id id symbol?]
                     [#:axis axis (or/c 'x 'y 'z) 'z]) mesh3d?]{Revolves a
nonnegative-radius profile around an axis.}
@defproc[(sweep3d [profile (listof vec2?)] [curve curve3d?]
                   [#:id id symbol?]) mesh3d?]{Sweeps a simple profile along a
sampled curve using a direct parallel-transport frame.}
@defproc[(mesh3d-smooth-normals [mesh mesh3d?]) mesh3d?]{Computes stable
area-weighted shared-vertex normals while retaining every semantic part ID.}
@defproc[(mesh3d-flat-normals [mesh mesh3d?]) mesh3d?]{Duplicates face vertices
so every triangle receives one normal. Triangle face IDs remain one-to-one;
vertex and edge ID vectors are deliberately absent because their parts have
been split into new representation corners.}
@defproc[(mesh3d-boundary-edges [mesh mesh3d?]) vector?]{Reports its
deterministically ordered manifold boundary edges.}

An example is @filepath{examples/3d/solid-of-revolution.rkt}.

