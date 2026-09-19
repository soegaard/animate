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

@title[#:tag "reference-animation-values"]{Changing named values}

Animate numbers and other named values used by displays or dependent objects.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(value-to [id (or/c symbol? scene-parameter?)] [destination any/c]) value-to-request?]{
Creates an absolute animation request for one named interpolable semantic value.
The value must already be present in the scene when the request is compiled, and
its kind must match @racket[destination]. Interior samples use
@racket[interpolate-value], while exact interval boundaries preserve the original
source and requested destination representations. Named values use the
same scheduler, easing, timing compositions, and conflict detection as Visual
requests. They are not painted directly; derived Visual resolvers may consume them
to determine concrete rendered geometry.

An immutable @racket[scene-parameter?] may be used in place of @racket[id].
}

@defproc[(value-to-request? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a request created by @racket[value-to].
}

@defproc[(change-number-to [id (or/c symbol? scene-parameter?)]
                           [destination (or/c finite-real? finite-complex?)])
         change-number-to-request?]{

Creates an absolute numerical transition. Finite reals interpolate normally;
finite complex values interpolate their Cartesian components. It uses the same
immutable scalar-value animation as @racket[value-to], but its numerical
contract communicates that it is intended to drive a numeric display.
}

@defproc[(change-number-to-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[change-number-to].
}

@defproc[(count-to [id (or/c symbol? scene-parameter?)]
                    [destination finite-real?])
         count-to-request?]{

Counts from the named parameter's value at this play clip's start to
@racket[destination]. The initial named value must therefore be a compatible
finite real when the request is compiled.
}

@defproc[(count-to-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[count-to].
}

@defproc[(count-from [id (or/c symbol? scene-parameter?)]
                      [from finite-real?]
                      [to finite-real?])
         count-from-request?]{

Counts between explicit endpoints. In particular, @racket[from] is the value
at clip phase zero even if the preceding scene has a different value. This is
useful for independently reproducible counters and does not introduce a mutable
tracker.
}

@defproc[(count-from-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[count-from].
}
