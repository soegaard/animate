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

@title[#:tag "reference-animation-emphasis"]{Drawing attention}

Use a temporary effect to draw attention to an object.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(pulse
          [target (or/c visual? symbol? visual-path?)]
          [#:scale-factor scale-factor any/c 6/5]
          [#:opacity-factor opacity-factor (real-in 0 1) 1]
          [#:cycles cycles exact-positive-integer? 1]
          [#:about about (or/c 'center 'reference vec2?) 'center])
         pulse-request?]{

Temporarily changes selected affine/opacity components of a present target
through a deterministic squared-sine there-and-back envelope. The envelope is
exactly zero at both clip endpoints, and the exact clip-start component values
are restored at completion. @racket[#:cycles] is an exact positive integer.

Only nonidentity components are written: a scale factor of one writes no scale,
and an opacity factor of one writes no opacity. A pulse can therefore run with
same-target movement when it does not write translation, but it conflicts with
any overlapping request that writes one of its selected components. Direct
Visual targets are checked immediately; symbol and nested-path targets are
checked at the leaf's exact local start.
}

@defproc[(pulse-request? [value any/c]) boolean?]{
Recognizes a @racket[pulse] request.
}

@defproc[(confetti
          [origin-or-target (or/c vec2? visual? symbol? visual-path?)]
          [#:count count exact-positive-integer? 24]
          [#:seed seed exact-integer? 0]
          [#:spread spread (and/c finite-real? (>=/c 0)) 2]
          [#:height height (and/c finite-real? (>=/c 0)) 2]
          [#:gravity gravity (and/c finite-real? (>=/c 0)) 3]
          [#:palette palette (or/c (listof color-spec?) (vectorof color-spec?))
                     default-confetti-palette]
          [#:id id (or/c #f symbol?) #f])
         confetti-request?]{

Creates a deterministic temporary overlay of simple path pieces. The complete
piece plan is generated at construction from @racket[seed], without reading or
mutating global random state. A @racket[vec2] is a fixed launch point; a Visual,
symbol, or path target is resolved to its world reference point once at the
play clip's start. Consequently, the target is not rewritten and later target
motion does not change an already compiled particle trajectory.

Each piece follows a direct ballistic formula using @racket[spread],
@racket[height], and @racket[gravity], so arbitrary-time sampling and forward
playback produce the same frame. With an explicit @racket[id], helpers use
deterministic child identities under that name; otherwise their identities are
derived from the composition expansion origin. They appear only at interior
samples and are all removed exactly at completion. Reusing an explicit
@racket[id] in a simultaneous play is rejected as a normal component conflict.
Inspection records the resolved origin, seed, generated count, and helper IDs.
}

@defproc[(confetti-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[confetti].
}
