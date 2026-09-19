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
@title[#:tag "ref-visuals-plots"]{Function, Parametric, and Data Plots}


@declare-exporting[animate/main]


Choose a function graph for @math{y = f(x)}, a parametric curve for an
ordered parameter domain, an implicit curve for a scalar-field contour, or a
data plot for an already ordered point series. Samplers return local path
geometry; styled constructors return ordinary path Visuals. Sampling and the
axes transform are construction-time snapshots unless an API explicitly says
it is derived.

See also @secref["ref-visuals-axes"], @secref["ref-visuals-calculus"], @secref["ref-visuals-ode"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "coordinate-curves"]{Coordinate Curves and Plots}

The procedures in this section convert ordered numeric coordinates to semantic
path geometry. They use the local coordinate system of an @racket[axes] Visual.
They do not store a sampling procedure or a caller-owned point list in the
result.

@subsection{Interpolation Modes}

@defproc[(curve-interpolation? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of these symbols:

@itemlist[
 @item{@racket['linear] connects each accepted pair with a line segment.}
 @item{@racket['smooth] creates cubic Bézier segments that pass through all
       accepted samples in order.}
]

Sampled function and parametric-curve procedures use @racket['smooth] by
default. Ordered data-series procedures use @racket['linear] by default. An
unsupported symbol or another value returns @racket[#f].

Smooth interpolation is applied separately to every accepted run. Suppose one
run contains points @italic{P0} through @italic{Pn}. For a segment from
@italic{Pi} to @italic{Pi+1}, the usual interior control points are:

@centered{@italic{C1} = @italic{Pi} +
          (@italic{Pi+1} - @italic{Pi-1}) / 6}

@centered{@italic{C2} = @italic{Pi+1} +
          (@italic{Pi} - @italic{Pi+2}) / 6}

At an end of a run, the endpoint is repeated for the missing neighboring
point. A run containing exactly two points uses a line-equivalent cubic whose
controls are one third and two thirds of the way along the segment. The result
therefore follows the same traversal order and reaches every accepted sample.

When clipping is enabled, sample pairs are clipped as line segments before
smooth interpolation is calculated. Generated control points are then clamped
to the closed axes rectangle. A cubic Bézier curve lies inside the convex hull
of its endpoints and controls, so the resulting visible curve stays inside the
rectangle. Clamping may reduce smoothness where a run touches a boundary.
}

@subsection[#:tag "sampled-function-graphs"]{Sampled Curves and Fields}

@defproc[(sample-implicit-path [axes axes-visual?]
                               [field (procedure-arity-includes/c 2)]
                               [#:level level finite-real? 0]
                               [#:x-count x-count (and/c exact-integer? (>=/c 2)) 65]
                               [#:y-count y-count (and/c exact-integer? (>=/c 2)) 65])
         path-geometry?]{

Samples a two-argument scalar field with deterministic marching squares and
returns axes-local open contour segments where the field equals @racket[level].
Adjacent cell segments are stitched into deterministic open or closed
subpaths. Non-finite field samples create gaps. The result is immutable path
geometry and does not retain the callback.
}

@defproc[(implicit-curve [axes axes-visual?]
                          [field (procedure-arity-includes/c 2)]
                          [#:id id symbol?]
                          [#:level level finite-real? 0]
                          [#:x-count x-count (and/c exact-integer? (>=/c 2)) 65]
                          [#:y-count y-count (and/c exact-integer? (>=/c 2)) 65]
                          [#:opacity opacity opacity? 1]
                          [#:stroke stroke any/c "darkorange"]
                          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         path-visual?]{

Constructs a styled path Visual from @racket[sample-implicit-path], copying the
current axes transform as a semantic snapshot.
}

@defproc[(vector-field [axes axes-visual?]
                       [field (procedure-arity-includes/c 2)]
                       [#:id id symbol?]
                       [#:x-count x-count (and/c exact-integer? (>=/c 1)) 9]
                       [#:y-count y-count (and/c exact-integer? (>=/c 1)) 7]
                       [#:scale scale finite-real? 1/4]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "seagreen"]
                       [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
                       [#:tip-length tip-length (and/c finite-real? (>/c 0)) 3/20]
                       [#:tip-width tip-width (and/c finite-real? (>/c 0)) 1/8])
         group-visual?]{

Samples @racket[field] over a closed numeric axes grid. The procedure receives
numeric x/y coordinates and must return exactly one @racket[vec2] vector.
Each nonzero result becomes an arrow; zero vectors are omitted. The returned
immutable group has stable child identities and can therefore use nested paths
for lookup and animation. Sampling and axes transforms are captured at
construction time; the group retains no procedure or renderer state.
}

@section[#:tag "ref-visuals-functions"]{Function Graphs}

@defproc[(sample-function-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'smooth])
         path-geometry?]{

Samples @racket[function] at @racket[sample-count] uniformly spaced x values in
increasing order. The closed interval includes both endpoints. When
@racket[x-min] or @racket[x-max] is @racket[#f], the corresponding bound comes
from @racket[(axes-visual-x-range axes)]. The resolved minimum must be less than
the resolved maximum. Their difference must remain a positive finite real.

For a logarithmic x axis, spacing is uniform in the selected base-logarithm
display coordinate instead. Thus a base-ten range from one through one thousand
samples successive decades evenly. Explicit @racket[x-min] and @racket[x-max]
bounds follow the same rule and must be strictly positive on a log axis.

All arguments are checked before @racket[function] is called. When sampling
completes without an error, the function is called exactly once for each sample
x value. Sampling stops at the first invalid result or exception. Each call
must return exactly one value. That value has these meanings:

@itemlist[
 @item{A finite real is one numeric y sample.}
 @item{@racket[#f] is an explicit gap and breaks the current run.}
 @item{Positive infinity, negative infinity, and NaN also create a gap.}
 @item{Any other result raises an exception that reports the x value and the
       returned value.}
]

Returning zero values or more than one value raises an exception that reports
the x value and result count. An exception raised by @racket[function] is not
converted to a gap. It is reported together with the sample x value and the
original exception message. This keeps programming errors separate from
explicit discontinuities.

When @racket[max-jump] is a number, two adjacent finite samples are connected
only when the absolute difference between their numeric y values is no greater
than that number. The threshold is applied before axes scaling and before
clipping. The default @racket[#f] performs no jump rejection. Use an explicit
@racket[#f] result when the location of a discontinuity is known.

When @racket[clip?] is true, every accepted sample pair is clipped to the closed
rectangle described by the axes x and y ranges. Clipping is performed on
segments, so an intersection with a boundary becomes an exact path endpoint
when exact arithmetic permits it. When an inexact coordinate difference would
overflow, clipping temporarily uses the exact represented input values. When
@racket[clip?] is false, finite out-of-range samples remain in the path.
Clipping does not decide whether a segment crossing the rectangle is a true
discontinuity.

The @racket[interpolation] argument controls the path segment kind as described
by @racket[curve-interpolation?]. Linear interpolation stores line segments.
Smooth interpolation stores cubic Bézier segments through each accepted run.
Breaks from non-finite values, explicit @racket[#f] results, maximum-jump
rejection, or clipping keep the runs separate.

When @racket[detect-discontinuities?] is true, two adjacent samples that lie
beyond opposite sides of the visible numeric y interval are treated as the
hidden sides of a vertical asymptote and are not connected. This opt-in rule
prevents clipping from drawing a false segment through the plot window while
preserving the historical default behavior for steep continuous graphs.

The result contains zero or more open subpaths in sampling order. An isolated
finite sample with no accepted adjacent pair does not create a point-only
subpath. Every stored point uses the untransformed local coordinate system of
@racket[axes]. Numeric x is multiplied by @racket[axes-x-unit-length], and
numeric y is multiplied by @racket[axes-y-unit-length]. The axes translation,
rotation, and scale are not applied to the returned geometry.

The sampling grid is deterministic. Exact bounds produce exact rational
intermediate x values when ordinary exact arithmetic permits it. The result
contains only immutable path geometry. Rendering it later does not call
@racket[function] again.
}

@defproc[(function-graph
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'smooth]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[sample-function-path] with the same axes, function, interval,
sample count, clipping, jump, discontinuity detection, and interpolation arguments. It wraps the result
in a built-in path Visual.

The graph copies the current translation, rotation, and scale of @racket[axes].
Its local geometry already uses the axes x and y unit lengths, so the graph and
axes coincide at construction time even when the axes are translated, rotated,
or non-uniformly scaled. This is a snapshot. Updating either immutable Visual
later does not update the other. Put both in a group or apply matching animation
requests when they should continue to move together.

The graph has no fill. The identity, opacity, and stroke width are checked
before the numeric function is called. @racket[stroke] and
@racket[stroke-width] are used by the ordinary path renderer. The result works
with @racket[create], @racket[uncreate], path replacement, movement, rotation,
non-uniform scaling, fading, groups, layout, and custom path renderers. There is
no graph-specific renderer or timeline request.
}

@; visuals-reference-r1 example: plots-1
A constructed function graph is an ordinary path Visual.

@examples[#:eval reference-eval
  (eval:check
   (path-visual?
    (function-graph (axes #:id 'coordinates)
                    (lambda (x) (* x x))
                    #:id 'parabola #:sample-count 9))
   #t)
]


@subsection[#:tag "ref-visuals-plots-lookup-1"]{Adaptive Sampling}

@defproc[(sample-adaptive-function-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:initial-sample-count initial-sample-count
                                   (and/c exact-integer? (>=/c 2))
                                   17]
          [#:max-deviation max-deviation
                            (and/c finite-real? (>=/c 0))
                            1/100]
          [#:max-depth max-depth (and/c exact-integer? (>=/c 0)) 12]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #t]
          [#:excluded-intervals excluded-intervals list? '()]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{

Samples @racket[function] adaptively. The procedure first evaluates a
deterministic, display-uniform grid of @racket[initial-sample-count] points,
then recursively evaluates each interval's display-space midpoint. An interval
is split while its midpoint differs from the chord midpoint by more than
@racket[max-deviation] in untransformed axes-local world units. Refinement stops
after @racket[max-depth] splits per initial interval, so the deviation threshold
is a target rather than a guaranteed global bound.

The x-coordinate rule is the same as @racket[sample-function-path]: linear
axes use arithmetic interpolation and log axes use uniform logarithmic display
interpolation. Callback values follow the same finite-real/@racket[#f]/nonfinite
rules, except that an exact numeric division-by-zero exception is treated as a
gap. Other callback exceptions are reported with their x value.

With @racket[detect-discontinuities?] true, an interval whose adjacent samples
lie beyond opposite visible y boundaries is refined and ultimately broken,
rather than clipped through the axes. @racket[max-jump] adds an independent
numeric y-distance break rule. @racket[excluded-intervals] is a list of either
@racket[(cons minimum maximum)] or @racket[(list minimum maximum)] values; each
finite increasing interval splits the domain and no segment crosses its
interior. Overlapping exclusions are merged deterministically.

The result uses the ordinary clipping and linear/smooth path interpolation
machinery. It contains immutable axes-local geometry and retains neither the
function nor adaptive evaluation cache. No finite initial grid can detect an
oscillation that aliases every one of its samples; raise
@racket[initial-sample-count] for that case.
}

@defproc[(adaptive-function-graph
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:initial-sample-count initial-sample-count
                                   (and/c exact-integer? (>=/c 2))
                                   17]
          [#:max-deviation max-deviation
                            (and/c finite-real? (>=/c 0))
                            1/100]
          [#:max-depth max-depth (and/c exact-integer? (>=/c 0)) 12]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #t]
          [#:excluded-intervals excluded-intervals list? '()]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[sample-adaptive-function-path] and wraps the result in the same
immutable axes-transform snapshot as @racket[function-graph]. The graph is an
ordinary path Visual: it can be created, morphed, faded, moved, or grouped by
the existing animation API.
}

@subsection[#:tag "ref-visuals-plots-lookup-2"]{Derived Function Graphs}

@defproc[(derived-function-graph
          [axes axes-visual?]
          [field (procedure-arity-includes/c 2)]
          [#:id id symbol?]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
                      (or/c false/c
                            (and/c finite-real? (>=/c 0)))
                      #f]
          [#:detect-discontinuities? detect-discontinuities? boolean? #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         derived-visual?]{

Creates a pure derived function graph. @racket[field] receives the sampled
@racket[derived-context?] first and one numeric x coordinate second. It must
return the same one-value result accepted by @racket[function-graph]. The
ordinary graph options have the same meanings as in @racket[function-graph].

For each resolved scene state, the field is sampled anew and produces one
concrete path Visual with the requested identity, style, and axes transform.
This permits an immutable @racket[parameter] or another resolved Visual to drive
a plot without a mutable updater. As with any @racket[derived-visual?], animate
its source values or dependencies rather than applying a direct Visual animation
to the derived graph.
}

@section{Parametric Curves}

@defstruct*[parameter-range ([start finite-real?]
                             [end finite-real?])
  #:transparent]{

Represents one ordered closed parameter domain. The fields have these meanings:

@itemlist[
 @item{@racket[start] is the first parameter passed to a sampling procedure.}
 @item{@racket[end] is the last parameter passed to a sampling procedure.}
]

The values must be distinct finite reals. The computed difference
@racket[(- end start)] must also remain a nonzero finite real. The order is
significant. When @racket[start] is greater than @racket[end], sampling proceeds
in decreasing order.

The structure is immutable and transparent. Its public bindings include
@racket[parameter-range], @racket[parameter-range?], both field accessors, and
@racket[struct:parameter-range].
}

@defproc[(sample-parametric-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:parameter-range domain parameter-range? (parameter-range 0 1)]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'smooth])
         path-geometry?]{

Samples @racket[function] at @racket[sample-count] uniformly spaced parameter
values from @racket[(parameter-range-start domain)] through
@racket[(parameter-range-end domain)]. Both endpoints are included exactly as
stored. Intermediate values follow the same increasing or decreasing order.
Exact endpoints produce exact rational intermediate values when ordinary exact
arithmetic permits it.

All arguments are checked before @racket[function] is called. Each sampling call
must return exactly one value:

@itemlist[
 @item{A @racket[vec2] is one finite numeric coordinate.}
 @item{@racket[#f] is an explicit gap.}
]

Another value, zero values, or multiple values raise an exception that reports
the parameter value. An exception from @racket[function] is reported with the
same parameter and the original exception message. Sampling stops at the first
error.

When @racket[max-distance] is a number, two adjacent coordinates are connected
only when their Euclidean distance in numeric-coordinate units is no greater
than that number. The distance is measured before independent axes scaling.
The default @racket[#f] applies no distance rejection.

Clipping and interpolation follow the common rules described above. The result
contains axes-local open subpaths and does not retain @racket[function] or
@racket[domain]. Empty runs and isolated finite coordinates produce no drawn
segment.
}

@defproc[(parametric-curve
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:parameter-range domain parameter-range? (parameter-range 0 1)]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 2))
                          201]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'smooth]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[sample-parametric-path] with the same sampling arguments and wraps
the result in an ordinary path Visual. Identity, opacity, and stroke width are
checked before the sampling procedure is called.

The returned path has no fill and copies the current axes translation, rotation,
and scale. This is a construction-time snapshot, not a live link. The result
can use every operation available to an ordinary path Visual, including
@racket[create], @racket[uncreate], morphing, affine animation, opacity, groups,
and renderer-aware layout.
}

@section{Ordered Data Plots}

@defproc[(data-series-path
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{

Converts @racket[points] to axes-local path geometry. The input must be a proper
list containing only @racket[vec2] values and @racket[#f]. A @racket[vec2] is
one numeric coordinate. @racket[#f] is an explicit gap.

List order is traversal order. The procedure does not sort by x, infer time
order, remove repeated coordinates, or retain the input list. An empty list, a
one-point list, or a finite coordinate isolated by gaps produces no drawn
segment.

The @racket[max-distance], @racket[clip?], and @racket[interpolation] arguments
have the same meanings as for @racket[sample-parametric-path]. Distance is
Euclidean in numeric-coordinate units. The result contains only immutable path
geometry.
}

@; visuals-reference-r1 example: plots-2
An explicit gap separates two accepted runs.

@examples[#:eval reference-eval
  (define data
    (data-series-path
     (axes #:id 'data-axes)
     (list (vec2 -2 0) (vec2 -1 1) #f (vec2 1 1) (vec2 2 0))))
  (eval:check (length (path-geometry-subpaths data)) 2)
]


@defproc[(data-plot
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:id id symbol?]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
                           (or/c false/c
                                 (and/c finite-real? (>=/c 0)))
                           #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "seagreen"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          3])
         path-visual?]{

Calls @racket[data-series-path] with the same point, clipping, distance, and
interpolation arguments and wraps the result in an ordinary path Visual.
Identity, opacity, and stroke width are checked before the point series is
converted.

The returned path has no fill and copies the axes translation, rotation, and
scale at construction time. It works with ordinary path rendering, creation,
removal, morphing, movement, rotation, non-uniform scaling, fading, groups, and
relative layout.
}

@(close-eval reference-eval)
