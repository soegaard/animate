#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-affine-and-decomp-37fab23"]{3D: Affine transforms}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


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

