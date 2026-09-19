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
@title[#:tag "ref-visuals-annotations"]{Live Endpoints and Mathematical Annotations}


@declare-exporting[animate/main]


Use live endpoint constructors when geometry must follow sampled values
or other Visuals. Use the static annotation constructors for fixed points.
An edge or corner supplied with @racket[anchor-of] requires renderer-measured
layout; a center reference is a semantic position. These marks express an
author's diagram, not a geometric proof.

See also @secref["ref-visuals-axes"], @secref["ref-visuals-relations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section{Dynamic Endpoint Geometry}

Live endpoint constructors provide deterministic geometry relationships
without mutable updaters. Each endpoint accepted by the procedures below may be a literal
@racket[vec2], a point-valued @racket[scene-parameter?] handle, a top-level
Visual/symbol/nested @racket[visual-path?], or a value made with
@racket[anchor-of]. A plain Visual reference selects its semantic reference
position. Parameter values must be @racket[vec2] at every sampled time.

@defproc[(anchor-of [target (or/c visual? symbol? visual-path?)]
                    [anchor (or/c 'bottom-left 'bottom 'bottom-right
                                  'left 'center 'right
                                  'top-left 'top 'top-right)
                            'center]
                    [#:offset offset vec2? origin])
         any/c]{

Creates one endpoint description for @racket[target]. A centre anchor is the
ordinary semantic point. An edge or corner selects the target's live
renderer-measured box at render time; @racket[offset] is a world-space offset
from that selected point. This result is intended as an endpoint argument to
the live endpoint constructors.
}

@defproc[(line-between [start any/c] [end any/c]
                       [#:id id symbol?]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width stroke-width? 2])
         relation-visual?]{

Creates a finite line segment with independently sampled endpoints.
}

@; visuals-reference-r1 example: annotations-1
Even a literal-endpoint connection is represented by a relation.

@examples[#:eval reference-eval
  (eval:check
   (relation-visual? (line-between origin (vec2 2 0) #:id 'connection))
   #t)
]


@defproc[(segment-between [start any/c] [end any/c]
                          [#:id id symbol?]
                          [#:opacity opacity opacity? 1]
                          [#:stroke stroke any/c "black"]
                          [#:stroke-width stroke-width stroke-width? 2])
         relation-visual?]{

The mathematical finite-segment spelling of @racket[line-between].
}

@defproc[(arrow-between [start any/c] [end any/c]
                        [#:id id symbol?]
                        [#:opacity opacity opacity? 1]
                        [#:stroke stroke any/c "black"]
                        [#:stroke-width stroke-width stroke-width? 2]
                        [#:tip-length tip-length (and/c finite-real? positive?) 3/10]
                        [#:tip-width tip-width (and/c finite-real? positive?) 1/4]
                        [#:start-tip? start-tip? boolean? #f]
                        [#:end-tip? end-tip? boolean? #t])
         relation-visual?]{

Creates an arrow with a shaft and optional tips that follow independently
sampled endpoints.
}

@defproc[(ray-from [start any/c] [through any/c]
                   [#:id id symbol?]
                   [#:length length (and/c finite-real? positive?) 2]
                   [#:opacity opacity opacity? 1]
                   [#:stroke stroke any/c "black"]
                   [#:stroke-width stroke-width stroke-width? 2]
                   [#:tip-length tip-length (and/c finite-real? positive?) 3/10]
                   [#:tip-width tip-width (and/c finite-real? positive?) 1/4]
                   [#:start-tip? start-tip? boolean? #f]
                   [#:end-tip? end-tip? boolean? #t])
         relation-visual?]{

Creates a finite visible ray that begins at @racket[start] and points through
@racket[through]. Its rendered length is fixed by @racket[length], avoiding an
ill-defined infinite renderer object.
}

Every endpoint constructor returns a @racket[relation-visual?]. Literal points,
parameters, and centre references create a @racket['semantic] relation; a
non-centre @racket[anchor-of] creates a @racket['layout] relation, measured
against the current renderer-visible box after normal scene sampling. The
relations retain their identity, support their ordinary outer movement and
opacity animation, and can be inspected before rendering. Endpoint geometry
must still resolve to distinct points at the sampled time.

@section{Mathematical Annotations}

Mathematical annotations are small semantic, path-backed marks for explanatory
diagrams. Selected marks support the same live endpoint protocol as
@racket[line-between]: a literal @racket[vec2], point-valued
@racket[scene-parameter], Visual ID/path (its semantic centre), or
@racket[anchor-of] description. Literal points return the immediate
@racket[path-visual?] or @racket[group-visual?] values. Parameter and
centre-reference inputs create semantic relations; an edge/corner anchor creates
a layout relation. Both are deterministic from the sampled state. The layout
phase is restricted to top-level relations, and it uses complete renderer bounds
rather than exact visible outlines.

@defproc[(arc [#:id id symbol?]
              [#:center center vec2? origin]
              [#:radius radius (and/c finite-real? positive?) 1]
              [#:start-angle start-angle finite-real? 0]
              [#:angle angle (and/c finite-real? (not/c zero?)) (/ pi 2)]
              [#:opacity opacity opacity? 1]
              [#:stroke stroke any/c "black"]
              [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates an open circular arc. Positive sweeps travel counter-clockwise; the
absolute sweep must be no greater than one full turn. The implementation splits
the arc into quarter-turn cubic Bézier pieces, retaining exact cardinal
endpoints rather than using a polyline approximation.
}

@defproc[(dashed-path [geometry path-geometry?]
                      [#:id id symbol?]
                      [#:dash-length dash-length (and/c finite-real? positive?) 1/5]
                      [#:gap-length gap-length stroke-width? 1/8]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale scale-factor? 1]
                      [#:opacity opacity opacity? 1]
                      [#:stroke stroke any/c "black"]
                      [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Selects dash intervals by the geometry's total arc length. Curves remain cubic
path fragments; they are not flattened into renderer-specific segments.
}

@defproc[(dashed-line [start vec2?] [end vec2?]
                      [#:id id symbol?]
                      [#:dash-length dash-length (and/c finite-real? positive?) 1/5]
                      [#:gap-length gap-length stroke-width? 1/8]
                      [#:opacity opacity opacity? 1]
                      [#:stroke stroke any/c "black"]
                      [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates a finite dashed line. @racket[start] and @racket[end] must differ.
}

@defproc[(angle-marker [first vec2?] [vertex vec2?] [second vec2?]
                [#:id id symbol?]
                [#:radius radius (and/c finite-real? positive?) 1/3]
                [#:reflex? reflex? boolean? #f]
                [#:opacity opacity opacity? 1]
                [#:stroke stroke any/c "black"]
                [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates an arc mark from the ray @racket[vertex]--@racket[first] to the ray
@racket[vertex]--@racket[second]. By default it selects the signed minor angle;
@racket[reflex?] selects its complementary reflex sweep. Collinear rays are
rejected instead of producing a deceptive zero-angle mark. Its name avoids
shadowing @racket[racket/base]'s numeric @racket[angle] procedure.
}

@defproc[(right-angle [first vec2?] [vertex vec2?] [second vec2?]
                      [#:id id symbol?]
                      [#:size size (and/c finite-real? positive?) 1/3]
                      [#:opacity opacity opacity? 1]
                      [#:stroke stroke any/c "black"]
                      [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates the conventional square-corner mark from two supplied rays. It does not
try to prove that those rays are perpendicular.
}

@defproc[(angle-between [first any/c] [vertex any/c] [second any/c]
                        [#:id id symbol?]
                        [#:radius radius (and/c finite-real? positive?) 1/3]
                        [#:reflex? reflex? boolean? #f]
                        [#:opacity opacity opacity? 1]
                        [#:stroke stroke any/c "black"]
                        [#:stroke-width stroke-width stroke-width? 2])
         visual?]{

Creates @racket[angle-marker] from three live endpoint descriptions. Literal
@racket[vec2] values return the same static path as @racket[angle-marker]. Otherwise,
all three endpoints are sampled together before the angle arc is built. It
still does not infer a mathematical relationship between the rays.
}

@defproc[(right-angle-between [first any/c] [vertex any/c] [second any/c]
                              [#:id id symbol?]
                              [#:size size (and/c finite-real? positive?) 1/3]
                              [#:opacity opacity opacity? 1]
                              [#:stroke stroke any/c "black"]
                              [#:stroke-width stroke-width stroke-width? 2])
         visual?]{

Creates @racket[right-angle] from three live endpoint descriptions. A right
angle remains an author assertion: the implementation follows the two rays but
does not verify they are perpendicular.
}

@defproc[(brace-between [start any/c] [end any/c]
                         [#:id id symbol?]
                         [#:offset offset (and/c finite-real? (not/c zero?)) 1/3]
                         [#:opacity opacity opacity? 1]
                         [#:stroke stroke any/c "black"]
                         [#:stroke-width stroke-width stroke-width? 2])
         visual?]{

Creates a symmetric cubic curly brace. Positive @racket[offset] places it to
the left of start-to-end travel; negative values place it on the other side.
With literal points it is an ordinary path; otherwise its two live endpoints
are sampled together. @racket[brace] is a short spelling with the same
arguments.
}

@defproc[(brace [start any/c] [end any/c]
                [#:id id symbol?]
                [#:offset offset (and/c finite-real? (not/c zero?)) 1/3]
                [#:opacity opacity opacity? 1]
                [#:stroke stroke any/c "black"]
                [#:stroke-width stroke-width stroke-width? 2])
         visual?]{

Short spelling for @racket[brace-between]. It creates the same symmetric cubic
brace with the same placement and styling rules.
}

@defproc[(brace-label [start any/c] [end any/c] [label string?]
                      [#:id id symbol?]
                      [#:offset offset (and/c finite-real? (not/c zero?)) 1/3]
                      [#:gap gap stroke-width? 1/6]
                      [#:font-size font-size (and/c finite-real? positive?) 1/4]
                      [#:color color color-spec? "black"]
                      [#:opacity opacity opacity? 1]
                      [#:stroke stroke any/c "black"]
                      [#:stroke-width stroke-width stroke-width? 2])
         visual?]{

Creates a brace and centered plain-text label. The child identities are
deterministically derived as @racket[id] plus @tt{-brace} and @tt{-label}.
With live endpoints the brace and label are rebuilt together from the same two
sampled points.
}

@defproc[(curved-arrow-between [start any/c] [end any/c]
                               [#:id id symbol?]
                               [#:angle angle finite-real? (/ pi 2)]
                               [#:opacity opacity opacity? 1]
                               [#:stroke stroke any/c "black"]
                               [#:stroke-width stroke-width stroke-width? 2]
                               [#:tip-length tip-length (and/c finite-real? positive?) 3/10]
                               [#:tip-width tip-width (and/c finite-real? positive?) 1/4])
         visual?]{

Creates @racket[curved-arrow] from two live endpoint descriptions. Each
sample rebuilds both the circular shaft and its final-tangent tip, so the arrow
head follows the changing arc. It does not select routes around obstacles or
support arbitrary Bézier/elliptical routes.
}

@defproc[(surrounding-rectangle [target (or/c visual? symbol? visual-path?)]
                                [#:id id symbol?]
                                [#:padding padding stroke-width? 1/8]
                                [#:opacity opacity opacity? 1]
                                [#:fill fill any/c #f]
                                [#:stroke stroke any/c "yellow"]
                                [#:stroke-width stroke-width stroke-width? 3])
         relation-visual?]{

Creates a layout relation around the sampled rendered bounding box of
@racket[target]. Padding is in world coordinates. The relation follows motion,
scale, rotation, and nested/derived target layout, retains its ordinary outer
style and opacity animation, and records its target as a semantic selection
dependency. Its current implementation is square-cornered; @racket[#f] selects
its default transparent fill. Like other layout relations, it must currently
remain top-level and its box includes renderer padding rather than only visible
ink.
}

@(close-eval reference-eval)
