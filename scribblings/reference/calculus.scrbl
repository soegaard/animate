#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     "../../calculus/main.rkt"
                     "../../calculus/render.rkt"
                     (only-in pict pict?)))

@title[#:tag "reference-calculus"]{Calculus lessons}

@defmodule[animate/calculus]

This module declares immutable single-variable calculus lessons. It is a
headless semantic API: importing it does not create a Pict, access a font,
open a window, or write a frame. Native conversion is in
@racketmodname[animate/calculus/render].

@defform[(define-calculus-model model-id
           (model [name expression] ...)
           maybe-constraints)]{
Defines @racket[model-id] as an immutable mathematical model. A
@racket[maybe-constraints] clause has the form
@racket[(constraints boolean-expression ...)]. Bindings are ordered: an
expression can use earlier bindings, but not later ones.
}

@defform[(define-calculus-lesson lesson-id
           (model [name expression] ...)
           (views [view-name view-expression] ...)
           clause ...
           (step step-id step-option ... command ...))]{
Defines @racket[lesson-id] as a @racket[calculus-lesson?]. One @racket[model]
and one nonempty @racket[views] clause are required, as is at least one named
@racket[step]. Optional clauses are @racket[roles], @racket[initially],
@racket[constraints], and @racket[timing]. A lesson declaration constructs data
only; compile it explicitly before inspecting values or preparing output.
}

Inside a model and its lesson clauses, the contextual vocabulary includes
@racket[parameter], domain constructors such as @racket[closed], held
@racket[function] and @racket[piecewise-function] declarations,
@racket[graph], @racket[point-on], @racket[input-reading],
@racket[derivative-function], @racket[definite-integral],
@racket[graph-view], @racket[formula-view], and exposition commands such as
@racket[show], @racket[hide], @racket[read], @racket[vary],
@racket[approach], @racket[together], and @racket[checkpoint]. These spellings
are not exports that change ordinary Racket code outside a declaration.

Finite analysis forms preserve source-declared mathematics independently of
frame order. @racket[(sequence (n) expression #:from first-index)] binds an
integer index, @racket[(partial-sum sequence #:from m #:to n)] is inclusive
and returns zero when @racket[n] is smaller than @racket[m], and
@racket[(sequence-points sequence #:through n)] represents only discrete
indexed samples. @racket[iteration-map] and @racket[newton-iteration] compute
an inspected prefix from their declared seed; a Newton derivative must be a
@racket[derivative-function] of that iteration's function. An unavailable
update remains a partial result rather than selecting a new seed.

@racket[level-set], @racket[root-point], and @racket[intersection-point]
validate supplied candidates only; none starts a hidden root search. Sign,
monotonicity, concavity, and feature declarations retain supplied scopes,
categories, and nonempty justifications. They validate that declaration data,
but do not claim to prove an interval theorem from graph samples.

Limit forms preserve a separate limiting context. @racket[neighborhood] and
@racket[punctured-neighborhood] are open domains with positive authored
radii. @racket[limit-statement] validates its direct real parameter, target,
side, and supplied justification without evaluating the source at the target.
@racket[epsilon-delta-condition] requires finite positive epsilon and delta;
@racket[continuity-condition] reports a declared limit/value mismatch as a
contradiction rather than treating it as a display preference.

Differential constructions retain function provenance: @racket[tangent] and
@racket[linearization] accept only a @racket[derivative-function] declared for
the same held function. @racket[vertical-tangent] is a separate supplied claim
and requires a nonempty justification rather than a fabricated finite slope.
@racket[taylor-polynomial] uses its supplied ordered compatible derivatives;
an empty derivative list produces the constant approximation at its base.

@defproc[(compile-calculus-lesson [lesson calculus-lesson?]
                                  [#:profile profile calculus-profile? default-calculus-profile]
                                  [#:values values hash? (hash)]
                                  [#:computation computation calculus-computation?
                                   default-calculus-computation])
         calculus-plan?]{
Compiles an immutable, headless timing plan. Overrides name only declared
parameters and must satisfy their declared domains.
}

@defproc[(calculus-plan-sample [plan calculus-plan?]
                               [#:at at (or/c 'initial 'final real? calculus-moment?) 'final])
         calculus-snapshot?]{
Samples a mathematical/presentation state without native rendering. Numeric
boundaries are right-continuous; use @racket[calculus-step-start],
@racket[calculus-step-end], or @racket[calculus-checkpoint] when an exact
semantic phase is important.
}

@defproc[(calculus-snapshot-ref [snapshot calculus-snapshot?]
                                [address (or/c symbol? (listof symbol?))])
         calculus-result?]{
Returns a structured result for a public object or part address. A nondefined
result has value @racket[#f]; distinguish it through
@racket[calculus-result-status], which reports @racket['defined],
@racket['outside-domain], @racket['undefined], or @racket['unresolved].
}

@defproc[(calculus-snapshot-visible? [snapshot calculus-snapshot?]
                                     [address (or/c symbol? (listof symbol?))]
                                     [#:view view (or/c #f symbol?) #f])
         boolean?]{
Reports effective presentation visibility. Mathematical existence and
visibility are deliberately independent.
}

@defmodule[animate/calculus/render]

The render adapter re-exports @racketmodname[animate/calculus] and is the
explicit bridge to native output.

@defproc[(prepare-calculus-lesson [lesson calculus-lesson?]
                                  [#:width width exact-positive-integer? 1280]
                                  [#:height height exact-positive-integer? 720]
                                  [#:quality quality calculus-render-quality?
                                   (calculus-render-quality)])
         prepared-calculus-lesson?]{
Compiles and binds one lesson to a native output size. Use
@racket[prepare-calculus-plan] when a plan is already available.
}

@defproc[(prepared-lesson->pict [prepared prepared-calculus-lesson?]
                                [#:at at (or/c 'initial 'final real? calculus-moment?) 'final])
         pict?]{
Returns the prepared Pict at one semantic moment. The companion
@racket[prepared-lesson->visual] and @racket[prepared-lesson->scene] use the
same prepared composition and dimensions.
}
