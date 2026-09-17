#lang scribble/manual
@(require (for-label racket/base animate animate/preview))

@title[#:tag "concept-formula-source-maps"]{Formula parts and source maps}

There are two ways to identify a piece of a formula. A @bold{named part} is a
part you explicitly named while authoring. A @bold{source selection} refers to
some of the TeX used to make the formula.

Given a formula named @racket[equation], these requests ask different questions:

@racketblock[
(formula-select equation 'denominator)
(formula-source-select equation "\\frac{x}{2}")
(formula-source-select equation (source-occurrence "x" 1))]

The first asks for the named denominator. The second selects a TeX source span.
The third distinguishes one occurrence of repeated source text. The exact
selection rules belong to the formula API reference.

A source map connects source spans to visible rendered pieces. It does not give
Animate an algebraic understanding of arbitrary TeX. For mathematical rewrites,
use the separate @tt{animate/math} authoring system.

The preview follows the same rule. When a rendered piece has one clear source
selection, the inspector can select it. When the source is ambiguous or missing,
it selects the enclosing formula rather than guessing from position or drawing
order. See @racket[scene-inspector-subject-at-path].
