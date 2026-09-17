#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "reference-animation-camera"]{Moving the camera}

Move the view without changing the coordinates of the objects.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(camera-shake
          [#:amplitude amplitude (and/c finite-real? (>=/c 0)) 1/10]
          [#:samples samples exact-positive-integer? 12]
          [#:seed seed exact-integer? 0]
          [#:decay decay (or/c 'none 'linear 'smooth) 'linear])
         succession-animation-request?]{

Constructs an eager succession of primary-camera @racket[camera-pan-by]
requests from a local deterministic pseudo-random offset plan. The plan begins
and ends at zero, and each leaf is the difference of consecutive offsets, so
the camera's exact final center equals its clip-start center. The explicit
@racket[seed] is the complete source of variation; no global random state is
read or changed. @racket[#:decay] controls the finite offset envelope.
}
