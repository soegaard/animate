#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-schlegel-d-6fdb2d3"]{3D: Schlegel diagrams and polyhedral nets}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[schlegel-diagram3d-data
            ([outer-face any/c] [viewpoint vec3?] [plane plane3?]
             [vertex-positions vector?] [edges vector?] [face-polygons vector?]
             [mappings hash?] [diagnostics hash?]) #:transparent]{Prepared
Schlegel-projection data. The diagnostics retain the deterministic outer face,
canonical target-plane basis, margin, and viewpoint distance.}
@defproc[(prepare-schlegel-diagram3d [complex polyhedral-complex3d?]
                                     [#:outer-face selector any/c #f]
                                     [#:viewpoint-distance distance positive-real? 3]
                                     [#:margin margin nonnegative-real? 1/20]
                                     [#:tolerance tolerance nonnegative-real? 1e-8])
         schlegel-diagram3d-data?]{Projects a selected simple outer face into a
canonical plane. It rejects projections whose inner vertices do not lie in the
outer polygon instead of returning a misleading diagram.}
@defproc[(schlegel-diagram3d [data schlegel-diagram3d-data?]
                             [#:id id symbol? 'schlegel]
                             [#:color color any/c "slateblue"]
                             [#:width width positive-real? 2])
         spatial-visual?]{Builds the flat 3D edge visual from prepared data.}

@defstruct*[net-overlap3d
            ([first-face exact-nonnegative-integer?]
             [second-face exact-nonnegative-integer?]
             [area nonnegative-real?]
             [boundary-crossings exact-nonnegative-integer?])
            #:transparent]{A positive-area pairwise overlap in root-plane
coordinates. Sharing only a hinge boundary has zero area and therefore does not
produce this record.}
@defstruct*[net-hinge3d
            ([parent exact-nonnegative-integer?] [child exact-nonnegative-integer?]
             [primal-edge exact-nonnegative-integer?]) #:transparent]{One
oriented parent-to-child hinge in a face-adjacency spanning tree.}
@defstruct*[net-face-transform3d
            ([face exact-nonnegative-integer?] [source-origin vec3?]
             [source-e vec3?] [source-f vec3?] [source-n vec3?]
             [target-origin vec3?] [target-e vec3?] [target-f vec3?]
             [target-n vec3?]) #:transparent]{An orientation-preserving rigid
frame from a source face to the net's root plane.}
@defstruct*[polyhedron-net3d
            ([root-face exact-nonnegative-integer?] [hinge-tree vector?]
             [cut-edges vector?] [face-transforms vector?] [flat-polygons vector?]
             [overlaps vector?] [diagnostics hash?]) #:transparent]{Prepared
net data. @racket[diagnostics] records strategy, search completion, selected
tree edges, overlap total, boundary crossings, and flat-net diameter.}
@defproc[(prepare-polyhedron-net3d [complex polyhedral-complex3d?]
                                   [#:root-face root exact-nonnegative-integer? 0]
                                   [#:hinges hinges (or/c #f (listof exact-nonnegative-integer?)) #f]
                                   [#:strategy strategy (or/c 'breadth-first 'depth-first 'minimum-overlap) 'breadth-first]
                                   [#:search-limit limit exact-positive-integer? 1000])
         polyhedron-net3d?]{Prepares a rigid flat net. Explicit @racket[hinges]
must form a connected spanning tree. The automatic breadth/depth policies use
source edge order. @racket['minimum-overlap] enumerates candidate trees in that
order and minimizes total positive overlap area, then boundary crossings and
flat-net diameter. When its bounded search is truncated,
@racket[(hash-ref (polyhedron-net3d-diagnostics result) 'search-complete?)] is
false and no optimality claim is made.}

@defproc[(polyhedron-net3d-face-child-ids [net polyhedron-net3d?]) vector?]{
Returns one stable direct-child symbol per polygonal face, in face-index order.
An explicit polygonal face identity is retained, so face @racket['front] is a
child at @racket['(net front)]; generated faces use deterministic
@racket['face-N] identities.}
@defproc[(polyhedron-net3d-group [complex polyhedral-complex3d?]
                                 [net polyhedron-net3d?]
                                 [#:id id symbol?]
                                 [#:face-materials materials (or/c #f vector?) #f])
         group3d?]{Creates the canonical group of independent mesh children
for a prepared net. @racket[materials], when present, has one @racket[material3d]
per face and is useful for making a net's face boundaries visually legible.}
@defproc[(polyhedron-net3d-sample-transforms [net polyhedron-net3d?]
                                             [progress (real-in 0 1)])
         vector?]{Returns the source-to-sampled local transform for every
canonical face child. Interior samples recursively rotate each child around its
source hinge and inherit its parent's current rigid map; the root stays fixed.
The endpoints use exact identity and prepared-flat transforms.}
@defproc[(unfold-polyhedron3d [target spatial-path?] [net polyhedron-net3d?])
         any/c]{Returns a @racket[scene-play] request that unfolds the direct
face children below @racket[target].}
@defproc[(fold-polyhedron3d [target spatial-path?] [net polyhedron-net3d?])
         any/c]{Returns the inverse request. It requires the exact flattened
endpoint produced by @racket[unfold-polyhedron3d], and returns the exact source
transforms.}

The canonical runnable demonstration is
@filepath{examples/3d/fold-unfold-polyhedron.rkt}.

@bold{Limitations.} Net faces must be simple polygonal faces. The overlap
kernel handles simple concave polygons by deterministic ear triangulation, but
does not repair self-intersection or hole boundaries. Fold/unfold presently
requires the independent, identity-local-transform face meshes made by
@racket[polyhedron-net3d-group]; it does not yet retarget arbitrary authored
mesh trees, animate labels/strokes with their faces, sequence hinges to avoid
intermediate collisions, or solve a global collision-free folding path.

