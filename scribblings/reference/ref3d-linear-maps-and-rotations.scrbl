#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-linear-maps-and-rotations"]{3D: Linear maps and rotations}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


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

