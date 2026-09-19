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
@title[#:tag "ref-visuals-images"]{Bitmap and SVG Visuals}


@declare-exporting[animate/main]


Choose @racket[image] for a bitmap, @racket[svg-image] for a static SVG
rendered by the SVG backend, or @racket[svg->visual] when individual supported
SVG elements must become addressable scene children. The first two defer file
reading until rendering; semantic SVG import reads the file during construction.

See also @secref["ref-visuals-protocols"], @secref["ref-visuals-shapes"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section{Bitmap Images}

@defproc[(image [source path-string?]
                [#:id id symbol?]
                [#:center center vec2? origin]
                [#:rotation rotation finite-real? 0]
                [#:scale scale scale-factor? 1]
                [#:opacity opacity opacity? 1]
                [#:width width (and/c finite-real? positive?)]
                [#:height height (and/c finite-real? positive?)])
         image-visual?]{

Creates an immutable bitmap-image Visual. @racket[source] is copied as a path
string but is not opened during construction, scene sampling, or timeline
compilation. @racket[width] and @racket[height] specify the unscaled local
world dimensions, independently of the bitmap's source-pixel dimensions.

The built-in renderer loads the source lazily, scales it to the requested world
size at the current camera scale, then applies the normal Visual scale and
rotation. A missing or unreadable source therefore raises a renderer-time error.
Its renderer-local bitmap cache is bounded and does not affect scene semantics.
Image Visuals implement affine and opacity protocols, so standard movement,
scaling, rotation, fading, grouping, layout, camera placement, and frame
rendering work without a special timeline request.
}

@defproc[(image-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in bitmap image Visual.
}

@defproc[(image-visual-source [visual image-visual?]) immutable-string?]{

Returns the copied renderer-resolved source pathname.
}

@defproc[(image-visual-width [visual image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world width.
}

@; visuals-reference-r1 example: images-1
A bitmap model can be inspected before its source is read.

@examples[#:eval reference-eval
  (define photo
    (image "diagram.png" #:id 'photo #:width 2 #:height 1))
  (eval:check (image-visual-width photo) 2)
]


@defproc[(image-visual-height [visual image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world height.
}

@section{Full-Fidelity SVG Images}

@defproc[(svg-image [source path-string?]
                    [#:id id symbol?]
                    [#:center center vec2? origin]
                    [#:rotation rotation finite-real? 0]
                    [#:scale scale scale-factor? 1]
                    [#:opacity opacity opacity? 1]
                    [#:width width (and/c finite-real? positive?)]
                    [#:height height (and/c finite-real? positive?)])
         svg-image-visual?]{

Creates an immutable full-fidelity static SVG Visual. @racket[source] is not
opened until rendering; the default renderer delegates then to the catalog
@tt{svg/svg} package. That renderer supports substantially more SVG
than the semantic importer, including transforms, gradients, clipping, masks,
text, local image references, CSS, and many static filters.

@racket[width] and @racket[height] specify unscaled local world dimensions,
independently of the SVG document's viewport. The Visual otherwise behaves like
@racket[image]: standard movement, scaling, rotation, opacity animation,
groups, layout, camera placement, and frame rendering work normally. The
renderer has a bounded local source-Pict cache. Use @racket[svg->visual] rather
than this constructor when individual SVG elements must be directly addressed
or animated.
}

@defproc[(svg-image-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in full-fidelity SVG Visual.
}

@defproc[(svg-image-visual-source [visual svg-image-visual?]) immutable-string?]{

Returns the copied renderer-resolved SVG source pathname.
}

@defproc[(svg-image-visual-width [visual svg-image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world width.
}

@defproc[(svg-image-visual-height [visual svg-image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world height.
}

@section{Semantic SVG Import}

@defproc[(svg->visual [source path-string?]
                      [#:id id symbol?]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale scale-factor? 1]
                      [#:opacity opacity opacity? 1])
         group-visual?]{

Reads an SVG XML file once and converts supported geometry into an immutable
semantic group. SVG @tt{path}, @tt{line}, @tt{polyline}, @tt{polygon},
@tt{rect}, @tt{circle}, @tt{ellipse}, and nested @tt{g} elements are supported.
The path importer accepts absolute and relative @tt{M}, @tt{L}, @tt{H}, @tt{V},
@tt{C}, @tt{Q}, and @tt{Z} commands; quadratic segments are converted exactly
to cubic semantic segments. Unsupported graphical tags are ignored.

The root takes @racket[id]. An SVG element's nonempty @tt{id} becomes its stable
child identity; missing IDs receive deterministic generated symbols. Nested
@tt{g} elements become nested built-in groups, so imported IDs participate in
@racket[scene-ref], @racket[scene-visual-at], derived-context lookup, and all
nested style and transform requests. The constructor rejects duplicate IDs using
the existing built-in group-tree invariant.

SVG's screen-down y coordinate is converted to the semantic world-up y
coordinate. Unitless @tt{translate(x[, y])} transforms are supported. Other
SVG transforms must be flattened before import. Inherited @tt{fill}, @tt{stroke},
@tt{stroke-width}, and @tt{opacity} attributes (including simple inline
@tt{style} declarations) are preserved. CSS stylesheets, clipping, text, use
elements, arcs, and paint servers are outside this deliberately semantic subset.
}

@(close-eval reference-eval)
