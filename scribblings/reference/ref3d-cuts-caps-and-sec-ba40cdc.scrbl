#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-cuts-caps-and-sec-ba40cdc"]{3D: Cuts, caps, and section measurements}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-R extends a plane section with an explicit local numerical policy,
plane basis, and component records. @racket[cut-mesh3d] returns both clipped
halves plus their shared @racket[section3d], optional separate cap meshes, and
when capped, exact-coordinate welded solid halves through
@tt{mesh-cut3d-result-positive-solid} and
@tt{mesh-cut3d-result-negative-solid}. It does not mutate the source mesh.
@racket[section3d-area],
@racket[section3d-centroid], and @racket[section3d-perimeter] operate on the
same preserved section topology.  Measurements reject an open/branch
component, repeated vertex, zero-area loop, self-intersection, and a touching
or intersecting pair of loops rather than silently treating it as an even/odd
region. @racket[clip-planes3d] and @racket[clip-box3d]
build ordered render-only half-space sequences.

@racket[section-fill3d] exposes a separate cap-style mesh for a section;
@racket[section-hatch3d] creates deterministic even/odd stroke intervals in
the plane-local basis, including empty intervals for nested holes.
@racket[slice-stack3d] retains stable section-group paths as planes advance
along a normal. @racket[prepare-cross-section-function3d] makes an immutable
table of sections, areas, centroids, and diagnostics, which
@racket[volume-by-slices3d] evaluates with a declared midpoint, trapezoid, or
Simpson rule. The sampling convention is part of the table and is checked by
the chosen numerical rule. @racket[riemann-volume3d] provides a separate
midpoint-column construction for graph-volume explanations; each row and cell
is an ordinary stable spatial child. @racket[washer-sum3d] creates stable
midpoint annular slabs about the x axis, and @racket[shell-sum3d] creates
stable midpoint cylindrical shells about the z axis. These are explanatory
geometry groups; numerical volume estimation remains explicit.

The cap triangulator handles simple concave loops and a deterministic
containment forest of nested holes. It bridges each immediate hole into its
outer loop with a visible, source-order tie-broken bridge, then verifies that
the cap triangle area equals outer area minus holes. @racket[mesh3d-weld]
performs exact-coordinate (never tolerance-based) boundary reuse for derived
cut solids; it intentionally omits per-vertex normals because the current
mesh representation has no per-corner normal channel.

Current limitations: cuts presently preserve positions, normals, and RGBA
colours, but do not yet offer general UV/scalar/semantic attribute descriptors;
cap construction for self-intersecting or touching contours does not yet have
robust recovery (measurements reject those contours); and repeated semantic
multi-plane cutting currently produces uncapped geometry.

@defproc[(cut-mesh-by-box3d [mesh mesh3d?] [bounds aabb3?]
                             [#:id id symbol?]
                             [#:settings settings section3d-settings?])
         mesh3d?]{Materializes the six inclusive local-axis box half-spaces as
ordered indexed geometry. This is the geometry counterpart to
@racket[clip-box3d], which remains render-only. The result is deliberately
uncapped; it does not claim to be a closed box-cut solid.}

@defproc[(mesh3d-weld [meshes (listof mesh3d?)]
                       [#:id id symbol?]
                       [#:material material material3d?])
         mesh3d?]{Combines meshes that share exact local boundary vertices
into one indexed mesh. It rejects mismatched transforms, opacity, or a missing
colour at a newly introduced vertex; it never performs tolerance-based welding.}
Multi-plane render clipping is semantic and ordered, but the optional OpenGL
backend has not yet received its corresponding multi-plane uniform path.
See @filepath{examples/3d/capped-cube-cutaway.rkt}.

@defproc[(riemann-volume3d [function procedure?]
                            [#:x-range x-range list? (list -1 1)]
                            [#:y-range y-range list? (list -1 1)]
                            [#:resolution resolution list? (list 8 8)]
                            [#:base base finite-real? 0]
                            [#:id id symbol?]) group3d?]{Builds midpoint
columns between @racket[base] and @racket[(function x y)].  Children have
stable @racket['row-n] then @racket['cell-n] identifiers. A zero-height
sample is a stable empty cell group, not an invented nonzero solid.}
@defproc[(washer-sum3d [outer procedure?] [inner procedure?]
                        [#:x-range x-range list? (list -1 1)]
                        [#:count count exact-positive-integer? 8]
                        [#:id id symbol?]) group3d?]{Builds midpoint annular
washer slabs about the x axis. @racket[outer] and @racket[inner] must return
nonnegative radii with @racket[inner] no larger than @racket[outer]. Children
are stably named @racket['washer-n].}
@defproc[(shell-sum3d [height procedure?]
                       [#:radius-range radius-range list? (list 0 1)]
                       [#:count count exact-positive-integer? 8]
                       [#:base base finite-real? 0]
                       [#:id id symbol?]) group3d?]{Builds midpoint annular
cylindrical shells about the z axis between @racket[base] and
@racket[(height radius)]. Children are stably named @racket['shell-n].}

