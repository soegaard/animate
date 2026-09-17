#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-navigable-5d87e57"]{3D: Triangle topology}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[mesh-vertex-topology3d
            ([index exact-nonnegative-integer?]
             [id (or/c symbol? exact-nonnegative-integer?)]
             [outgoing-halfedges vector?] [boundary? boolean?]
             [component (or/c #f exact-nonnegative-integer?)]) #:transparent]{A
source vertex and its deterministic outgoing half-edge indexes.}
@defstruct*[mesh-halfedge3d
            ([index exact-nonnegative-integer?] [from exact-nonnegative-integer?]
             [to exact-nonnegative-integer?] [triangle exact-nonnegative-integer?]
             [next exact-nonnegative-integer?] [previous exact-nonnegative-integer?]
             [opposite any/c] [edge exact-nonnegative-integer?]) #:transparent]{One
directed triangle side. @racket[opposite] is @racket[#f] at a boundary, one
index for a two-incidence edge, or an immutable vector of all other incident
half-edges at a nonmanifold edge.}
@defstruct*[mesh-edge-topology3d
            ([index exact-nonnegative-integer?]
             [id (or/c symbol? exact-nonnegative-integer?)] [vertices vector?]
             [halfedges vector?] [boundary? boolean?] [nonmanifold? boolean?])
            #:transparent]{One undirected triangle edge in first-incidence order.}
@defstruct*[mesh-triangle-topology3d
            ([index exact-nonnegative-integer?]
             [id (or/c symbol? exact-nonnegative-integer?)] [vertices vector?]
             [halfedges vector?] [component exact-nonnegative-integer?])
            #:transparent]{One declared triangle face and its three half-edges.}
@defstruct*[mesh-boundary-component3d
            ([index exact-nonnegative-integer?] [edges vector?] [vertices vector?]
             [halfedges vector?] [component (or/c #f exact-nonnegative-integer?)]
             [closed? boolean?]) #:transparent]{A connected boundary-edge graph.
@racket[closed?] reports whether it is a genuine degree-two boundary loop.}
@defstruct*[mesh-component-topology3d
            ([index exact-nonnegative-integer?] [triangles vector?]
             [vertices vector?] [edges vector?] [boundary-components vector?]
             [manifold? boolean?] [orientable? boolean?]) #:transparent]{One
edge-connected face component; isolated source vertices become explicit
zero-face components.}
@defstruct*[mesh-topology3d
            ([vertices vector?] [halfedges vector?] [edges vector?]
             [triangles vector?] [components vector?] [boundaries vector?]
             [diagnostics hash?]) #:transparent]{An immutable triangle-topology
complex. Its structural skeleton is cached by @racket[geometry-key3d]; semantic
IDs are attached per queried mesh, so equally shaped meshes still keep their
own author-visible names.}
@defproc[(mesh3d-topology [mesh mesh3d?]) mesh-topology3d?]{Builds the stable
half-edge complex. It never welds, repairs, or changes mesh geometry.}
@defproc[(mesh-topology3d-vertex-neighbours [topology mesh-topology3d?]
                                             [vertex-index exact-nonnegative-integer?])
         vector?]{Returns adjacent source vertices in first-edge encounter order.}
@defproc[(mesh-topology3d-incident-edges [topology mesh-topology3d?]
                                          [vertex-index exact-nonnegative-integer?])
         vector?]{Returns incident topological-edge indexes.}
@defproc[(mesh-topology3d-incident-faces [topology mesh-topology3d?]
                                          [vertex-index exact-nonnegative-integer?])
         vector?]{Returns incident triangle indexes.}
@defproc[(mesh-topology3d-face-neighbours [topology mesh-topology3d?]
                                           [face-index exact-nonnegative-integer?])
         vector?]{Returns adjacent triangle indexes in local-half-edge order.}
@defproc[(mesh-topology3d-boundary-components [topology mesh-topology3d?]) vector?]{Returns
the deterministic boundary-component records.}
@defproc[(mesh-topology3d-connected-components [topology mesh-topology3d?]) vector?]{Returns
edge-connected face components plus any isolated vertices.}
@defproc[(mesh-topology3d-manifold? [topology mesh-topology3d?]) boolean?]{Checks
edge and vertex-fan manifoldness without repairing an invalid mesh.}
@defproc[(mesh-topology3d-closed? [topology mesh-topology3d?]) boolean?]{Checks
for a nonempty manifold topology without boundaries.}
@defproc[(mesh-topology3d-orientable? [topology mesh-topology3d?]) boolean?]{Reports
whether the retained local winding relations have a consistent global parity.}
@defstruct*[mesh3d-component-invariants3d
            ([component exact-nonnegative-integer?]
             [vertex-count exact-nonnegative-integer?]
             [edge-count exact-nonnegative-integer?]
             [face-count exact-nonnegative-integer?]
             [euler-characteristic exact-integer?]
             [boundary-count exact-nonnegative-integer?]
             [manifold? boolean?] [orientable? boolean?]
             [genus (or/c #f exact-nonnegative-integer?)] [reason any/c])
            #:transparent]{Per-component combinatorial invariants. @racket[genus]
is absent and @racket[reason] explains why when a genus claim would be false.}
@defstruct*[mesh3d-genus-report
            ([components vector?] [valid? boolean?] [reason any/c])
            #:transparent]{The genus result for every component, without
silently guessing values for nonmanifold, nonorientable, or zero-face inputs.}
@defproc[(mesh3d-euler-characteristic [mesh-or-topology (or/c mesh3d? mesh-topology3d?)])
         exact-integer?]{Returns @italic{V − E + F} for the retained complex.}
@defproc[(mesh3d-boundary-count [mesh-or-topology (or/c mesh3d? mesh-topology3d?)])
         exact-nonnegative-integer?]{Returns the number of connected boundary graphs.}
@defproc[(mesh3d-component-invariants [mesh-or-topology (or/c mesh3d? mesh-topology3d?)])
         vector?]{Returns immutable per-component invariant reports.}
@defproc[(mesh3d-genus [mesh-or-topology (or/c mesh3d? mesh-topology3d?)])
         mesh3d-genus-report?]{Returns explicit genus reports. For each valid
connected orientable surface, @racket[g = (2 - b - chi) / 2].}

The triangle topology layer does not repair malformed input or turn a branching
boundary graph into a fictitious loop.

