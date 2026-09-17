#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-vectors"]{3D: Vectors}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


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

