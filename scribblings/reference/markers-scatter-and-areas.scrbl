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


@; recipe-redistribution begin: marker-introduction
@title[#:tag "point-markers-scatter-areas"]{
  Point Markers, Scatter Plots, and Filled Areas}

Point markers, ordered scatter-plot groups, and closed areas represent data
and regions derived from sampled function graphs or ordered data series.
These values remain ordinary immutable Visuals. They use the existing affine,
opacity, group, path, timeline, camera, and renderer protocols.


@; recipe-redistribution end: marker-introduction

@declare-exporting[animate #:use-sources (animate/main)]

@; recipe-redistribution begin: marker-api
@defproc[(point-marker-shape? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is one of:

@racketblock[
'circle
'square
'diamond
'triangle-up
'triangle-down
]

The set is explicit. Other symbols are rejected.
}

@defproc[(point-marker [#:id identifier symbol?]
                       [#:center center vec2? origin]
                       [#:rotation rotation finite-real? 0]
                       [#:scale scale any/c 1]
                       [#:opacity opacity opacity? 1]
                       [#:shape shape point-marker-shape? 'circle]
                       [#:size size positive-real? 1/5]
                       [#:fill fill any/c "royalblue"]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width
                        nonnegative-real? 1])
         point-marker-visual?]{
Constructs one semantic point marker. @racket[size] is a local world-unit
extent before affine scale. It is the circle diameter, square side, diamond
width and height, or triangle width and height. Stroke width is cosmetic and is
not multiplied by semantic scale.

The marker implements the basic Visual, affine-Visual, and opacity-Visual
protocols. It can therefore be moved, rotated, scaled, faded, grouped, and used
with renderer-aware layout.

The constructor rejects a non-symbol identity, non-finite position or rotation,
nonpositive scale or size, opacity outside the closed unit interval, an unknown
shape, and a negative or non-finite stroke width. Fill and stroke values are
passed to the selected rendering backend in the same way as for the existing
circle, rectangle, and path Visuals.
}

@defproc[(point-marker-visual? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a point-marker Visual.}

@defproc[(point-marker-visual-shape [visual point-marker-visual?])
         point-marker-shape?]{
Returns the marker shape.}

@defproc[(point-marker-visual-size [visual point-marker-visual?])
         positive-real?]{
Returns the full local marker extent before affine scale.}

@defproc[(point-marker-visual-fill [visual point-marker-visual?]) any/c]{
Returns the adapter-specific fill style.}

@defproc[(point-marker-visual-stroke [visual point-marker-visual?]) any/c]{
Returns the adapter-specific stroke style.}

@defproc[(point-marker-visual-stroke-width [visual point-marker-visual?])
         nonnegative-real?]{
Returns the cosmetic stroke width.}

The default Pict adapter converts marker shapes to existing semantic circle,
rectangle, or path primitives after explicit renderer selection. A custom
renderer placed before the defaults can override the complete marker. Semantic
opacity is applied once after either custom rendering or fallback conversion.

@defproc[(scatter-plot [axes axes-visual?]
                       [points (listof (or/c vec2? false/c))]
                       [#:id identifier symbol?]
                       [#:clip? clip? boolean? #t]
                       [#:shape shape point-marker-shape? 'circle]
                       [#:size size positive-real? 1/5]
                       [#:opacity opacity opacity? 1]
                       [#:fill fill any/c "royalblue"]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width
                        nonnegative-real? 1])
         group-visual?]{
Constructs an ordered group of point markers from numeric coordinates.
@racket[#f] entries are omitted. When @racket[clip?] is true, points whose
centers lie outside either closed axes range are also omitted. Marker geometry
is not clipped at an axes boundary.

Visible markers preserve input order. Their identities are derived from the
plot identity and original zero-based list index:

@verbatim{plot-id-marker-index}

Indexes are not renumbered when a @racket[#f] value or clipped point is omitted.
The returned group copies the current axes center and rotation. Numeric marker
positions include the current x and y axes scale, while the markers themselves
start upright and keep the requested world-unit size. This is a
construction-time snapshot. Later changes to the axes do not update the
scatter plot.

The @racket[opacity] argument belongs to the complete returned group. Individual
marker children start with opacity one. The returned group can be transformed
or faded through the ordinary timeline requests.

The constructor rejects anything other than a proper list of @racket[vec2]
values and @racket[#f] gaps. It also validates the identity, clipping flag,
shape, positive finite size, opacity, and nonnegative finite stroke width before
creating any marker child.
}

@defproc[(sample-function-area-path
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:baseline baseline finite-real? 0]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count exact-integer? 201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'smooth])
         path-geometry?]{
Samples @racket[function] with the same endpoint, gap, jump, clipping, and
interpolation rules as @racket[sample-function-path]. Every accepted open graph
run becomes one closed subpath. A straight edge is added from the horizontal
baseline to the first graph point, and another from the last graph point back
to the baseline. The implicit closing edge joins the two baseline points.

When clipping is enabled, @racket[baseline] is clamped to the displayed y range.
The graph segments are clipped first, and only the visible accepted runs are
closed. Therefore this operation fills beneath the visible sampled graph path;
it does not reconstruct a region whose complete graph lies outside the display.
Each discontinuous run becomes a separate closed region. Smooth cubic graph
segments remain cubic inside the area.

The baseline must be finite. All other domain, sample-count, callback-result,
exception, clipping, jump, and interpolation errors are the same as for
@racket[sample-function-path]. Sampling stops at the first reported error.
}

@defproc[(function-area
          [axes axes-visual?]
          [function (procedure-arity-includes/c 1)]
          [#:id identifier symbol?]
          [#:baseline baseline finite-real? 0]
          [#:x-min x-min (or/c finite-real? false/c) #f]
          [#:x-max x-max (or/c finite-real? false/c) #f]
          [#:sample-count sample-count exact-integer? 201]
          [#:clip? clip? boolean? #t]
          [#:max-jump max-jump
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'smooth]
          [#:opacity opacity opacity? 1/2]
          [#:fill fill any/c "cornflowerblue"]
          [#:stroke stroke any/c #f]
          [#:stroke-width stroke-width nonnegative-real? 0])
         path-visual?]{
Creates a styled path Visual from @racket[sample-function-area-path]. The
returned Visual copies the current axes translation, rotation, and scale. The
procedure is used only during construction and is not retained. The default
style is a half-opacity fill with no visible outline.

The identity must be a symbol, opacity must be in the closed unit interval, and
stroke width must be a nonnegative finite real. Sampling and baseline errors are
reported by @racket[sample-function-area-path].
}

@defproc[(data-series-area-path
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:baseline baseline finite-real? 0]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear])
         path-geometry?]{
Converts an ordered data series to closed area subpaths. Data order, explicit
@racket[#f] gaps, clipping, maximum-distance breaks, and interpolation follow
@racket[data-series-path]. Each accepted run is closed to the horizontal
baseline using the same rules as a function area.

The baseline must be finite. Point-list, clipping, distance, and interpolation
errors are the same as for @racket[data-series-path].
}

@defproc[(data-area
          [axes axes-visual?]
          [points (listof (or/c vec2? false/c))]
          [#:id identifier symbol?]
          [#:baseline baseline finite-real? 0]
          [#:clip? clip? boolean? #t]
          [#:max-distance max-distance
           (or/c nonnegative-real? false/c) #f]
          [#:interpolation interpolation curve-interpolation? 'linear]
          [#:opacity opacity opacity? 1/2]
          [#:fill fill any/c "lightgreen"]
          [#:stroke stroke any/c #f]
          [#:stroke-width stroke-width nonnegative-real? 0])
         path-visual?]{
Creates a styled path Visual from @racket[data-series-area-path]. The returned
Visual copies the current axes transform and stores no reference to the input
list. It uses the ordinary path renderer and therefore supports opacity,
groups, @racket[create], @racket[uncreate], path morphing, affine animation, and
animated cameras.

The identity, opacity, and stroke width are validated before the path Visual is
created. Geometry-construction errors are reported by
@racket[data-series-area-path].
}
@; recipe-redistribution end: marker-api

For a worked composition, see @secref["cookbook-plot-styling-recipes"].

@seclink["part-reference"]{Reference} · @seclink["visuals"]{Visuals}
