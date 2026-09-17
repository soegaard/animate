#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-conservati-fc6b09c"]{3D: Conservative mesh correspondence}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[spatial-correspondence3d
            ([source any/c] [destination any/c] [reason any/c] [mode any/c]
             [route any/c] [diagnostics hash?]) #:transparent]{The common
author-visible planning record for a matched spatial part. A later face-part
operation may use its @racket[source], @racket[destination], and @racket[route]
fields to describe direct group children.}
@defstruct*[mesh-correspondence3d
            ([vertex-map vector?] [edge-map vector?] [face-map vector?]
             [unmatched-source hash?] [unmatched-destination hash?]
             [diagnostics hash?]) #:transparent]{A source-index-to-destination-
index plan. Every map entry is an index or @racket[#f]. Unmatched hashes are
keyed by @racket['vertex], @racket['edge], and @racket['face].}
@defproc[(prepare-mesh-correspondence3d [source mesh3d?] [destination mesh3d?]
                                        [#:vertex-map vertex-map (or/c #f vector?) #f]
                                        [#:edge-map edge-map (or/c #f vector?) #f]
                                        [#:face-map face-map (or/c #f vector?) #f]
                                        [#:geometric-fallback? geometric-fallback? boolean? #f]
                                        [#:geometric-frame geometric-frame 'local-normalized]
                                        [#:geometric-limit geometric-limit exact-positive-integer? 64]
                                        [#:maximum-geometric-cost maximum-geometric-cost
                                                                 (or/c #f nonnegative-real?) #f])
         mesh-correspondence3d?]{Creates an injective correspondence plan.
Priority is explicit author map, shared semantic part IDs, unchanged indexed
topology, then a unique local topological signature. Symmetric signature
classes are retained as ambiguity records rather than being paired arbitrarily.

Passing @racket[#:geometric-fallback? #t] explicitly permits a final bounded
minimum-cost assignment only between still-unmatched source parts and unused
destination parts. The current declared @racket['local-normalized] frame
centres each mesh's local AABB and divides by its largest extent. The cost
records normalized position, available normal agreement, local valence, and a
penalty for unequal explicit semantic IDs. Its diagnostics retain the initial
reason, candidate indexes, accepted pairs and their costs, and rejected pairs.
@racket[#:maximum-geometric-cost] rejects an assigned pair above its threshold
rather than treating it as a successful correspondence.}

@bold{Limitations.} Geometric fallback is deliberately local-frame-only and
bounded; it is not a graph-isomorphism proof, a provenance-map matcher, or a
large-mesh nearest-neighbour service. A plan that still contains ambiguity or
unmatched records requires an explicit map or a separate cross-fade; it never
silently morphs unrelated index arrays.

