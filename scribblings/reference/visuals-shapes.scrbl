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
@title[#:tag "ref-visuals-shapes"]{Shapes and Path Visuals}


@declare-exporting[animate/main]


Use @racket[circle] and @racket[rectangle] for the two basic shape Visuals,
@racket[make-path-visual] for existing local geometry, and @racket[line] or
@racket[polygon] for points supplied in a containing coordinate system. The
catalogue constructors below reuse ordinary path and group Visuals.

See also @secref["ref-visuals-protocols"], @secref["ref-visuals-annotations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section{Circle Visuals}

@defproc[(circle
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:radius radius (and/c finite-real? positive?) 1]
          [#:fill fill any/c "dodgerblue"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         circle-visual?]{

Creates a semantic circle. The @racket[id] argument is required and must be a
symbol. @racket[center], @racket[rotation], and @racket[scale] form its affine
transform. The center is in the Visual's containing coordinate system: world
coordinates at the top level and group-local coordinates for a child.
@racket[radius] is measured in local world units before scale is applied.

The built-in Pict renderer treats @racket[fill] and @racket[stroke] as color
values and @racket[stroke-width] as a Pict border width. These style values are
stored without adapter-specific validation.

Circle Visuals implement @racket[gen:visual],
@racket[gen:affine-visual], @racket[gen:opacity-visual], and
@racket[gen:stroke-width-visual]. The
@racket[opacity] value multiplies the complete rendered circle after renderer
dispatch.
}

@defproc[(circle-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in circle Visual.
}

@defproc[(circle-visual-radius [circle circle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local radius in world units.
}

@; visuals-reference-r1 example: shapes-1
Inspect local geometry without rendering it.

@examples[#:eval reference-eval
  (define disk (circle #:id 'disk #:radius 3/4))
  (eval:check (circle-visual-radius disk) 3/4)
]


@defproc[(circle-visual-fill [circle circle-visual?]) any/c]{

Returns the stored fill style.
}

@defproc[(circle-visual-stroke [circle circle-visual?]) any/c]{

Returns the stored stroke style.
}

@defproc[(circle-visual-stroke-width [circle circle-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored stroke width.
}

@section{Rectangle Visuals}

@defproc[(rectangle
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:width width (and/c finite-real? positive?) 2]
          [#:height height (and/c finite-real? positive?) 1]
          [#:fill fill any/c "goldenrod"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         rectangle-visual?]{

Creates a semantic rectangle. The untransformed rectangle is centered at its
reference position and is axis-aligned in local coordinates. The
@racket[center] value is in the Visual's containing coordinate system: world
coordinates at the top level and group-local coordinates for a child. Width and
height are measured before scale and rotation are applied.

The @racket[id] argument is required. Style values are stored for an adapter to
interpret. Rectangle Visuals implement the basic, affine, opacity, and
stroke-width Visual protocols. The @racket[opacity] value multiplies the complete rendered
rectangle.
}

@defproc[(rectangle-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in rectangle Visual.
}

@defproc[(rectangle-visual-width [rectangle rectangle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local width in world units.
}

@defproc[(rectangle-visual-height [rectangle rectangle-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local height in world units.
}

@defproc[(rectangle-visual-fill [rectangle rectangle-visual?]) any/c]{

Returns the stored fill style.
}

@defproc[(rectangle-visual-stroke [rectangle rectangle-visual?]) any/c]{

Returns the stored stroke style.
}

@defproc[(rectangle-visual-stroke-width [rectangle rectangle-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored stroke width.
}

@section{Path Visuals}

A path Visual combines local @racket[path-geometry] with identity, affine
placement, fill, stroke, and cosmetic stroke width. Its geometry may contain
line segments, cubic Bézier segments, or both. It implements
@racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual].

The Visual's reference position is the translation component of its affine
transform. Its path points remain local model data. Scale and rotation are
applied around the local origin before the Visual is translated to its
reference position.

@defproc[(make-path-visual
          [path path-geometry?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:fill fill any/c #f]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width
                          (and/c finite-real? (>=/c 0))
                          2])
         path-visual?]{

Creates a semantic path Visual from local @racket[path] geometry. The
@racket[id] argument is required. @racket[center] is the Visual's reference
position in its containing coordinate system. It is a world-space point at the
top level and a group-local point when the Visual is a child. Rotation is
measured counter-clockwise in radians, and scale is applied to local x and y
coordinates before rotation.
@racket[opacity] is global and is applied to the complete rendered path after
renderer dispatch.

The built-in Pict renderer interprets a false @racket[fill] as transparent and
a false @racket[stroke] as no outline. Other style values are passed to the
Racket drawing backend as color values. Stroke width is cosmetic and measured
in output pixels; semantic scale does not multiply it.

Empty path geometry is accepted and produces a transparent one-pixel Pict in
the built-in renderer.
}

@defproc[(path-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in path Visual.
}

@defproc[(path-visual-path [visual path-visual?]) path-geometry?]{

Returns @racket[visual]'s local semantic path geometry. The returned geometry
has not been translated, rotated, scaled, or converted to pixels.
}

@defproc[(path-visual-fill [visual path-visual?]) any/c]{

Returns the stored fill style. The built-in renderer uses it only for closed
subpaths. A false value disables filling.
}

@defproc[(path-visual-stroke [visual path-visual?]) any/c]{

Returns the stored stroke style. A false value disables stroking in the
built-in renderer.
}

@defproc[(path-visual-stroke-width [visual path-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the stored cosmetic stroke width.
}

@defproc[(path-visual-with-path [visual path-visual?]
                                [path path-geometry?])
         path-visual?]{

Returns a new path Visual with its local geometry replaced by @racket[path].
Identity, affine transform, opacity, fill, stroke, and stroke width are
preserved. The original Visual is unchanged.
}

@defproc[(line [start vec2?]
               [end vec2?]
               [#:id id symbol?]
               [#:rotation rotation finite-real? 0]
               [#:scale scale scale-factor? 1]
               [#:opacity opacity opacity? 1]
               [#:stroke stroke any/c "black"]
               [#:stroke-width stroke-width
                               (and/c finite-real? (>=/c 0))
                               2])
         path-visual?]{

Creates an open path Visual between two points in one containing coordinate
system. The points are world-space values when the result is top level and
local values when the result is placed in a group. @racket[start] and
@racket[end] must differ.

The constructor uses the midpoint of the two points as the Visual's reference
position and subtracts that midpoint from both stored path points. The local
line is therefore centered at the origin. Rotation and scale are applied around
that midpoint. The fill style is always @racket[#f]. The optional
@racket[opacity] value is preserved as semantic global opacity.

For example:

@racketblock[
(line (vec2 -2 0)
      (vec2 2 0)
      #:id 'axis
      #:stroke "navy"
      #:stroke-width 3)
]
}

@; visuals-reference-r1 example: shapes-2
The reference position is the midpoint of the supplied endpoints.

@examples[#:eval reference-eval
  (define segment (line (vec2 -2 0) (vec2 4 0) #:id 'segment))
  (eval:check (vec2-x (visual-position segment)) 1)
]


@defproc[(polygon [vertices (listof vec2?)]
                  [#:id id symbol?]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale scale-factor? 1]
                  [#:opacity opacity opacity? 1]
                  [#:fill fill any/c "cornflowerblue"]
                  [#:stroke stroke any/c "black"]
                  [#:stroke-width stroke-width
                                  (and/c finite-real? (>=/c 0))
                                  2])
         path-visual?]{

Creates a closed path Visual through at least three @racket[vertices] in one
containing coordinate system. The vertices are world-space values at the top
level and local values when the result is placed in a group. Vertex order is
significant.

The constructor computes the center of the vertices' axis-aligned bounding box
and uses it as the Visual's reference position. It subtracts that center from
every stored path point, so scale and rotation occur around the bounding-box
center. The constructor does not calculate a polygon centroid.

The closing edge from the last vertex to the first is implicit. Do not repeat
the first vertex merely to close the polygon; repeating it adds a zero-length
segment before the implicit closing edge. The optional @racket[opacity] value is
stored as semantic global opacity.
}

@section{Mathematical Shape Catalogue}

The shape catalogue provides a compact family of path-backed shapes. Except for the two
convenience groups, each constructor returns an ordinary @racket[path-visual?]
with the usual affine placement, opacity, fill, and stroke protocols. They do
not introduce renderer-specific leaf classes; the existing path renderer draws
their line and cubic geometry, including odd-even holes in @racket[annulus].

@defproc[(ellipse [#:id id symbol?]
                  [#:center center vec2? origin]
                  [#:width width (and/c finite-real? positive?) 2]
                  [#:height height (and/c finite-real? positive?) 1]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale scale-factor? 1]
                  [#:opacity opacity opacity? 1]
                  [#:fill fill any/c "cornflowerblue"]
                  [#:stroke stroke any/c "black"]
                  [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates a cubic Bézier ellipse centered at @racket[center]. Width and height
are unscaled world dimensions. Rotation and scale are applied around the centre.
}

@defproc[(annulus [#:id id symbol?]
                  [#:center center vec2? origin]
                  [#:inner-radius inner-radius (and/c finite-real? positive?) 1/2]
                  [#:outer-radius outer-radius (and/c finite-real? positive?) 1]
                  [#:rotation rotation finite-real? 0]
                  [#:scale scale scale-factor? 1]
                  [#:opacity opacity opacity? 1]
                  [#:fill fill any/c "cornflowerblue"]
                  [#:stroke stroke any/c "black"]
                  [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates a closed ring with an odd-even transparent hole. The inner radius must
be strictly smaller than the outer radius. A nonuniform semantic scale can turn
the ring into an elliptical annulus.
}

@defproc[(sector [#:id id symbol?]
                 [#:center center vec2? origin]
                 [#:radius radius (and/c finite-real? positive?) 1]
                 [#:start-angle start-angle finite-real? 0]
                 [#:angle angle finite-real? (/ pi 2)]
                 [#:rotation rotation finite-real? 0]
                 [#:scale scale scale-factor? 1]
                 [#:opacity opacity opacity? 1]
                 [#:fill fill any/c "cornflowerblue"]
                 [#:stroke stroke any/c "black"]
                 [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates the closed radial wedge from @racket[start-angle] through the signed
central @racket[angle]. The sweep must be nonzero and no longer than a complete
turn. A positive sweep is counter-clockwise.
}

@defproc[(regular-polygon [#:id id symbol?]
                          [#:center center vec2? origin]
                          [#:sides sides exact-integer? 5]
                          [#:radius radius (and/c finite-real? positive?) 1]
                          [#:start-angle start-angle finite-real? (/ pi 2)]
                          [#:rotation rotation finite-real? 0]
                          [#:scale scale scale-factor? 1]
                          [#:opacity opacity opacity? 1]
                          [#:fill fill any/c "cornflowerblue"]
                          [#:stroke stroke any/c "black"]
                          [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates an equal-radius polygon with one vertex initially at
@racket[start-angle]. @racket[sides] must be an exact integer at least three.
}

@defproc[(star [#:id id symbol?]
               [#:center center vec2? origin]
               [#:points points exact-integer? 5]
               [#:outer-radius outer-radius (and/c finite-real? positive?) 1]
               [#:inner-radius inner-radius (and/c finite-real? positive?) 1/2]
               [#:start-angle start-angle finite-real? (/ pi 2)]
               [#:rotation rotation finite-real? 0]
               [#:scale scale scale-factor? 1]
               [#:opacity opacity opacity? 1]
               [#:fill fill any/c "gold"]
               [#:stroke stroke any/c "black"]
               [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates an alternating outer/inner regular star boundary. @racket[points] must
be at least two, and the inner radius must be strictly smaller than the outer
radius.
}

@defproc[(rounded-rectangle [#:id id symbol?]
                            [#:center center vec2? origin]
                            [#:width width (and/c finite-real? positive?) 2]
                            [#:height height (and/c finite-real? positive?) 1]
                            [#:corner-radius corner-radius stroke-width? 1/5]
                            [#:rotation rotation finite-real? 0]
                            [#:scale scale scale-factor? 1]
                            [#:opacity opacity opacity? 1]
                            [#:fill fill any/c "cornflowerblue"]
                            [#:stroke stroke any/c "black"]
                            [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates a rectangle with four cubic quarter-circle corners. Corner radius is
nonnegative and may not exceed either half-extent. A zero radius creates the
same outline topology as a sharp rectangle.
}

@defproc[(arc-between-points [start vec2?]
                             [end vec2?]
                             [#:id id symbol?]
                             [#:angle angle finite-real? (/ pi 2)]
                             [#:opacity opacity opacity? 1]
                             [#:stroke stroke any/c "black"]
                             [#:stroke-width stroke-width stroke-width? 2])
         path-visual?]{

Creates the circular arc joining two distinct points with the specified signed
central sweep. Its magnitude must be nonzero and strictly less than one full
turn. Sign selects the side of the chord and traversal direction.
}

@defproc[(curved-arrow [start vec2?]
                       [end vec2?]
                       [#:id id symbol?]
                       [#:angle angle finite-real? (/ pi 2)]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width stroke-width? 2]
                       [#:tip-length tip-length (and/c finite-real? positive?) 3/10]
                       [#:tip-width tip-width (and/c finite-real? positive?) 1/4])
         group-visual?]{

Creates a circular @racket[arc-between-points] with a triangular tip aligned to
its final tangent. The returned group has child identities formed from
@racket[id] plus @tt{-shaft} and @tt{-tip}.
}

@defproc[(double-arrow [start vec2?]
                        [end vec2?]
                        [#:id id symbol?]
                        [#:rotation rotation finite-real? 0]
                        [#:scale scale scale-factor? 1]
                        [#:opacity opacity opacity? 1]
                        [#:stroke stroke any/c "black"]
                        [#:stroke-width stroke-width stroke-width? 2]
                        [#:tip-length tip-length (and/c finite-real? positive?) 3/10]
                        [#:tip-width tip-width (and/c finite-real? positive?) 1/4])
         arrow-visual?]{

Creates the ordinary semantic @racket[arrow] from @racket[start] to
@racket[end] with both @racket[start-tip?] and @racket[end-tip?] enabled.
}

@defproc[(labeled-point [label string?]
                         [#:id id symbol?]
                         [#:center center vec2? origin]
                         [#:radius radius (and/c finite-real? positive?) 1/10]
                         [#:label-offset label-offset vec2? (vec2 1/4 1/4)]
                         [#:font-size font-size (and/c finite-real? positive?) 1/4]
                         [#:font-family font-family any/c 'roman]
                         [#:fill fill any/c "crimson"]
                         [#:stroke stroke any/c "firebrick"]
                         [#:stroke-width stroke-width stroke-width? 2]
                         [#:color color any/c stroke]
                         [#:opacity opacity opacity? 1])
         group-visual?]{

Creates a dot and a plain-text label as one group. Its stable child identities
are @racket[id] plus @tt{-dot} and @tt{-label}; moving or fading the outer group
therefore carries both together. Label placement is the explicit local
@racket[label-offset], not a collision-aware layout operation.
}

@(close-eval reference-eval)
