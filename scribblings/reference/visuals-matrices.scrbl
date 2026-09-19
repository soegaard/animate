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
@title[#:tag "ref-visuals-matrices"]{Matrices, Tables, and Vector Diagrams}


@declare-exporting[animate/main]


Use @racket[matrix] or @racket[table] for rows of Visual entries. Their
path helpers name cells without requiring a constructed matrix or table.
Number planes and vector diagrams are also ordinary group trees; their
stable child paths identify the components to animate.

See also @secref["ref-visuals-protocols"], @secref["ref-visuals-axes"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section{Matrices and Tables}

@racket[matrix] and @racket[table] return ordinary immutable
@racket[group-visual?] values. Their rows and cells are regular nested groups,
not a separate rendering or animation object. Existing path-addressed operations
therefore work directly: @racket[(indicate (matrix-entry-path 'A 1 2))],
@racket[move-to], @racket[follow-anchor], and @racket[transform-from-copy] need no
matrix/table variants.

Both constructors take a nonempty rectangular list of nonempty rows. Each entry
must be an affine Visual. The constructor re-bases every entry at its cell
centre, preserving identity, rotation, scale, opacity, style, and children but
intentionally replacing its supplied reference position. Width and height can
be one shared measure, one explicit per-axis list, or an @racket['auto]
construction-time measurement. The result is still an ordinary immutable group
with no renderer dependency after construction.

@defproc[(matrix
          [rows (listof (listof (and/c visual? affine-visual?)))]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:entry-width entry-width
                          (or/c 'auto (and/c finite-real? positive?)
                                (listof (and/c finite-real? positive?))) 1]
          [#:entry-height entry-height
                           (or/c 'auto (and/c finite-real? positive?)
                                 (listof (and/c finite-real? positive?))) 1]
          [#:entry-padding entry-padding (and/c finite-real? (>=/c 0)) 1/5]
          [#:column-gap column-gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:row-gap row-gap (and/c finite-real? (>=/c 0)) 1/4]
          [#:brackets? brackets? boolean? #t]
          [#:bracket-width bracket-width (and/c finite-real? positive?) 1/5]
          [#:bracket-gap bracket-gap (and/c finite-real? (>=/c 0)) 1/10]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:typography typography (or/c false/c typography-theme?) #f])
         group-visual?]{

Creates an immutable matrix grid. Rows are named @racket['row-1],
@racket['row-2], and so on; a row's cells are named @racket['col-1],
@racket['col-2], and so on. Thus a matrix named @racket['A] exposes its second
entry in the first row at @racket['(A row-1 col-2)]. Equal @racket['col-1]
names in different rows are permitted because their complete paths differ.

When @racket[brackets?] is true, the matrix has ordinary open path children
named @racket['left-bracket] and @racket['right-bracket]. They use square
brackets, @racket[stroke], and @racket[stroke-width].

For either entry dimension, a positive scalar supplies one shared cell extent;
a list supplies one extent per column or row; and @racket['auto] measures each
entry with the active default Pict renderer and selects the largest visible-box
extent in that column or row. @racket[entry-padding] is added on both sides of
each auto-sized extent. This is a snapshot: later text/formula changes do not
reflow a constructed matrix.

When entries include semantic text, pass @racket[#:typography] to choose the
snapshot used for @racket['auto] measurement. Changing a project's typography
later changes that text's rendering, but does not resize an already constructed
matrix.
}

@defproc[(matrix-row-id [row exact-positive-integer?]) symbol?]{

Returns the local row identity, such as @racket['row-2].
}

@defproc[(matrix-column-id [column exact-positive-integer?]) symbol?]{

Returns the local column identity, such as @racket['col-2].
}

@defproc[(matrix-row-path [matrix-id symbol?] [row exact-positive-integer?])
         visual-path?]{

Returns the row's stable nested path, such as @racket['(A row-2)].
}

@defproc[(matrix-entry-path [matrix-id symbol?]
                            [row exact-positive-integer?]
                            [column exact-positive-integer?])
         visual-path?]{

Returns the cell group's stable nested path, such as @racket['(A row-2 col-1)].
It does not require a matrix value at construction time, which makes it useful
in independently declared animation requests.
}

@; visuals-reference-r1 example: matrices-1
Paths can be prepared without constructing or measuring a matrix.

@examples[#:eval reference-eval
  (eval:check (matrix-row-path 'A 2) '(A row-2))
  (eval:check (matrix-entry-path 'A 2 1) '(A row-2 col-1))
]


@defproc[(matrix-bracket-path [matrix-id symbol?]
                              [side (or/c 'left 'right)])
         visual-path?]{

Returns the path for the selected square-bracket child.
}

@defproc[(table
          [rows (listof (listof (and/c visual? affine-visual?)))]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:cell-width cell-width
                         (or/c 'auto (and/c finite-real? positive?)
                               (listof (and/c finite-real? positive?))) 1]
          [#:cell-height cell-height
                          (or/c 'auto (and/c finite-real? positive?)
                                (listof (and/c finite-real? positive?))) 3/4]
          [#:cell-padding cell-padding (and/c finite-real? (>=/c 0)) 1/5]
          [#:column-gap column-gap (and/c finite-real? (>=/c 0)) 0]
          [#:row-gap row-gap (and/c finite-real? (>=/c 0)) 0]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:typography typography (or/c false/c typography-theme?) #f])
         group-visual?]{

Creates an immutable grid table. Its row/cell names use the same
@racket['row-N]/@racket['col-N] convention as @racket[matrix]. Shared grid
boundaries are ordinary child paths named @racket['grid-column-0],
@racket['grid-column-1], and so on, followed by @racket['grid-row-0],
@racket['grid-row-1], and so on. Each boundary is drawn once, avoiding doubled
cell-border strokes.

The cell-size arguments follow the same scalar/list/@racket['auto] policy as
@racket[matrix]. Auto measurement adds @racket[cell-padding] on all sides and
does not remeasure after construction. Pass @racket[#:typography] when
automatic cell sizing measures semantic text.
}

@defproc[(table-row-id [row exact-positive-integer?]) symbol?]{

Returns the table's local @racket['row-N] identity.
}

@defproc[(table-column-id [column exact-positive-integer?]) symbol?]{

Returns the table's local @racket['col-N] identity.
}

@defproc[(table-row-path [table-id symbol?] [row exact-positive-integer?])
         visual-path?]{

Returns the row's stable table path.
}

@defproc[(table-cell-path [table-id symbol?]
                          [row exact-positive-integer?]
                          [column exact-positive-integer?])
         visual-path?]{

Returns the cell group's stable table path, such as
@racket['(results row-2 col-3)].
}

@section[#:tag "linear-algebra-diagrams"]{Linear-Algebra Diagrams}

Linear-algebra diagram constructors create small, conventional diagrams
without a mutable diagram class. Each constructor below returns an ordinary immutable
Visual or @racket[group-visual?]. Its children retain their normal nested paths,
so existing scene operations work directly. In particular,
@racket[apply-matrix] can map one complete top-level diagram coherently.

@defproc[(number-plane
          [#:id id symbol?]
          [#:x-range x-range axis-range? (axis-range -4 4 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:x-length x-length (and/c finite-real? positive?) 8]
          [#:y-length y-length (and/c finite-real? positive?) 6]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:grid? grid? boolean? #t]
          [#:labels? labels? boolean? #f]
          [#:grid-stroke grid-stroke any/c "lightsteelblue"]
          [#:grid-stroke-width grid-stroke-width
                               (and/c finite-real? (>=/c 0)) 1]
          [#:axes-stroke axes-stroke any/c "navy"]
          [#:axes-stroke-width axes-stroke-width
                               (and/c finite-real? (>=/c 0)) 2]
          [#:label-font-size label-font-size
                              (and/c finite-real? positive?) 1/4]
          [#:label-color label-color any/c "navy"])
         group-visual?]{

Creates a conventional Cartesian number plane. The returned group has an
@racket['axes] child and, when requested, @racket['grid] and @racket['labels]
children. The grid uses the plane's ranges and display lengths; its geometry is
therefore in the same coordinate system as the axes. Numeric labels are absent
by default, because dense labels are often inappropriate in an animation.

The stable direct-child paths are produced by
@racket[number-plane-grid-path], @racket[number-plane-axes-path], and
@racket[number-plane-labels-path]. When @racket[#:grid?] or @racket[#:labels?]
is false, its corresponding path intentionally does not resolve.
}

@defproc[(number-plane-grid-path [plane-id symbol?]) visual-path?]{
Returns @racket[(list plane-id 'grid)].
}

@defproc[(number-plane-axes-path [plane-id symbol?]) visual-path?]{
Returns @racket[(list plane-id 'axes)].
}

@defproc[(number-plane-labels-path [plane-id symbol?]) visual-path?]{
Returns @racket[(list plane-id 'labels)].
}

@defproc[(vector-arrow [endpoint vec2?]
                       [#:start start vec2? origin]
                       [#:id id symbol?]
                       [#:stroke stroke any/c "darkorchid"]
                       [#:stroke-width stroke-width
                                        (and/c finite-real? (>=/c 0)) 3]
                       [#:tip-length tip-length
                                      (and/c finite-real? positive?) 3/10]
                       [#:tip-width tip-width
                                     (and/c finite-real? positive?) 1/4])
         arrow-visual?]{

Creates an ordinary arrow from @racket[start] to @racket[endpoint]. The name is
deliberately @racket[vector-arrow], not @racket[vector], so requiring
@racketmodname[animate] does not shadow Racket's built-in vector constructor.
}

@defproc[(vector-coordinates [arrow arrow-visual?]) vec2?]{
Returns the arrow's endpoint minus its start point, in the arrow's containing
coordinate system.
}

@defproc[(vector-label [arrow arrow-visual?]
                       [#:id id symbol?]
                       [#:text text (or/c false/c string?) #f]
                       [#:offset offset vec2? (vec2 1/5 1/5)]
                       [#:font-size font-size
                                     (and/c finite-real? positive?) 1/4]
                       [#:color color any/c "darkorchid"])
         text-visual?]{

Creates a static text label beside @racket[arrow]'s endpoint. Without
@racket[#:text], its content is the vector's coordinate pair. This is a
construction-time snapshot: if the arrow itself is separately animated, rebuild
the label through @racket[derived-visual] when it needs to follow the arrow.
}

@defproc[(basis-vectors
          [#:id id symbol?]
          [#:origin origin vec2? origin]
          [#:e1 e1 vec2? (vec2 1 0)]
          [#:e2 e2 vec2? (vec2 0 1)]
          [#:e1-color e1-color any/c "crimson"]
          [#:e2-color e2-color any/c "forestgreen"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3])
         group-visual?]{

Creates a group with conventional @racket['e1] and @racket['e2] arrow children.
The @racket[e1] and @racket[e2] arguments are endpoints, not displacement
vectors: their common start is @racket[origin].
}

@defproc[(linear-transformation-diagram
          [#:id id symbol?]
          [#:x-range x-range axis-range? (axis-range -4 4 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:vector-end vector-end vec2? (vec2 3 2)]
          [#:unit-square? unit-square? boolean? #t]
          [#:grid? grid? boolean? #t])
         group-visual?]{

Creates the standard matrix-action diagram. Its stable children are
@racket['plane], @racket['basis], @racket['vector], and, unless disabled,
@racket['unit-square]. The first two have their own paths such as
@racket['(diagram plane grid)] and @racket['(diagram basis e1)].

For example, this keeps all geometric parts together while a title remains
fixed outside the mapped group:

@racketblock[
(define diagram
  (linear-transformation-diagram #:id 'diagram
                                 #:vector-end (vec2 3 2)))

(scene-play
 (scene-add (make-scene) diagram)
 (apply-matrix 'diagram
               (linear2 1 1
                        0 1))
 #:duration 3)
]
}

@(close-eval reference-eval)
