#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "3d-algebra"]{3D Algebra and Opaque Rendering}

@defmodule[animate/3d]

This module provides the pure spatial algebra kernel. Its values describe
right-handed mathematical coordinates; they neither render nor depend on a
renderer. All coordinate and matrix fields reject NaN and infinite values.

@section{Vectors}

@defstruct*[vec3 ([x finite-real?]
                  [y finite-real?]
                  [z finite-real?])
  #:transparent]{
An immutable spatial point or displacement. Positive @racket[z] points out of
the screen toward a conventional viewer.
}

@defthing[origin3 vec3? #:value (vec3 0 0 0)]{The spatial origin.}
@defthing[x-axis3 vec3? #:value (vec3 1 0 0)]{The positive x unit vector.}
@defthing[y-axis3 vec3? #:value (vec3 0 1 0)]{The positive y unit vector.}
@defthing[z-axis3 vec3? #:value (vec3 0 0 1)]{The positive z unit vector.}

@defproc[(vec3+ [first vec3?] [second vec3?]) vec3?]{Adds components.}
@defproc[(vec3- [first vec3?] [second vec3?]) vec3?]{Subtracts components.}
@defproc[(vec3* [first vec3?] [second vec3?]) vec3?]{Multiplies components.}
@defproc[(vec3-scale [scalar finite-real?] [value vec3?]) vec3?]{Scales every component.}
@defproc[(vec3-dot [first vec3?] [second vec3?]) finite-real?]{Returns the Euclidean dot product.}
@defproc[(vec3-cross [first vec3?] [second vec3?]) vec3?]{
Returns @racket[first] × @racket[second] in the right-handed coordinate system.
}
@defproc[(vec3-length [value vec3?]) nonnegative-real?]{Returns Euclidean length.}
@defproc[(vec3-distance [first vec3?] [second vec3?]) nonnegative-real?]{Returns Euclidean distance.}
@defproc[(vec3-normalize [value vec3?]) vec3?]{
Returns an inexact unit vector. The zero vector raises an exception.
}
@defproc[(vec3-lerp [first vec3?] [second vec3?] [progress finite-real?]) vec3?]{
Linearly interpolates components; progress outside @racket[0] through @racket[1]
performs extrapolation.
}
@defproc[(vec3-finite? [value any/c]) boolean?]{Reports whether @racket[value] is a finite @racket[vec3].}

@section{Linear maps and rotations}

@defstruct*[linear3 ([m00 finite-real?] [m01 finite-real?] [m02 finite-real?]
                     [m10 finite-real?] [m11 finite-real?] [m12 finite-real?]
                     [m20 finite-real?] [m21 finite-real?] [m22 finite-real?])
  #:transparent]{
A 3×3 matrix in row-major order, acting on column vectors. Thus
@racket[(linear3 a b c d e f g h i)] represents rows
@racketblock[
[a b c]
[d e f]
[g h i]
]
and @racket[(linear3-compose outer inner)] means outer ∘ inner: @racket[inner]
acts first.
}

@defthing[identity-linear3 linear3?]{The identity matrix.}
@defproc[(linear3-compose [outer linear3?] [inner linear3?]) linear3?]{Composes two maps as outer ∘ inner.}
@defproc[(linear3-invert [map linear3?]) linear3?]{Returns the inverse or raises an exception for a singular matrix.}
@defproc[(linear3-determinant [map linear3?]) finite-real?]{Returns the determinant.}
@defproc[(linear3-transpose [map linear3?]) linear3?]{Returns the transpose.}
@defproc[(linear3-apply-vector [map linear3?] [value vec3?]) vec3?]{Applies @racket[map] to a column vector.}
@defproc[(linear3-normal-transform [map linear3?]) linear3?]{
Returns the inverse-transpose normal map. The linear map must be invertible.
}

@defproc[(rotation3? [value any/c]) boolean?]{Recognizes a normalized proper rotation.}
@defproc[(rotation3-components [rotation rotation3?]) vector?]{
Returns a debugging vector containing scalar-first quaternion components. The
constructor is intentionally not public; all public construction normalizes
and canonicalizes quaternion sign.
}
@defthing[identity-rotation3 rotation3?]{The identity rotation.}
@defproc[(axis-angle [axis vec3?] [angle finite-real?]) rotation3?]{
Constructs the right-handed rotation by @racket[angle] radians about nonzero
@racket[axis].
}
@defproc[(rotation3-from-to [from-direction vec3?] [to-direction vec3?]) rotation3?]{
Returns the shortest rotation sending one nonzero direction to the other.
Opposite directions use a deterministic perpendicular axis.
}
@defproc[(rotation3-look-at [forward vec3?] [#:up up vec3? y-axis3]) rotation3?]{
Maps local positive z to @racket[forward] while keeping local positive y as
close as possible to @racket[up]. Parallel inputs are rejected.
}
@defproc[(rotation3-compose [outer rotation3?] [inner rotation3?]) rotation3?]{Composes rotations as outer ∘ inner.}
@defproc[(rotation3-invert [rotation rotation3?]) rotation3?]{Returns the inverse rotation.}
@defproc[(rotation3-apply [rotation rotation3?] [value vec3?]) vec3?]{Rotates a displacement vector.}
@defproc[(rotation3->linear3 [rotation rotation3?]) linear3?]{Converts a rotation to its proper orthogonal matrix.}
@defproc[(rotation3-slerp [from rotation3?] [to rotation3?]
                           [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         rotation3?]{
Interpolates along the shortest quaternion arc. Near coincident rotations use
normalized linear interpolation. Progress zero and one return the exact input
endpoint values.
}

@section{Affine and decomposed transforms}

@defproc[(affine3 [linear linear3?] [translation vec3?]) affine3?]{
Constructs a full affine map. It can represent shear, reflection, and singular
linear maps exactly.
}
@defproc[(affine3? [value any/c]) boolean?]{Recognizes a full affine map.}
@defproc[(affine3-linear [map affine3?]) linear3?]{Returns the linear component.}
@defproc[(affine3-translation [map affine3?]) vec3?]{Returns the translation component.}
@defthing[identity-affine3 affine3?]{The identity affine map.}
@defproc[(affine3-compose [outer affine3?] [inner affine3?]) affine3?]{Composes maps as outer ∘ inner.}
@defproc[(affine3-invert [map affine3?]) affine3?]{Returns the inverse; singular maps raise an exception.}
@defproc[(affine3-apply-point [map affine3?] [point vec3?]) vec3?]{Applies both linear component and translation.}
@defproc[(affine3-apply-vector [map affine3?] [value vec3?]) vec3?]{Applies only the linear component.}
@defproc[(affine3-normal-transform [map affine3?]) linear3?]{Returns the inverse-transpose normal map.}
@defproc[(affine3-lerp [from affine3?] [to affine3?]
                         [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         affine3?]{Interpolates corresponding matrix entries and translation, with exact endpoints.}

@defstruct*[transform3 ([translation vec3?]
                        [rotation rotation3?]
                        [scale vec3?])
  #:transparent]{
An author-oriented transform with nonzero scale components. It applies local
scale, then rotation, then translation. Negative scale is allowed, but an
interpolation that would cross a zero scale is rejected.
}
@defproc[(make-transform3 [#:translation translation vec3? origin3]
                           [#:rotation rotation rotation3? identity-rotation3]
                           [#:scale scale vec3? (vec3 1 1 1)])
         transform3?]{Constructs a validated decomposed transform.}
@defthing[identity-transform3 transform3?]{The decomposed identity transform.}
@defproc[(transform3->affine3 [transform transform3?]) affine3?]{Converts a decomposed transform to an exact affine map.}
@defproc[(transform3-compose [outer transform3?] [inner transform3?]) affine3?]{
Composes transforms as an @racket[affine3], retaining shear that arbitrary
nonuniform-scale composition can induce.
}
@defproc[(transform3-apply-point [transform transform3?] [point vec3?]) vec3?]{Applies scale, rotation, then translation.}
@defproc[(transform3-lerp [from transform3?] [to transform3?]
                            [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         transform3?]{Interpolates translation, scale, and shortest-arc rotation with exact endpoints.}

@section{Bounds, rays, and planes}

@defproc[(aabb3 [minimum (or/c #f vec3?)] [maximum (or/c #f vec3?)]) aabb3?]{
Constructs an inclusive axis-aligned box. Both corners must be @racket[vec3]
values ordered coordinatewise, or both must be @racket[#f] for the empty box.
}
@defproc[(aabb3? [value any/c]) boolean?]{Recognizes a spatial AABB.}
@defproc[(aabb3-minimum [bounds aabb3?]) (or/c #f vec3?)]{Returns the lower corner or @racket[#f] when empty.}
@defproc[(aabb3-maximum [bounds aabb3?]) (or/c #f vec3?)]{Returns the upper corner or @racket[#f] when empty.}
@defthing[aabb3-empty aabb3?]{The empty AABB.}
@defproc[(aabb3-empty? [bounds aabb3?]) boolean?]{Reports whether bounds are empty.}
@defproc[(aabb3-union [first aabb3?] [second aabb3?]) aabb3?]{Returns their least enclosing AABB.}
@defproc[(aabb3-from-points [points (listof vec3?)]) aabb3?]{Returns enclosing bounds, or @racket[aabb3-empty] for no points.}
@defproc[(aabb3-transform [bounds aabb3?] [map affine3?]) aabb3?]{Transforms all eight corners and encloses them.}
@defproc[(aabb3-center [bounds aabb3?]) vec3?]{Returns nonempty bounds' centre; empty bounds raise an exception.}
@defproc[(aabb3-size [bounds aabb3?]) vec3?]{Returns nonempty bounds' nonnegative size; empty bounds raise an exception.}
@defproc[(aabb3-contains? [bounds aabb3?] [point vec3?]) boolean?]{Tests inclusive containment.}

@defstruct*[ray3 ([origin vec3?] [direction vec3?]) #:transparent]{
A ray @racket[(+ origin (* t direction))] for @racket[t] at least zero. Its
direction must be nonzero but is not normalized automatically.
}
@defproc[(plane3 [point vec3?] [normal vec3?]) plane3?]{Constructs a point-normal plane and normalizes its nonzero normal.}
@defproc[(plane3? [value any/c]) boolean?]{Recognizes a spatial plane.}
@defproc[(plane3-point [plane plane3?]) vec3?]{Returns one point in the plane.}
@defproc[(plane3-normal [plane plane3?]) vec3?]{Returns its normalized normal.}
@defstruct*[ray3-plane-hit ([point vec3?] [distance nonnegative-real?]) #:transparent]{A forward ray-plane intersection.}
@defstruct*[ray3-aabb-hit ([entry nonnegative-real?] [exit nonnegative-real?]) #:transparent]{The inclusive ray-parameter interval inside an AABB.}
@defstruct*[ray3-triangle-hit ([point vec3?]
                               [distance nonnegative-real?]
                               [barycentric vec3?]
                               [normal vec3?]) #:transparent]{
An exact, double-sided ray/triangle hit. @racket[barycentric] holds the weights
for the triangle's first, second, and third vertices, and @racket[normal]
follows the triangle's declared winding.
}
@defproc[(ray3-at [ray ray3?] [distance finite-real?]) vec3?]{Returns the algebraic point at @racket[distance].}
@defproc[(ray3-intersect-plane [ray ray3?] [plane plane3?])
         (or/c #f ray3-plane-hit?)]{Returns the nearest forward hit, or @racket[#f] when parallel or behind the origin.}
@defproc[(ray3-intersect-aabb [ray ray3?] [bounds aabb3?])
         (or/c #f ray3-aabb-hit?)]{Returns forward entry/exit parameters, or @racket[#f] for no hit.}
@defproc[(ray3-intersect-triangle [ray ray3?] [first vec3?] [second vec3?]
                                  [third vec3?])
         (or/c #f ray3-triangle-hit?)]{
Returns the nearest exact forward intersection with the finite triangle, or
@racket[#f]. Both windings are pickable; renderer back-face culling is a
separate display decision.
}

@section{Spatial Visuals and paths}

SCENE-3D-B keeps spatial content in a protocol distinct from ordinary
two-dimensional @racket[visual?] values. This prevents an ordinary scene path
or two-dimensional animation request from silently treating a mesh as a Pict.
Only its enclosing @racket[view3d] is an ordinary two-dimensional Visual.

@defproc[(spatial-visual? [value any/c]) boolean?]{Recognizes an immutable
spatial Visual.}
@defproc[(spatial-container? [value any/c]) boolean?]{Recognizes an immutable
spatial container. It is deliberately separate from the ordinary 2D container
protocol.}
@defproc[(spatial-id [object spatial-visual?]) symbol?]{Returns its stable
identity within one spatial container.}
@defproc[(spatial-transform [object spatial-visual?]) transform3?]{Returns its
local transform.}
@defproc[(spatial-with-transform [object spatial-visual?] [transform transform3?])
         spatial-visual?]{Returns a transformed immutable copy.}
@defproc[(spatial-opacity [object spatial-visual?]) (and/c real? (between/c 0 1))]{
Returns the opacity inherited by descendants.}
@defproc[(spatial-with-opacity [object spatial-visual?]
                               [opacity (and/c real? (between/c 0 1))])
         spatial-visual?]{Returns an immutable opacity update.}
@defproc[(spatial-local-bounds [object spatial-visual?]) aabb3?]{Returns local
untransformed spatial bounds.}

@defproc[(spatial-position [object spatial-visual?]) vec3?]{Returns the
translation component of the local transform.}
@defproc[(spatial-with-position [object spatial-visual?] [position vec3?])
         spatial-visual?]{Replaces that local translation.}
@defproc[(spatial-rotation [object spatial-visual?]) rotation3?]{Returns the
local rotation.}
@defproc[(spatial-with-rotation [object spatial-visual?] [rotation rotation3?])
         spatial-visual?]{Replaces that local rotation.}
@defproc[(spatial-scale [object spatial-visual?]) vec3?]{Returns the local
scale.}
@defproc[(spatial-with-scale [object spatial-visual?] [scale vec3?])
         spatial-visual?]{Replaces the nonzero local scale components.}

@defstruct*[spatial-child ([id symbol?] [visual spatial-visual?])
  #:transparent]{
An immutable direct-child entry. Its id must be the child Visual's
@racket[spatial-id]. Direct-child order is significant and stable.
}
@defproc[(group3d [children (listof spatial-visual?)]
                  [#:id id symbol?]
                  [#:transform transform transform3? identity-transform3]
                  [#:opacity opacity (and/c real? (between/c 0 1)) 1])
         group3d?]{
Creates an immutable spatial container. Direct child identities must be unique
and cannot equal the group's identity.
}
@defproc[(group3d? [value any/c]) boolean?]{Recognizes a spatial group.}
@defproc[(group3d-children [group group3d?]) (listof spatial-visual?)]{
Returns direct children in their declared order.}
@defproc[(group3d-with-children [group group3d?]
                                 [children (listof spatial-visual?)])
         group3d?]{Returns an immutable direct-child replacement.}

@defproc[(spatial-path? [value any/c]) boolean?]{Recognizes a nonempty list of
symbols.}
@defproc[(spatial-relative-ref [container spatial-container?]
                               [path spatial-path?]) spatial-visual?]{
Resolves a nonempty path relative to a spatial container.
}
@defproc[(spatial-relative-replace [container spatial-container?]
                                   [path spatial-path?]
                                   [replacement spatial-visual?])
         spatial-container?]{Rebuilds an immutable spatial ancestry, requiring
the replacement to retain the final path identity.}

@section{Meshes}

@defproc[(mesh3d [#:id id symbol?]
                  [#:vertices vertices vector?]
                  [#:triangles triangles vector? #()]
                  [#:edges edges (or/c #f vector?) #f]
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
colours are interpolated perspective-correctly.
}
@defproc[(mesh3d? [value any/c]) boolean?]{Recognizes an immutable indexed mesh.}
@defproc[(mesh3d-vertices [mesh mesh3d?]) vector?]{Returns immutable vertices.}
@defproc[(mesh3d-triangles [mesh mesh3d?]) vector?]{Returns immutable triangle indices.}
@defproc[(mesh3d-edges [mesh mesh3d?]) vector?]{Returns immutable wireframe edge indices.}
@defproc[(mesh3d-normals [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable normals.}
@defproc[(mesh3d-colors [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable colours.}
@defproc[(mesh3d-material [mesh mesh3d?]) material3d?]{Returns the surface material.}
@defproc[(mesh3d-wireframe-color [mesh mesh3d?]) any/c]{Returns the current edge colour.}
@defproc[(mesh3d-wireframe-width [mesh mesh3d?]) positive-real?]{Returns the cosmetic edge width.}
@defproc[(mesh3d-local-bounds [mesh mesh3d?]) aabb3?]{Returns bounds enclosing local vertices.}

@subsection{Topology diagnostics and explicit orientation repair}

@defstruct*[mesh3d-duplicate-triangle
            ([first-triangle-index exact-nonnegative-integer?]
             [duplicate-triangle-index exact-nonnegative-integer?]
             [winding (or/c 'same 'reversed)]) #:transparent]{
Records a later triangle that has the same three indexed vertices as an earlier
one, independent of cyclic rotation.}

@defstruct*[mesh3d-analysis
            ([vertex-count exact-nonnegative-integer?]
             [triangle-count exact-nonnegative-integer?]
             [edge-count exact-nonnegative-integer?]
             [degenerate-triangles vector?]
             [duplicate-triangles vector?]
             [boundary-edges vector?]
             [boundary-loops vector?]
             [nonmanifold-edges vector?]
             [inconsistent-winding-edges vector?]
             [connected-components vector?]
             [isolated-vertices vector?]
             [signed-component-volumes vector?]
             [watertight? boolean?]
             [orientable? boolean?]
             [consistently-wound? boolean?]) #:transparent]{
An immutable, deterministic report over indexed geometry. Edge records retain
first-triangle encounter order; components and loops retain source-index order.
Degeneracy uses a tolerance proportional to the mesh's squared extent rather
than one universal world-coordinate epsilon.}

@defproc[(analyze-mesh3d [mesh mesh3d?]) mesh3d-analysis?]{Computes topology
and geometric diagnostics without changing @racket[mesh].}
@defproc[(mesh3d-validate [mesh mesh3d?]) mesh3d-analysis?]{An explicit alias
for @racket[analyze-mesh3d]. Mesh construction remains cheap and does not
implicitly run this potentially expensive analysis.}
@defstruct*[mesh3d-orientation-report
            ([initial-analysis mesh3d-analysis?]
             [final-analysis mesh3d-analysis?]
             [flipped-triangle-indices vector?]
             [outward? boolean?]) #:transparent]{An immutable explanation of
an explicit orientation repair. Per-vertex normals are authored attributes and
are not silently regenerated by repair.}
@defproc[(mesh3d-orient-consistently [mesh mesh3d?])
         (values mesh3d? mesh3d-orientation-report?)]{
Returns a replacement mesh with each manifold adjacent pair oppositely wound,
or raises for degenerate, non-manifold, or parity-conflicting input.}
@defproc[(mesh3d-orient-outward [mesh mesh3d?])
         (values mesh3d? mesh3d-orientation-report?)]{
Additionally makes every closed, orientable, nonzero-volume component
outward-facing. Open, non-manifold, non-orientable, and zero-volume components
fail explicitly because they have no unambiguous outside.}
@defproc[(mesh3d-self-intersection-candidates [mesh mesh3d?]) vector?]{Returns
deterministic pairs of non-adjacent faces whose local AABBs overlap. This is a
broad-phase candidate query, not a narrow-phase proof of intersection.}

@section{Materials and lights}

@defproc[(material3d [#:color color any/c "cornflowerblue"]
                      [#:shading shading (or/c 'unlit 'flat 'smooth) 'flat]
                      [#:ambient ambient nonnegative-real? 1]
                      [#:diffuse diffuse nonnegative-real? 1]
                      [#:specular specular nonnegative-real? 0]
                      [#:roughness roughness positive-real? 1]
                      [#:double-sided? double-sided? boolean? #f]
                      [#:wireframe? wireframe? boolean? #f])
         material3d?]{
Constructs an immutable surface material. @racket['unlit] uses its base
colour; @racket['flat] evaluates one face normal using ambient and directional
lights; and @racket['smooth] interpolates supplied vertex normals. The colour
may include alpha; the renderer's explicit transparent pass controls its
compositing policy. Specular, roughness, and wireframe flags are immutable
authoring data reserved for later renderer stages.
}
@defproc[(material3d? [value any/c]) boolean?]{Recognizes a material.}
@defproc[(material3d-color [material material3d?]) rgba-color?]{Returns base colour and alpha.}
@defproc[(material3d-shading [material material3d?]) (or/c 'unlit 'flat 'smooth)]{Returns its active shading mode.}
@defproc[(material3d-ambient [material material3d?]) nonnegative-real?]{Returns ambient coefficient.}
@defproc[(material3d-diffuse [material material3d?]) nonnegative-real?]{Returns diffuse coefficient.}
@defproc[(material3d-specular [material material3d?]) nonnegative-real?]{Returns retained specular coefficient.}
@defproc[(material3d-roughness [material material3d?]) positive-real?]{Returns retained roughness.}
@defproc[(material3d-double-sided? [material material3d?]) boolean?]{Reports whether back-face culling is disabled for this mesh.}
@defproc[(material3d-wireframe? [material material3d?]) boolean?]{Returns retained wireframe intent.}

@defproc[(ambient-light3d [#:intensity intensity nonnegative-real? 1]
                           [#:color color any/c "white"])
         ambient-light3d?]{Creates uniform opaque ambient illumination.}
@defproc[(directional-light3d [direction vec3?]
                               [#:intensity intensity nonnegative-real? 1]
                               [#:color color any/c "white"])
         directional-light3d?]{Creates an opaque directional light. Its
direction is the direction in which illumination travels, so a normal facing
its negation receives diffuse light.}
@defproc[(ambient-light3d? [value any/c]) boolean?]{Recognizes ambient light.}
@defproc[(ambient-light3d-intensity [light ambient-light3d?]) nonnegative-real?]{Returns ambient intensity.}
@defproc[(ambient-light3d-color [light ambient-light3d?]) rgba-color?]{Returns opaque ambient colour.}
@defproc[(directional-light3d? [value any/c]) boolean?]{Recognizes directional light.}
@defproc[(directional-light3d-direction [light directional-light3d?]) vec3?]{Returns normalized travel direction.}
@defproc[(directional-light3d-intensity [light directional-light3d?]) nonnegative-real?]{Returns directional intensity.}
@defproc[(directional-light3d-color [light directional-light3d?]) rgba-color?]{Returns opaque directional colour.}

@section{Cameras and projection}

A camera's local @racket[x] axis is screen-right, local @racket[y] is
screen-up, and local negative @racket[z] is forward. A default camera is at
@racket[(vec3 0 0 8)] and looks at @racket[origin3]. The camera is reusable:
viewport aspect is supplied when projecting or rendering, rather than stored in
the camera.

@defstruct*[perspective-projection3d ([vertical-field-of-view finite-real?])
  #:transparent]{A perspective projection measured in radians.}
@defstruct*[orthographic-projection3d ([vertical-size positive-real?])
  #:transparent]{An orthographic projection with the stated visible vertical
size.}
@defproc[(perspective-camera3d [#:position position vec3? (vec3 0 0 8)]
                               [#:look-at target vec3? origin3]
                               [#:up up vec3? y-axis3]
                               [#:rotation rotation (or/c #f rotation3?) #f]
                               [#:near near positive-real? 1/10]
                               [#:far far positive-real? 100]
                               [#:vertical-field-of-view field-of-view finite-real? (/ pi 4)])
         camera3d?]{Creates a perspective camera. An explicit rotation wins
over the look-at fields.}
@defproc[(orthographic-camera3d [#:position position vec3? (vec3 0 0 8)]
                                [#:look-at target vec3? origin3]
                                [#:up up vec3? y-axis3]
                                [#:rotation rotation (or/c #f rotation3?) #f]
                                [#:near near positive-real? 1/10]
                                [#:far far positive-real? 100]
                                [#:vertical-size size positive-real? 6])
         camera3d?]{Creates a parallel orthographic camera.}
@defproc[(camera3d? [value any/c]) boolean?]{Recognizes an immutable camera.}
@defproc[(camera3d-position [camera camera3d?]) vec3?]{Returns its world position.}
@defproc[(camera3d-rotation [camera camera3d?]) rotation3?]{Returns camera-local axes in world coordinates.}
@defproc[(camera3d-near [camera camera3d?]) positive-real?]{Returns nearest visible forward depth.}
@defproc[(camera3d-far [camera camera3d?]) positive-real?]{Returns farthest visible forward depth.}
@defproc[(camera3d-projection [camera camera3d?]) (or/c perspective-projection3d? orthographic-projection3d?)]{Returns its lens.}
@defproc[(camera3d-forward [camera camera3d?]) vec3?]{Returns world-space local negative z.}
@defproc[(camera3d-right [camera camera3d?]) vec3?]{Returns world-space local positive x.}
@defproc[(camera3d-up [camera camera3d?]) vec3?]{Returns world-space local positive y.}
@defproc[(camera3d-look-at [camera camera3d?] [target vec3?]
                           [#:up up vec3? y-axis3]) camera3d?]{Returns an
immutable reorientation toward @racket[target].}
@defproc[(camera3d-world->view [camera camera3d?] [point vec3?]) vec3?]{
Converts a world point to camera coordinates; visible forward points have
negative z.}
@defproc[(camera3d-view-depth [camera camera3d?] [point vec3?]) finite-real?]{
Returns positive depth along the camera's forward axis.}
@defproc[(camera3d-project [camera camera3d?] [point vec3?]
                           [#:aspect aspect positive-real? 1])
         (or/c #f vec2?)]{
Projects to normalized viewport coordinates. It returns @racket[#f] behind the
camera or outside the inclusive near/far interval.
}
@defproc[(camera3d-pixel-ray [camera camera3d?] [pixel-x finite-real?]
                             [pixel-y finite-real?]
                             [#:width width exact-positive-integer?]
                             [#:height height exact-positive-integer?]) ray3?]{
Returns a world ray through a top-left-origin pixel coordinate.}
@defproc[(camera3d-frustum [camera camera3d?]
                           [#:aspect aspect positive-real? 1]) vector?]{
Returns immutable inward-facing near, far, left, right, bottom, and top planes.}

@section{Spatial viewports}

@defproc[(view3d [children (listof spatial-visual?)]
                  [#:id id symbol?]
                  [#:center center vec2? origin]
                  [#:width width positive-real? 12]
                  [#:height height positive-real? 27/4]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale (or/c positive-real? vec2?) 1]
                  [#:opacity opacity (and/c real? (between/c 0 1)) 1]
                  [#:camera camera camera3d? (perspective-camera3d)]
                  [#:lights lights (listof (or/c ambient-light3d? directional-light3d?)) null]
                  [#:background background any/c "white"]
                  [#:render-mode render-mode (or/c 'wireframe 'opaque) 'wireframe]
                  [#:transparency-mode transparency-mode
                   (or/c 'object-sorted 'triangle-sorted) 'triangle-sorted])
         view3d?]{
Creates the boundary between a normal two-dimensional Scene and a spatial tree.
Its position, rotation, scale, opacity, and placement act as they do for other
ordinary Visuals. @racket['wireframe] retains the initial clipped-edge adapter.
@racket['opaque] uses a deterministic software triangle renderer: six-plane
frustum clipping, CCW front-face culling (unless a material is double-sided),
pixel-centre rasterization, and a z-buffer. An empty @racket[lights] list uses
a deterministic ambient-plus-directional default.
When material or effective spatial opacity is below one, transparent triangles
are composited after the opaque depth-writing pass using the selected explicit
sorting mode.
}
@defproc[(view3d? [value any/c]) boolean?]{Recognizes a 2D viewport Visual
containing a spatial tree.}
@defproc[(view3d-children [view view3d?]) (listof spatial-visual?)]{Returns direct spatial children.}
@defproc[(view3d-width [view view3d?]) positive-real?]{Returns local 2D viewport width.}
@defproc[(view3d-height [view view3d?]) positive-real?]{Returns local 2D viewport height.}
@defproc[(view3d-camera [view view3d?]) camera3d?]{Returns the spatial camera.}
@defproc[(view3d-lights [view view3d?]) list?]{Returns immutable light declarations.}
@defproc[(view3d-background [view view3d?]) any/c]{Returns the opaque viewport background.}
@defproc[(view3d-render-mode [view view3d?]) (or/c 'wireframe 'opaque)]{Returns the renderer mode.}
@defproc[(view3d-transparency-mode [view view3d?])
         (or/c 'object-sorted 'triangle-sorted)]{Returns its transparent-pass
ordering policy.}
@defproc[(view3d-spatial-ref [view view3d?] [path spatial-path?]) spatial-visual?]{
Resolves a path rooted with the outer view identity, such as
@racket['(world cube)].
}
@defproc[(view3d-spatial-has? [view view3d?] [path any/c]) boolean?]{Reports
whether a rooted spatial path exists.}
@defproc[(view3d-spatial-replace [view view3d?] [path spatial-path?]
                                  [replacement spatial-visual?]) view3d?]{
Returns a view with one same-identity descendant replaced.}
@defproc[(view3d-spatial-update [view view3d?] [path spatial-path?]
                                 [update procedure?]) view3d?]{
Applies an immutable same-identity update to a descendant.}

@section{Spatial animation and camera authoring}

SCENE-3D-D keeps three-dimensional motion in the ordinary immutable
@racket[scene] timeline. A spatial target is a path beginning with its owning
@racket[view3d] identifier, for example @racket['(world cube)]. A camera target
is the owning view identifier alone, for example @racket['world]. Every request
captures its endpoint from the clip-start state. Sampling at a time does not
depend on having sampled an earlier frame.

@racketblock[
(scene-play
 (scene-add (make-scene) world matrix)
 (rotate3d-by '(world cube) (axis-angle y-axis3 pi))
 (camera3d-orbit-by 'world #:azimuth (/ pi 2))
 #:duration 2)
]

@defproc[(move3d-to [path spatial-path?] [position vec3?]) any/c]{Moves one
spatial Visual to an absolute local translation.}
@defproc[(move3d-by [path spatial-path?] [delta vec3?]) any/c]{Moves one
spatial Visual by a local translation from its clip-start value.}
@defproc[(rotate3d-to [path spatial-path?] [rotation rotation3?]) any/c]{Sets
an absolute local orientation.}
@defproc[(rotate3d-by [path spatial-path?] [rotation rotation3?]) any/c]{Applies
a local rotation after the clip-start orientation.}
@defproc[(scale3d-to [path spatial-path?] [scale vec3?]) any/c]{Sets a
nonzero componentwise local scale.}
@defproc[(scale3d-by [path spatial-path?] [factor vec3?]) any/c]{Multiplies
the clip-start componentwise local scale.}
@defproc[(transform3d-to [path spatial-path?] [transform transform3?]) any/c]{
Sets translation, rotation, and scale together. A scale interpolation that
would pass through zero is rejected when the clip is compiled.}

@defproc[(camera3d-move-to [view-id symbol?] [position vec3?]) any/c]{Moves a
camera to an absolute position, retaining its lens and orientation.}
@defproc[(camera3d-look-at-to [view-id symbol?] [target vec3?]
                              [#:up up vec3? y-axis3]) any/c]{Reorients a
camera to look at a world point.}
@defproc[(camera3d-orbit-by [view-id symbol?]
                             [#:center center vec3? origin3]
                             [#:azimuth azimuth finite-real? 0]
                             [#:elevation elevation finite-real? 0]) any/c]{
Creates a finite orbit about @racket[center]. Position follows the exact orbit;
at every sampled position, orientation is a normalized quaternion that looks
directly at @racket[center]. This prevents a camera from looking away from its
subject midway through a large orbit.}
@defproc[(camera3d-roll-to [view-id symbol?] [angle finite-real?]) any/c]{Sets
the absolute roll around the current forward direction.}
@defproc[(camera3d-field-of-view-to [view-id symbol?]
                                    [field-of-view finite-real?]) any/c]{
Interpolates a perspective camera's vertical field of view. It rejects an
orthographic camera.}
@defproc[(camera3d-orthographic-height-to [view-id symbol?]
                                           [height positive-real?]) any/c]{
Interpolates an orthographic camera's visible height. It rejects a perspective
camera.}
@defproc[(camera3d-dolly-by [view-id symbol?] [distance finite-real?]) any/c]{
Moves along the clip-start forward axis; positive distance moves forward.}
@defproc[(camera3d-fit [view-id symbol?]
                        [#:padding padding positive-real? 11/10]) any/c]{
Frames the current spatial bounds conservatively.}
@defproc[(camera3d-follow [view-id symbol?] [path spatial-path?]) any/c]{
Retains the clip-start camera offset from a spatial target path rooted at the
same view. It is resolved after local spatial transforms at each sampled time.}

All these forms work as leaves of @racket[timed], @racket[succession],
@racket[animation-group], and @racket[lagged-start]. A 3D camera remains
separate from the ordinary two-dimensional render camera, so a formula or
caption stays fixed while the view's spatial camera moves.

In interactive preview, an inspection camera is an overlay on the authored
camera: drag in a spatial viewport to orbit, shift-drag to pan its target, use
the mouse wheel to dolly (or orthographic zoom), and press @tt{R} to return to
the authored view. The override is part of the immutable preview render
request—including a subprocess worker request—and is never written into source
or the Scene. The Animate menu can reset it or copy an expression/animation
scratch form for authoring.

For runnable examples, see @filepath{examples/3d/wireframe-cube.rkt},
@filepath{examples/3d/opaque-cube.rkt}, and
@filepath{examples/3d/depth-test.rkt};
@filepath{examples/3d/camera-orbit.rkt} is the canonical motion probe.

@bold{Current limitation:} opaque mode is a software rasterizer for filled
triangles. It has flat, unlit, and smooth shading, depth-aware transparency,
spatial relations, and projected labels, but no texture mapping, no specular
response, no shadows, order-independent transparency, or 3D picking. An
ordinary two-dimensional traversal of a spatial child is rejected: use rooted
3D animation paths or @racket[view3d-spatial-*].

@section{Semantic spatial relations and projected labels}

SCENE-3D-E adds derived spatial geometry without a mutable per-frame updater.
A @racket[spatial-relation] is a spatial Visual declaration with a concrete
template, an explicit list of inputs, and a resolver. During a regular
@racket[scene] sample, Animate first samples ordinary spatial and camera
animation, then resolves spatial relations inside each @racket[view3d], then
renders the spatial viewport, and finally resolves projected labels as ordinary
two-dimensional Visuals. This order means a label may use the resolved
position of a relation result, while ordinary 2D layout can still use the
label.

The three dependency declarations make a resolver's inputs inspectable:

@defproc[(spatial-dependency? [value any/c]) boolean?]{Recognizes a declared
spatial relation dependency.}
@defproc[(spatial-visual-dependency [target spatial-path?]) spatial-dependency?]{
Declares a relative or view-rooted path to a spatial Visual.}
@defproc[(spatial-value-dependency [target symbol?]) spatial-dependency?]{
Declares one immutable named Scene value.}
@defproc[(spatial-camera-dependency [view-id symbol?]) spatial-dependency?]{
Declares the camera of one owning @racket[view3d].}

@defproc[(spatial-relation [template spatial-visual?]
                           [#:depends-on dependencies (listof spatial-dependency?) null]
                           [#:structure structure (or/c 'root-only 'fixed) 'root-only]
                           [#:cache-key cache-key any/c #f]
                           [resolver procedure?])
         spatial-relation?]{
Creates a semantic spatial Visual. @racket[resolver] accepts a
@racket[spatial-relation-context?] and the transform-free local template, and
must return concrete spatial geometry with the template's ID. Its outer
transform and opacity remain independently animatable.

A @racket['root-only] relation may change all of its internal structure and can
only be addressed at its own root path. A @racket['fixed] relation must return
the template's exact child-ID tree, so a descendant is addressable. Generic
resolver procedures are intentionally not cross-process-cacheable; supply a
stable @racket[#:cache-key] to declare an explicit cache identity.}

@defproc[(spatial-relation? [value any/c]) boolean?]{Recognizes a semantic
spatial relation.}
@defproc[(spatial-relation-dependencies [relation spatial-relation?])
         (listof spatial-dependency?)]{Returns the declared inputs.}
@defproc[(spatial-relation-structure [relation spatial-relation?])
         (or/c 'root-only 'fixed)]{Returns the declared structural policy.}
@defproc[(spatial-relation-cacheability [relation spatial-relation?])
         (or/c 'explicit-key 'disabled)]{Reports whether the relation has an
explicit stable cache key.}

The resolver context is read-only and accepts only declared inputs.
@defproc[(spatial-relation-context? [value any/c]) boolean?]{Recognizes a
spatial relation resolver context.}
@defproc[(spatial-relation-context-spatial-ref
          [context spatial-relation-context?] [target spatial-path?])
         spatial-visual?]{Resolves a declared relative or rooted target.}
@defproc[(spatial-relation-context-spatial-world-transform
          [context spatial-relation-context?] [target spatial-path?])
         affine3?]{Returns a declared target's sampled world transform.}
@defproc[(spatial-relation-context-spatial-position
          [context spatial-relation-context?] [target spatial-path?])
         vec3?]{Returns a declared target's sampled world origin.}
@defproc[(spatial-relation-context-value-ref
          [context spatial-relation-context?] [target symbol?])
         any/c]{Reads a declared immutable named Scene value.}
@defproc[(spatial-relation-context-camera [context spatial-relation-context?])
         camera3d?]{Reads the declared camera of the owning view.}

An undeclared access is an authoring error. Relations resolve lazily with one
cache for the sampled viewport; a cycle reports complete paths rooted at the
owning view, such as @racket['(world links ab)].

The initial relation vocabulary is intentionally small:

@defproc[(segment-between3d [from spatial-path?] [to spatial-path?]
                             [#:id id symbol?]
                             [#:color color any/c "slategray"]
                             [#:width width positive-real? 2]
                             [#:opacity opacity real? 1])
         spatial-relation?]{Produces a finite semantic segment between the
current world origins of two declared targets.}
@defproc[(line-between3d [from spatial-path?] [to spatial-path?]
                          [#:id id symbol?]
                          [#:padding padding nonnegative-real? 10]
                          [#:color color any/c "slategray"]
                          [#:width width positive-real? 2]
                          [#:opacity opacity real? 1])
         spatial-relation?]{Produces the displayed portion of the infinite
line through two current origins.}
@defproc[(arrow-between3d [from spatial-path?] [to spatial-path?]
                           [#:id id symbol?]
                           [#:color color any/c "slategray"]
                           [#:width width positive-real? 2]
                           [#:tip-size tip-size positive-real? 1/4]
                           [#:opacity opacity real? 1])
         spatial-relation?]{Produces a segment with a small semantic arrow
head at @racket[to].}
@defproc[(plane-through3d [first spatial-path?] [second spatial-path?]
                           [third spatial-path?] [#:id id symbol?]
                           [#:color color any/c "lightskyblue"]
                           [#:opacity opacity real? 1])
         spatial-relation?]{Produces a double-sided triangular plane through
three current origins.}
@defproc[(normal-at3d [target spatial-path?] [normal vec3?]
                       [#:id id symbol?]
                       [#:length length positive-real? 1]
                       [#:color color any/c "darkmagenta"]
                       [#:width width positive-real? 2]
                       [#:tip-size tip-size positive-real? 1/4]
                       [#:opacity opacity real? 1])
         spatial-relation?]{Produces a directed normal marker from a target's
current origin.}
@defproc[(distance-segment3d [from spatial-path?] [to spatial-path?]
                              [#:id id symbol?]
                              [#:color color any/c "darkgoldenrod"]
                              [#:width width positive-real? 2]
                              [#:opacity opacity real? 1])
         spatial-relation?]{Produces a semantically named finite distance
segment.}

@defproc[(distance-dimension3d [from spatial-path?] [to spatial-path?]
                                [#:id id symbol?]
                                [#:offset offset vec3? (vec3 0 1/3 0)]
                                [#:color color any/c "darkgoldenrod"]
                                [#:width width positive-real? 2]
                                [#:tip-size tip-size positive-real? 1/6]
                                [#:opacity opacity real? 1])
         spatial-relation?]{Produces extension segments and a two-ended
dimension line. The offset is an explicit world-space vector, so the mark
retains mathematical meaning under camera motion.}
@defproc[(angle-marker3d [first spatial-path?] [vertex spatial-path?]
                          [second spatial-path?] [#:id id symbol?]
                          [#:radius radius positive-real? 1/3]
                          [#:samples samples exact-integer? 12]
                          [#:color color any/c "darkorange"]
                          [#:width width positive-real? 2]
                          [#:opacity opacity real? 1])
         spatial-relation?]{Produces the smaller arc from @racket[first]
through @racket[vertex] to @racket[second]. The three current points must
remain non-collinear.}
@defproc[(right-angle-marker3d [first spatial-path?] [vertex spatial-path?]
                                [second spatial-path?] [#:id id symbol?]
                                [#:size size positive-real? 1/3]
                                [#:color color any/c "darkorange"]
                                [#:width width positive-real? 2]
                                [#:opacity opacity real? 1])
         spatial-relation?]{Produces a three-segment corner following the
two current rays. It is square when the rays are perpendicular; it deliberately
does not silently assert that an animated non-right configuration is right.}
@defproc[(dihedral-angle3d [axis-from spatial-path?] [axis-to spatial-path?]
                            [first-face-point spatial-path?]
                            [second-face-point spatial-path?]
                            [#:id id symbol?]
                            [#:radius radius positive-real? 1/3]
                            [#:samples samples exact-integer? 12]
                            [#:color color any/c "darkorange"]
                            [#:width width positive-real? 2]
                            [#:opacity opacity real? 1])
         spatial-relation?]{Produces a signed smaller arc around the ordered
hinge, using one off-axis point from each incident face. Face points on the
hinge and coincident face directions are rejected when the relation resolves.}
@defproc[(normal-marker3d [target spatial-path?] [normal vec3?]
                           [#:id id symbol?]
                           [#:length length positive-real? 1]
                           [#:color color any/c "darkmagenta"]
                           [#:width width positive-real? 2]
                           [#:tip-size tip-size positive-real? 1/4]
                           [#:opacity opacity real? 1])
         spatial-relation?]{The fixed-child-tree annotation spelling of
@racket[normal-at3d]. The supplied normal is a world direction.}
@defproc[(coordinate-tripod3d [target spatial-path?] [#:id id symbol?]
                               [#:length length positive-real? 1]
                               [#:width width positive-real? 2]
                               [#:tip-size tip-size positive-real? 1/4]
                               [#:x-color x-color any/c "firebrick"]
                               [#:y-color y-color any/c "forestgreen"]
                               [#:z-color z-color any/c "royalblue"]
                               [#:opacity opacity real? 1])
         spatial-relation?]{Produces three current-origin arrows for the
fixed world x, y, and z directions.}

@defproc[(projected-label [template visual?] [#:view view-id symbol?]
                          [#:target target (or/c vec3? spatial-path?)]
                          [#:offset offset vec2? origin]
                          [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                           'always-visible]
                          [#:placement placement label-placement3d?
                           default-label-placement3d]
                          [#:leader leader (or/c #f leader-style3d?) #f]
                          [#:visibility visibility (or/c 'always 'inside-frustum
                                                        'anchor-visible)
                           'always])
         projected-label?]{
Creates an ordinary 2D text, formula, or other concrete Visual whose centre
follows a point projected through a sampled @racket[view3d]. @racket[offset]
is in screen pixels (with Animate's y-up convention), so it is not enlarged
or rotated by the spatial camera. The final compositor jointly measures and
places sibling labels. @racket['inside-frustum] suppresses an anchor outside
the camera rectangle; @racket['anchor-visible] additionally suppresses an
anchor behind opaque geometry. A @racket[leader-style3d] requests a crisp
two-dimensional grey connector from the selected label-box attachment to its
projected anchor; @racket['nearest] and @racket['center] are the supported
attachments, and @racket[elbow?] selects a horizontal-first elbow.}
@defproc[(projected-label? [value any/c]) boolean?]{Recognizes a projected
label definition.}
@defstruct*[label-placement3d ([preferred list?]
                               [distance nonnegative-real?]
                               [candidates exact-positive-integer?]
                               [keep-inside? boolean?]
                               [avoid-overlap? boolean?]
                               [avoid list?]
                               [stability-weight nonnegative-real?]
                               [leader-threshold nonnegative-real?])
  #:transparent]{The immutable direct-mode placement policy. Directions are
chosen in declared @racket[preferred] order when candidate costs tie.}
@defthing[default-label-placement3d label-placement3d?]{The standard
north-east-first direct placement policy.}
@defstruct*[leader-style3d ([attachment (or/c 'nearest 'center)]
                            [elbow? boolean?]
                            [minimum-length nonnegative-real?])
  #:transparent]{Requests a compositor leader. Its length is measured in
output pixels after label placement.}
@defproc[(follow-projected-point [template visual?] [#:view view-id symbol?]
                                 [#:point point vec3?]
                                 [#:offset offset vec2? origin]
                                 [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                  'always-visible]
                                 [#:placement placement label-placement3d?
                                  default-label-placement3d]
                                 [#:leader leader (or/c #f leader-style3d?) #f]
                                 [#:visibility visibility (or/c 'always 'inside-frustum
                                                               'anchor-visible)
                                  'always])
         projected-label?]{The literal-point spelling of @racket[projected-label].}
@defproc[(follow-projected-spatial [template visual?] [#:view view-id symbol?]
                                   [#:target target spatial-path?]
                                   [#:offset offset vec2? origin]
                                   [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                    'always-visible]
                                   [#:placement placement label-placement3d?
                                    default-label-placement3d]
                                   [#:leader leader (or/c #f leader-style3d?) #f]
                                   [#:visibility visibility (or/c 'always 'inside-frustum
                                                                 'anchor-visible)
                                    'always])
         projected-label?]{The spatial-path spelling of @racket[projected-label].}

The canonical example uses all of this without a second timeline:

@racketblock[
(define label-a
  (follow-projected-spatial
   (math-tex #:id 'label-a "A")
   #:view 'world
   #:target '(tetrahedron A)
   #:offset (vec2 -20 -18)))

(scene-play
 (scene-add (make-scene) world label-a)
 (rotate3d-by '(world tetrahedron) (axis-angle y-axis3 pi))
 (camera3d-orbit-by 'world #:azimuth pi)
 #:duration 2)
]

For the complete moving tetrahedron with labels A–D, see
@filepath{examples/3d/projected-labels.rkt}.

@section{Textured billboards}

@racket[billboard3d] is the depth-tested spatial counterpart to a projected
label. It is appropriate for a sprite, image annotation, or marker that must
exist in the 3D viewport rather than above it. A billboard image is immutable
straight-ARGB data, so it can be sampled by a render worker and uploaded by an
OpenGL renderer without retaining a GUI @tt{bitmap%} or a renderer-local
texture in the Scene.

@defproc[(billboard-image3d [width exact-positive-integer?]
                             [height exact-positive-integer?]
                             [argb bytes?])
         billboard-image3d?]{Creates an immutable source image. @racket[argb]
contains exactly four bytes per pixel in top-to-bottom straight ARGB order.
The constructor copies the bytes.}
@defproc[(billboard-image3d? [value any/c]) boolean?]{Recognizes a billboard
image source.}
@defproc[(billboard-style3d [#:width width positive? 32]
                             [#:height height (or/c #f positive?) #f]
                             [#:size-mode size-mode (or/c 'screen 'world) 'screen]
                             [#:facing facing (or/c 'camera 'axis) 'camera]
                             [#:axis axis vec3? y-axis3]
                             [#:opacity opacity (real-in 0 1) 1]
                             [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                             [#:depth-bias depth-bias nonnegative-real? 1e-5])
         billboard-style3d?]{Creates an immutable billboard policy. In
@racket['screen] mode, @racket[width] and @racket[height] are output pixels;
in @racket['world] mode they are physical plane dimensions. An omitted height
preserves image aspect ratio. @racket['camera] uses camera image-plane axes;
@racket['axis] keeps @racket[axis] upright and rotates around it toward the
camera. Axis-facing therefore requires world sizing. Depth modes have the same
meaning as @racket[stroke3d]: @racket['test] is normally occluded,
@racket['always] is an overlay, and @racket['hidden] paints only behind opaque
geometry.}
@defproc[(billboard3d [image billboard-image3d?] [position vec3?]
                      [#:id id symbol?]
                      [#:style style billboard-style3d? (billboard-style3d)]
                      [#:transform transform transform3? identity-transform3]
                      [#:opacity opacity (real-in 0 1) 1])
         spatial-visual?]{Creates one immutable spatial billboard. Its child
path is stable, its camera-dependent plane is resolved only during frame
preparation, and transparent texels do not write scene depth.}

The software renderer and the explicit Racket/OpenGL renderer consume the same
prepared corners, depth policy, and ARGB source. The executable probe is
@filepath{examples/3d/textured-billboards.rkt}.

@bold{Billboard limitations:} source images use nearest sampling; a billboard
whose world quad crosses the frustum boundary is conservatively omitted rather
than clipped; partial alpha does not write depth; and billboards do not yet
participate in exact spatial picking or cast/receive shadows. Use
@racket[projected-label] for source-mapped formulas and crisp vector text.

@section{Spatial curves and vector diagrams}

SCENE-3D-F added finite spatial diagram geometry; SCENE-3D-O separates a
sampled curve's centreline from its rendering style. A mathematical
@racket[stroke3d] is resolved after projection and can retain a constant pixel
width. A @racket[tube-style3d] creates explicit physical tube geometry whose
apparent width changes with the camera. Partial curves, reveals, and
curve-following are sampled directly from the complete immutable centreline at
the requested scene time; they never use a mutable updater or the preceding
frame.

@defproc[(stroke3d [#:color color color-spec? "steelblue"]
                   [#:width width positive? 2]
                   [#:width-mode width-mode (or/c 'screen 'world) 'screen]
                   [#:cap cap (or/c 'butt 'square 'round) 'round]
                   [#:join join (or/c 'miter 'bevel 'round) 'round]
                   [#:miter-limit miter-limit positive? 4]
                   [#:dash dash (or/c #f list? vector?) #f]
                   [#:dash-offset dash-offset finite-real? 0]
                   [#:dash-space dash-space (or/c 'screen 'world) width-mode]
                   [#:opacity opacity (real-in 0 1) 1]
                   [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                   [#:depth-bias depth-bias nonnegative-real? 1e-5])
         stroke3d?]{Creates an immutable mathematical-stroke style. In
@racket['screen] mode, width and default dashes are pixels after projection;
in @racket['world] mode width is a full physical diameter. A dash pattern is
an even-length list or vector of positive finite lengths. @racket['test]
draws visible portions, @racket['hidden] draws occluded portions, and
@racket['always] ignores depth.}
@defproc[(stroke3d? [value any/c]) boolean?]{Recognizes a stroke style.}
@defproc[(stroke3d-color [style stroke3d?]) color-spec?]{Returns stroke colour.}
@defproc[(stroke3d-width [style stroke3d?]) positive?]{Returns width.}
@defproc[(stroke3d-width-mode [style stroke3d?]) (or/c 'screen 'world)]{Returns width units.}
@defproc[(stroke3d-cap [style stroke3d?]) (or/c 'butt 'square 'round)]{Returns endpoint-cap style.}
@defproc[(stroke3d-join [style stroke3d?]) (or/c 'miter 'bevel 'round)]{Returns polyline-join style.}
@defproc[(stroke3d-miter-limit [style stroke3d?]) positive?]{Returns miter limit.}
@defproc[(stroke3d-dash [style stroke3d?]) (or/c #f vector?)]{Returns the validated dash pattern.}
@defproc[(stroke3d-dash-offset [style stroke3d?]) finite-real?]{Returns dash phase.}
@defproc[(stroke3d-dash-space [style stroke3d?]) (or/c 'screen 'world)]{Returns dash units.}
@defproc[(stroke3d-opacity [style stroke3d?]) (real-in 0 1)]{Returns local opacity.}
@defproc[(stroke3d-depth-mode [style stroke3d?]) (or/c 'test 'always 'hidden)]{Returns depth policy.}
@defproc[(stroke3d-depth-bias [style stroke3d?]) nonnegative-real?]{Returns normalized depth bias.}
@defproc[(stroke3d-with-color [style stroke3d?] [color color-spec?]) stroke3d?]{Recolours a stroke.}
@defproc[(stroke3d-with-opacity [style stroke3d?] [opacity (real-in 0 1)]) stroke3d?]{Changes local opacity.}

@defproc[(tube-style3d [#:radius radius positive? 1/20]
                        [#:sides sides exact-positive-integer? 8]
                        [#:color color color-spec? "steelblue"])
         tube-style3d?]{Creates the explicit physical style used when a curve
should lower to a tube mesh.}
@defproc[(tube-style3d? [value any/c]) boolean?]{Recognizes a tube style.}
@defproc[(tube-style3d-radius [style tube-style3d?]) positive?]{Returns physical radius.}
@defproc[(tube-style3d-sides [style tube-style3d?]) exact-positive-integer?]{Returns radial tessellation count.}
@defproc[(tube-style3d-color [style tube-style3d?]) color-spec?]{Returns tube colour.}

@defproc[(point-style3d [#:size size positive? 8]
                         [#:size-mode size-mode (or/c 'screen 'world) 'screen]
                         [#:color color color-spec? "cornflowerblue"]
                         [#:opacity opacity (real-in 0 1) 1]
                         [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                         [#:depth-bias depth-bias nonnegative-real? 1e-5])
         point-style3d?]{Creates a circular point-marker style. Screen size is
its diameter in pixels; world size is a physical diameter projected at the
point anchor.}
@defproc[(point-style3d? [value any/c]) boolean?]{Recognizes a point-marker style.}
@defproc[(arrow-style3d [#:length length positive? 12]
                         [#:length-mode length-mode (or/c 'screen 'world) 'screen]
                         [#:width width (or/c #f positive?) #f]
                         [#:color color color-spec? "tomato"]
                         [#:opacity opacity (real-in 0 1) 1]
                         [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                         [#:depth-bias depth-bias nonnegative-real? 1e-5])
         arrow-style3d?]{Creates a screen or world arrowhead style. Its
direction is taken from the final projected nondegenerate shaft segment.}
@defproc[(arrow-style3d? [value any/c]) boolean?]{Recognizes an arrowhead style.}

@defproc[(point3d [position vec3?] [#:id id symbol?]
                  [#:style style point-style3d? (point-style3d)])
         spatial-visual?]{Creates one finite screen/world point marker.}
@defproc[(curve3d? [value any/c]) boolean?]{Recognizes a sampled spatial curve.}
@defproc[(line3d [from vec3?] [to vec3?] [#:id id symbol?]
                 [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)])
         curve3d?]{Creates a finite straight spatial line. The alias
@racket[segment3d] has the same arguments.}
@defproc[(segment3d [from vec3?] [to vec3?] [#:id id symbol?]
                    [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)])
         curve3d?]{Creates the same finite geometry as @racket[line3d].}
@defproc[(polyline3d [points (or/c list? vector?)] [#:id id symbol?]
                     [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)]
                     [#:closed? closed? boolean? #f]
                     [#:transform transform transform3? identity-transform3]
                     [#:opacity opacity (real-in 0 1) 1])
         curve3d?]{Creates a sampled polyline. Adjacent repeated points are
removed before stroke preparation or tube frames are formed.}
@defproc[(parametric-curve3d [procedure procedure?]
                             [#:range range (list/c finite-real? finite-real?) (list 0 1)]
                             [#:samples samples exact-positive-integer? 64]
                             [#:id id symbol?]
                             [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)]
                             [#:closed? closed? boolean? #f])
         curve3d?]{Samples @racket[procedure] at equally spaced, inclusive
range endpoints. The declared @racket[samples] locations are deterministic.}
@defproc[(tube3d [points (or/c list? vector?)] [#:id id symbol?]
                [#:radius radius positive? 1/20]
                [#:sides sides exact-positive-integer? 8]
                [#:closed? closed? boolean? #f]
                [#:width-mode width-mode 'world])
         mesh3d?]{Creates a tube mesh using transported local frames.}
@defproc[(arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                  [#:shaft-style shaft-style stroke3d? (stroke3d #:color "tomato")]
                  [#:tip-style tip-style arrow-style3d? (arrow-style3d #:color "tomato")])
         group3d?]{Creates a shaft and screen/world marker tip at stable
descendants @racket['shaft] and @racket['tip].}
@defproc[(double-arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                         [#:shaft-style shaft-style stroke3d? (stroke3d #:color "tomato")]
                         [#:tip-style tip-style arrow-style3d? (arrow-style3d #:color "tomato")])
         group3d?]{Creates a shaft with one marker tip at each endpoint.}

@defproc[(with-edges3d [mesh mesh3d?]
                        [#:edges edges (or/c 'explicit 'all 'boundary 'crease 'silhouette 'feature) 'feature]
                        [#:visible visible (or/c #f stroke3d?) (stroke3d #:color "black" #:width 2)]
                        [#:hidden hidden (or/c #f stroke3d?) #f]
                        [#:crease-angle crease-angle finite-real? (/ pi 6)]
                        [#:surface surface (or/c 'visible 'depth-only 'none) 'visible])
         edge-overlay3d?]{Wraps a mesh with camera-prepared outlines without
adding a path component. @racket['feature] means boundary, crease, and
silhouette edges. A @racket['depth-only] surface occludes lines without
painting a surface colour.}
@defproc[(edge-style3d? [value any/c]) boolean?]{Recognizes a mesh-outline style.}
@defproc[(edge-overlay3d? [value any/c]) boolean?]{Recognizes an outlined mesh wrapper.}

@defproc[(axes3d [#:id id symbol?]
                  [#:x-range x-range list? (list -3 3)]
                  [#:y-range y-range list? (list -3 3)]
                  [#:z-range z-range list? (list -3 3)])
         group3d?]{Creates finite axes. Paths such as
@racket['(world axes x-axis)], @racket['(world axes x-ticks)], and
@racket['(world axes labels x)] remain stable. The final path is an invisible
3D anchor intended for @racket[follow-projected-spatial].}
@defproc[(coordinate-plane3d [plane (or/c 'xy 'xz 'yz)] [#:id id symbol?])
         mesh3d?]{Creates one finite double-sided coordinate plane.}
@defproc[(grid-plane3d [plane (or/c 'xy 'xz 'yz)] [#:id id symbol?])
         group3d?]{Creates a finite grid of physical-width spatial lines.}
@defproc[(basis-vectors3d [#:id id symbol?]) group3d?]{Creates coloured i, j,
and k arrows.}
@defproc[(vector-arrow3d [vector vec3?] [#:id id symbol?]) group3d?]{Creates
one arrow from the origin to @racket[vector].}
@defproc[(vector-components3d [vector vec3?] [#:id id symbol?]) group3d?]{Creates
orthogonal component arrows plus a resultant at stable descendants.}

@defproc[(move-along-curve3d [target spatial-path?] [curve spatial-path?]
                              [#:start start finite-real? 0]
                              [#:end end finite-real? 1]) any/c]{Moves a
spatial target by arc-length fraction along a curve path in the same
@racket[view3d].}
@defproc[(orient-along-curve3d [target spatial-path?] [curve spatial-path?]
                                [#:start start finite-real? 0]
                                [#:end end finite-real? 1]) any/c]{Rotates the
target's local positive x direction to the sampled tangent.}

For an already-present curve path, @racket[(create '(world curve))],
@racket[(uncreate '(world curve))], and @racket[(show-passing-flash
'(world curve))] use the same direct curve sampling. A passing flash adds a
temporary coloured tube sliver over its unchanged source curve; it disappears
at each clip endpoint. The canonical vector-camera-orbit example is
@filepath{examples/3d/vector-components.rkt}.

@section{Parametric surfaces and calculus}

SCENE-3D-G adds fixed-topology rectangular parametric surfaces. A surface is
sampled once at inclusive parameter-grid sites and therefore has stable vertex
and triangle identities. Its normals use declared analytic derivatives when
both are supplied; otherwise they use deterministic centred/one-sided finite
differences, adjacent-face fallback, and explicit unresolved-index reporting.

@defproc[(parametric-surface3d [procedure procedure?]
                               [#:u-range u-range list? (list -1 1)]
                               [#:v-range v-range list? (list -1 1)]
                               [#:resolution resolution list? (list 33 33)]
                               [#:id id symbol?]) surface3d?]{Creates a fixed
rectangular sampled parameterization.}
@defproc[(function-surface3d [function procedure?]
                             [#:x-range x-range list? (list -1 1)]
                             [#:y-range y-range list? (list -1 1)]
                             [#:resolution resolution list? (list 33 33)]
                             [#:id id symbol?]) surface3d?]{Creates the graph
@racket[(vec3 x y (function x y))] and retains scalar-field data for calculus
helpers.}
@defproc[(surface3d? [value any/c]) boolean?]{Recognizes an immutable sampled
surface.}
@defproc[(surface3d-resolution [surface surface3d?]) list?]{Returns its fixed
@racket[(list u-count v-count)] topology.}
@defproc[(surface3d-position-at [surface surface3d?] [u finite-real?]
                                 [v finite-real?]) vec3?]{Evaluates a point in
the authored parameter domain.}
@defproc[(surface3d-normal-at [surface surface3d?] [u finite-real?]
                               [v finite-real?]) vec3?]{Returns a safe unit
normal, using the recorded deterministic fallback when necessary.}
@defproc[(surface-color [surface surface3d?] [color color-spec?]) surface3d?]{
Changes the uniform material colour without changing samples or topology.}
@defproc[(surface-color-by-height [surface surface3d?]) surface3d?]{Adds an
opaque per-vertex z-height colour field.}
@defproc[(surface-color-by-scalar [surface surface3d?] [scalar procedure?])
         surface3d?]{Adds a deterministic opaque per-vertex colour ramp from
the scalar evaluated at each existing sample.}
@defproc[(surface-checkerboard [surface surface3d?]) surface3d?]{Adds a
deterministic parameter-space checkerboard colour field.}
@defproc[(surface-point [surface surface3d?] [u finite-real?] [v finite-real?]
                        [#:id id symbol?]) mesh3d?]{Creates a point at a
surface parameter.}
@defproc[(surface-tangent-u [surface surface3d?] [u finite-real?]
                            [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the @racket[u] tangent direction.}
@defproc[(surface-tangent-v [surface surface3d?] [u finite-real?]
                            [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the @racket[v] tangent direction.}
@defproc[(surface-normal [surface surface3d?] [u finite-real?]
                          [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the direct tangent-plane normal direction.}
@defproc[(surface-tangent-plane [surface surface3d?] [u finite-real?]
                                 [v finite-real?] [#:id id symbol?]) mesh3d?]{
Creates a finite tangent parallelogram at the parameter point.}
@defproc[(surface-coordinate-curve [surface surface3d?] [#:id id symbol?])
         curve3d?]{Samples one fixed-@racket[u] or fixed-@racket[v] coordinate
curve.}
@defproc[(surface-gradient-arrow [surface surface3d?] [x finite-real?]
                                  [y finite-real?] [#:id id symbol?]) group3d?]{
Creates the xy gradient arrow for a declared @racket[function-surface3d].}

@section{Adaptive, trimmed, and implicit surfaces}

SCENE-3D-Q adds three producers which all lower to the same immutable indexed
surface record returned by @racket[surface3d-mesh].  The record preserves
vertex and triangle provenance as well as a topology key, while renderer
caches remain outside authored values.

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
boundary.  The initial extractor is a fixed-resolution algorithm; it does not
yet adapt its 3D cells. @racket[view3d-surface-pick] uses the ordinary CPU BVH
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

The canonical acceptance scene is @filepath{examples/3d/tangent-plane.rkt}.

@section{Constructive solids}

SCENE-3D-H adds deterministic indexed solid meshes. The standard constructors
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
area-weighted shared-vertex normals.}
@defproc[(mesh3d-flat-normals [mesh mesh3d?]) mesh3d?]{Duplicates face vertices
so every triangle receives one normal.}
@defproc[(mesh3d-boundary-edges [mesh mesh3d?]) vector?]{Reports its
deterministically ordered manifold boundary edges.}

The canonical acceptance scene is @filepath{examples/3d/solid-of-revolution.rkt}.

@section{Clipping, sections, and transparency}

SCENE-3D-I distinguishes a render instruction from a geometric operation.
@racket[clip3d] keeps its source subtree intact and clips only the triangles
submitted to a @racket[view3d] renderer. @racket[slice-mesh3d] instead returns
new half-space mesh geometry; it deliberately does not invent a cap. Use
@racket[section-by-plane3d] for the actual plane intersection and
@racket[section-curve3d] to draw every loop or open chain as ordinary spatial
curves.

@defproc[(clip-plane3d [plane plane3?]
                        [#:keep keep (or/c 'positive 'negative) 'positive])
         clip-plane3d?]{Describes the retained half-space of a clipping plane.}
@defproc[(clip-plane3d? [value any/c]) boolean?]{Recognizes a clipping-plane
description.}
@defproc[(clip3d [content spatial-visual?]
                  [clip (or/c plane3? clip-plane3d?)]
                  [#:id id symbol?])
         clip3d?]{Wraps one spatial subtree with local render-only clipping.}
@defproc[(clip3d? [value any/c]) boolean?]{Recognizes a render-clip wrapper.}
@defproc[(slice-mesh3d [mesh mesh3d?]
                        [clip (or/c plane3? clip-plane3d?)])
         mesh3d?]{Returns actual, deterministically triangulated clipped mesh
geometry in the source mesh's local coordinates. Generated cut vertices reuse
one source-edge registry and therefore interpolate the supported per-vertex
normal and RGBA colour attributes consistently across neighbouring triangles.}
@defproc[(slice-mesh-by-planes3d [mesh mesh3d?]
                                  [clips (listof (or/c plane3? clip-plane3d?))])
         mesh3d?]{Applies plane cuts in declaration order to produce actual
geometry. This is not @racket[clip-planes3d], which remains render-only.}
@defproc[(section-by-plane3d [mesh mesh3d?]
                              [clip (or/c plane3? clip-plane3d?)])
         section3d?]{Returns deterministic @racket[section3d] topology. Its
@racket[section3d-loops] and @racket[section3d-chains] accessors distinguish
closed components from open ones.}
@defproc[(section3d? [value any/c]) boolean?]{Recognizes plane-section
topology.}
@defproc[(section3d-loops [section section3d?]) (listof (listof vec3?))]{Returns
its closed components in deterministic plane orientation.}
@defproc[(section3d-chains [section section3d?]) (listof (listof vec3?))]{Returns
its open components in deterministic endpoint order.}
@defproc[(section-curve3d [mesh mesh3d?]
                           [clip (or/c plane3? clip-plane3d?)]
                           [#:id id symbol?])
         group3d?]{Builds a group of physical-radius tube curves for every
section component.}

@racket[material3d] accepts an alpha-bearing semantic colour. In an opaque
@racket[view3d], fully opaque geometry writes the depth buffer first; transparent
geometry is then rendered far-to-near with @racket['object-sorted] or
@racket['triangle-sorted] @racket[#:transparency-mode]. Transparent triangles
depth-test against opaque geometry but do not write depth. A
@racket[projected-label] accepts @racket[#:occlusion 'always-visible],
@racket['hide], or @racket['fade]; its occlusion test uses that opaque depth
target, preserving the label as a crisp 2D Visual.

@section{Cuts, caps, and section measurements}

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

@section{Spatial anchors and label layout}

SCENE-3D-S begins the annotation layer with immutable @racket[anchor3d?]
descriptors. @racket[vertex-anchor3d], @racket[edge-anchor3d],
@racket[face-anchor3d], @racket[curve-anchor3d], @racket[surface-anchor3d],
and bounds/origin anchors resolve after every spatial transformation into a
@racket[resolved-anchor3d] world point, normal/tangent when available, source
path, and stable provenance identity. Parametric surface anchors—including
generated adaptive and trimmed surfaces—expose evaluated normals and
@racket[u]-tangents after their complete world transform. A
@racket[surface-pick-anchor3d] carries an immutable exact pick provenance;
this makes an implicit surface's interpolated normal available without
pretending it owns a UV tangent frame.

@defproc[(surface-pick-anchor3d [pick surface-pick3d?]) anchor3d?]{Creates an
immutable anchor from one exact surface-picking result. Parametric picks retain
their UV coordinate. Implicit picks retain the lowered triangle index and
barycentric point, so later spatial transforms affect the resolved world point
and normal without mutating the original pick.}

@racket[label3d] uses such an anchor while retaining its content as a crisp
ordinary 2D Visual. @racket[label-placement3d] and
@racket[layout-labels3d] provide a deterministic, pure direct-mode candidate
layout in output pixels. The outer scene compositor resolves and measures all
projected labels for a sampled frame before it positions any one label, then
consumes that one batched direct layout without re-rendering the viewport.
@racket[prepare-label-layout3d] optionally computes
an immutable dynamic-programming candidate table for a declared finite frame
grid, applying explicit movement and switching penalties without relying on
the previously displayed frame. Equal-priority labels retain declaration order,
and equal-cost candidates retain the declared preferred-direction order.

@defproc[(prepare-scene-label-layout3d
          [scene scene?]
          [#:frames frames (listof exact-nonnegative-integer?)]
          [#:view view-id (or/c #f symbol?) #f]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c #f camera?) #f]
          [#:supersample supersample exact-positive-integer? 1]
          [#:switch-penalty switch-penalty nonnegative-real? 0]
          [#:movement-penalty movement-penalty nonnegative-real? 0])
         prepared-label-layout3d?]{Samples the declared source-frame grid,
resolves and measures the same stable projected-label slots used by final
composition, and returns an immutable table.  A @racket[#:view] selection
prepares one @racket[view3d] while labels in other viewports keep their direct
layout.  The function has no previous-frame dependency and does not create a
3D renderer artifact while it measures labels.  Supply its result through the
@racket[#:prepared-label-layout] option of @racket[scene-frame->bitmap],
@racket[render-frame-indices!], or the project render operations.}

Current limitations: prepared tables are explicit render inputs rather than a
default project-render policy, and a table applies only to the source-frame
grid and viewport raster for which it was measured. Core
world-space dimensions, angle markers, normal markers, and coordinate tripods
are fixed-structure spatial relations, but they do not yet supply automatic
formula labels or camera-facing screen sizing. Leaders are fixed one-pixel grey
2D paths and are attached for top-level projected labels; they intentionally do
not claim 3D occlusion or textured styling. The executable anchor probe is
@filepath{examples/3d/anchor-aware-labels.rkt}.

The canonical acceptance scene is
@filepath{examples/3d/sphere-plane-section.rkt}.

@section{Spatial maps and homotopies}

SCENE-3D-J adds map requests to the ordinary immutable @racket[scene]
timeline. Every target is a rooted spatial path, and every map procedure is
authored in world coordinates. This makes a map applied to a nested child mean
the same thing as applying it to an equivalent top-level child. A surrounding
parent map must therefore be invertible when the result is rebased into that
parent's local coordinate system.

@racket[apply-linear3] and @racket[apply-affine3] retain the original spatial
subtree and attach a full affine map to it. They consequently preserve the
indexed topology exactly, even for a shear, reflection, or singular map. A
named child of a transformed @racket[group3d] remains addressable. The
canonical @racket[linear-transformation-diagram3d] groups coordinate planes,
a unit cube, basis arrows, and an arbitrary vector so one map applies to all
of them coherently.

@racketblock[
(scene-play
 (scene-add (make-scene) world)
 (apply-linear3 '(world diagram)
                (linear3 1 0 1
                         0 1 0
                         0 0 1))
 (apply-homotopy3
  '(world sheet)
  (lambda (point phase)
    (vec3 (vec3-x point)
          (* (cos phase) (vec3-y point))
          (* (sin phase) (vec3-y point)))))
 #:duration 2)
]

@defproc[(linear-transformation-diagram3d
          [#:id id symbol?]
          [#:vector vector vec3? (vec3 3/2 1 1/2)]
          [#:cube-side cube-side positive-real? 1]
          [#:plane-size plane-size positive-real? 3])
         group3d?]{Creates the named coordinate-plane, unit-cube, basis-arrow,
and vector diagram intended for a coherent linear transformation.}
@defproc[(apply-linear3 [path spatial-path?] [map linear3?]) any/c]{Animates a
world-coordinate linear map from identity to @racket[map].}
@defproc[(apply-affine3 [path spatial-path?] [map affine3?]) any/c]{Animates a
world-coordinate affine map from identity to @racket[map].}
@defproc[(apply-pointwise3 [path spatial-path?] [map-point procedure?]
                            [#:on-failure on-failure
                             (or/c 'error 'drop-triangle) 'error]
                            [#:recompute-normals? recompute-normals? boolean? #t])
         any/c]{Maps the source mesh's authored world-space vertices. During
the clip, each vertex moves linearly from its source position to
@racket[(map-point source-point)]. The default reports a bad map result; the
explicit @racket['drop-triangle] policy removes every incident triangle.}
@defproc[(apply-homotopy3 [path spatial-path?] [homotopy procedure?]
                           [#:on-failure on-failure
                            (or/c 'error 'drop-triangle) 'error]
                           [#:recompute-normals? recompute-normals? boolean? #t])
         any/c]{Evaluates @racket[(homotopy source-point phase)] directly at
each nonzero requested phase. Unlike endpoint interpolation, the supplied
homotopy controls the complete intermediate geometry.}

The canonical acceptance scene is
@filepath{examples/3d/spatial-maps-and-homotopies.rkt}.

@section{Prepared spatial ODE trajectories and vector fields}

SCENE-3D-T0/T1/T2/T3/T4 turns the earlier direct-time flow support into an
immutable trajectory-data model with event-aware preparation, explicit
stopping policies, display-ready adaptive streamlines, and deterministic seed
sets.
@racket[prepare-ode-trajectory3d] records dense RK4 or Dormand--Prince
segments once; subsequent position, tangent, arc-length, and event-hit lookup
accepts any supported time in any order and never calls the author field. A
field accepts either @racket[(field x y z)] or
@racket[(field time x y z)] and must return exactly one finite @racket[vec3].
Use @racket[ode-field3d] when the field needs an explicit cache identity or
when its autonomous status matters to later flow analysis.

An @racket[ode-event3d] evaluates a finite scalar on the stored trajectory
while it is prepared. Its procedure accepts either @racket[(event point)] or
@racket[(event time point)]. A sign-changing root is found by deterministic
bisection of the dense Hermite segment; a zero at a shared accepted node is
reported once. Event directions always mean increasing @italic{physical} time,
including when the requested range runs backward. A terminal event becomes a
canonical end node and shortens the relevant side of the returned range;
nonterminal hits remain in the immutable hit vector.

@racket[trajectory-termination3d] makes every other stopping condition
explicit: a symmetric time budget about the seed, an AABB exit, an accumulated
arc-length budget, a low-speed threshold, a maximum step count, policy-owned
events, and a choice between reporting or tolerating an author-field failure.
Preparation resolves a winning condition against the stored dense Hermite
segments and records an immutable termination hit.  An AABB exit reports the
outward face normal.  On one branch, simultaneous candidates are ordered as
field failure, terminal event in declaration order, bounds exit, arc-length
limit, low speed, maximum steps, then the requested time limit.  The returned
range ends exactly at the selected dense point when that condition can be
located inside a segment.

@racket[flow-particle3d] is a semantic spatial relation. Before an image or
preview worker resolves it, Animate samples its requested phase values into an
immutable table. Thus worker rendering reads positions and tangents only; it
does not evaluate the field procedure. The fixed solver's
@racket[#:checkpoint-every] value remains diagnostic preparation metadata for
now; it no longer changes lookup cost.

@racket[prepare-streamline3d] uses the same dense prepared trajectory but adds
an explicit choice of parameterization. @racket['time] means
@italic{dp/ds = F(p)}, preserving the field's speed. @racket['arc-length]
means @italic{dp/ds = F(p)/||F(p)||}; it therefore requires an autonomous
field and ends at an equilibrium rather than inventing a direction. The
prepared display samples are recursively subdivided in world coordinates until
the chord error, tangent turn, and segment length satisfy an immutable
@racket[streamline-sample-policy3d]. Camera zoom does not change their points.
For a bidirectional streamline, the returned samples run from the backward end
through one copy of the seed to the forward end; the seed index and per-branch
diagnostics remain inspectable.

@racketblock[
(define lorenz-path
  (prepare-ode-trajectory3d
   (ode-field3d
    (lambda (x y z) (vec3 (* 10 (- y x)) (- (* x (- 28 z)) y)
                          (- (* x y) (* 8/3 z))))
    #:cache-key 'lorenz-10-28-8/3)
   (vec3 0 1 21/20)
   #:time-range (cons 0 20)
   #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-6)))

(define phase (parameter 'time 0))
(flow-particle3d lorenz-path phase #:id 'particle #:tangent-length 1)
]

@defproc[(prepare-ode-trajectory3d
          [field any/c]
          [seed vec3?]
          [#:time-range time-range (cons/c finite-real? finite-real?)]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:checkpoint-every checkpoint-every exact-positive-integer? 16]
          [#:solver solver any/c #f]
          [#:events events list? '()]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:cancellation-token cancellation-token any/c #f])
         ode-trajectory3d?]{Prepares one immutable spatial trajectory over the
closed range @racket[(cons start-time end-time)]. The seed is at time zero;
the range may extend on either side of it. Terminal event hits may shorten
that closed range. @racket[#:events] and policy-owned events form one
declaration-ordered set whose identifiers must be distinct. A preview
cancellation token is checked before and between solver steps and before event
root refinement; cancellation raises rather than returning a partial trajectory.}
@defproc[(ode-field3d [procedure procedure?]
                       [#:cache-key cache-key any/c #f]
                       [#:autonomous? autonomous? boolean? #t]) any/c]{
Constructs explicit author-time field metadata.  The procedure is used only
during numerical preparation; a prepared trajectory retains its cache key but
not this procedure.}
@defproc[(fixed-rk4-solver3d [#:step-size step-size positive? 1/20])
         any/c]{Constructs fixed-step RK4 solver settings.}
@defproc[(adaptive-rk45-solver3d [#:relative-tolerance relative-tolerance positive? 1e-6]
                                 [#:absolute-tolerance absolute-tolerance positive? 1e-9]
                                 [#:initial-step initial-step positive? 1/20]
                                 [#:minimum-step minimum-step positive? 1e-9]
                                 [#:maximum-step maximum-step positive? 1]
                                 [#:maximum-steps maximum-steps exact-positive-integer? 100000])
         any/c]{Constructs immutable adaptive RK45 settings.
The earlier @racket[adaptive-rk45] setting remains accepted while examples are
migrated.}
@defproc[(ode-event3d [#:id id symbol?]
                       [#:function function procedure?]
                       [#:direction direction (or/c 'any 'increasing 'decreasing) 'any]
                       [#:terminal? terminal? boolean? #t]
                       [#:value-tolerance value-tolerance positive? 1e-9]
                       [#:time-tolerance time-tolerance positive? 1e-9]
                       [#:maximum-iterations maximum-iterations exact-positive-integer? 64]
                       [#:cache-key cache-key any/c #f]) any/c]{Constructs an
event descriptor. Event identifiers must be distinct in one preparation call.
The optional cache key describes the opaque event procedure for a future
persistent preparation cache; the completed trajectory itself never retains
the procedure.}
@defproc[(ode-event-hit3d? [value any/c]) boolean?]{Recognizes one immutable
prepared event-hit record. Its accessors begin with
@tt{ode-event-hit3d-}, including @tt{ode-event-hit3d-time},
@tt{ode-event-hit3d-position}, and @tt{ode-event-hit3d-provenance}.}
@defproc[(trajectory-termination3d
          [#:time-limit time-limit (or/c false/c nonnegative-real?) #f]
          [#:arc-length-limit arc-length-limit (or/c false/c nonnegative-real?) #f]
          [#:bounds bounds (or/c false/c aabb3?) #f]
          [#:minimum-speed minimum-speed (or/c false/c nonnegative-real?) #f]
          [#:maximum-steps maximum-steps exact-positive-integer? 100000]
          [#:events events list? '()]
          [#:on-field-error on-field-error (or/c 'error 'terminate) 'error])
         trajectory-termination3d?]{Constructs an immutable stopping policy.
A time limit constrains absolute physical time to
@racket[(- time-limit)] through @racket[time-limit]. An AABB means the first
exit from a nonempty box, not a request to clip the displayed mesh. The arc
budget is measured independently from the seed on each branch. A field error
normally remains an author error; @racket['terminate] instead ends at the last
accepted node and records a @racket['field-error] hit.}
@defproc[(trajectory-termination3d? [value any/c]) boolean?]{Recognizes a
termination policy. Accessors begin with @tt{trajectory-termination3d-}.}
@defproc[(trajectory-termination-hit3d? [value any/c]) boolean?]{Recognizes an
immutable winning-policy record. Its accessors begin with
@tt{trajectory-termination-hit3d-}; @tt{reason}, @tt{time}, @tt{position},
and @tt{details} are deliberately serializable inspection data.}
@defproc[(streamline-sample-policy3d
          [#:maximum-chord-error maximum-chord-error nonnegative-real? 1/100]
          [#:maximum-turn-angle maximum-turn-angle nonnegative-real? (/ pi 12)]
          [#:maximum-segment-length maximum-segment-length positive? 1/4]
          [#:minimum-segment-length minimum-segment-length positive? 1/2000])
         streamline-sample-policy3d?]{Constructs an immutable, world-space
display resampling policy. The minimum length is an explicit recursion floor
and must not exceed the maximum length. Accessors begin with
@tt{streamline-sample-policy3d-}.}
@defproc[(prepare-streamline3d
          [field any/c]
          [seed vec3?]
          [#:direction direction (or/c 'forward 'backward 'both) 'forward]
          [#:parameterization parameterization (or/c 'time 'arc-length) 'time]
          [#:solver solver any/c (adaptive-rk45-solver3d)]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:sample-policy sample-policy streamline-sample-policy3d?
                           (streamline-sample-policy3d)]
          [#:cancellation-token cancellation-token any/c #f])
         prepared-streamline3d?]{Prepares one immutable streamline. If no
policy is supplied, preparation uses a finite eight-unit time budget. A
supplied policy with no time limit uses the same finite safety horizon unless
another termination condition ends first. A preview worker can pass its
cooperative cancellation token; cancellation is checked before numerical steps
and while the retained curve is resampled, and returns no partial streamline.}
@defproc[(prepared-streamline3d? [value any/c]) boolean?]{Recognizes an
immutable prepared streamline. Its accessors begin with
@tt{prepared-streamline3d-}; @tt{curve-samples} is an immutable vector of
world-space @racket[vec3] values and @tt{seed-index} names the seed's sole
joined occurrence.}
@defproc[(adaptive-streamline3d [prepared prepared-streamline3d?]
                                [#:id id symbol?]
                                [#:style style any/c]
                                [#:opacity opacity real? 1]) spatial-visual?]{Converts
prepared display samples to an ordinary spatial curve. A zero-length prepared
streamline lowers to an empty named group rather than a fictitious segment.}
@defproc[(seed-set3d? [value any/c]) boolean?]{Recognizes an immutable,
canonical ordered collection of streamline seed points. Its accessors begin
with @tt{seed-set3d-}; @tt{points} is an immutable vector and @tt{count} is its
length. @tt{provenance}, @tt{diagnostics}, and @tt{cache-key} contain immutable
numeric/source descriptions rather than random-generator state or procedures.}
@defproc[(explicit-seeds3d [points (or/c list? vector?)]) seed-set3d?]{Retains
the declared finite @racket[vec3] point sequence exactly, including intentional
duplicate seeds.}
@defproc[(grid-seeds3d
          [#:x-range x-range list? (list -1 1)]
          [#:y-range y-range list? (list -1 1)]
          [#:z-range z-range list? (list -1 1)]
          [#:counts counts list? (list 3 3 3)]
          [#:order order symbol? 'xyz]) seed-set3d?]{Makes an endpoint-inclusive
rectangular seed lattice. A singleton axis is centred in its supplied range.
The last axis changes fastest; the six @racket['xyz]-style axis orders select
one visible canonical nesting order.}
@defproc[(plane-seeds3d [plane plane3?]
                        [#:u-range u-range list? (list -1 1)]
                        [#:v-range v-range list? (list -1 1)]
                        [#:counts counts list? (list 3 3)]) seed-set3d?]{Samples
the deterministic local plane coordinates of @racket[plane].}
@defproc[(curve-seeds3d [curve curve3d?]
                        [#:count count exact-positive-integer? 8]
                        [#:spacing spacing (or/c 'parameter 'arc-length) 'arc-length])
         seed-set3d?]{Samples a retained curve. @racket['parameter] means uniform
progress through the curve's stored sample sequence—not an unavailable source
procedure parameter—while @racket['arc-length] uses the retained polyline
arc-length query.}
@defproc[(surface-seeds3d [surface surface3d?]
                          [#:u-count u-count exact-positive-integer? 8]
                          [#:v-count v-count exact-positive-integer? 8]
                          [#:inside-domain? inside-domain? boolean? #t])
         seed-set3d?]{Samples a retained parametric surface in u-major order.
When @racket[inside-domain?] is true, points rejected by a retained domain
predicate are omitted and the diagnostic reports that omission.}
@defproc[(sphere-seeds3d [center vec3?] [radius nonnegative-real?]
                         [#:count count exact-positive-integer? 64]
                         [#:method method 'fibonacci]) seed-set3d?]{Makes
deterministic Fibonacci points on a sphere.}
@defproc[(poisson-seeds3d [bounds aabb3?]
                          [#:minimum-distance minimum-distance positive? 1]
                          [#:count-limit count-limit exact-nonnegative-integer? 128]
                          [#:seed seed exact-integer? 0]) seed-set3d?]{Makes an
acceptance-ordered deterministic Bridson-style Poisson set. It uses a local
SplitMix64 generator, FIFO active points, thirty candidates per active point,
and inclusive box/minimum-distance checks; it neither reads nor mutates the
process-global pseudo-random generator.}
@defproc[(prepared-streamline-set3d? [value any/c]) boolean?]{Recognizes an
immutable collection prepared from one @racket[seed-set3d?]. Its accessors
begin with @tt{prepared-streamline-set3d-}; @tt{streamlines} is an immutable
vector of accepted @racket[prepared-streamline3d?] values in seed declaration
order.}
@defproc[(prepare-streamlines3d
          [field any/c] [seeds seed-set3d?]
          [#:direction direction (or/c 'forward 'backward 'both) 'forward]
          [#:parameterization parameterization (or/c 'time 'arc-length) 'time]
          [#:solver solver any/c (adaptive-rk45-solver3d)]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:sample-policy sample-policy streamline-sample-policy3d?
                           (streamline-sample-policy3d)]
          [#:separation separation (or/c false/c positive?) #f]
          [#:parallel? parallel? boolean? #t]
          [#:cancellation-token cancellation-token any/c #f]) prepared-streamline-set3d?]{Prepares
one immutable streamline per accepted seed. When @racket[separation] is false,
the result is independent and canonical in seed order. A positive separation
processes seeds in that order, rejects a seed already too near an accepted
line, and makes a later candidate stop at a terminal separation event. The
set diagnostic reports accepted/rejected seeds, terminal reasons, field work,
curve samples, the policy separation, discarded short lines, and whether the
set was independent, serial, or ordered by separation. A cancellation token
is checked at every seed boundary and never leaves a partial set.}
@defproc[(adaptive-streamline-set3d [prepared prepared-streamline-set3d?]
                                    [#:id id symbol?]
                                    [#:style style any/c]
                                    [#:opacity opacity real? 1]) group3d?]{Lowers
all accepted prepared lines to ordinary named curve children.}
@defproc[(poincare-section3d [trajectory prepared-trajectory3d?] [plane plane3?]
                             [#:trajectory-id trajectory-id symbol? 'trajectory]
                             [#:direction direction (or/c 'any 'positive 'negative) 'any]
                             [#:tolerance tolerance positive? 1e-8]
                             [#:deduplicate-time deduplicate-time positive? tolerance]
                             [#:tangent-policy tangent-policy (or/c 'ignore 'include) 'ignore])
         vector?]{Extracts immutable @racket[poincare-hit3d?] crossings by
running the event root finder over retained dense trajectory segments. A
positive/negative direction means increasing/decreasing signed distance along
increasing physical time. Shared endpoint roots are time-deduplicated; a
tangent contact is omitted unless explicitly included.}
@defproc[(poincare-hit3d? [value any/c]) boolean?]{Recognizes an immutable
crossing record. Its accessors begin with @tt{poincare-hit3d-}; @tt{source-event}
is the serializable dense root record, not an event procedure.}
@defproc[(poincare-hit3d-plane-coordinates [hit poincare-hit3d?] [plane plane3?])
         vector?]{Returns the point's deterministic two-coordinate plane basis
projection, suitable for an ordinary two-dimensional plot.}
@defproc[(poincare-hits3d [hits (or/c list? vector?)] [#:id id symbol?]
                          [#:style style any/c]) group3d?]{Lowers hit values to
ordinary spatial point markers.}
@defproc[(prepare-poincare-map3d [field any/c] [plane plane3?] [seeds seed-set3d?]
                                 [#:direction direction (or/c 'any 'positive 'negative) 'any]
                                 [#:tangent-policy tangent-policy (or/c 'ignore 'include) 'ignore])
         prepared-poincare-map3d?]{Prepares per-seed first and second crossings.
Missing returns remain @racket[#f] in the same seed slot; the result is not a
claim that an arbitrary flow has a global return map.}
@defproc[(prepared-poincare-map3d? [value any/c]) boolean?]{Recognizes an
immutable per-seed return-map record. Its accessors begin with
@tt{prepared-poincare-map3d-}.}
@defproc[(jacobian3d [field any/c] [point vec3?]
                     [#:time time finite-real? 0]
                     [#:derivative derivative (or/c false/c procedure?) #f]
                     [#:step step (or/c false/c positive?) #f]
                     [#:domain domain (or/c false/c procedure?) #f])
         jacobian3d-result?]{Returns an immutable local derivative matrix for
an ODE field at @racket[point]. An analytic @racket[#:derivative] follows the
field's usual @racket[(x y z)] or @racket[(time x y z)] calling convention and
must return a finite @racket[linear3]. Otherwise the result uses deterministic
scale-aware symmetric finite differences. The optional @racket[#:domain]
predicate receives a @racket[vec3]; it is the only reason a one-sided stencil
is used. The result records its method, coordinate steps, total evaluations,
and a local first-versus-second-order error indicator where it is available.}
@defproc[(jacobian3d-result? [value any/c]) boolean?]{Recognizes the transparent
immutable result record returned by @racket[jacobian3d]. Its constructor and
accessors begin with @tt{jacobian3d-result-}.}
@defproc[(equilibrium-points3d [field any/c] [seeds seed-set3d?]
                                [#:solver solver equilibrium-solver3d?
                                           default-equilibrium-solver3d]
                                [#:jacobian derivative (or/c false/c procedure?) #f]
                                [#:merge-distance merge-distance positive? 1e-6]
                                [#:domain domain (or/c false/c procedure?) #f]
                                [#:time time finite-real? 0]
                                [#:cancellation-token cancellation-token any/c #f]) equilibrium-search3d?]{Runs
bounded damped Newton searches from precisely the declared seed order. A
successful root is clustered against earlier successful roots only, so the
earliest seed is its canonical representative. Failed seeds remain as
@racket[equilibrium-seed-result3d?] entries with an explicit status such as
@racket['singular-jacobian], @racket['out-of-domain], @racket['stalled], or
@racket['iteration-limit]. A cancellation token is checked between seed
searches and Newton/backtracking iterations; it raises instead of returning a
partial root collection.}
@defproc[(equilibrium-search3d? [value any/c]) boolean?]{Recognizes the
immutable search result. Its @tt{seeds}, @tt{roots}, @tt{seed-results}, and
@tt{diagnostics} accessors retain all seed outcomes rather than only the
converged representatives.}
@defproc[(equilibrium-seed-result3d? [value any/c]) boolean?]{Recognizes one
immutable seed outcome. Its accessors begin with @tt{equilibrium-seed-result3d-}.}
@defproc[(equilibrium-solver3d [residual-tolerance positive?]
                               [step-tolerance positive?]
                               [maximum-iterations exact-positive-integer?]
                               [damping positive?]
                               [minimum-damping positive?]) equilibrium-solver3d?]{Constructs
the explicit tolerances and deterministic backtracking schedule used by an
equilibrium search.}
@defproc[(equilibrium-solver3d? [value any/c]) boolean?]{Recognizes an
equilibrium solver settings value.}
@defthing[default-equilibrium-solver3d equilibrium-solver3d?]{The default
bounded damped Newton settings.}
@defproc[(eigensystem3d-of [matrix linear3?] [#:tolerance tolerance positive? 1e-10])
         eigensystem3d?]{Computes a bounded deterministic real 3×3 eigensystem.
Eigenvalues are ordered by real component, then imaginary component, with the
positive member of a conjugate pair first. Real eigenvectors use the sign whose
largest-magnitude component is positive. Diagnostics report the characteristic
discriminant and near-defect tolerance rather than concealing numerically
ambiguous cases.}
@defproc[(eigensystem3d? [value any/c]) boolean?]{Recognizes immutable
eigensystem data. Its accessors begin with @tt{eigensystem3d-}.}
@defproc[(linearize3d [field any/c] [point vec3?]
                       [#:time time finite-real? 0]
                       [#:jacobian derivative (or/c false/c procedure?) #f]
                       [#:tolerance tolerance positive? 1e-8]) linearization3d?]{Combines
a Jacobian and deterministic eigensystem at a point. It classifies sink,
source, saddle, spiral sink/source, center-like, nonhyperbolic, or indeterminate
using the declared tolerance; complex pairs expose complementary invariant-plane
data where a stable real normal is available.}
@defproc[(linearization3d? [value any/c]) boolean?]{Recognizes an immutable
local linearization. Its accessors begin with @tt{linearization3d-}.}
@defproc[(linearization-diagram3d [value linearization3d?]
                                  [#:id id symbol? 'linearization]
                                  [#:scale scale positive? 1]) group3d?]{Lowers
the retained real eigendirections to named finite 3D diagram lines. Stable,
unstable, and center directions receive separately configurable stroke styles.
The finite extent is explicitly author-chosen by @racket[scale]; invariant planes
remain data because no universal plane-patch size is mathematically correct.}
@defproc[(prepare-flow-map3d [field any/c] [seeds seed-set3d?]
                             [#:start-time start-time finite-real? 0]
                             [#:end-time end-time finite-real? 1]
                             [#:solver solver any/c #f]
                             [#:termination termination any/c #f]
                             [#:on-termination policy (or/c 'absent 'use-termination-point) 'absent]
                             [#:parallel? parallel? boolean? #t]
                             [#:cancellation-token cancellation-token any/c #f]) prepared-flow-map3d?]{Prepares
one retained trajectory in every declared seed slot. A normally completed slot
has its endpoint; an early-terminated slot is @racket[#f] by default, or its
actual stopping point under @racket['use-termination-point]. Thus source,
endpoint, and termination provenance stay aligned in seed order. Its diagnostics
contain a versioned preparation identity when @racket[field]
is an @racket[ode-field3d] with an explicit cache key and every termination
event has an explicit cache key. The identity records solver, seed-set,
termination, time-parameterization, dense-resampling, and endpoint policy.
An opaque field or event is reported as @racket['memory-only], so it is never
mistaken for persistently serializable numerical input.}
@defproc[(prepared-flow-map3d? [value any/c]) boolean?]{Recognizes an immutable
prepared flow map. Its accessors begin with @tt{prepared-flow-map3d-}.}
@defproc[(flow-map3d-ref [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         (or/c false/c vec3?)]{Returns the endpoint in seed order, or @racket[#f]
for an absent endpoint.}
@defproc[(flow-map3d-pairs [map prepared-flow-map3d?]) vector?]{Returns immutable
@racket[(cons seed endpoint)] entries for slots with endpoints.}
@defproc[(flow-map3d-displacement [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         (or/c false/c vec3?)]{Returns endpoint minus source for one slot.}
@defproc[(flow-map-grid3d [map prepared-flow-map3d?]
                           [#:id id symbol? 'flow-map-grid]
                           [#:connectivity connectivity 'axis-neighbours]) group3d?]{Lowers
a flow map from an explicit @racket['grid] seed set to retained endpoint edges.
An absent endpoint breaks its incident edges. Arbitrary unstructured seed sets
are rejected because no neighbourhood relation is implied by their order.}
@defproc[(flow-volume-cell3d [map prepared-flow-map3d?]
                              [cell-index exact-nonnegative-integer?]
                              [#:id id (or/c false/c symbol?) #f]
                              [#:material material material3d? default-material3d]) mesh3d?]{Lowers
one retained hexahedral seed cell to its eight endpoint corners and twelve
outward-wound triangular faces. @racket[cell-index] enumerates lower corners in
the source grid's retained declaration order; it is not a loose seed index. The
operation requires an explicit complete grid and eight retained endpoints. It
does not interpolate, repair an absent endpoint, or infer volume from an
unstructured cloud.}
@defproc[(flow-map3d-local-jacobian [map prepared-flow-map3d?]
                                    [index exact-nonnegative-integer?]) linear3?]{Estimates
the local endpoint derivative from a retained explicit grid neighbourhood.
Interior slots use central differences and grid boundaries use a retained
one-sided difference. An absent endpoint, incomplete axis neighbourhood, or
unstructured seed set is an error rather than a guessed result.}
@defproc[(flow-map3d-volume-factor [map prepared-flow-map3d?]
                                   [index exact-nonnegative-integer?]) finite-real?]{Returns
the determinant of @racket[flow-map3d-local-jacobian] at one grid slot.}
@defproc[(trajectory-samples3d [trajectory prepared-trajectory3d?]
                                [#:count count exact-integer? 64]) vector?]{Returns
an immutable uniform-time sequence of positions from retained dense trajectory
data. It never invokes the author ODE field.}
@defproc[(trajectory-tube3d [trajectory prepared-trajectory3d?]
                             [#:id id symbol? 'trajectory-tube]
                             [#:radius radius positive? 1/20]
                             [#:sides sides exact-integer? 12]
                             [#:samples samples exact-integer? 64]
                             [#:caps? caps? boolean? #t]) mesh3d?]{Lowers retained
trajectory samples into a deterministic finite tube mesh. It is a display
choice, not a re-integration, and its world radius and sample count are
explicit.}
@defproc[(trajectory-ribbon3d [trajectory prepared-trajectory3d?]
                               [#:id id symbol? 'trajectory-ribbon]
                               [#:width width positive? 1/10]
                               [#:samples samples exact-integer? 64]
                               [#:initial-normal initial-normal (or/c false/c vec3?) #f]) mesh3d?]{Lowers
prepared samples to a two-sided ribbon mesh. Its normal frame uses discrete
parallel transport, projected at every retained tangent. A closed-loop twist
correction is intentionally not automatic: a finite display ribbon must not
silently choose a loop-closing convention for its author.}
@defproc[(trajectory-bundle3d [map prepared-flow-map3d?]
                               [#:id id symbol? 'trajectory-bundle]
                               [#:style style (or/c 'tube 'ribbon) 'tube]
                               [#:radius radius positive? 1/20]
                               [#:width width positive? 1/10]
                               [#:sides sides exact-integer? 12]
                               [#:samples samples exact-integer? 64]
                               [#:initial-normal initial-normal (or/c false/c vec3?) #f]) group3d?]{Lowers
every retained trajectory of a prepared flow map in stable seed order. The
selected tube or parallel-transport ribbon style is display-only: it never
calls the author field or reintegrates a seed. A trajectory that terminated
early remains a shorter retained bundle child.}
@defproc[(trajectory-inspection3d [trajectory prepared-trajectory3d?]) immutable-hash?]{Returns
a read-only report of retained solver diagnostics, termination, event hits, and
arc length.}
@defproc[(trajectory-pick-inspection3d [trajectory prepared-trajectory3d?]
                                        [point vec3?]
                                        [#:samples samples exact-integer? 128]
                                        [#:near-event-time near-event-time (or/c false/c nonnegative-real?) #f])
         immutable-hash?]{Returns a read-only nearest-trajectory report for a
world-space pick. It records the nearest declared uniform curve sample, its
nearest sampled-polyline interpolation time and position, retained arc-length
position and derivative, and a nearby retained event hit when one lies within
the declared or sample-interval time radius. It does not reintegrate or invoke
the author field.}
@defproc[(equilibrium-inspection3d [search equilibrium-search3d?]) immutable-hash?]{Returns
the complete retained convergence report without hiding failed seed slots.}
@defproc[(linearization-inspection3d [value linearization3d?]) immutable-hash?]{Returns
the local Jacobian, eigendata, classification, and tolerance diagnostics.}
@defproc[(flow-map-inspection3d [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         immutable-hash?]{Returns one flow-map source/endpoint trajectory slot,
including its absent-endpoint status when applicable. These inspection values
do not mutate a Scene, selection, camera, or preview overlay.}
@defproc[(ode-trajectory3d? [value any/c]) boolean?]{Recognizes a prepared
immutable spatial trajectory.}
@defproc[(ode-trajectory3d-position [trajectory ode-trajectory3d?]
                                     [time finite-real?]) vec3?]{Returns the
position at a supported time. Every prepared lookup reads only stored data.}
@defproc[(ode-trajectory3d-time-range [trajectory ode-trajectory3d?])
         (cons/c finite-real? finite-real?)]{Returns its supported range.}
@defproc[(ode-trajectory3d-event-hits [trajectory ode-trajectory3d?]) vector?]{Returns
an immutable vector of @racket[ode-event-hit3d?] records, sorted by increasing
physical time. Simultaneous hits use event declaration order as their
tie-break. Each hit records its event identifier, dense root time and position,
event value, physical crossing direction, segment index, iteration count, and
root-finding provenance.}
@defproc[(ode-trajectory3d-termination [trajectory ode-trajectory3d?]) vector?]{Returns
the immutable, increasing-physical-time vector of selected
@racket[trajectory-termination-hit3d?] records. There is normally zero or one
hit for a one-sided trajectory and up to two for a range extending on both
sides of the seed.}
@defproc[(ode-trajectory3d-step-size [trajectory ode-trajectory3d?])
         (or/c positive? false/c)]{Returns a fixed path's RK4 step, or
@racket[#f] for an adaptive path.}
@defproc[(ode-trajectory3d-checkpoint-every [trajectory ode-trajectory3d?])
         (or/c exact-positive-integer? false/c)]{Returns a fixed path's
checkpoint preparation metadata, or @racket[#f] for an adaptive path.  It does
not cause later reintegration.}
@defproc[(ode-trajectory3d-solver [trajectory ode-trajectory3d?]) any/c]{Returns
the immutable fixed-RK4 or adaptive-RK45 solver setting.}
@defproc[(ode-trajectory3d-derivative [trajectory ode-trajectory3d?]
                                       [time finite-real?]) vec3?]{Returns the
stored dense-output tangent at a supported time.}
@defproc[(ode-trajectory3d-speed [trajectory ode-trajectory3d?]
                                  [time finite-real?]) nonnegative-real?]{Returns
the tangent magnitude.}
@defproc[(ode-trajectory3d-arc-length-at [trajectory ode-trajectory3d?]
                                          [time finite-real?]) nonnegative-real?]{
Returns accumulated arc length from the prepared range start.}
@defproc[(ode-trajectory3d-time-at-arc-length [trajectory ode-trajectory3d?]
                                               [arc-length nonnegative-real?])
         finite-real?]{Inverts the prepared arc-length table deterministically.}
@defproc[(ode-trajectory3d-diagnostics [trajectory ode-trajectory3d?]) any/c]{Returns
immutable solver, field-evaluation, step, dense-segment, termination, and
arc-length diagnostics for both fixed and adaptive trajectories.}

@bold{Current T5 limits.} Arc length is a deterministic eight-chord estimate
per stored dense segment rather than a certified integral, so an arc-length
endpoint is deterministic but not mathematically certified. The low-speed
policy observes accepted nodes and one midpoint per segment; it does not yet
require a configurable run of consecutive slow observations. T2 detects
sign-changing roots and exact/tolerance-zero endpoints, but does not search for
an isolated tangency whose sampled event values retain the same sign. AABB
exits are split at all dense-coordinate extrema and then bisected; numerical
roots remain tolerance-limited, although an accepted face node is preserved
exactly. A standalone streamline without a time limit has the documented
eight-unit safety horizon. Seed sets create finite immutable points; they do
not infer seeding topology from a field. Curve @racket['parameter] spacing is
the stored polyline sample index rather than a source-function parameter,
surface sets require a retained parametric evaluator/range, and Poisson's
floating geometric candidates are repeatable rather than a mathematical
blue-noise certificate. Streamline separation uses display-sample segments and
a cell hash, so it is an explicit finite geometric policy rather than a proof
about the continuous ODE. Independent sets retain canonical order but this
pure layer does not concurrently call arbitrary author field procedures.
Poincare extraction detects endpoint/sign-changing crossings in retained dense
segments. It does not search inside a same-sign segment for an isolated tangent,
and an included tangent is only an explicit endpoint contact. Return maps retain
only first/second crossings, not a proof of a global map. Equilibrium/
linearization, flow-map analysis, and certified arc-length integration are
later SCENE-3D-T slices.

@defproc[(vector-field3d
          [field (or/c (procedure-arity-includes/c 3)
                       (procedure-arity-includes/c 4))]
          [#:id id symbol?]
          [#:x-range x-range list? (list -2 2)]
          [#:y-range y-range list? (list -2 2)]
          [#:z-range z-range list? (list -2 2)]
          [#:x-count x-count exact-positive-integer? 5]
          [#:y-count y-count exact-positive-integer? 5]
          [#:z-count z-count exact-positive-integer? 5]
          [#:normalize? normalize? boolean? #f]
          [#:length-range length-range (or/c false/c list? pair?) #f]
          [#:color-by-magnitude? color-by-magnitude? boolean? #f]
          [#:seed-order seed-order symbol? 'xyz]) group3d?]{Samples an
explicit finite rectangular grid once. Zero derivatives are omitted.
@racket[#:seed-order] is one of @racket['xyz], @racket['xzy], @racket['yxz],
@racket['yzx], @racket['zxy], or @racket['zyx], giving stable child order.
When requested, magnitude controls the displayed arrow length and colour.}
@defproc[(streamline3d [field procedure?] [seed vec3?] [#:id id symbol?])
         curve3d?]{Creates one finite static RK4 streamline.}
@defproc[(streamlines3d [field procedure?] [seeds (listof vec3?)]
                         [#:id id symbol?]) group3d?]{Creates deterministic
static streamline children.}
@defproc[(flow-particle3d [trajectory ode-trajectory3d?]
                           [phase scene-parameter?]
                           [#:id id symbol?]
                           [#:tangent-length tangent-length
                            (or/c false/c positive?) #f]) spatial-relation?]{
Creates a prepared position marker, optionally with a visible nonzero tangent.
At an equilibrium, the tangent child remains structurally present but invisible
rather than claiming an arbitrary direction.}
@defproc[(flow-cloud3d [trajectories (listof ode-trajectory3d?)]
                        [phase scene-parameter?] [#:id id symbol?]) group3d?]{
Creates one prepared particle per trajectory using the shared time parameter.}

The canonical acceptance scenes are
@filepath{examples/3d/prepared-lorenz-flow.rkt} and
@filepath{examples/3d/lorenz-events.rkt}; the latter distinguishes retained
nonterminal rise/fall roots through the same Lorenz surface. Explicit policies are shown
in @filepath{examples/3d/event-aware-trajectory.rkt} and
@filepath{examples/3d/trajectory-termination.rkt}, while
@filepath{examples/3d/adaptive-streamlines.rkt} shows T3's world-space
resampling and @filepath{examples/3d/deterministic-seed-sets.rkt} shows T4
Poisson seed provenance. @filepath{examples/3d/poincare-section.rkt} shows T5
dense plane crossings.

@section{Spatial inspection and exact picking}

SCENE-3D-L exposes the spatial hierarchy that an already sampled
@racket[view3d] submits to its renderer. Inspection is immutable query data;
it never adds a wireframe, selection flag, acceleration structure, or other
hidden state to an authored Scene. The preview uses the same query data after a
viewport click and paints its AABB, exact triangle, normal, local frame, and
ray-pixel marker only after the cached bitmap has been drawn.

@defstruct*[spatial-inspection
            ([path (listof symbol?)]
             [kind symbol?]
             [local-transform transform3?]
             [world-transform affine3?]
             [local-bounds aabb3?]
             [world-bounds aabb3?]
             [material any/c]
             [triangle-count exact-nonnegative-integer?]
             [vertex-count exact-nonnegative-integer?]
             [camera-position vec3?]
             [view-position (or/c #f vec3?)]
             [projected-position (or/c #f vec2?)]
             [view-depth (or/c #f nonnegative-real?)]
             [metadata immutable-hash?]) #:transparent]{
One deterministic pre-order description of a spatial group, mesh, curve, or
surface. @racket[path] begins with the enclosing @racket[view3d] identity;
@racket[local-transform] is the authored decomposition while
@racket[world-transform] includes all spatial ancestors. Empty geometry has
false projection/depth fields rather than an invented point.
}

@defstruct*[spatial-pick
            ([inspection spatial-inspection?]
             [path (listof symbol?)]
             [triangle-index (or/c #f exact-nonnegative-integer?)]
             [point vec3?]
             [distance nonnegative-real?]
             [barycentric vec3?]
             [normal vec3?]
             [ray ray3?]
             [metadata immutable-hash?]) #:transparent]{
The nearest spatial pick. @racket[spatial-pick-kind] returns
@racket['mesh-triangle], @racket['stroke-segment], @racket['point-marker], or
@racket['arrow-marker]. Mesh hits are exact ray/triangle intersections; screen
marks use the same prepared projected footprint and depth predicate as the
renderer. Stroke metadata includes source segment index/progress, world point,
view depth, pixel distance, and style. Ties are resolved by depth, drawing
index, then authored triangle or source segment index.
}
@defstruct*[surface-pick3d
            ([spatial-pick spatial-pick?]
             [surface-kind symbol?]
             [parameter (or/c #f vector?)]
             [trim-boundary any/c]
             [source-cell any/c]
             [interpolated-normal (or/c #f vec3?)]) #:transparent]{
A refinement of an exact mesh @racket[spatial-pick] for a @racket[surface3d].
The source cell is immutable triangle provenance, not an implementation cache.
}
@defproc[(spatial-pick-kind [pick spatial-pick?])
         (or/c 'mesh-triangle 'stroke-segment 'point-marker 'arrow-marker)]{
Returns the selected primitive kind.}

@defproc[(view3d-spatial-inspections [view view3d?]) (listof spatial-inspection?)]{
Returns deterministic pre-order records, including containers.
}
@defproc[(view3d-spatial-inspection-tree [view view3d?])
         (listof spatial-inspection?)]{An explicit spelling for the same
pre-order hierarchy, convenient for a tree UI.}
@defproc[(view3d-spatial-inspection-at [view view3d?]
                                        [path (listof symbol?)])
         (or/c #f spatial-inspection?)]{Returns the matching record, or
@racket[#f] when @racket[path] does not occur in this view.}
@defproc[(view3d-pick [view view3d?] [ray ray3?])
         (or/c #f spatial-pick?)]{
Picks a spatial object with world ray @racket[ray]. It first culls world AABBs,
transforms the candidate ray to mesh-local coordinates, traverses a local BVH,
and finishes with exact triangle and barycentric testing.
}
@defproc[(view3d-surface-pick [view view3d?] [ray ray3?])
         (or/c #f surface-pick3d?)]{
Uses the same CPU path as @racket[view3d-pick], returning @racket[#f] unless
the nearest hit is a surface. Parametric parameters are interpolated from
retained vertex provenance; an implicit result retains its source grid/tetrahedron
record instead.}
@defproc[(view3d-pixel-pick [view view3d?] [pixel-x finite-real?]
                             [pixel-y finite-real?]
                             [#:width width exact-positive-integer?]
                             [#:height height exact-positive-integer?])
         (or/c #f spatial-pick?)]{
Builds the camera ray through a top-left-origin viewport pixel. It performs
exact mesh picking and supplements it with prepared screen-stroke and marker
footprints; it does not sample a rendered bitmap or require a GUI.
}

@defproc[(mesh3d-bvh [mesh mesh3d?]) mesh3d-bvh?]{Returns the immutable local
acceleration tree used for picking. It splits on the longest centroid axis,
uses a stable median, and breaks ties by triangle index. The cache is an
implementation resource, not semantic scene state.}
@defproc[(mesh3d-bvh? [value any/c]) boolean?]{Recognizes an inspection BVH.}
@defproc[(bvh3d-node? [value any/c]) boolean?]{Recognizes an internal BVH node.}
@defproc[(bvh3d-leaf? [value any/c]) boolean?]{Recognizes a BVH leaf.}
@defproc[(bvh3d-bounds [tree mesh3d-bvh?]) aabb3?]{Returns local bounds for a
node or leaf.}
@defproc[(bvh3d-triangle-indices [tree mesh3d-bvh?])
         (listof exact-nonnegative-integer?)]{Returns the complete stable set
of contained triangle indices.}
@defproc[(bvh3d-ray-candidates [tree mesh3d-bvh?] [ray ray3?])
         (listof exact-nonnegative-integer?)]{Returns deterministic local
triangle candidates. Exact triangle testing remains separate.}

The canonical preview probe is
@filepath{examples/3d/spatial-inspector-picking.rkt}. Open it with
@racketmodname[animate/preview], click a visible facet, then use the
@tt{Animate → 3D selection} menu to copy the spatial path, hit point, or
normal; its scratch action also supplies a clipping plane. Focusing the
inspection camera changes only the preview override, never the authored
camera or timeline.

@section{Retained renderer backends}

SCENE-3D-N keeps @racket[animate/3d] pure and places effectful implementation
choice in @racketmodname[animate/3d/render]. SCENE-3D-O extends that compiled
view with ordered, renderer-neutral centreline strokes and screen markers. A
backend receives an immutable @racket[render3d-request] containing a
camera-independent compiled view, a frame specification, and a canonical
attachment demand.  It returns one immutable @racket[renderer3d-frame-artifact]
which owns every delivered attachment. Thus changing a backend, releasing its
cache, or recovering from a failed optional native renderer cannot mutate a
@racket[view3d], any of its spatial children, or a completed frame.

@defmodule[animate/3d/render]

@defproc[(renderer3d? [value any/c]) boolean?]{Recognizes a renderer-backend
instance.}
@defproc[(renderer3d-id [renderer renderer3d?]) symbol?]{Returns a stable
backend identity, such as @racket['software-reference].}
@defproc[(renderer3d-capabilities [renderer renderer3d?])
         renderer3d-capability-set?]{Returns the backend's declared facility
set.}
@defproc[(renderer3d-fingerprint [renderer renderer3d?]
                                 [request render3d-request?]) any/c]{Returns
an implementation-owned cache key for this immutable request. It is diagnostic
and cache data, never a scene identity.}
@defproc[(renderer3d-prepare [renderer renderer3d?]
                             [request render3d-request?]) any/c]{Builds or
retrieves backend-owned preparation data.}
@defproc[(renderer3d-render [renderer renderer3d?]
                            [preparation any/c]
                            [request render3d-request?])
         renderer3d-render-result?]{Rasterizes a fresh frame from a
preparation and request.}
@defproc[(renderer3d-release [renderer renderer3d?]) void?]{Releases every
resource retained by @racket[renderer]. It does not change an existing Scene or
an already returned render result.}

@defstruct*[renderer3d-capability-set
            ([wireframe boolean?]
             [opaque-triangles boolean?]
             [perspective boolean?]
             [orthographic boolean?]
             [depth-buffer boolean?]
             [flat-shading boolean?]
             [smooth-shading boolean?]
             [transparency boolean?]
             [clipping-planes boolean?]) #:transparent]{
The explicit feature record returned by @racket[renderer3d-capabilities].
Project capability declarations use this same record rather than a separate
3D capability type.
}

@defstruct*[compiled-geometry3d
            ([key any/c] [mesh mesh3d?] [local-bounds aabb3?]
             [face-normals vector?] [edge-adjacency vector?]
             [analysis mesh3d-analysis?]) #:transparent]{A camera-independent
geometry resource. Its canonical key includes local vertices, triangle and
explicit-edge topology, normals, and per-vertex colours; it excludes material,
opacity, transforms, camera, lights, and viewport settings.}
@defstruct*[compiled-instance3d
            ([path (listof symbol?)] [geometry-key any/c]
             [world-transform affine3?] [normal-transform linear3?]
             [material material3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]
             [surface-mode (or/c 'visible 'depth-only 'none)]) #:transparent]{The
ordered placement and style of one compiled geometry use.}
@defstruct*[compiled-stroke3d
            ([path (listof symbol?)] [points vector?] [closed? boolean?]
             [world-transform affine3?] [style stroke3d?] [opacity real?]
             [clip-planes list?] [drawing-index exact-nonnegative-integer?]
             [source-kind symbol?] [source-metadata immutable-hash?])
            #:transparent]{A camera-independent sampled centreline. Screen
width, dashes, clipping, depth classification, and cap/join coverage are
prepared only for a concrete frame.}
@defstruct*[compiled-point-marker3d
            ([path (listof symbol?)] [position vec3?] [world-transform affine3?]
             [style point-style3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]) #:transparent]{A
camera-independent point marker.}
@defstruct*[compiled-arrow-marker3d
            ([path (listof symbol?)] [from vec3?] [to vec3?]
             [world-transform affine3?] [style arrow-style3d?] [opacity real?]
             [clip-planes list?] [drawing-index exact-nonnegative-integer?])
            #:transparent]{A camera-independent arrowhead marker.}
@defstruct*[compiled-edge-overlay3d
            ([path (listof symbol?)] [geometry-key any/c]
             [world-transform affine3?] [normal-transform linear3?]
             [style edge-style3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]) #:transparent]{An
outlined mesh reference whose feature selection is deliberately deferred until
camera-frame preparation.}
@defstruct*[compiled-view3d
            ([geometries vector?] [instances vector?] [strokes vector?]
             [point-markers vector?] [arrow-markers vector?] [edge-overlays vector?]
             [background any/c]
             [render-mode symbol?] [transparency-mode symbol?]) #:transparent]{
The immutable camera-independent renderer input. Use
@racket[compiled-view3d-primitives] for stable drawing-index order across these
primitive vectors.}
@defstruct*[frame3d-spec
            ([camera camera3d?] [lights list?] [width exact-positive-integer?]
             [height exact-positive-integer?]) #:transparent]{The state which
may change from one rendered frame to the next.}
@defproc[(compile-view3d [view view3d?]) compiled-view3d?]{Lowers a spatial
tree deterministically, sharing equal geometry resources in first encounter
order. It does not inspect the view's camera.}
@defproc[(compiled-view3d-primitives [view compiled-view3d?]) vector?]{Returns
the mesh instances, strokes, point markers, arrow markers, and edge overlays in
stable drawing-index order.}
@defproc[(view3d->frame3d-spec [view view3d?]
                                [width exact-positive-integer?]
                                [height exact-positive-integer?]) frame3d-spec?]{
Extracts frame-varying camera, light, and viewport state.}
@defproc[(view3d->render3d-request [view view3d?]
                                   [width exact-positive-integer?]
                                   [height exact-positive-integer?]
                                   [#:cancellation-token cancellation-token any/c #f]
                                   [#:attachments attachments (listof symbol?) '(color)])
         render3d-request?]{Conveniently compiles @racket[view] and packages
the resulting compiled view, frame specification, and requested attachments.
The canonical attachment names are @racket['color], @racket['linear-depth],
@racket['object-id], and @racket['normal]. A renderer may return a superset,
but cannot omit a requested attachment.}
@defstruct*[render3d-request
            ([compiled-view compiled-view3d?]
             [frame-spec frame3d-spec?]
             [attachments (listof symbol?)]
             [cancellation-token any/c]) #:transparent]{
One backend-local request. The cancellation field is either @racket[#f] or the
preview's cooperative cancellation token; it is not serialised into scene
state.
}
@defstruct*[renderer3d-render-result
            ([artifact renderer3d-frame-artifact?]) #:transparent]{
A completed backend-independent frame. The artifact is its only frame payload
and may outlive the backend that produced it.
}
@defstruct*[renderer3d-frame-artifact
            ([width exact-positive-integer?]
             [height exact-positive-integer?]
             [straight-argb (or/c #f bytes?)]
             [linear-depth-snapshot (or/c #f vector?)]
             [object-id-snapshot (or/c #f vector?)]
             [normal-snapshot (or/c #f vector?)]
             [camera camera3d?]
             [diagnostics any/c]) #:transparent]{
The immutable attachment owner for a completed frame. Pixel snapshots are
top-left-origin. Linear depth is positive camera-space depth; an uncovered
pixel is @racket[+inf.0].}
@defproc[(renderer3d-frame-artifact-attachments
          [artifact renderer3d-frame-artifact?])
         (listof symbol?)]{Returns the canonical set of attachments actually
present in @racket[artifact].}
@defproc[(renderer3d-frame-linear-depth-at
          [artifact renderer3d-frame-artifact?]
          [x exact-nonnegative-integer?]
          [y exact-nonnegative-integer?])
         (or/c #f real?)]{Returns the positive linear depth at a top-left
pixel, or @racket[#f] when the artifact has no depth attachment or the pixel is
outside the viewport.}
@defproc[(renderer3d-render-result->bitmap [result renderer3d-render-result?])
         bitmap?]{Converts the copied ARGB frame to a Racket bitmap for the
ordinary @racket[view3d] Pict boundary.}

@defproc[(software-renderer3d) renderer3d?]{Creates a stateless deterministic
reference backend.}
@defproc[(retained-software-renderer3d [#:capacity capacity exact-positive-integer? 32])
         renderer3d?]{Creates a bounded, thread-safe backend that retains
prepared camera-space triangles, while allocating a new colour/depth target for
every render.}
@defthing[default-software-renderer3d renderer3d?]{The bounded retained backend
used by @racket[view3d]'s opaque Pict adapter.}
@defparam[current-view3d-renderer3d renderer renderer3d?]{Dynamically selects
the backend used by opaque @racket[view3d] rendering. The parameter affects the
effectful rendering boundary only; it is not captured in semantic scene values.}
@defproc[(retained-software-renderer3d-cache-hits [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports retained preparation hits.}
@defproc[(retained-software-renderer3d-cache-misses [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports retained preparation misses.}
@defproc[(retained-software-renderer3d-cache-size [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports the current bounded cache size.}
@defstruct*[renderer3d-statistics
            ([spatial-compilations exact-nonnegative-integer?]
             [geometry-fingerprints exact-nonnegative-integer?]
             [geometry-cache-hits exact-nonnegative-integer?]
             [geometry-cache-misses exact-nonnegative-integer?]
             [geometry-cache-bytes integer?]
             [instance-count exact-nonnegative-integer?]
             [source-triangle-count exact-nonnegative-integer?]
             [clipped-triangle-count exact-nonnegative-integer?]
             [raster-triangle-count exact-nonnegative-integer?]
             [pixel-count exact-nonnegative-integer?]
             [bitmap-conversion-count exact-nonnegative-integer?]
             [preparation-milliseconds real?]
             [raster-milliseconds real?]
             [readback-milliseconds real?]) #:transparent]{An immutable
snapshot of renderer-owned counters and elapsed-time observations. They are
benchmark evidence, not timing assertions for CI.}
@defproc[(renderer3d-statistics-reset! [renderer renderer3d?]) void?]{Resets
the built-in software renderer's counters without changing semantic values.}
@defproc[(renderer3d-statistics-snapshot [renderer renderer3d?])
         renderer3d-statistics?]{Returns a coherent immutable metric snapshot.}

@section{Optional Racket/OpenGL backend}

@defmodule[animate/3d/opengl]

SCENE-3D-P adds an explicit GPU implementation of the same
@racket[renderer3d] protocol. Requiring this module is the opt-in boundary for
@racketmodname[opengl] and @racketmodname[racket/gui/base]; neither
@racketmodname[animate], @racketmodname[animate/3d], nor
@racketmodname[animate/3d/render] loads it. The renderer owns a hidden canvas
only to obtain a context, renders each @racket[view3d] to an owned RGBA8/depth
framebuffer, reads it back, flips the rows, and returns the ordinary top-down
straight-alpha ARGB result used by the Pict compositor.

@defproc[(opengl-renderer3d-spec
          [#:samples samples exact-positive-integer? 4]
          [#:cache-megabytes cache-megabytes exact-positive-integer? 512]
          [#:fallback fallback (or/c 'error 'software) 'error])
         opengl-renderer3d-spec?]{Declares an explicit backend configuration.
@racket['error] rejects an unavailable context. @racket['software] is the only
deliberate fallback policy and is reported in backend statistics; no request
silently changes backend.}
@defproc[(opengl-renderer3d-spec? [value any/c]) boolean?]{Recognizes an
OpenGL backend declaration.}
@defproc[(opengl-renderer3d [spec opengl-renderer3d-spec?
                                  (opengl-renderer3d-spec)]) renderer3d?]{
Creates a retained backend with one serialized owned OpenGL context. It checks
for OpenGL 3.2 and GLSL 1.50 plus VBO/EBO/VAO/FBO/depth/readback support before
returning.}
@defproc[(opengl-renderer3d? [value any/c]) boolean?]{Recognizes an OpenGL
renderer instance, including one whose explicit fallback is active.}
@defproc[(opengl-renderer3d-available?) boolean?]{Creates and closes a short
lived hidden context to test availability. It is a real capability probe, not
a package-presence test.}
@defproc[(opengl-renderer3d-info [renderer opengl-renderer3d?]) immutable-hash?]{
Returns serializable GL version, GLSL version, vendor, renderer, profile,
limits, required-capability, and optional-feature diagnostics.}
@defproc[(opengl-renderer3d-statistics [renderer opengl-renderer3d?]) immutable-hash?]{
Returns backend counters plus geometry-cache and framebuffer-cache information.}
@defproc[(opengl-renderer3d-reset-statistics! [renderer opengl-renderer3d?]) void?]{
Resets measured counters without changing cached immutable geometry.}
@defproc[(opengl-renderer3d-release! [renderer opengl-renderer3d?]) void?]{
Deletes shader, VAO/VBO/EBO, framebuffer, and context-owner resources. It is
idempotent and never changes an authored spatial value.}

For final project output, use an explicit declaration:

@racketblock[
(render-spec
 #:renderer3d
 (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 512 #:fallback 'error)
 #:workers 1)
]

An OpenGL project must run in Racket 9.3 @exec{gracket}; a plain @exec{racket}
process produces an actionable project diagnostic instead of selecting software
implicitly. Project preview inherits this declaration and owns the retained
renderer for the lifetime of its window. Camera motion changes uniforms and a
viewport-size change only reallocates the FBO; neither reuploads immutable
geometry.

@bold{OpenGL limitations:} The first backend has one serialized context and
therefore requires @racket[#:workers 1]; it does not create threaded GPU
workers. It uses FBO readback rather than direct OpenGL preview-canvas
composition. There is no GPU picking, general mesh textures, shadows, specular/roughness
lighting, persistent mapped buffers, PBO pipelining, compute/geometry shaders,
or order-independent transparency. The software backend remains the portable
default and conformance reference. Compare GPU/software pixels by tolerance:
opaque interiors, antialiased edges, and transparent regions need different
thresholds and must not be expected to be bit-identical.

The reference/retained conformance tests compare projected output at exact
endpoints and in nonmonotonic camera-frame order. The canonical probe is
@filepath{examples/3d/retained-renderer.rkt}; evaluating
@tt{(retained-renderer-summary)} there demonstrates a cache hit without
changing the visible scene.

The repository tool @filepath{tools/run-3d-probes.rkt} renders the canonical
visual probes for any visible stage from @tt{3D-B} through @tt{3D-P}. For
example, @tt{gracket tools/run-3d-probes.rkt --stage 3D-P --renderer opengl
--output rendered-examples/3d-p-opengl} writes frame PNGs plus @tt{manifest.rktd} and a
@tt{diagnostics.rktd} file per probe. The manifest records Animate and Racket
versions, renderer ID, output dimensions, sample times, sampled 3D cameras,
renderer-fingerprint digests, compiled geometry keys/counts, frame hashes, and
for O, compiled stroke/marker/outline counts and requested screen/world width
modes. @tt{--compare-renderers software,opengl} writes side-by-side software
and OpenGL trees, per-frame absolute-difference PNGs, and channel-difference
metrics in @tt{comparison.rktd}.
Probe images are human review evidence; semantic and small-raster tests remain
the correctness oracle. @filepath{tools/benchmark-3d.rkt} measures the same
ten named workloads through either backend. Its OpenGL run reports first
context/shader/allocation work separately from warm frames, plus retained
geometry, framebuffer, readback, and renderer counters. It has no CI timing
threshold; the acceptance checks are zero geometry uploads for warm
camera/object-transform work and zero framebuffer reallocations at an unchanged
viewport.

@bold{Current limitation:} Screen strokes use deterministic software coverage,
not analytic antialiasing. Curve centreline detail is limited by authored
samples. Hidden-line classification uses opaque and @racket['depth-only]
surfaces only: transparent surfaces are not reliable hidden-line occluders.
Screen points and arrowheads are camera-facing marks, not lit mesh spheres or
cones. Surface topology is a fixed rectangular grid. Solid construction currently
supports only simple single contours (no holes or self-intersections), and
revolution accepts only nonnegative-radius profiles around a cardinal axis.
There is no adaptive tessellation, trimmed domain, texture mapping, arbitrary
implicit surface, or cap generation for arbitrary sliced meshes.
Transparent intersections are not order-independent: triangle sorting is a
useful deterministic approximation, not OIT. Section joining does not repair
pathological nonmanifold meshes. Projected labels are crisp 2D overlays; the
final compositor now uses overlap-aware candidate selection among direct-mode
projected labels (it minimizes overlap but cannot guarantee a disjoint result), but
prepared trajectories remain explicit inputs for their sampled frame grid.
Leaders and visibility policies are consumed by final composition. Only opaque
depth is considered for their hide/fade policy. Billboard image annotations
are depth-tested, but do not yet provide source-mapped text or exact picking.
Linear and affine map requests do not resample geometry; singular maps use a
deterministic authored-normal shading fallback. Pointwise and homotopy maps
currently accept only an unwrapped @racket[mesh3d], not curves, surfaces, or
arbitrary containers. They use the source's fixed authored vertices without
adaptive remeshing, so non-injective maps can create degenerate or
self-intersecting triangles. @racket['drop-triangle] leaves open holes and
does not cap or repair them; it is deliberately not the default. Turning off
normal recomputation preserves source normals and can make nonlinear shading
misleading. Spatial ODE fields require finite @racket[vec3] results. Vector
fields and streamlines have finite explicit author samples; they do not offer
adaptive field-line topology, event detection, or adaptive stopping. There is
no 3D ODE source inspector. Spatial picking accelerates indexed mesh triangles
(including generated tube/surface meshes) with object bounds and a local BVH,
and uses the same prepared screen footprints for strokes and markers. It does
not yet expose texture UVs, interpolate supplied vertex normals for a pick,
support analytic implicit geometry, or perform a GPU-backed selection pass.
Preview overlays and selection scratch values are
diagnostic-only and are intentionally absent from normal frame/video renders.
The retained software backend caches immutable geometry separately from the
reference renderer's camera-space preparations; a camera or viewport change may
therefore miss that software preparation cache. The optional OpenGL backend
retains immutable geometry separately and uses tolerant, not bit-exact, image
comparison.
