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
@title[#:tag "ref-visuals-calculus"]{Graph Helpers and Traced Paths}


@declare-exporting[animate/main]


These helpers construct axes-aware graph annotations and areas from
numeric procedures. Tangents are numerical approximations, not symbolic
derivatives. @racket[traced-path] is driven by an explicit phase value and
reconstructs its sampled history without depending on previously rendered frames.

See also @secref["ref-visuals-plots"], @secref["ref-visuals-ode"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "coordinate-calculus-helpers"]{Coordinate and Calculus Helpers}

Coordinate and calculus helpers construct static, axes-aware teaching
diagrams. They evaluate numeric procedures during construction and return
ordinary immutable Visuals or points. For an animated construction, place one
of these calls inside @racket[derived-visual] and rebuild it from the sampled
parameter value.

@defproc[(graph-point [axes axes-visual?]
                      [function (procedure-arity-includes/c 1)]
                      [x finite-real?])
         vec2?]{

Evaluates @racket[function] at numeric @racket[x] and converts the resulting
coordinate through @racket[axes-coordinates->point]. The result is in the
axes' containing world coordinate system.
}

@; visuals-reference-r1 example: calculus-1
The result is a point, not a rendered marker.

@examples[#:eval reference-eval
  (define sample
    (graph-point (axes #:id 'coordinates) (lambda (x) (* x x)) 1))
  (eval:check (vec2? sample) #t)
]


@defproc[(graph-label [axes axes-visual?]
                      [function (procedure-arity-includes/c 1)]
                      [x finite-real?]
                      [label string?]
                      [#:id id symbol?]
                      [#:offset offset vec2? (vec2 1/5 1/5)]
                      [#:font-size font-size finite-real? 1/4]
                      [#:color color any/c "black"])
         text-visual?]{

Creates plain text at @racket[(graph-point axes function x)] plus the
world-space @racket[offset].
}

@defproc[(vertical-line-to-graph [axes axes-visual?]
                                 [function (procedure-arity-includes/c 1)]
                                 [x finite-real?]
                                 [#:id id symbol?]
                                 [#:baseline baseline finite-real? 0]
                                 [#:opacity opacity opacity? 1]
                                 [#:stroke stroke any/c "gray"]
                                 [#:stroke-width stroke-width
                                                 (and/c finite-real? (>=/c 0))
                                                 2])
         path-visual?]{

Creates the axes-aware vertical projection from @tt{(x, baseline)} to
@tt{(x, function(x))}. On a logarithmic y axis, the default baseline is the
minimum visible y value rather than zero.
}

@defproc[(horizontal-line-to-graph [axes axes-visual?]
                                   [function (procedure-arity-includes/c 1)]
                                   [x finite-real?]
                                   [#:id id symbol?]
                                   [#:baseline baseline finite-real? 0]
                                   [#:opacity opacity opacity? 1]
                                   [#:stroke stroke any/c "gray"]
                                   [#:stroke-width stroke-width
                                                   (and/c finite-real? (>=/c 0))
                                                   2])
         path-visual?]{

Creates the horizontal projection from @tt{(baseline, function(x))} to the
graph point. On a logarithmic x axis, the default baseline is the minimum
visible x value.
}

@defproc[(tangent-line [axes axes-visual?]
                       [function (procedure-arity-includes/c 1)]
                       [x finite-real?]
                       [#:id id symbol?]
                       [#:dx dx (and/c finite-real? (>/c 0)) 1/100]
                       [#:length length (and/c finite-real? (>/c 0)) 2]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "crimson"]
                       [#:stroke-width stroke-width
                                       (and/c finite-real? (>=/c 0))
                                       3])
         path-visual?]{

Estimates a tangent with the symmetric numeric difference at @racket[x]. The
visible segment has world-space @racket[length] and is centred on the graph
point. It is a numeric approximation, not symbolic differentiation.
}

@defproc[(secant-line [axes axes-visual?]
                      [function (procedure-arity-includes/c 1)]
                      [x finite-real?]
                      [dx (and/c finite-real? (not/c zero?))]
                      [#:id id symbol?]
                      [#:opacity opacity opacity? 1]
                      [#:stroke stroke any/c "darkorange"]
                      [#:stroke-width stroke-width
                                      (and/c finite-real? (>=/c 0))
                                      3])
         path-visual?]{

Connects the graph points at @racket[x] and @racket[(+ x dx)].
}

@defproc[(secant-slope-group [axes axes-visual?]
                             [function (procedure-arity-includes/c 1)]
                             [x finite-real?]
                             [dx (and/c finite-real? (not/c zero?))]
                             [#:id id symbol?]
                             [#:opacity opacity opacity? 1]
                             [#:secant-stroke secant-stroke any/c "darkorange"]
                             [#:guide-stroke guide-stroke any/c "gray"]
                             [#:stroke-width stroke-width
                                             (and/c finite-real? (>=/c 0))
                                             3]
                             [#:marker-radius marker-radius
                                              (and/c finite-real? (>/c 0))
                                              1/10])
         group-visual?]{

Builds a secant, endpoint markers, dashed @italic{Δx}/@italic{Δy} legs, and
labels. Its stable children are named from @racket[id]: @tt{id-secant},
@tt{id-delta-x}, @tt{id-delta-y}, @tt{id-first-point},
@tt{id-second-point}, and the two corresponding label names.
}

@defproc[(area-under-graph [axes axes-visual?]
                           [function (procedure-arity-includes/c 1)]
                           [#:id id symbol?]
                           [#:x-min x-min (or/c finite-real? false/c) #f]
                           [#:x-max x-max (or/c finite-real? false/c) #f]
                           [#:baseline baseline finite-real? 0]
                           [#:sample-count sample-count
                                            (and/c exact-integer? (>=/c 2))
                                            101]
                           [#:opacity opacity opacity? 2/5]
                           [#:fill fill any/c "cornflowerblue"]
                           [#:stroke stroke any/c #f]
                           [#:stroke-width stroke-width
                                           (and/c finite-real? (>=/c 0))
                                           0])
         path-visual?]{

Samples one finite function and closes the result to @racket[baseline]. The
result copies the current axes transform and uses one closed path subpath.
}

@defproc[(area-between-curves [axes axes-visual?]
                              [first-function (procedure-arity-includes/c 1)]
                              [second-function (procedure-arity-includes/c 1)]
                              [#:id id symbol?]
                              [#:x-min x-min (or/c finite-real? false/c) #f]
                              [#:x-max x-max (or/c finite-real? false/c) #f]
                              [#:sample-count sample-count
                                               (and/c exact-integer? (>=/c 2))
                                               101]
                              [#:opacity opacity opacity? 2/5]
                              [#:fill fill any/c "mediumpurple"]
                              [#:stroke stroke any/c #f]
                              [#:stroke-width stroke-width
                                              (and/c finite-real? (>=/c 0))
                                              0])
         path-visual?]{

Samples two finite functions over one domain and returns their closed filled
band in axes-local geometry.
}

@defproc[(riemann-rectangles [axes axes-visual?]
                              [function (procedure-arity-includes/c 1)]
                              [#:id id symbol?]
                              [#:x-min x-min (or/c finite-real? false/c) #f]
                              [#:x-max x-max (or/c finite-real? false/c) #f]
                              [#:count count exact-positive-integer? 8]
                              [#:baseline baseline finite-real? 0]
                              [#:opacity opacity opacity? 2/5]
                              [#:fill fill any/c "seagreen"]
                              [#:stroke stroke any/c "darkgreen"]
                              [#:stroke-width stroke-width
                                              (and/c finite-real? (>=/c 0))
                                              1])
         path-visual?]{

Creates one closed midpoint rectangle per display-space interval. On a
logarithmic x axis the rectangles are evenly spaced in log display coordinates,
not by raw numeric width.
}

@section{Deterministic Traced Paths}

@defproc[(traced-path
          [phase (or/c symbol? scene-parameter?)]
          [position (-> derived-context? finite-real? vec2?)]
          [#:id id symbol?]
          [#:start-time start-time finite-real? 0]
          [#:sample-count sample-count (and/c exact-integer? (>=/c 2)) 121]
          [#:trail-length trail-length (or/c false/c (and/c finite-real? (>=/c 0))) #f]
          [#:dissipate? dissipate? boolean? #f]
          [#:minimum-opacity minimum-opacity opacity? 0]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "crimson"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3])
         derived-visual?]{

Creates a locus from an explicit scalar scene value. At every sampled frame,
Animate calls @racket[position] at deterministically spaced times from
@racket[start-time] to the current value of @racket[phase]. Therefore a frame
at time @math{t} is independent of previously rendered frames; this is unlike a
mutable frame-history trail. The procedure receives the same read-only derived
context as other derived Visuals and must return a @racket[vec2] for every
sampled time.

With @racket[trail-length], the interval instead begins at the larger of
@racket[start-time] and current phase minus that length. With
@racket[dissipate?], the resolved trace is an ordinary group of consecutive
path segments whose opacity rises from @racket[minimum-opacity] to
@racket[opacity]; otherwise it is one ordinary path Visual. No automatic
tracking of arbitrary Visual motion or adaptive/discontinuity sampling is
attempted.
}

@(close-eval reference-eval)
