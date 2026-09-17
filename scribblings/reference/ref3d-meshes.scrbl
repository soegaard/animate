#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes"]{3D: Meshes}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defproc[(mesh3d [#:id id symbol?]
                  [#:vertices vertices vector?]
                  [#:triangles triangles vector? #()]
                  [#:edges edges (or/c #f vector?) #f]
                  [#:vertex-ids vertex-ids (or/c #f vector?) #f]
                  [#:edge-ids edge-ids (or/c #f vector?) #f]
                  [#:face-ids face-ids (or/c #f vector?) #f]
                  [#:normals normals (or/c #f vector?) #f]
                  [#:colors colors (or/c #f vector?) #f]
                  [#:material material material3d?]
                  [#:transform transform transform3? identity-transform3]
                  [#:opacity opacity (and/c real? (between/c 0 1)) 1]
                  [#:wireframe-color color any/c "steelblue"]
                  [#:wireframe-width width positive-real? 2])
         mesh3d?]{
Creates an immutable indexed mesh. Vertices are @racket[vec3] values. Triangles
are vectors of three valid vertex indices and edges are vectors of two valid
indices. Inputs are copied to immutable vectors. When @racket[edges] is
@racket[#f], a stable de-duplicated edge list is derived from triangles.

In @racket['wireframe] mode the stable edge order remains visible. In
@racket['opaque] mode triangles are flattened in declared order, clipped,
depth-tested, and shaded with @racket[material]. Flat and smooth materials use
the declared face or interpolated vertex normals respectively; per-vertex
colours are interpolated perspective-correctly. Material, wireframe, and
per-vertex colours are @racket[color-spec?] values, so literals, theme roles,
and colour expressions remain part of the immutable mesh and resolve together
when a renderer prepares a frame.

Optional semantic ID vectors are immutable vectors of unique symbols, aligned
with vertices, edges, and declared triangle faces respectively. They describe
author-visible mathematical parts, not GPU geometry. A symbol may appear in
more than one kind because the part kind distinguishes it. Omit a vector to
use the stable numeric source indices rather than manufacturing names.
}
@defproc[(mesh3d? [value any/c]) boolean?]{Recognizes an immutable indexed mesh.}
@defproc[(mesh3d-vertices [mesh mesh3d?]) vector?]{Returns immutable vertices.}
@defproc[(mesh3d-triangles [mesh mesh3d?]) vector?]{Returns immutable triangle indices.}
@defproc[(mesh3d-edges [mesh mesh3d?]) vector?]{Returns immutable wireframe edge indices.}
@defproc[(mesh3d-vertex-ids [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable semantic vertex IDs.}
@defproc[(mesh3d-edge-ids [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable semantic edge IDs.}
@defproc[(mesh3d-face-ids [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable semantic triangle-face IDs.}
@defproc[(mesh3d-vertex-id [mesh mesh3d?] [index exact-nonnegative-integer?])
         (or/c symbol? exact-nonnegative-integer?)]{Returns the explicit vertex
semantic ID or, if absent, its stable source index.}
@defproc[(mesh3d-edge-id [mesh mesh3d?] [index exact-nonnegative-integer?])
         (or/c symbol? exact-nonnegative-integer?)]{Returns the explicit edge
semantic ID or, if absent, its stable source index.}
@defproc[(mesh3d-face-id [mesh mesh3d?] [index exact-nonnegative-integer?])
         (or/c symbol? exact-nonnegative-integer?)]{Returns the explicit face
semantic ID or, if absent, its stable source index.}
@defstruct*[geometry-key3d
            ([digest bytes?] [byte-length exact-nonnegative-integer?]
             [vertex-count exact-nonnegative-integer?]
             [triangle-count exact-nonnegative-integer?]
             [edge-count exact-nonnegative-integer?])] #:transparent]{A
renderer geometry identity. It intentionally excludes semantic part IDs.}
@defproc[(mesh3d-geometry-key [mesh mesh3d?]) geometry-key3d?]{Returns the
immutable render-geometry key, excluding material, placement, and semantic IDs.}
@defstruct*[mesh3d-semantic-key3d
            ([geometry geometry-key3d?]
             [vertex-ids (or/c #f vector?)] [edge-ids (or/c #f vector?)]
             [face-ids (or/c #f vector?)] [provenance-schema symbol?])
            #:transparent]{An authoring identity layered over geometry.}
@defproc[(mesh3d-semantic-key [mesh mesh3d?]) mesh3d-semantic-key3d?]{Returns
the immutable semantic key. It is not a renderer cache key.}

@defstruct*[mesh-part-reference3d
            ([kind (or/c 'vertex 'edge 'face)] [id any/c]) #:transparent]{An
immutable reference to one source or result mesh part. The kind is explicit so
a topology-changing operation can accurately record cross-kind derivation,
such as a primal face becoming a dual vertex.}
@defstruct*[mesh-part-provenance-entry3d
            ([source-part (or/c #f mesh-part-reference3d?)]
             [result-parts vector?]
             [relation (or/c 'preserved 'merged 'split 'generated 'discarded 'ambiguous 'derived)])
            #:transparent]{One source-to-result multimap entry. A generated
entry has no source; a discarded entry has no result parts.}
@defstruct*[mesh-part-provenance3d
            ([vertices vector?] [edges vector?] [faces vector?] [warnings vector?])
            #:transparent]{Shared immutable provenance for a topology-changing
mesh operation. Entries are grouped by source part kind; warnings document
intentional identity loss or ambiguity.}
@defproc[(make-mesh-part-provenance3d
          [#:vertices vertices vector? #()]
          [#:edges edges vector? #()]
          [#:faces faces vector? #()]
          [#:warnings warnings vector? #()]) mesh-part-provenance3d?]{Builds a
validated provenance value.}
@defproc[(mesh-part-provenance3d-source-results
          [provenance mesh-part-provenance3d?]
          [source mesh-part-reference3d?]) (or/c #f vector?)]{Looks up one
source part's zero, one, or many result parts.}
@defproc[(mesh-part-provenance3d-result-sources
          [provenance mesh-part-provenance3d?]
          [result mesh-part-reference3d?]) vector?]{Returns every source part
that contributes to the specified result part.}

