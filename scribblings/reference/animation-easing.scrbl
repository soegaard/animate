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

@title[#:tag "reference-animation-easing"]{Choosing a speed curve}

An easing function maps elapsed progress to animation progress.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(linear-reveal-front
          [direction vec2?]
          [#:origin origin (or/c 'automatic vec2?) 'automatic]
          [#:padding padding (and/c finite-real? (>=/c 0)) 1/20])
         linear-reveal-front?]{

Constructs a deterministic half-plane reveal front. @racket[direction] must be
finite and nonzero and is normalized once at construction. @racket['automatic]
uses the frozen layout-box center as the sweep reference; an explicit
@racket[vec2] supplies a local reference point. Padding is a nonnegative
fraction of the larger frozen-box dimension.
}

@defproc[(linear-reveal-front? [value any/c]) boolean?]{
Recognizes a linear reveal front.
}

@defproc[(rate-function? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in callable semantic rate
function.
}

@defproc[(rate-function-name [value rate-function?]) symbol?]{

Returns the stable built-in kind, such as @racket['smooth].
}

@defproc[(rate-function-parameters [value rate-function?]) list?]{

Returns the validated constructor parameters in their stable order.
}

@defproc[(rate-function->datum [value rate-function?]) pair?]{

Returns a compact serializable description, for example
@racket['(smooth 10)].
}

@defproc[(rate-function-apply [value rate-function?]
                              [progress finite-real?]) finite-real?]{

Applies one semantic rate function. The scene machinery supplies clamped
progress; built-ins return exact 0 or 1 at the corresponding clip boundaries.
}

@defthing[linear rate-function?]{

The default rate function, callable as @racket[(linear progress)]. It returns
@racket[progress] unchanged.
}

@defproc[(smooth [#:inflection inflection positive-real? 10]) rate-function?]{

Returns a normalized logistic S curve. Greater @racket[inflection] makes its
departure from zero and arrival at one sharper.
}

@defproc[(smoothstep) rate-function?]{

Returns the cubic @math{3t^2-2t^3} curve with zero slope at both endpoints.
}

@defproc[(rush-into) rate-function?]{

Returns a smooth curve that starts slowly and accelerates into its endpoint.
}

@defproc[(rush-from) rate-function?]{

Returns a smooth curve that leaves quickly and decelerates toward its endpoint.
}

@defproc[(there-and-back) rate-function?]{

Returns a smooth excursion from zero to one and back to zero.
}

@defproc[(there-and-back-with-pause
          [#:pause-ratio pause-ratio (and/c finite-real? (>=/c 0) (</c 1)) 1/3])
         rate-function?]{

Returns an outward-and-returning curve that holds one for the specified fraction
of its unit interval.
}

@defproc[(reverse-rate [function rate-function?]) rate-function?]{

Returns the time reversal of a semantic rate function.
}

@defproc[(compose-rate [first rate-function?] [rest rate-function?] ...)
         rate-function?]{

Returns nested timing composition: @racket[(compose-rate outer inner)] evaluates
@racket[outer] after @racket[inner].
}

@defproc[(squish-rate [function rate-function?]
                      [#:from from (and/c finite-real? (>=/c 0) (<=/c 1)) 0]
                      [#:to to (and/c finite-real? (>=/c 0) (<=/c 1)) 1])
         rate-function?]{

Runs @racket[function] only over the strict interval from @racket[from] to
@racket[to], holding zero before it and one after it.
}
