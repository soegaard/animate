#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-supplementary-q-t-3c0e1ed"]{3D: Trajectory display}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defthing[prepared-trajectory3d? procedure?]{Recognizes an immutable prepared
trajectory.}
@defthing[streamline-sample-policy3d? procedure?]{Recognizes an immutable
world-space streamline resampling policy.}

