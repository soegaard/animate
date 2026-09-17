#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-bounds-rays-and-planes"]{3D: Bounds, rays, and planes}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


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

