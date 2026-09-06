#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     racket/contract
                     racket/math
                     animate
                     animate/3d))

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

@defproc[(projected-label [template visual?] [#:view view-id symbol?]
                          [#:target target (or/c vec3? spatial-path?)]
                          [#:offset offset vec2? origin]
                          [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                           'always-visible])
         projected-label?]{
Creates an ordinary 2D text, formula, or other concrete Visual whose centre
follows a point projected through a sampled @racket[view3d]. @racket[offset]
is in screen pixels (with Animate's y-up convention), so it is not enlarged
or rotated by the spatial camera.}
@defproc[(projected-label? [value any/c]) boolean?]{Recognizes a projected
label definition.}
@defproc[(follow-projected-point [template visual?] [#:view view-id symbol?]
                                 [#:point point vec3?]
                                 [#:offset offset vec2? origin]
                                 [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                  'always-visible])
         projected-label?]{The literal-point spelling of @racket[projected-label].}
@defproc[(follow-projected-spatial [template visual?] [#:view view-id symbol?]
                                   [#:target target spatial-path?]
                                   [#:offset offset vec2? origin]
                                   [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                    'always-visible])
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

@section{Spatial curves and vector diagrams}

SCENE-3D-F adds finite spatial diagram geometry. A curve stores its complete
deterministic centre-line sample sequence; rendering lowers that value to a
physical-radius tube. Partial curves, reveals, and curve-following are sampled
directly from that complete sequence at the requested scene time. They never
use a mutable updater or the previous rendered frame.

@defproc[(point3d [position vec3?] [#:id id symbol?]
                  [#:radius radius positive? 1/10]
                  [#:color color color-spec? "cornflowerblue"])
         mesh3d?]{Creates a finite octahedral spatial point.}
@defproc[(curve3d? [value any/c]) boolean?]{Recognizes a sampled spatial curve.}
@defproc[(line3d [from vec3?] [to vec3?] [#:id id symbol?]
                 [#:radius radius positive? 1/20]
                 [#:width-mode width-mode 'world])
         curve3d?]{Creates a finite straight spatial line. The alias
@racket[segment3d] has the same arguments.}
@defproc[(segment3d [from vec3?] [to vec3?] [#:id id symbol?]
                    [#:radius radius positive? 1/20]
                    [#:width-mode width-mode 'world])
         curve3d?]{Creates the same finite geometry as @racket[line3d].}
@defproc[(polyline3d [points (or/c list? vector?)] [#:id id symbol?]
                     [#:radius radius positive? 1/20]
                     [#:closed? closed? boolean? #f]
                     [#:width-mode width-mode 'world])
         curve3d?]{Creates a sampled polyline. Adjacent repeated points are
removed before tangents and tube frames are formed.}
@defproc[(parametric-curve3d [procedure procedure?]
                             [#:range range (list/c finite-real? finite-real?) (list 0 1)]
                             [#:samples samples exact-positive-integer? 64]
                             [#:id id symbol?]
                             [#:radius radius positive? 1/20])
         curve3d?]{Samples @racket[procedure] at equally spaced, inclusive
range endpoints. The declared @racket[samples] locations are deterministic.}
@defproc[(tube3d [points (or/c list? vector?)] [#:id id symbol?]
                [#:radius radius positive? 1/20]
                [#:sides sides exact-positive-integer? 8]
                [#:closed? closed? boolean? #f]
                [#:width-mode width-mode 'world])
         mesh3d?]{Creates a tube mesh using transported local frames.}
@defproc[(arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                  [#:radius radius positive? 1/20]) group3d?]{Creates a
shaft and conical tip at stable descendants @racket['shaft] and @racket['tip].}
@defproc[(double-arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                         [#:radius radius positive? 1/20]) group3d?]{Creates a
shaft with one conical tip at each endpoint.}

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
geometry in the source mesh's local coordinates.}
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

SCENE-3D-K adds direct-time flow geometry without a mutable per-frame updater.
@racket[prepare-ode-trajectory3d] records an immutable numerical path once;
subsequent position lookup accepts any supported time in any order. A field
accepts either @racket[(field x y z)] or @racket[(field time x y z)] and must
return exactly one finite @racket[vec3]. The fixed default is checkpointed RK4.
With @racket[adaptive-rk45], accepted Dormand--Prince nodes and endpoint
derivatives are stored, so lookup uses cubic Hermite dense output and never
calls the author field.

@racket[flow-particle3d] is a semantic spatial relation. Before an image or
preview worker resolves it, Animate samples its requested phase values into an
immutable table. Thus worker rendering reads positions and tangents only; it
does not evaluate the field procedure. Direct lookup of a fixed RK4 trajectory
may still take the bounded suffix after its nearest checkpoint.

@racketblock[
(define lorenz-path
  (prepare-ode-trajectory3d
   (lambda (x y z) (vec3 (* 10 (- y x)) (- (* x (- 28 z)) y)
                         (- (* x y) (* 8/3 z))))
   (vec3 0 1 21/20)
   #:time-range (cons 0 20)
   #:solver (adaptive-rk45 #:relative-tolerance 1e-6)))

(define phase (parameter 'time 0))
(flow-particle3d lorenz-path phase #:id 'particle #:tangent-length 1)
]

@defproc[(prepare-ode-trajectory3d
          [field (or/c (procedure-arity-includes/c 3)
                       (procedure-arity-includes/c 4))]
          [seed vec3?]
          [#:time-range time-range (cons/c finite-real? finite-real?)]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:checkpoint-every checkpoint-every exact-positive-integer? 16]
          [#:solver solver (or/c false/c adaptive-rk45?) #f])
         ode-trajectory3d?]{Prepares one immutable spatial trajectory over the
closed range @racket[(cons start-time end-time)]. The seed is at time zero;
the range may extend on either side of it.}
@defproc[(ode-trajectory3d? [value any/c]) boolean?]{Recognizes a prepared
fixed-RK4 or adaptive-RK45 spatial trajectory.}
@defproc[(ode-trajectory3d-position [trajectory ode-trajectory3d?]
                                     [time finite-real?]) vec3?]{Returns the
position at a supported time. Adaptive lookup reads only stored data.}
@defproc[(ode-trajectory3d-time-range [trajectory ode-trajectory3d?])
         (cons/c finite-real? finite-real?)]{Returns its supported range.}
@defproc[(ode-trajectory3d-step-size [trajectory ode-trajectory3d?])
         (or/c positive? false/c)]{Returns a fixed path's RK4 step, or
@racket[#f] for an adaptive path.}
@defproc[(ode-trajectory3d-checkpoint-every [trajectory ode-trajectory3d?])
         (or/c exact-positive-integer? false/c)]{Returns a fixed path's
checkpoint spacing, or @racket[#f] for an adaptive path.}
@defproc[(ode-trajectory3d-solver [trajectory ode-trajectory3d?]) any/c]{Returns
@racket['fixed-rk4] or the immutable @racket[adaptive-rk45?] configuration.}
@defproc[(ode-trajectory3d-diagnostics [trajectory ode-trajectory3d?]) any/c]{For
an adaptive path, returns immutable solver name, accepted/rejected step count,
final time, and maximum norm-relative embedded-error ratio; it returns
@racket[#f] for fixed RK4.}

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

The canonical acceptance scene is
@filepath{examples/3d/prepared-lorenz-flow.rkt}.

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
             [triangle-index exact-nonnegative-integer?]
             [point vec3?]
             [distance nonnegative-real?]
             [barycentric vec3?]
             [normal vec3?]
             [ray ray3?]
             [metadata immutable-hash?]) #:transparent]{
The nearest exact spatial pick. Its metadata contains immutable material and
drawing-order facts plus the tested world-space triangle for a preview overlay.
Ties are resolved first by drawing index and then by authored triangle index.
}

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
@defproc[(view3d-pixel-pick [view view3d?] [pixel-x finite-real?]
                             [pixel-y finite-real?]
                             [#:width width exact-positive-integer?]
                             [#:height height exact-positive-integer?])
         (or/c #f spatial-pick?)]{
Builds the camera ray through a top-left-origin viewport pixel and performs the
same exact pick. It does not sample a rendered bitmap or require a GUI.
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

SCENE-3D-M keeps @racket[animate/3d] pure and places effectful implementation
choice in @racketmodname[animate/3d/render]. A backend receives an immutable
@racket[render3d-request], may retain a preparation that it owns, and returns
copied ARGB bytes. Thus changing a backend, releasing its cache, or recovering
from a failed optional native renderer cannot mutate a @racket[view3d] or any
of its spatial children.

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

@defstruct*[render3d-request
            ([view view3d?]
             [width exact-positive-integer?]
             [height exact-positive-integer?]
             [cancellation-token any/c]) #:transparent]{
One backend-local request. The cancellation field is either @racket[#f] or the
preview's cooperative cancellation token; it is not serialised into scene
state.
}
@defstruct*[renderer3d-render-result
            ([width exact-positive-integer?]
             [height exact-positive-integer?]
             [argb-bytes bytes?]
             [diagnostics any/c]) #:transparent]{
A completed backend-independent frame. Its ARGB byte vector is immutable and
may outlive the backend that produced it.
}
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

The reference/retained conformance tests compare projected output at exact
endpoints and in nonmonotonic camera-frame order. The canonical probe is
@filepath{examples/3d/retained-renderer.rkt}; evaluating
@tt{(retained-renderer-summary)} there demonstrates a cache hit without
changing the visible scene.

The repository tool @filepath{tools/run-3d-probes.rkt} renders the canonical
visual probes for any visible stage from @tt{3D-B} through @tt{3D-M}. For
example, @tt{racket tools/run-3d-probes.rkt --stage 3D-M --output
rendered-examples/3d-m} writes frame PNGs plus @tt{manifest.rktd} and a
@tt{diagnostics.rktd} file per probe. The manifest records Animate and Racket
versions, renderer ID, output dimensions, sample times, sampled 3D cameras,
renderer-fingerprint digests, and frame hashes. Probe images are human review
evidence; semantic and small-raster tests remain the correctness oracle.

@bold{Current limitation:} Curve radii are physical @racket['world] units and
surface topology is a fixed rectangular grid. Solid construction currently
supports only simple single contours (no holes or self-intersections), and
revolution accepts only nonnegative-radius profiles around a cardinal axis.
There is no adaptive tessellation, trimmed domain, texture mapping, arbitrary
implicit surface, or cap generation for arbitrary sliced meshes.
Transparent intersections are not order-independent: triangle sorting is a
useful deterministic approximation, not OIT. Section joining does not repair
pathological nonmanifold meshes. Projected labels are crisp 2D overlays and
may overlap; only opaque depth is considered for their hide/fade policy.
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
no 3D ODE source inspector. Spatial picking currently accelerates indexed mesh
triangles (including generated curve/surface meshes) with object bounds and a
local BVH. It does not yet expose texture UVs, interpolate supplied vertex
normals for a pick, support analytic implicit geometry, or perform a
GPU-backed selection pass. Preview overlays and selection scratch values are
diagnostic-only and are intentionally absent from normal frame/video renders.
The retained backend currently caches the reference renderer's prepared
camera-space triangles; it is not a GPU renderer. No optional Pict3D package is
bundled, so a native Pict3D/GPU adapter remains a future backend implementation
behind the same protocol. A changed camera or viewport dimensions therefore
miss the current preparation cache, and GPU/software pixel comparisons will
need tolerances when such an adapter exists.
