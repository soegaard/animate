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
@title[#:tag "ref-visuals-protocols"]{Visual Protocols and Groups}


@declare-exporting[animate/main]


Use the basic protocol for identity and reference position. The optional
protocols describe the updates a Visual supports; @racket[group] supplies ordered
composition rather than another leaf renderer. Positions are expressed in the
containing coordinate system, so a child's position is local to its group.

See also @secref["ref-visuals-shapes"], @secref["ref-visuals-relations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section{The Basic Visual Protocol}

@defproc[(visual-path? [value any/c]) boolean?]{

Returns @racket[#t] for a nonempty list of symbol identities used to address a
nested built-in group child, such as @racket['(scatter marker)]. The first
symbol identifies a top-level Visual and each remaining symbol names one child.
}

@defproc[(visual-target-path [target (or/c visual? symbol? visual-path?)])
         visual-path?]{

Converts a top-level Visual or symbol to its one-element path, and returns an
existing nested path unchanged.
}

@; visuals-reference-r1 example: protocols-1
A symbol becomes a one-element path; an existing nested path is retained.

@examples[#:eval reference-eval
  (eval:check (visual-target-path 'marker) '(marker))
  (eval:check (visual-target-path '(scatter marker)) '(scatter marker))
]


@defthing[#:kind "generic interface" gen:visual any/c]{

The generic interface for semantic Visual values. A structure type implements
this interface with @racket[#:methods] in its @racket[struct] definition.
It must implement @racket[visual-id], @racket[visual-position], and
@racket[visual-with-position].
}

@defproc[(visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements @racket[gen:visual].
}

@defproc[(visual-id [visual visual?]) symbol?]{

Returns the stable identity of @racket[visual]. Scene lookup and animation
targeting use this symbol.

A custom Visual implementation must always return a symbol. Immutable update
methods must preserve the symbol.
}

@defproc[(visual-position [visual visual?]) vec2?]{

Returns the reference position of @racket[visual] in its containing coordinate
system. A top-level Visual uses world coordinates. A child of a group uses
coordinates local to that group. For the built-in affine Visuals, the result is
the translation component of the affine transform.
}

@defproc[(visual-with-position [visual visual?]
                               [position vec2?])
         visual?]{

Returns a new Visual with @racket[position] as its reference position in the
same containing coordinate system. The result must preserve identity. Built-in
Visuals also preserve geometry, style, rotation, scale, opacity, and child
order when applicable.
}

@; visuals-reference-r1 example: protocols-2
Moving a model value preserves its identity without changing the original.

@examples[#:eval reference-eval
  (define dot (circle #:id 'dot))
  (define shifted-dot (visual-with-position dot (vec2 2 1)))
  (eval:check (visual-id shifted-dot) 'dot)
  (eval:check (visual-position dot) origin)
]


A minimal position-only Visual can be defined as follows:

@racketblock[
(struct marker (id position)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (marker-id value))
   (define (visual-position value)
     (marker-position value))
   (define (visual-with-position value position)
     (struct-copy marker value [position position]))])
]

Such a Visual can use @racket[move-to], but it cannot use rotation or scale
animations.

@section{Whole-Visual Affine Maps}

@defproc[(affine-map [content visual?] [map affine2?]) affine-map-visual?]{

Wraps an affine Visual in a general affine map while preserving its stable
identity. The Pict adapter applies @racket[map]'s complete linear component to
the semantic subtree; normal scene placement uses its mapped reference point.
This makes a group shear or reflect as one coherent diagram.

The wrapper is itself an @racket[affine-visual?]. It retains a canonical local
copy of the subtree plus its full local-to-parent map, which lets ordinary group
composition preserve the map and lets descendants remain addressable. This is
the semantic bridge used by nested @racket[apply-affine] requests.
}

@defproc[(affine-map-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a semantic affine-map wrapper.
}

@defproc[(affine-map-visual-content [visual affine-map-visual?]) visual?]{

Returns the canonical local semantic content of @racket[visual]. Its ordinary
decomposed transform is neutral; @racket[affine-map-visual-map] contains the
complete local-to-parent placement.
}

@defproc[(affine-map-visual-map [visual affine-map-visual?]) affine2?]{

Returns the current outer general affine map.
}

@section{The Affine-Visual Protocol}

@defthing[#:kind "generic interface" gen:affine-visual any/c]{

The optional generic interface for Visuals that support complete affine
transforms. A structure type implementing this interface must provide
@racket[visual-transform] and @racket[visual-with-transform]. It normally also
implements @racket[gen:visual].
}

@defproc[(affine-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:affine-visual].
}

@defproc[(visual-transform [visual affine-visual?]) affine-transform?]{

Returns the complete affine transform of @racket[visual]. Its translation must
agree with @racket[visual-position]. Custom implementations must return an
@racket[affine-transform?] value.
}

@defproc[(visual-with-transform [visual affine-visual?]
                                [transform affine-transform?])
         affine-visual?]{

Returns a new affine Visual with @racket[transform] installed. A correct
implementation preserves the Visual's identity, geometry, style, child order,
and opacity when those fields apply. The result's @racket[visual-position],
@racket[visual-rotation], and @racket[visual-scale] results must agree with the
installed transform.
}

@defproc[(visual-rotation [visual affine-visual?]) finite-real?]{

Returns the counter-clockwise rotation of @racket[visual] in radians.
}

@defproc[(visual-scale [visual affine-visual?]) vec2?]{

Returns the positive x and y scale factors of @racket[visual].
}

@defproc[(visual-with-rotation [visual affine-visual?]
                               [rotation finite-real?])
         affine-visual?]{

Returns a new affine Visual with @racket[rotation] installed. Position, scale,
geometry, style, and opacity are preserved.
}

@defproc[(visual-with-scale [visual affine-visual?]
                            [scale scale-factor?])
         affine-visual?]{

Returns a new affine Visual with @racket[scale] installed. Position, rotation,
geometry, style, child order, and opacity are preserved.

A built-in group or formula assembly accepts only a uniform scale, so its x
and y components must be equal. Other built-in affine Visuals, including arrows
and axes, accept non-uniform scale.
}

@section{The Opacity-Visual Protocol}

@defproc[(opacity? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real number in the closed
interval from @racket[0] through @racket[1]. Exact and inexact values are
accepted. Negative values, values greater than one, infinities, NaN values, and
non-real values are rejected.
}

@defthing[#:kind "generic interface" gen:opacity-visual any/c]{

The optional generic interface for Visuals that support global opacity. A
structure type implementing this interface must provide @racket[visual-opacity]
and @racket[visual-with-opacity]. It normally also implements
@racket[gen:visual].

Opacity is semantic model data. Renderers should draw the Visual normally. The
Pict adapter applies global opacity after it selects and runs a renderer.
}

@defproc[(opacity-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:opacity-visual]. Implementing this protocol does not require
implementing @racket[gen:affine-visual].
}

@defproc[(visual-opacity [visual opacity-visual?]) opacity?]{

Returns the global opacity of @racket[visual]. A custom implementation must
return a value accepted by @racket[opacity?]. Animation and rendering adapters
validate this result at their boundaries.
}

@defproc[(visual-with-opacity [visual opacity-visual?]
                              [opacity opacity?])
         opacity-visual?]{

Returns a new opacity Visual with @racket[opacity] installed. A correct
implementation preserves Visual identity, reference position, geometry, affine
transform, style, child order when applicable, and every other semantic field.
It must return the requested opacity exactly.

The built-in circle, rectangle, path, arrow, axes, plain-text, formula,
formula-assembly, and group Visuals implement this protocol.
}

A position-only custom Visual can implement opacity as follows:

@racketblock[
(struct marker (id position opacity)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (marker-id value))
   (define (visual-position value)
     (marker-position value))
   (define (visual-with-position value position)
     (struct-copy marker value [position position]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity value)
     (marker-opacity value))
   (define (visual-with-opacity value opacity)
     (struct-copy marker value [opacity opacity]))])
]

@section{The Stroke-Width-Visual Protocol}

@defproc[(stroke-width? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a nonnegative finite real number.
Exact and inexact values are accepted, including zero. Negative values,
infinities, NaN values, and non-real values are rejected. This semantic domain is
renderer-independent: alternate renderers may support widths outside the narrower
range accepted by the default Pict backend.
}

@defthing[#:kind "generic interface" gen:stroke-width-visual any/c]{

The optional generic interface for Visuals with one semantic cosmetic stroke
width. A structure type implementing this interface must provide
@racket[visual-stroke-width] and @racket[visual-with-stroke-width]. It normally
also implements @racket[gen:visual].

The protocol is renderer-independent model data. Built-in renderers read the
stored widths of the Visual types they support; third-party renderers decide how
to interpret the width exposed by their own Visual implementations.
}

@defproc[(stroke-width-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:stroke-width-visual]. Implementing this protocol does not require
implementing @racket[gen:affine-visual] or @racket[gen:opacity-visual].
}

@defproc[(visual-stroke-width [visual stroke-width-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the cosmetic stroke width of @racket[visual]. A custom implementation
must return a value accepted by @racket[stroke-width?]. Animation compilation
validates this result before constructing a stroke-width transition.
}

@defproc[(visual-with-stroke-width
          [visual stroke-width-visual?]
          [stroke-width (and/c finite-real? (>=/c 0))])
         stroke-width-visual?]{

Returns a new stroke-width Visual with @racket[stroke-width] installed. A
correct implementation preserves Visual identity and every semantic field other
than stroke width, returns a Visual that still implements the protocol, and
installs the requested width exactly, including exact/inexact numeric
representation.

The built-in circle, rectangle, path, arrow, axes, number-line, and point-marker
Visuals implement this protocol. Coordinate plots and filled areas that are
themselves path Visuals participate without a separate plot-animation mechanism.
A @racket[scatter-plot] result is instead a top-level group; its nested
point-marker children are not independent scene-state animation targets, so the
scatter group does not implement this protocol. A callout's
@racket[callout-visual-connector-width] is likewise separate frame-space connector
style and is not controlled by @racket[stroke-width-to].
}

A position-only custom Visual can opt in independently of affine transforms and
opacity:

@racketblock[
(struct width-marker (id position stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id value)
     (width-marker-id value))
   (define (visual-position value)
     (width-marker-position value))
   (define (visual-with-position value position)
     (struct-copy width-marker value [position position]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width value)
     (width-marker-stroke-width value))
   (define (visual-with-stroke-width value stroke-width)
     (struct-copy width-marker value [stroke-width stroke-width]))])
]

@section{Fill-Color and Stroke-Color Visual Protocols}

@defthing[#:kind "generic interface" gen:fill-color-visual any/c]{

The optional interface for Visuals with a replaceable fill-color slot. A
structure type implementing it provides @racket[visual-fill-color] and
@racket[visual-with-fill-color]. A current slot value may be @racket[#f] to mean
no fill, but fill-paint interpolation requires the current value to
satisfy @racket[paint?].
}

@defproc[(fill-color-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:fill-color-visual].
}

@defproc[(visual-fill-color [visual fill-color-visual?]) any/c]{

Returns the Visual's fill style slot. Built-ins normally return a textual color,
an @racket[rgba-color], a gradient or pattern paint, or @racket[#f]. Animation
compilation accepts a source for @racket[fill-color-to] only when this result
satisfies @racket[paint?].
}

@defproc[(visual-with-fill-color [visual fill-color-visual?]
                                 [color paint?])
         fill-color-visual?]{

Returns a Visual with @racket[color] installed as its fill paint. Correct custom
implementations preserve Visual identity and all other semantic fields and
install the requested value exactly. For @racket[rgba-color] endpoints, exactness
includes the exact/inexact representation of every channel.
}

@defthing[#:kind "generic interface" gen:stroke-color-visual any/c]{

The corresponding optional interface for a replaceable stroke-color slot. It
provides @racket[visual-stroke-color] and @racket[visual-with-stroke-color]. A
current @racket[#f] stroke means no stroke and is not a color
interpolation source.
}

@defproc[(stroke-color-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] implements
@racket[gen:stroke-color-visual].
}

@defproc[(visual-stroke-color [visual stroke-color-visual?]) any/c]{

Returns the Visual's stroke style slot. @racket[stroke-color-to] requires the
current result to satisfy @racket[color-spec?].
}

@defproc[(visual-with-stroke-color [visual stroke-color-visual?]
                                   [color color-spec?])
         stroke-color-visual?]{

Returns a Visual with @racket[color] installed as its stroke color while
preserving identity and every unrelated semantic field. The requested style must
be installed exactly, including exact/inexact channel representation for
@racket[rgba-color] values.
}

Circles, rectangles, paths, and point markers implement both protocols. Arrows,
axes, and number lines implement the stroke-color protocol. A @racket[scatter-plot]
result is a group whose nested marker children are not independent scene-state
targets, so the group itself implements neither color protocol. Callout
@racket[callout-visual-connector-stroke] is separate frame-space connector style
and is not controlled by @racket[stroke-color-to]. The protocols are independent
of affine transforms, opacity, and stroke width, so third-party Visuals may opt
into either one separately.

@section{Group Visuals}

A group is a semantic composite. Its children are stored as ordinary Visual
values, not as Picts. The child list is significant back-to-front order. Child
positions are local to the group anchor.

All children must implement both @racket[gen:visual] and
@racket[gen:affine-visual]. Circles, rectangles, paths, function graphs,
parametric curves, data plots, arrows, axes, plain text, formulas, and groups all
satisfy this requirement. A child may itself be a group. Direct siblings must
have distinct identities, and a group identity may not occur anywhere below that
group. The same child identity may be reused in separate nested branches; its
complete Visual path identifies it unambiguously. A custom affine Visual is
treated as one leaf because there is no public protocol for inspecting children
hidden inside it.

@defproc[(group
          [children (listof (and/c visual? affine-visual?))]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         group-visual?]{

Creates a semantic group with @racket[children] in significant back-to-front
order. An empty list creates a valid empty group.

The @racket[center] value places the group anchor in its containing coordinate
system. At the top level this is a world-space point. In a parent group it is a
local point. Each child's existing reference position is interpreted in the
group's local coordinates.

The group @racket[scale] may be a positive finite scalar or a positive
@racket[vec2], but its normalized x and y components must be equal. This
uniform-scale restriction lets parent transforms compose exactly with rotated
children without introducing shear. The group may be rotated by any finite
angle.

The group @racket[opacity] is applied to the complete composed result. Child
opacity is applied first, so opacity is inherited multiplicatively through
nested groups.

The constructor rejects a non-affine child, a nonsymbol child identity, a
repeated identity anywhere in the built-in group tree, or a descendant whose
identity equals @racket[id]. For a custom affine child, its reported position
must agree with the translation in its reported affine transform.

Nested children are addressed by nonempty paths such as @racket['(parent child)]
for scene-state lookup and compatible animation requests. Their identity remains
local to the containing group, so a bare child symbol is not a top-level scene
identity.
}

@defproc[(group-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in group Visual.
}

@defproc[(group-visual-children [group group-visual?])
         (listof (and/c visual? affine-visual?))]{

Returns the group's children in significant back-to-front order. The returned
Visuals use coordinates local to the group. The list is immutable model data.
}

@; visuals-reference-r1 example: protocols-3
Child order is available directly from the semantic group.

@examples[#:eval reference-eval
  (define pair
    (group (list (circle #:id 'left) (rectangle #:id 'right))
           #:id 'pair))
  (eval:check (map visual-id (group-visual-children pair)) '(left right))
]


@defproc[(group-visual-with-children
          [group group-visual?]
          [children (listof (and/c visual? affine-visual?))])
         group-visual?]{

Returns a new group with @racket[children] as its significant back-to-front
child list. Identity, group transform, and opacity are preserved. The same
child and identity validation as @racket[group] is performed. The original
group is unchanged.
}

@(close-eval reference-eval)
