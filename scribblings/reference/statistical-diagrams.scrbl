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


@; recipe-redistribution begin: statistical-introduction
@title[#:tag "probability-and-statistical-diagrams"]{
  Probability and Statistical Diagrams}

Small, immutable, addressable diagram groups support common probability and
statistics explanations. These constructors do not analyse data
or add a separate scene protocol: their bars, cells, tree branches, quartile
box, and error-bar elements are ordinary named children that work with existing
paths, colours, transforms, and attention effects.


@; recipe-redistribution end: statistical-introduction

@declare-exporting[animate #:use-sources (animate/main)]

@; recipe-redistribution begin: statistical-api
@defproc[(bar-chart [values (and/c list? pair?)]
                    [#:id identifier symbol?]
                    [#:labels labels (or/c (listof string?) false/c) #f]
                    [#:center center vec2? origin]
                    [#:width width positive-real? 6]
                    [#:height height positive-real? 3]
                    [#:maximum maximum (or/c positive-real? false/c) #f]
                    [#:fill fill any/c "cornflowerblue"]
                    [#:stroke stroke any/c "navy"]
                    [#:stroke-width stroke-width nonnegative-real? 2]
                    [#:value-labels? value-labels? boolean? #t])
         group-visual?]{

Creates a baseline and one upward nonnegative bar per value. Values are scaled
against @racket[maximum], or the largest supplied value (at least one). Labels
and value labels are optional ordinary text children. The path of one bar is
@racket[(bar-chart-bar-path identifier index)], where indexes start at one.
}

@defproc[(histogram [samples (and/c list? pair?)]
                    [#:id identifier symbol?]
                    [#:bins bins exact-positive-integer? 8]
                    [#:range range (or/c pair? false/c) #f]
                    [#:center center vec2? origin]
                    [#:width width positive-real? 6]
                    [#:height height positive-real? 3])
         group-visual?]{

Counts finite numeric samples into equally wide bins, then returns the same
addressable bar-group shape as @racket[bar-chart]. A supplied range is an
increasing pair; samples outside it are omitted and a sample at the upper bound
belongs to the final bin.
}

@defproc[(stacked-bar-chart [rows (and/c list? pair?)]
                            [#:id identifier symbol?]
                            [#:center center vec2? origin]
                            [#:width width positive-real? 6]
                            [#:height height positive-real? 3]
                            [#:maximum maximum (or/c positive-real? false/c) #f]
                            [#:colors colors (and/c list? pair?) any/c]
                            [#:stroke stroke any/c "navy"]
                            [#:stroke-width stroke-width nonnegative-real? 1])
         group-visual?]{

Creates one bar per equal-length nonnegative row and stacks each row's values
from the common baseline. Use @racket[stacked-bar-path] and
@racket[stacked-bar-segment-path] for one bar or segment, with one-based
indexes.
}

@defproc[(sample-space [rows (and/c list? pair?)]
                       [#:id identifier symbol?]
                       [#:center center vec2? origin]
                       [#:width width positive-real? 5]
                       [#:height height positive-real? 3])
         group-visual?]{

Creates equally sized, coloured cells from a nonnegative rectangular matrix.
Each cell displays its supplied weight. Its path is
@racket[(sample-space-cell-path identifier row column)], with one-based row and
column indexes; the geometry remains equal even for unequal weights.
}

@defstruct*[probability-branch ([id symbol?]
                                [label string?]
                                [probability nonnegative-real?]
                                [children (listof probability-branch?)])
  #:transparent]{

Describes one immutable node in a finite probability tree. Branch identities
must be globally unique within one @racket[probability-tree] input.
}

@defproc[(probability-tree [branches (and/c list? pair?)]
                           [#:id identifier symbol?]
                           [#:center center vec2? origin]
                           [#:width width positive-real? 6]
                           [#:level-gap gap positive-real? 1]
                           [#:node-radius radius positive-real? 1/6])
         group-visual?]{

Lays out an explicit finite forest by leaf order. Child edge labels display the
child branch probability. A node can be addressed with
@racket[(probability-tree-node-path identifier branch-id)].
}

@defproc[(box-plot [values (listof finite-real?)]
                   [#:id identifier symbol?]
                   [#:center center vec2? origin]
                   [#:width width positive-real? 5]
                   [#:height height positive-real? 3/4])
         group-visual?]{

Creates whiskers, a quartile box, and a median line from at least two values.
Quartiles use deterministic linear interpolation between sorted observations;
outliers are not inferred or displayed. @racket[box-plot-summary] is the
transparent five-number summary structure used by the constructor.
}

@defstruct*[error-bar-point ([x finite-real?]
                             [y finite-real?]
                             [error nonnegative-real?])
  #:transparent]{

Describes a point with symmetric vertical error.}

@defproc[(error-bars [points (and/c list? pair?)]
                     [#:id identifier symbol?]
                     [#:center center vec2? origin]
                     [#:cap-width cap-width positive-real? 1/5])
         group-visual?]{

Creates addressable vertical stems, end caps, and point markers. The path for a
one-based point index is @racket[(error-bar-path identifier index)].
}

@defproc[(bar-chart-bar-path [identifier symbol?]
                             [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based bar.}

@defproc[(stacked-bar-path [identifier symbol?]
                           [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based stacked bar.}

@defproc[(stacked-bar-segment-path [identifier symbol?]
                                   [bar-index exact-positive-integer?]
                                   [segment-index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based stacked-bar segment.}

@defproc[(sample-space-cell-path [identifier symbol?]
                                 [row exact-positive-integer?]
                                 [column exact-positive-integer?])
         visual-path?]{Returns the path of one one-based sample-space cell.}

@defproc[(probability-tree-node-path [identifier symbol?] [branch-id symbol?])
         visual-path?]{Returns the path of one named probability-tree node.}

@defstruct*[box-plot-summary ([minimum finite-real?]
                               [lower-quartile finite-real?]
                               [median finite-real?]
                               [upper-quartile finite-real?]
                               [maximum finite-real?])
  #:transparent]{
The deterministic five-number summary used by @racket[box-plot].
}

@defproc[(error-bar-path [identifier symbol?]
                         [index exact-positive-integer?])
         visual-path?]{Returns the path of one one-based error-bar group.}

See @filepath{examples/probability-and-statistics.rkt} for one composition that
uses chart, finite-outcome, tree, distribution, and uncertainty views together.
}

@; recipe-redistribution end: statistical-api

@seclink["part-reference"]{Reference} · @seclink["visuals"]{Visuals}
