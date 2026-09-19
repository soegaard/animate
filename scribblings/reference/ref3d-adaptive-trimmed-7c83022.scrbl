#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-adaptive-trimmed-7c83022"]{3D: Adaptive, trimmed, and implicit surfaces}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Adaptive, trimmed, and implicit surface constructors all lower to the same
immutable indexed surface record returned by @racket[surface3d-local-mesh].  The record preserves
vertex and triangle provenance as well as a topology key, while renderer
caches remain outside authored values.

Surfaces implement @racket[gen:surface3d].  The protocol deliberately separates
local geometry from the authored spatial envelope: @racket[surface3d-local-mesh]
always has identity placement and full opacity, while @racket[surface3d->mesh3d]
restores the surface's transform and opacity for standalone use.  A
@racket[surface-domain3d] owns any executable retained-domain predicate; the
serializable @racket[surface-diagnostics3d] value never embeds that procedure.

@racket[adaptive-parametric-surface3d] accepts the same parameterization shape
as @racket[parametric-surface3d], but samples it on a deterministic dyadic
quadtree.  Its position, normal-angle, and maximum-edge-length tolerances are
camera independent.  Neighbouring cells are conformed before lowering, so
their shared edge vertices are identical rather than merely close.

@racket[trimmed-parametric-surface3d] accepts signed @racket[surface-trim]
fields in parameter space, or an explicit Boolean field made with
@racket[trim-field3d], @racket[trim-and3d], @racket[trim-or3d], and
@racket[trim-not3d].  A list remains conjunction for the simple case.  Its
trim classifier samples each adaptive cell's corners, side midpoints, and
centre before requesting a split, rather than imposing a fixed global lattice
on every planar trimmed surface. It clips the retained adaptive triangles and
shares edge/trim intersections by canonical keys.  Consequently
@racket[surface3d-domain-contains?] and @racket[surface3d-position-at?] can
distinguish a point in the original parameter box from one outside its trim.
Root refinement uses deterministic bisection for true sign crossings.

@racket[implicit-surface3d] currently uses deterministic fixed-grid
marching tetrahedra. It canonicalizes exact iso vertices, uses an author
gradient when supplied (otherwise bounded one-sided finite differences), and
reports extraction-boundary crossings. Its @racket[#:on-invalid] policy may
raise, skip invalid cells, or use bounded local subdivision before recording
unresolved cells in diagnostics. This API does not provide adaptive octree implicit extraction.

@defproc[(trim-expression3d? [value any/c]) boolean?]{Recognizes an immutable
signed trim field or Boolean trim expression.}
@defproc[(trim-field3d [field procedure?]
                        [#:keep keep (or/c 'positive 'negative) 'positive]
                        [#:id id symbol?]
                        [#:tolerance tolerance positive?])
         trim-expression3d?]{Creates one retained signed trim field. Its
non-negative side is retained; @racket['negative] reverses the source field.}
@defproc[(surface-trim [field procedure?]
                         [#:keep keep (or/c 'positive 'negative) 'positive]
                         [#:id id symbol?]
                         [#:tolerance tolerance positive?])
         trim-expression3d?]{The established spelling for @racket[trim-field3d].}
@defproc[(trim-and3d [first trim-expression3d?]
                      [rest trim-expression3d?] ...)
         trim-expression3d?]{Intersects nonempty signed trim expressions.}
@defproc[(trim-or3d [first trim-expression3d?]
                     [rest trim-expression3d?] ...)
         trim-expression3d?]{Unites nonempty signed trim expressions.}
@defproc[(trim-not3d [expression trim-expression3d?]) trim-expression3d?]{Complements
one signed trim expression.}

@bold{Current trim limitations:} Nine samples are a conservative local
discovery rule, not a proof that an arbitrarily tiny component between all
sample positions will be found.  Compound trim provenance identifies its
source field deterministically, but reconstructed named boundary loops are not
yet exposed as a separate surface value.

@racket[implicit-surface3d] samples a finite scalar field within a declared
axis-aligned box and extracts one level set with deterministic marching
tetrahedra.  It shares lattice-edge intersections, estimates normals from
central field differences, and records whether the surface touches the box
boundary.  The extractor uses a fixed resolution; it does not adapt its 3D cells. @racket[view3d-surface-pick] uses the ordinary CPU BVH
hit and attaches the retained triangle provenance: barycentrically interpolated
@racket[(vector u v)] parameters for parametric surfaces and the source cube/
tetrahedron record for implicit ones. It does not claim a separate analytic
implicit intersection solver.

Adaptive and trimmed parametric surfaces retain their evaluator and parameter
domain as well as their lowered mesh. Therefore @racket[surface-anchor3d] can
provide a deterministic local finite-difference tangent/normal frame for those
surfaces. An implicit surface has no invented UV coordinate. Instead,
@racket[surface-pick-anchor3d] converts one immutable @racket[surface-pick3d]
into an anchor: it resolves the current barycentric mesh point and interpolated
normal, while truthfully leaving the tangent unavailable.

The focused executable probe is
@filepath{examples/3d/adaptive-trimmed-implicit-surfaces.rkt}.
@defproc[(reveal-surface-u [target spatial-path?]) any/c]{Reveals an existing
surface directly from its minimum-u boundary without changing its grid size.}
@defproc[(reveal-surface-v [target spatial-path?]) any/c]{The analogous
minimum-v reveal.}
@defproc[(transform-surface3d [target spatial-path?] [destination surface3d?])
         any/c]{Interpolates matching topology and material structure directly
from immutable source/destination grids.}

An example is @filepath{examples/3d/tangent-plane.rkt}.

