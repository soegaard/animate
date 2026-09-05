#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate
                     animate/preview))

@section{Formula Source Maps}

Formula parts and source selections deliberately answer different questions.
Use @racket[formula-select] for a part the author explicitly named; use
@racket[formula-source-select] when selecting canonical TeX source. The latter
can represent repeated occurrences precisely with @racket[source-occurrence].

@racketblock[
(formula-select equation 'denominator)
(formula-source-select equation "\\frac{x}{2}")
(formula-source-select equation (source-occurrence "x" 1))]

Source maps describe visible rendered leaves; they do not claim algebraic
understanding of arbitrary TeX.

@racketmodname[animate/preview] uses the same distinction when a formula leaf
is inspected. Given an already sampled @racket[scene-state],
@racket[scene-inspector-subject-at-path] maps a unique rendered leaf back to
its exact source-map unit. A leaf shared by several source spans, or one with
no map entry, deliberately selects the enclosing formula rather than choosing
an occurrence based on drawing order or position.
