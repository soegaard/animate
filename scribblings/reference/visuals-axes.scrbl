#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate/main
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@(require "../private/reference-examples.rkt")

@; Animate Visuals reference revision R1 (20260919).
@title[#:tag "ref-visuals-axes"]{Arrows and Coordinate Axes}


@declare-exporting[animate/main]


Arrow endpoints and axes reference points are semantic coordinates.
Numeric axis ranges are distinct from their displayed world lengths:
@racket[axes-coordinates->point] applies the axis scales and placement, while
@racket[axes-point->coordinates] performs the inverse conversion.

See also @secref["ref-visuals-annotations"], @secref["ref-visuals-plots"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "arrows-and-axes"]{Arrow and Cartesian Axes Visuals}

Arrow and axes values are semantic affine Visuals. They implement
@racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual]. Their raw structure constructors and internal local
geometry fields are not public.

@subsection{Arrows}

@defproc[(arrow
          [start vec2?]
          [end vec2?]
          [#:id id symbol?]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2]
          [#:tip-length tip-length
                        (and/c finite-real? positive?)
                        3/10]
          [#:tip-width tip-width
                       (and/c finite-real? positive?)
                       1/4]
          [#:start-tip? start-tip? boolean? #f]
          [#:end-tip? end-tip? boolean? #t])
         arrow-visual?]{

Creates a semantic arrow whose untransformed shaft begins at @racket[start] and
ends at @racket[end]. Both points are in one containing coordinate system. They
are world coordinates for a top-level Visual and local coordinates when the
arrow is later placed in a group.

The points must be distinct and their distance must be finite. The constructor
uses their midpoint as the Visual's reference position and stores the two
endpoints relative to that midpoint. The optional @racket[rotation] and
@racket[scale] therefore act around the midpoint.

@racket[start-tip?] and @racket[end-tip?] independently select closed triangular
tips. The default is one tip at the end. Both flags may be false, or both may be
true. @racket[tip-length] measures the distance from an apex to the center of its
base. @racket[tip-width] measures the full base width. Both are local world-unit
geometry and are affected by semantic scale. A tip is allowed to be longer than
the shaft.

@racket[stroke] is adapter-specific style data. The built-in Pict renderer uses
it for the shaft, tip fill, and tip outline. @racket[stroke-width] is a cosmetic
output width and is not multiplied by semantic scale. @racket[opacity] is
applied to the complete rendered arrow after renderer dispatch.
}

@defproc[(arrow-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in arrow Visual.
}

@defproc[(arrow-visual-length [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled length of the stored local shaft. Translation, rotation,
and semantic scale do not change this result.
}

@defproc[(arrow-visual-stroke [arrow arrow-visual?]) any/c]{

Returns the stored adapter-specific stroke style.
}

@defproc[(arrow-visual-stroke-width [arrow arrow-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(arrow-visual-tip-length [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length of each enabled triangular tip.
}

@defproc[(arrow-visual-tip-width [arrow arrow-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local base width of each enabled triangular tip.
}

@defproc[(arrow-visual-start-tip? [arrow arrow-visual?]) boolean?]{

Reports whether the start endpoint has a triangular tip.
}

@defproc[(arrow-visual-end-tip? [arrow arrow-visual?]) boolean?]{

Reports whether the end endpoint has a triangular tip.
}

@defproc[(arrow-visual-start [arrow arrow-visual?]) vec2?]{

Returns the current start point in the arrow's containing coordinate system.
The complete affine transform has been applied.
}

@defproc[(arrow-visual-end [arrow arrow-visual?]) vec2?]{

Returns the current end point in the arrow's containing coordinate system. The
complete affine transform has been applied.
}

@defproc[(arrow-visual-point-at
          [arrow arrow-visual?]
          [progress (real-in 0 1)])
         vec2?]{

Returns the current shaft point at @racket[progress]. A value of @racket[0]
returns the transformed start, @racket[1] returns the transformed end, and
@racket[1/2] returns the transformed midpoint. The procedure follows the shaft
only; tip geometry does not affect the result.
}

@subsection{Axis Ranges}

@defstruct*[axis-range ([minimum finite-real?]
                        [maximum finite-real?]
                        [tick-step
                         (and/c finite-real? positive?)])
  #:transparent]{

Represents one closed numeric interval and the spacing of its regular ticks.
The fields have these meanings:

@itemlist[
 @item{@racket[minimum] is the smallest represented coordinate.}
 @item{@racket[maximum] is the largest represented coordinate.}
 @item{@racket[tick-step] is the positive distance between regular tick
       coordinates.}
]

@racket[minimum] must be less than @racket[maximum]. The computed difference
@racket[(- maximum minimum)] must also remain a positive finite real; this
rejects an inexact endpoint pair whose subtraction overflows. The structure is immutable and
transparent. Linear axes require their ranges to contain zero; logarithmic axes
require strictly-positive ranges. Its public bindings include @racket[axis-range],
@racket[axis-range?], the three field accessors, and
@racket[struct:axis-range].
}

@defproc[(axis-range-contains? [range axis-range?] [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real in the closed interval
from @racket[(axis-range-minimum range)] through
@racket[(axis-range-maximum range)]. Non-real values, infinities, and NaN return
@racket[#f].
}

@defproc[(axis-range-tick-values [range axis-range?])
         (listof finite-real?)]{

Returns the nonzero integer multiples of @racket[(axis-range-tick-step range)]
that lie in the closed interval. The values are in increasing numeric order.
An interval endpoint is included when it is such a multiple. Zero is omitted
because the two Cartesian shafts already intersect there.

For example:

@racketblock[
(axis-range-tick-values (axis-range -3 5 2))
]

returns @racket['(-2 2 4)]. The procedure does not choose ticks from camera
pixels or available label space.

Exact endpoint quotients are handled exactly. For inexact quotients, the
procedure uses a fixed relative tolerance of @racket[1e-12] when choosing the
first and last integer indexes. This prevents ordinary decimal input such as
@racket[-0.3], @racket[0.3], and @racket[0.1] from losing endpoint ticks because
of binary floating-point rounding. It raises an exception when dividing a range
endpoint by the step produces an infinite or NaN index.
}

@; visuals-reference-r1 example: axes-1
The zero tick is omitted; nonzero multiples stay in increasing order.

@examples[#:eval reference-eval
  (eval:check (axis-range-tick-values (axis-range -3 5 2)) '(-2 2 4))
]


@defproc[(axis-scale? [value any/c]) boolean?]{

Returns @racket[#t] for the supported scale symbols @racket['linear] and
@racket['log].
}

@subsection{Cartesian Axes}

@defproc[(axes
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:x-range x-range axis-range? (axis-range -6 6 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:x-scale x-scale axis-scale? 'linear]
          [#:y-scale y-scale axis-scale? 'linear]
          [#:x-log-base x-log-base
                        (and/c finite-real? (>/c 1))
                        10]
          [#:y-log-base y-log-base
                        (and/c finite-real? (>/c 1))
                        10]
          [#:x-length x-length
                      (and/c finite-real? positive?)
                      12]
          [#:y-length y-length
                      (and/c finite-real? positive?)
                      6]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2]
          [#:tick-size tick-size
                       (and/c finite-real? (>=/c 0))
                       3/20]
          [#:tip-length tip-length
                        (and/c finite-real? positive?)
                        3/10]
          [#:tip-width tip-width
                       (and/c finite-real? positive?)
                       1/4]
          [#:x-tip? x-tip? boolean? #t]
          [#:y-tip? y-tip? boolean? #t])
         axes-visual?]{

Creates semantic two-dimensional Cartesian axes. On the default linear scales,
numeric coordinate @tt{(0, 0)} is the Visual's local origin and reference point
before @racket[center], @racket[rotation], and @racket[scale] are applied.

The full interval from @racket[(axis-range-minimum x-range)] to
@racket[(axis-range-maximum x-range)] is mapped to @racket[x-length] local world
units. The y interval is mapped independently to @racket[y-length]. The x and y
unit lengths can therefore differ. Each resulting length-per-display-unit must
remain a positive finite real.

With @racket['log] for @racket[x-scale] or @racket[y-scale], that axis accepts
only a strictly-positive @racket[axis-range]. Numeric coordinates are converted
through @racket[(log value)] in the configured base before they are placed. A
log axis uses numeric one as its shaft reference when it is visible (otherwise
the minimum range value); coordinate zero is invalid. @racket[x-log-base] and
@racket[y-log-base] must be finite and greater than one. The
@racket[tick-step] of a log range is a step in base-logarithm exponent space, so
the usual value of one produces ticks at successive powers of the base.

The x shaft is drawn at numeric y coordinate zero on a linear y axis, and at
numeric one (or the visible minimum) on a log y axis; the y shaft follows the
same rule for its x coordinate. Regular ticks come from
@racket[axis-range-tick-values] on linear axes and powers of the configured base
on log axes. @racket[tick-size] is the full local length of
each tick. A value of zero hides all ticks while preserving the ranges and
coordinate conversion.

@racket[x-tip?] and @racket[y-tip?] select triangular tips at the maximum-x and
maximum-y endpoints, respectively. @racket[tip-length] and @racket[tip-width]
are local world-unit geometry. @racket[stroke-width] is cosmetic. The built-in
renderer uses @racket[stroke] for shafts, ticks, tip fill, and tip outlines.

The constructor does not create numeric labels, axis-name labels, grid lines,
or sampled plots. They can be added as separate Visuals. Renderer-aware layout
can place labels around the complete axes render box.
}

@defproc[(axes-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in Cartesian-axes Visual.
}

@defproc[(axes-visual-x-range [axes axes-visual?]) axis-range?]{

Returns the stored horizontal numeric range.
}

@defproc[(axes-visual-y-range [axes axes-visual?]) axis-range?]{

Returns the stored vertical numeric range.
}

@defproc[(axes-visual-x-scale [axes axes-visual?]) axis-scale?]{

Returns the stored horizontal coordinate scale.
}

@defproc[(axes-visual-y-scale [axes axes-visual?]) axis-scale?]{

Returns the stored vertical coordinate scale.
}

@defproc[(axes-visual-x-log-base [axes axes-visual?])
         (and/c finite-real? (>/c 1))]{

Returns the stored horizontal logarithm base. It affects coordinate conversion
only when @racket[(axes-visual-x-scale axes)] is @racket['log].
}

@defproc[(axes-visual-y-log-base [axes axes-visual?])
         (and/c finite-real? (>/c 1))]{

Returns the stored vertical logarithm base. It affects coordinate conversion
only when @racket[(axes-visual-y-scale axes)] is @racket['log].
}

@defproc[(axes-visual-x-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing the full x range.
}

@defproc[(axes-visual-y-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing the full y range.
}

@defproc[(axes-visual-stroke [axes axes-visual?]) any/c]{

Returns the stored adapter-specific line and tip style.
}

@defproc[(axes-visual-stroke-width [axes axes-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(axes-visual-tick-size [axes axes-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the unscaled full local length of each tick.
}

@defproc[(axes-visual-tip-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length of each enabled maximum-end tip.
}

@defproc[(axes-visual-tip-width [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local base width of each enabled maximum-end tip.
}

@defproc[(axes-visual-x-tip? [axes axes-visual?]) boolean?]{

Reports whether the maximum-x endpoint has a triangular tip.
}

@defproc[(axes-visual-y-tip? [axes axes-visual?]) boolean?]{

Reports whether the maximum-y endpoint has a triangular tip.
}

@defproc[(axes-x-unit-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing one x display-space unit. On a
linear axis it is
@racket[(/ (axes-visual-x-length axes)
           (- (axis-range-maximum (axes-visual-x-range axes))
              (axis-range-minimum (axes-visual-x-range axes))))]. On a log
axis the denominator is the corresponding base-logarithm span.
}

@defproc[(axes-y-unit-length [axes axes-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local length representing one y display-space unit. On a
linear axis it is
@racket[(/ (axes-visual-y-length axes)
           (- (axis-range-maximum (axes-visual-y-range axes))
              (axis-range-minimum (axes-visual-y-range axes))))]. On a log
axis the denominator is the corresponding base-logarithm span.
}

@defproc[(axes-coordinates->point
          [axes axes-visual?]
          [x finite-real?]
          [y finite-real?])
         vec2?]{

Converts numeric coordinate @tt{(x, y)} to a point in the axes' containing
coordinate system. The procedure first maps each coordinate through its linear
or logarithmic display scale, multiplies by the independent local unit lengths,
then applies semantic scale, rotation, and translation.

The numeric coordinates are not required to lie inside the displayed ranges.
This permits extrapolation and placement just outside the visible axes. A value
on a logarithmic axis must nevertheless be a positive finite real.
}

@defproc[(axes-point->coordinates [axes axes-visual?] [point vec2?]) vec2?]{

Converts @racket[point] from the axes' containing coordinate system to numeric
axis coordinates. The procedure removes translation, rotation, and positive
scale, then divides by the independent x and y unit lengths.

For finite inputs this is the inverse of @racket[axes-coordinates->point] up to
ordinary numeric precision. A nonzero rotation normally introduces inexact
trigonometric results.
}

@; visuals-reference-r1 example: axes-2
Equal display lengths and numeric spans give one world unit per coordinate unit.

@examples[#:eval reference-eval
  (define grid
    (axes #:id 'grid
          #:x-range (axis-range -3 3 1) #:x-length 6
          #:y-range (axis-range -2 2 1) #:y-length 4))
  (define point (axes-coordinates->point grid 2 1))
  (eval:check (list (vec2-x point) (vec2-y point)) '(2 1))
]

@(close-eval reference-eval)
