#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-determinis-b37f679"]{3D: Deterministic convex hulls}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[convex-hull3d-coplanar-group3d
            ([face-id any/c] [triangle-indices vector?]
             [boundary-vertex-indices (or/c #f vector?)]
             [source-point-indices vector?]) #:transparent]{One merged coplanar
supporting face of a three-dimensional hull. The source-point vector includes
every retained input point on that plane, including a point in the face
interior.}
@defstruct*[convex-hull3d-result
            ([dimension (integer-in 0 3)] [mesh mesh3d?]
             [source-point-indices vector?] [coplanar-groups vector?]
             [interior-indices vector?] [diagnostics hash?]) #:transparent]{A
truthful hull result. @racket[source-point-indices] maps returned mesh vertices
to original input indexes. @racket[interior-indices] includes non-extreme and
merged-duplicate inputs. For dimension 0, 1, and 2, @racket[mesh] is,
respectively, a point mesh, segment mesh, or planar triangle fan---never a
fabricated three-dimensional solid.}
@defproc[(convex-hull3d [points (or/c vector? list?)]
                         [#:id id symbol? 'hull]
                         [#:tolerance tolerance (or/c 'automatic nonnegative-real?) 'automatic]
                         [#:merge-tolerance merge-tolerance (or/c #f nonnegative-real?) #f]
                         [#:orientation-tolerance orientation-tolerance (or/c #f nonnegative-real?) #f]
                         [#:coplanar-tolerance coplanar-tolerance (or/c #f nonnegative-real?) #f]
                         [#:coplanar coplanar (or/c 'merge 'triangulate) 'merge]
                         [#:on-degenerate on-degenerate (or/c 'report 'error) 'report])
         convex-hull3d-result?]{Builds a deterministic convex hull. It retains
original source indexes. @racket[#:merge-tolerance],
@racket[#:orientation-tolerance], and @racket[#:coplanar-tolerance] control
point clustering, degeneracy/orientation classification, and supporting-face
grouping independently. A numeric legacy @racket[#:tolerance] supplies all
three unless an explicit policy keyword overrides that stage. The automatic
merge policy accepts only exact duplicates; automatic orientation uses a
scale-aware threshold for inexact classification. Exact coordinates use exact
determinant signs.

The next outside point is chosen by greatest positive face distance, then
stable coordinate/source order. @racket['merge] returns polygonal supporting-face records; @racket['triangulate] leaves that vector empty. If a
point set is lower-dimensional, @racket['report] returns its actual dimension
and @racket['error] raises instead. Diagnostics state the effective tolerances,
the exact/inexact orientation policy, duplicate count, and near-zero decision
count.}

@bold{Limitations.} The convex-hull implementation is deterministic but is not a general
computational-geometry repair system: it does not resolve self-intersecting
input, and inexact near-degenerate cases use the recorded scale-aware policy
instead of a bigfloat/exact-predicate fallback. Near-duplicate clustering with
an explicit tolerance is deterministic and transitive: a chain of close points
forms one cluster even when its endpoints are not directly close. Concave hulls, Delaunay triangulation, and arbitrary
polygon-with-hole operations are not supported.

