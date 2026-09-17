#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-polygonal-da981bf"]{3D: Polygonal faces}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[polyhedral-plane3d
            ([normal vec3?] [offset finite-real?]) #:transparent]{A transformed
unit-normal plane with equation @racketidfont{normal . point = offset}.}
@defstruct*[polyhedral-source-face-id3d
            ([triangle-index exact-nonnegative-integer?]) #:transparent]{The
transparent generated identity of an automatically grouped face. It names the
least source triangle rather than hiding provenance in a hash string.}
@defstruct*[polyhedral-face-declaration3d
            ([id symbol?] [triangle-indices (or/c vector? list?)]) #:transparent]{An
explicit polygonal face declaration. All declarations together must partition
the mesh's source triangles exactly once.}
@defstruct*[polyhedral-face3d
            ([id any/c] [triangle-indices vector?]
             [boundary-vertex-indices (or/c #f vector?)]
             [normal (or/c #f vec3?)] [plane (or/c #f polyhedral-plane3d?)]
             [centroid (or/c #f vec3?)] [area nonnegative-real?]
             [provenance hash?]) #:transparent]{One mathematical polygonal face
over one or more render triangles. A simple boundary is a cyclic immutable
vertex-index vector. It is @racket[#f] when the region has multiple loops,
branches, or repeated boundary vertices; the enclosing complex retains the
diagnostic rather than choosing a false polygon.}
@defproc[(polyhedral-complex3d [mesh mesh3d?]
                                [#:faces faces any/c #f]
                                [#:coplanar-angle angle nonnegative-real? 1e-7]
                                [#:plane-distance distance nonnegative-real? 1e-7])
         polyhedral-complex3d?]{Builds an immutable mathematical-face complex.
With @racket[#:faces #f] (the default) or @racket['coplanar], it merges only
edge-connected, consistently oriented render triangles whose world-space planes
agree within the stated angle (in radians) and distance tolerances. The source
mesh is retained for provenance; all mathematical calculations use an immutable
world-space analysis mesh with an identity transform.

Use @racket['triangles] to retain every render triangle as a face. An explicit
partition is a list/vector of @racket[polyhedral-face-declaration3d] values or
concise @racket[(face-id triangle-index ...)] lists; explicit declarations
always override automatic merging.}
@defproc[(polyhedral-complex3d? [value any/c]) boolean?]{Recognizes a
polygonal-face complex.}
@defproc[(polyhedral-complex3d-source-mesh [complex polyhedral-complex3d?]) mesh3d?]{Returns
the unchanged authored mesh whose stable part identities are the source of the
complex's provenance.}
@defproc[(polyhedral-complex3d-analysis-mesh [complex polyhedral-complex3d?]) mesh3d?]{Returns
the immutable world-space mesh used for planes, topology, duals, Schlegel
diagrams, and nets. Its local transform is @racket[identity-transform3]. A
reflected source transform is baked with reversed triangle winding so geometric
normals remain consistent.}
@defproc[(polyhedral-complex3d-source-transform [complex polyhedral-complex3d?]) transform3?]{Returns
the authored local-to-world transform recorded before analysis-space baking.}
@defproc[(polyhedral-complex3d-mesh [complex polyhedral-complex3d?]) mesh3d?]{Returns
the analysis mesh. New code should use @racket[polyhedral-complex3d-source-mesh]
or @racket[polyhedral-complex3d-analysis-mesh] to state which coordinate space
it needs.}
@defproc[(polyhedral-complex3d-topology [complex polyhedral-complex3d?]) mesh-topology3d?]{Returns
the U-1 triangle topology used to build the complex.}
@defproc[(polyhedral-complex3d-faces [complex polyhedral-complex3d?]) vector?]{Returns
faces in deterministic least-source-triangle order.}
@defproc[(polyhedral-complex3d-edge-to-faces [complex polyhedral-complex3d?]) vector?]{Returns
one immutable polygonal-face-index vector per topological edge. A render
diagonal inside a grouped square has one incident polygonal face.}
@defproc[(polyhedral-complex3d-vertex-to-faces [complex polyhedral-complex3d?]) vector?]{Returns
one immutable polygonal-face-index vector per source vertex.}
@defproc[(polyhedral-complex3d-diagnostics [complex polyhedral-complex3d?]) hash?]{Returns
the construction mode, tolerances, inherited triangle-topology diagnostics, and
per-face boundary reports. @racket['invalid-face-indices] identifies regions
that are not simple polygons.}

@bold{Limitations.} U-2 groups only existing triangles; it neither repairs
nonmanifold/self-intersecting input nor creates a polygonal approximation. A
region with holes is retained and diagnosed, but does not yet expose a usable
multi-loop polygon. Hole triangulation, duals, Schlegel diagrams, nets, and
face-transform animation are later U stages.

