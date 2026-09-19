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


@; recipe-redistribution begin: coordinate-introduction
@title[#:tag "number-lines-and-coordinate-decorations"]{
  Number Lines and Coordinate Decorations}

Number-line Visuals and coordinate-decoration constructors provide grid lines
and upright numeric labels derived from an existing coordinate object. These
constructors produce immutable snapshots. Changing the source axes or number
line later does not update an already constructed grid or label list.


@; recipe-redistribution end: coordinate-introduction

@declare-exporting[animate #:use-sources (animate/main)]

@; recipe-redistribution begin: coordinate-api
@defproc[(number-line [range axis-range?]
                      [#:id identifier symbol?]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale any/c 1]
                      [#:opacity opacity opacity? 1]
                      [#:length length positive-real? 10]
                      [#:stroke stroke string? "black"]
                      [#:stroke-width stroke-width
                       nonnegative-real? 2]
                      [#:tick-size tick-size
                       nonnegative-real? 1/5]
                      [#:tip-length tip-length
                       nonnegative-real? 2/5]
                      [#:tip-width tip-width
                       nonnegative-real? 3/10]
                      [#:start-tip? start-tip? boolean? #f]
                      [#:end-tip? end-tip? boolean? #f])
         number-line-visual?]{

Constructs a horizontal semantic number line. @racket[range] must contain zero.
The Visual's reference position is the point representing numeric zero, not
necessarily the geometric midpoint of the shaft. @racket[length] is the local
world-unit length of the complete interval.

The regular ticks come from @racket[axis-range-tick-values], with zero inserted
for the number-line representation. Stroke width is cosmetic. Tick and tip
sizes are semantic local geometry and therefore follow affine scale.
}

@defproc[(number-line-visual? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a number-line Visual.}

@defproc[(number-line-visual-range [visual number-line-visual?]) axis-range?]{
Returns the numeric range and regular tick step.}

@defproc[(number-line-visual-length [visual number-line-visual?])
         positive-real?]{
Returns the local shaft length for the complete numeric interval.}

@defproc[(number-line-visual-stroke [visual number-line-visual?]) string?]{
Returns the shaft, tick, and tip color name.}

@defproc[(number-line-visual-stroke-width [visual number-line-visual?])
         nonnegative-real?]{
Returns the cosmetic stroke width.}

@defproc[(number-line-visual-tick-size [visual number-line-visual?])
         nonnegative-real?]{
Returns the full local length of every regular tick.}

@defproc[(number-line-visual-tip-length [visual number-line-visual?])
         nonnegative-real?]{
Returns the local length of each enabled triangular tip.}

@defproc[(number-line-visual-tip-width [visual number-line-visual?])
         nonnegative-real?]{
Returns the full local width of each enabled triangular tip.}

@defproc[(number-line-visual-start-tip? [visual number-line-visual?])
         boolean?]{
Reports whether the minimum endpoint has a tip.}

@defproc[(number-line-visual-end-tip? [visual number-line-visual?])
         boolean?]{
Reports whether the maximum endpoint has a tip.}

@defproc[(number-line-unit-length [visual number-line-visual?])
         positive-real?]{
Returns the local world-unit distance representing one numeric unit.}

@defproc[(number-line-tick-values
          [visual number-line-visual?]
          [#:include-zero? include-zero? boolean? #t])
         (listof finite-real?)]{
Returns regular tick values in increasing numeric order. Zero is included by
default and can be omitted explicitly.}

@defproc[(number-line-number->point
          [visual number-line-visual?]
          [number finite-real?])
         vec2?]{
Maps @racket[number] to the containing coordinate system. The result includes
the number line's complete translation, rotation, and scale. Values outside the
visible range are extrapolated.}

@defproc[(number-line-point->number
          [visual number-line-visual?]
          [point vec2?])
         real?]{
Projects @racket[point] onto the transformed number line and returns the
corresponding numeric value. A point need not lie exactly on the line.}

@defproc[(number-line-visual-start [visual number-line-visual?]) vec2?]{
Returns the transformed point at the numeric minimum.}

@defproc[(number-line-visual-end [visual number-line-visual?]) vec2?]{
Returns the transformed point at the numeric maximum.}

@defproc[(axes-grid-lines
          [axes axes-visual?]
          [#:id identifier symbol?]
          [#:x-grid? x-grid? boolean? #t]
          [#:y-grid? y-grid? boolean? #t]
          [#:include-zero? include-zero? boolean? #f]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke string? "lightgray"]
          [#:stroke-width stroke-width nonnegative-real? 1])
         path-visual?]{
Constructs an ordinary path Visual containing vertical grid lines at x ticks
and horizontal grid lines at y ticks. X lines precede y lines in traversal
order. Zero is omitted by default because the axes already draw the coordinate
axes there. The returned path copies the current axes transform.}

@defproc[(axes-number-labels
          [axes axes-visual?]
          [#:id-prefix identifier-prefix symbol?]
          [#:include-zero? include-zero? boolean? #f]
          [#:font-size font-size positive-real? 3/10]
          [#:color color string? "black"]
          [#:x-gap x-gap nonnegative-real? 1/10]
          [#:y-gap y-gap nonnegative-real? 1/10]
          [#:number->string number->string procedure?
           number->string])
         (listof text-visual?)]{
Constructs upright plain-text labels at the current tick positions. X labels
come first in increasing value order, followed by y labels. When zero is
included, it appears once among the x labels; it is not duplicated on the y
axis. The x gap and y gap are semantic distances from the corresponding tick
extent to the label anchor.

The formatter is called once per label with the numeric value. It must accept
one argument and return exactly one string. It is not retained in the returned
Visuals. Child identities have the forms
@tt{prefix-x-index} and @tt{prefix-y-index}, where each index starts at zero.
}

@defproc[(number-line-number-labels
          [number-line number-line-visual?]
          [#:id-prefix identifier-prefix symbol?]
          [#:include-zero? include-zero? boolean? #t]
          [#:font-size font-size positive-real? 3/10]
          [#:color color string? "black"]
          [#:gap gap nonnegative-real? 1/10]
          [#:number->string number->string procedure?
           number->string])
         (listof text-visual?)]{
Constructs upright plain-text labels below the current number-line ticks.
Values and result order are those of @racket[number-line-tick-values]. Child
identities have the form @tt{prefix-number-index}. The formatter contract is the
same as for @racket[axes-number-labels].
}

Number-line rendering is implemented by converting the model to ordinary
semantic path geometry after explicit renderer selection. A custom renderer can
therefore override the complete number line. Semantic opacity is applied once
after either custom rendering or fallback conversion. Grid lines use the normal
path renderer, while labels use the normal plain-text renderer.



@; recipe-redistribution end: coordinate-api

@seclink["part-reference"]{Reference} · @seclink["visuals"]{Visuals}
