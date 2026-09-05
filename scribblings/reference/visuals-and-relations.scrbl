#lang scribble/manual
@(require (for-label (except-in racket/base angle string-copy)
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

@section[#:tag "visuals"]{Visuals}

@declare-exporting[animate/main]

@subsection{The Basic Visual Protocol}

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

@subsection{Whole-Visual Affine Maps}

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

@subsection{The Affine-Visual Protocol}

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

@subsection{The Opacity-Visual Protocol}

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

@subsection{The Stroke-Width-Visual Protocol}

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

@subsection{Fill-Color and Stroke-Color Visual Protocols}

@defthing[#:kind "generic interface" gen:fill-color-visual any/c]{

The optional interface for Visuals with a replaceable fill-color slot. A
structure type implementing it provides @racket[visual-fill-color] and
@racket[visual-with-fill-color]. A current slot value may be @racket[#f] to mean
no fill, but SCENE-EC fill-paint interpolation requires the current value to
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
current @racket[#f] stroke means no stroke and is not a SCENE-AT color
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

@subsection{Circle Visuals}

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

@subsection{Rectangle Visuals}

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

@subsection[#:tag "plain-text-visuals"]{Plain, Multiline, and Rich Text Visuals}

A text Visual stores immutable Unicode content, inline style runs, and explicit
font/layout anchors. @racket[plain-text] preserves the original one-line API;
@racket[paragraph] adds explicit lines and renderer-measured wrapping; and
@racket[rich-text] adds styled spans. Every form implements @racket[gen:visual],
@racket[gen:affine-visual], and @racket[gen:opacity-visual]. Its raw structure
constructor and internal transform and opacity fields are not public.

The reference position is an anchor selected on the untransformed text box.
Horizontal alignment chooses its left edge, center, or right edge. Vertical
alignment chooses its top edge, center, font baseline, or bottom edge. For a
paragraph the baseline is the first rendered line's baseline. Scale and
rotation are applied around that anchor.

@defproc[(text-font-family? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of the supported portable font
family symbols:

@racketblock[
'default
'decorative
'roman
'script
'swiss
'modern
'symbol
'system
]

A family is a portable request, not a promise of one particular installed font
face. The drawing backend chooses a suitable platform font.
}

@defproc[(text-font-style? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['normal], @racket['italic], or
@racket['slant]. These are the supported font slant styles.
}

@defproc[(text-font-weight? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['normal], @racket['bold], or
@racket['light].
}

@defproc[(text-horizontal-alignment? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['left], @racket['center], or
@racket['right]. The value identifies the horizontal part of the text box that
is placed at the Visual's reference position.
}

@defproc[(text-vertical-alignment? [value any/c]) boolean?]{

Returns @racket[#t] for @racket['top], @racket['center],
@racket['baseline], or @racket['bottom]. The @racket['baseline] choice places
the font baseline at the Visual's reference position.
}

@defproc[(text-span
          [content string?]
          [#:font-size font-size (or/c false/c (and/c finite-real? positive?)) #f]
          [#:font-face font-face (or/c false/c string?) #f]
          [#:font-family font-family (or/c false/c text-font-family?) #f]
          [#:font-style font-style (or/c false/c text-font-style?) #f]
          [#:font-weight font-weight (or/c false/c text-font-weight?) #f]
          [#:color color any/c #f])
         text-span?]{

Creates one immutable inline rich-text run. A false style keyword inherits the
corresponding outer @racket[rich-text] style. Spans may contain explicit line
breaks. They are text only: a formula, image, or another Visual cannot be an
inline span in this stage.
}

@defproc[(text-span? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in immutable text span.
}

@defproc[(text-span-content [span text-span?]) string?]{

Returns the span's immutable Unicode source text.
}

@defproc[(text-span-font-size [span text-span?])
         (or/c false/c (and/c finite-real? positive?))]{

Returns the optional local font size, or @racket[#f] when it inherits.
}

@defproc[(text-span-font-face [span text-span?]) (or/c false/c string?)]{

Returns the optional preferred face string.
}

@defproc[(text-span-font-family [span text-span?])
         (or/c false/c text-font-family?)]{

Returns the optional portable font family.
}

@defproc[(text-span-font-style [span text-span?])
         (or/c false/c text-font-style?)]{

Returns the optional font slant.
}

@defproc[(text-span-font-weight [span text-span?])
         (or/c false/c text-font-weight?)]{

Returns the optional font weight.
}

@defproc[(text-span-color [span text-span?]) any/c]{

Returns the optional adapter colour, or @racket[#f] when it inherits.
}

@defproc[(plain-text
          [content string?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1/2]
          [#:font-face font-face (or/c string? #f) #f]
          [#:font-family font-family text-font-family? 'default]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         text-visual?]{

Creates a semantic one-line text Visual. The required @racket[id] is its stable
Visual identity. @racket[center] is the selected text anchor in the containing
coordinate system. At the top level it is a world-space point; inside a group
it is local to that group.

@racket[content] may be empty and may contain arbitrary Unicode characters, but
it may not contain a carriage return or newline. The constructor copies the
string into immutable storage. A mutable @racket[font-face] string is copied in
the same way. A false @racket[font-face] asks the backend to select a face from
@racket[font-family]. When both are supplied, the face is preferred and the
family remains the fallback classification.

@racket[font-size] is measured in local world units before the Visual's
@racket[scale] is applied. The default is one half world unit. Non-uniform scale
may stretch the rendered text independently in x and y. Rotation is
counter-clockwise in radians.

@racket[color] is deliberately opaque model data. The built-in Pict renderer
passes it to Pict color handling. A different renderer may interpret it
differently. @racket[opacity] is semantic global opacity and is applied to the
complete rendered line after renderer dispatch.

The alignment arguments determine which point of the original text box is at
@racket[center]. Alignment is resolved before scale and rotation. This makes a
left-baseline label, for example, grow to the right and rotate around the start
of its baseline.
}

@defproc[(paragraph
          [content string?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:font-size font-size (and/c finite-real? positive?) 1/2]
          [#:font-face font-face (or/c string? #f) #f]
          [#:font-family font-family text-font-family? 'default]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center]
          [#:width width (or/c false/c (and/c finite-real? positive?)) #f]
          [#:line-spacing line-spacing (and/c finite-real? positive?) 1]
          [#:line-alignment line-alignment text-horizontal-alignment? 'left])
         text-visual?]{

Creates one ordinary multiline text Visual. Carriage-return, newline, and
CRLF sequences are explicit line breaks. With a false @racket[width], only
those explicit breaks create lines. Otherwise, @racket[width] is a positive
local world-space maximum: at rendering time Animate measures text runs with
the active camera/font backend and wraps at inter-word whitespace. It does not
hyphenate an overlong word.

@racket[line-spacing] multiplies the largest natural line height in the
paragraph. @racket[line-alignment] aligns every resolved line inside the widest
resolved line, while @racket[horizontal-alignment] selects the anchor of that
complete paragraph. The first line supplies a @racket['baseline] anchor.
}

@defproc[(rich-text
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:font-size font-size (and/c finite-real? positive?) 1/2]
          [#:font-face font-face (or/c string? #f) #f]
          [#:font-family font-family text-font-family? 'default]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center]
          [#:width width (or/c false/c (and/c finite-real? positive?)) #f]
          [#:line-spacing line-spacing (and/c finite-real? positive?) 1]
          [#:line-alignment line-alignment text-horizontal-alignment? 'left]
          [piece (or/c string? text-span?)] ...)
         text-visual?]{

Creates a paragraph layout from ordinary strings and @racket[text-span] values.
Strings inherit all outer font properties. A span overrides only its specified
properties. The wrapping, line-spacing, and anchor rules are the same as for
@racket[paragraph]. Adjacent spans are separately shaped Pict runs, so a font
backend cannot kern or ligate across their boundary.
}

@defproc[(text-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in plain, paragraph, or rich
text Visual.
}

@defproc[(text-visual-content [visual text-visual?]) string?]{

Returns the immutable concatenation of the Visual's source text spans. It can
contain explicit line breaks; automatic wrapping does not alter this source.
}

@defproc[(text-visual-spans [visual text-visual?]) (listof text-span?)]{

Returns the significant ordered immutable rich-text spans. A plain-text or
paragraph Visual contains one inheriting span.
}

@defproc[(text-visual-font-size [visual text-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled font size in local world units.
}

@defproc[(text-visual-font-face [visual text-visual?])
         (or/c string? #f)]{

Returns the preferred immutable font-face string, or @racket[#f] when no face
was requested. Font availability and exact substitution are properties of the
rendering environment, not the semantic model.
}

@defproc[(text-visual-font-family [visual text-visual?])
         text-font-family?]{

Returns the portable fallback font-family symbol.
}

@defproc[(text-visual-font-style [visual text-visual?])
         text-font-style?]{

Returns the stored font slant style.
}

@defproc[(text-visual-font-weight [visual text-visual?])
         text-font-weight?]{

Returns the stored font weight.
}

@defproc[(text-visual-color [visual text-visual?]) any/c]{

Returns the stored adapter color value.
}

@defproc[(text-visual-horizontal-alignment [visual text-visual?])
         text-horizontal-alignment?]{

Returns the horizontal anchor alignment.
}

@defproc[(text-visual-vertical-alignment [visual text-visual?])
         text-vertical-alignment?]{

Returns the vertical anchor alignment.
}

@defproc[(text-visual-width [visual text-visual?])
         (or/c false/c (and/c finite-real? positive?))]{

Returns the requested local world-space wrapping width, or @racket[#f] when
only explicit line breaks determine lines.
}

@defproc[(text-visual-line-spacing [visual text-visual?])
         (and/c finite-real? positive?)]{

Returns the multiplicative resolved-line advance.
}

@defproc[(text-visual-line-alignment [visual text-visual?])
         text-horizontal-alignment?]{

Returns the alignment used inside the resolved paragraph width.
}

@defproc[(text-visual-with-content [visual text-visual?]
                                   [content string?])
         text-visual?]{

Returns a new text Visual with @racket[content] installed as one inheriting
immutable span. Identity, affine transform, opacity, font data, colour, and
layout options are preserved. Explicit line breaks are accepted; the original
Visual is unchanged.
}

@defproc[(text-visual-with-spans [visual text-visual?]
                                 [spans (listof text-span?)])
         text-visual?]{

Returns a new text Visual with @racket[spans] installed atomically. Outer font
defaults and all layout/anchor settings are preserved. The content accessor of
the result is the immutable concatenation of the supplied spans.
}

@subsection[#:tag "numeric-displays"]{Numeric Displays}

SCENE-EF provides number-shaped text and numerical transitions without
introducing a mutable value tracker. Static constructors return ordinary
@racket[text-visual?] values. @racket[parameter-display] and
@racket[rolling-number-display] format the current scalar scene parameter
independently at each sampled frame. Both are fixed-structure
@racket[relation-visual?] values with an explicit scalar dependency.

@defproc[(numeric-display-anchor? [value any/c]) boolean?]{

Recognizes @racket['left], @racket['center], @racket['right],
@racket['decimal], and @racket['sign].
}

@defproc[(format-integer [value exact-integer?]
                         [#:grouping? grouping? boolean? #f]
                         [#:show-sign? show-sign? boolean? #f]
                         [#:unit unit string? ""])
         string?]{

Formats an exact integer with an optional leading plus sign, comma grouping,
and trailing literal unit. For example,
@racket[(format-integer -1234567 #:grouping? #t)] returns
@racket["-1,234,567"].
}

@defproc[(format-decimal [value finite-real?]
                         [#:decimal-places decimal-places
                                           exact-nonnegative-integer?
                                           2]
                         [#:grouping? grouping? boolean? #f]
                         [#:show-sign? show-sign? boolean? #f]
                         [#:unit unit string? ""])
         string?]{

Formats a finite real with exactly @racket[decimal-places] fractional digits,
rounding once before the integral and fractional fields are separated. It keeps
trailing zeroes. The procedure raises an exception if multiplying the magnitude
by its requested decimal factor would overflow.
}

@defproc[(unit [symbol string?]
               [#:power power exact-integer? 1])
         numeric-unit?]{

Creates one semantic upright unit factor. @racket[power] must be nonzero.
Negative powers represent denominator factors; for example,
@racket[(unit "s" #:power -2)] formats as @racket["s⁻²"].
}

@defproc[(numeric-unit? [value any/c]) boolean?]{
Recognizes an immutable semantic unit created by @racket[unit] or
@racket[unit-product].
}

@defproc[(unit-product [first numeric-unit?]
                       [rest numeric-unit?] ...)
         numeric-unit?]{

Concatenates unit factors in declared order. This is display data, not a
dimension-calculation system.
}

@defproc[(format-unit [value (or/c string? numeric-unit?)]) string?]{

Returns a literal unit unchanged or turns semantic factors into Unicode upright
text, such as @racket["m·s⁻²"].
}

@defproc[(format-scientific [value finite-real?]
                            [#:significant-figures figures exact-positive-integer? 3]
                            [#:show-sign? show-sign? boolean? #f]
                            [#:unit unit (or/c string? numeric-unit?) ""])
         string?]{

Formats a normalized decimal mantissa and a signed ASCII @tt{e} exponent. It
uses ordinary text rather than typeset exponent geometry so it remains stable
in every supported text renderer.
}

@defproc[(format-significant [value finite-real?]
                             [#:significant-figures figures exact-positive-integer? 3]
                             [#:notation notation (or/c 'auto 'fixed 'scientific) 'auto]
                             [#:grouping? grouping? boolean? #f]
                             [#:show-sign? show-sign? boolean? #f]
                             [#:unit unit (or/c string? numeric-unit?) ""])
         string?]{

Rounds to a requested number of significant figures. @racket['auto] selects
scientific notation for large values and values below @racket[1e-3].
}

@defproc[(format-rational [value finite-real?]
                          [#:max-denominator maximum exact-positive-integer? 1000]
                          [#:mixed? mixed? boolean? #f]
                          [#:show-sign? show-sign? boolean? #f]
                          [#:unit unit (or/c string? numeric-unit?) ""])
         string?]{

Chooses the nearest fraction among positive denominators through
@racket[maximum], then reduces it. This gives legible deterministic output for
inexact animated samples; it is not symbolic rational arithmetic.
}

@defproc[(format-complex [value (or/c finite-real? finite-complex?)]
                         [#:decimal-places decimal-places exact-nonnegative-integer? 2]
                         [#:grouping? grouping? boolean? #f]
                         [#:show-sign? show-sign? boolean? #f]
                         [#:imaginary-unit imaginary-unit string? "i"]
                         [#:unit unit (or/c string? numeric-unit?) ""])
         string?]{

Formats Cartesian components as, for example, @racket["3.00 - 0.50i"].
There is deliberately no polar or symbolic simplification mode.
}

@defproc[(integer [value exact-integer?]
                  [#:id id symbol?]
                  [#:center center vec2? origin]
                  [#:font-size font-size (and/c finite-real? positive?) 1/2]
                  [#:font-family font-family text-font-family? 'default]
                  [#:font-style font-style text-font-style? 'normal]
                  [#:font-weight font-weight text-font-weight? 'normal]
                  [#:color color any/c "black"]
                  [#:horizontal-alignment horizontal-alignment
                                           text-horizontal-alignment? 'center]
                  [#:vertical-alignment vertical-alignment
                                         text-vertical-alignment? 'center]
                  [#:grouping? grouping? boolean? #f]
                  [#:show-sign? show-sign? boolean? #f]
                  [#:unit unit string? ""])
         text-visual?]{

Creates an ordinary one-line integer display. Its placement and text styling
have the same meaning as for @racket[plain-text].
}

@defproc[(decimal-number [value finite-real?]
                         [#:id id symbol?]
                         [#:center center vec2? origin]
                         [#:font-size font-size (and/c finite-real? positive?) 1/2]
                         [#:font-family font-family text-font-family? 'default]
                         [#:font-style font-style text-font-style? 'normal]
                         [#:font-weight font-weight text-font-weight? 'normal]
                         [#:color color any/c "black"]
                         [#:horizontal-alignment horizontal-alignment
                                                  text-horizontal-alignment? 'center]
                         [#:vertical-alignment vertical-alignment
                                                text-vertical-alignment? 'center]
                         [#:decimal-places decimal-places
                                           exact-nonnegative-integer? 2]
                         [#:grouping? grouping? boolean? #f]
                         [#:show-sign? show-sign? boolean? #f]
                         [#:unit unit string? ""])
         text-visual?]{

Creates a fixed-place decimal display. In contrast to the generic
@racket[numeric-label], an exact integer still receives the requested decimal
point and trailing zeroes here.
}

@defproc[(scientific-number [value finite-real?] [#:id id symbol?]
                            [#:center center vec2? origin]
                            [#:significant-figures figures exact-positive-integer? 3]
                            [#:unit unit (or/c string? numeric-unit?) ""]
                            [#:font-size font-size (and/c finite-real? positive?) 1/2]
                            [#:font-family font-family text-font-family? 'default]
                            [#:color color any/c "black"])
         text-visual?]{

Creates a static label using @racket[format-scientific].
}

@defproc[(significant-number [value finite-real?] [#:id id symbol?]
                             [#:center center vec2? origin]
                             [#:significant-figures figures exact-positive-integer? 3]
                             [#:notation notation (or/c 'auto 'fixed 'scientific) 'auto]
                             [#:unit unit (or/c string? numeric-unit?) ""]
                             [#:font-size font-size (and/c finite-real? positive?) 1/2]
                             [#:font-family font-family text-font-family? 'default]
                             [#:color color any/c "black"])
         text-visual?]{

Creates a static label using @racket[format-significant].
}

@defproc[(rational-number [value finite-real?] [#:id id symbol?]
                          [#:center center vec2? origin]
                          [#:max-denominator maximum exact-positive-integer? 1000]
                          [#:mixed? mixed? boolean? #f]
                          [#:unit unit (or/c string? numeric-unit?) ""]
                          [#:font-size font-size (and/c finite-real? positive?) 1/2]
                          [#:font-family font-family text-font-family? 'default]
                          [#:color color any/c "black"])
         text-visual?]{

Creates a static label using @racket[format-rational].
}

@defproc[(complex-number [value (or/c finite-real? finite-complex?)] [#:id id symbol?]
                         [#:center center vec2? origin]
                         [#:decimal-places decimal-places exact-nonnegative-integer? 2]
                         [#:imaginary-unit imaginary-unit string? "i"]
                         [#:unit unit (or/c string? numeric-unit?) ""]
                         [#:font-size font-size (and/c finite-real? positive?) 1/2]
                         [#:font-family font-family text-font-family? 'default]
                         [#:color color any/c "black"])
         text-visual?]{

Creates a static Cartesian-complex label using @racket[format-complex].
}

@defproc[(numeric-label [value (or/c finite-real? finite-complex?)]
                        [#:id id symbol?]
                        [#:center center vec2? origin]
                        [#:kind kind (or/c 'auto 'integer 'decimal 'scientific
                                           'significant 'rational 'complex) 'auto]
                        [#:decimal-places decimal-places
                                          exact-nonnegative-integer? 2]
                        [#:significant-figures figures exact-positive-integer? 3]
                        [#:notation notation (or/c 'auto 'fixed 'scientific) 'auto]
                        [#:max-denominator maximum exact-positive-integer? 1000]
                        [#:mixed? mixed? boolean? #f]
                        [#:grouping? grouping? boolean? #f]
                        [#:show-sign? show-sign? boolean? #f]
                        [#:imaginary-unit imaginary-unit string? "i"]
                        [#:unit unit (or/c string? numeric-unit?) ""]
                        [#:font-size font-size (and/c finite-real? positive?) 1/2]
                        [#:font-family font-family text-font-family? 'default]
                        [#:font-style font-style text-font-style? 'normal]
                        [#:font-weight font-weight text-font-weight? 'normal]
                        [#:color color any/c "black"]
                        [#:horizontal-alignment horizontal-alignment
                                                 text-horizontal-alignment? 'center]
                        [#:vertical-alignment vertical-alignment
                                               text-vertical-alignment? 'center])
         text-visual?]{

At @racket['auto], creates integer output for an exact integer, fixed decimal
output for another finite real, and Cartesian output for a finite complex value.
The explicit @racket[#:kind] choices select every SCENE-EF formatter.
}

@defproc[(parameter-display
          [source (or/c symbol? scene-parameter?)]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:kind kind (or/c 'integer 'decimal 'scientific 'significant
                             'rational 'complex) 'decimal]
          [#:decimal-places decimal-places exact-nonnegative-integer? 2]
          [#:significant-figures figures exact-positive-integer? 3]
          [#:notation notation (or/c 'auto 'fixed 'scientific) 'auto]
          [#:max-denominator maximum exact-positive-integer? 1000]
          [#:mixed? mixed? boolean? #f]
          [#:grouping? grouping? boolean? #f]
          [#:show-sign? show-sign? boolean? #f]
          [#:imaginary-unit imaginary-unit string? "i"]
          [#:unit unit (or/c string? numeric-unit?) ""]
          [#:anchor anchor numeric-display-anchor? 'right]
          [#:font-size font-size (and/c finite-real? positive?) 1/2]
          [#:font-family font-family text-font-family? 'default]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment? 'center])
         relation-visual?]{

Reads @racket[source] from each sampled scene state and formats its finite real
or Cartesian-complex value. A @racket['decimal] display has exactly its
requested decimal places; an @racket['integer] display rounds a finite real to
the nearest integer. Scientific, significant, rational, and complex kinds use
the correspondingly named formatter. The source must be installed with
@racket[scene-set-value] before the relation is resolved. Its dependency and
built-in serializable specification are inspectable with
@racket[relation-visual-dependencies] and
@racket[relation-visual-cacheability]. Because the display has fixed child
structure, its decimal @racket['whole] and @racket['fraction] paths remain
addressable as its value changes.

The @racket[#:anchor] choice fixes one stable reference as the text width
changes. @racket['left], @racket['center], and @racket['right] are the normal
text anchors. @racket['sign] forces a visible sign and anchors its left edge.
@racket['decimal] creates a small resolved group containing local
@racket['whole] and @racket['fraction] children on opposite sides of the fixed
decimal point. They are separate text runs, so this first release does not
attempt kerning across that join.
}

@defproc[(rolling-number-display
          [source (or/c symbol? scene-parameter?)]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:integer-digits integer-digits exact-positive-integer? 3]
          [#:decimal-places decimal-places exact-nonnegative-integer? 0]
          [#:show-sign? show-sign? boolean? #f]
          [#:unit unit (or/c string? numeric-unit?) ""]
          [#:anchor anchor numeric-display-anchor? 'right]
          [#:font-size font-size (and/c finite-real? positive?) 1/2]
          [#:font-family font-family text-font-family? 'modern]
          [#:font-style font-style text-font-style? 'normal]
          [#:font-weight font-weight text-font-weight? 'normal]
          [#:color color any/c "black"]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment? 'center])
         derived-visual?]{

Creates a fixed-slot odometer-style display. The source must produce a
nonnegative finite real smaller than @racket[(expt 10 integer-digits)]. Each
slot clips its current and next glyphs and rolls in the last tenth of its digit
interval before a carry. The result is calculated directly from the sampled
number, including at a frame rendered out of order; it stores no bitmap or prior
numeric state. Digit advances use a nominal monospaced width, so a font with
tabular figures gives the best alignment.
}

@subsection{Matrices and Tables}

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
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
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
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         group-visual?]{

Creates an immutable grid table. Its row/cell names use the same
@racket['row-N]/@racket['col-N] convention as @racket[matrix]. Shared grid
boundaries are ordinary child paths named @racket['grid-column-0],
@racket['grid-column-1], and so on, followed by @racket['grid-row-0],
@racket['grid-row-1], and so on. Each boundary is drawn once, avoiding doubled
cell-border strokes.

The cell-size arguments follow the same scalar/list/@racket['auto] policy as
@racket[matrix]. Auto measurement adds @racket[cell-padding] on all sides and
does not remeasure after construction.
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

@subsection{Deterministic Traced Paths}

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
attempted in this stage.
}

@subsection[#:tag "formula-visuals"]{LaTeX Formula Visuals}

A formula Visual stores an immutable LaTeX mathematical snippet and explicit
typesetting data. It implements @racket[gen:visual],
@racket[gen:affine-visual], and @racket[gen:opacity-visual]. Its raw structure
constructor and internal transform and opacity fields are not public.

Formula model values are backend-independent. They do not contain Picts, PDF
pages, Poppler values, process handles, or cached TeX results. The built-in
adapter calls @racketmodname[latex-pict] only when a nonempty formula is
rendered.

@defproc[(formula-mode? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of the supported formula modes:

@racketblock[
'inline
'display
'display-environment
]

The @racket['inline] mode uses ordinary inline mathematics. The
@racket['display] mode uses display-style mathematics in a tight inline box.
The @racket['display-environment] mode uses a real LaTeX display environment,
which can include wider horizontal margins.
}

@defproc[(latex-option? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a symbol or string accepted as one
ordered LaTeX option. Mutable strings satisfy this predicate; constructors copy
them into immutable model storage.
}

@defproc[(latex-formula
          [source string?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:preview-options preview-options
                             (listof latex-option?)
                             '()]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         formula-visual?]{

Creates a semantic mathematical formula Visual. The required @racket[id] is
its stable Visual identity. @racket[center] is the selected formula anchor in
the containing coordinate system. At the top level it is a world-space point;
inside a group it is local to that group.

@racket[source] is a LaTeX mathematical snippet without surrounding dollar
signs, @litchar{\\( ... \\)}, or @litchar{\\[ ... \\]} delimiters. The selected
@racket[mode] supplies those delimiters. Formula source may contain carriage
returns and newlines. It may also be empty. The constructor copies it into an
immutable string.

The mode-to-typesetter mapping is:

@tabular[
 #:style 'boxed
 (list
  (list @bold{Mode} @bold{latex-pict operation})
  (list @racket['inline] @tt{tex-math})
  (list @racket['display] @tt{tex-display-math})
  (list @racket['display-environment] @tt{tex-real-display-math}))]

The @racket[font-size] value is measured in local world units before semantic
@racket[scale] is applied. The adapter asks @racketmodname[latex-pict] to typeset
at its natural scale and then maps the selected document base of 10pt, 11pt, or
12pt to the requested world-unit size. When no standard size option is present,
10pt is assumed. Supplying more than one distinct standard size option is an
error. Other document-class options and preamble commands may still change the
formula's visible metrics.

The complete visible height and width depend on the formula content. The
constructor does not automatically separate two independent formula Visuals,
so their rendered boxes can overlap when their anchors are placed too close
together. Use @racket[visual-layout-box], @racket[visual-place-above],
@racket[visual-place-below], or @racket[arrange-visuals-vertically] when spacing
must follow the actual rendered boxes.

@racket[preamble] is inserted into the generated LaTeX document. The
@racket[document-class-options] and @racket[preview-options] lists are passed in
stored order. Their strings and @racket[preamble] are copied into immutable
storage. Option order is significant because a LaTeX document class or package
may interpret options in order. The adapter passes these values and an extra
typesetter scale of one explicitly, so process-wide @racketmodname[latex-pict]
parameters do not silently change a formula Visual.

The alignment arguments select the left, center, or right horizontal point and
the top, center, baseline, or bottom vertical point of the untransformed
typeset Pict. That point is placed at @racket[center]. Scale and rotation are
then applied around the anchor.

Named parts in a @racket[formula-assembly] can be styled with
@racket[formula-style], @racket[formula-color], or
@racket[formula-color-map]. This is an assembly-level semantic operation: a
bare @racket[latex-formula] has no part namespace. The Pict and tagged-SVG
adapters apply the selected colour at their own rendering boundaries rather
than relying on a generic outer recolouring operation.

Rendering a nonempty formula requires the @racketmodname[latex-pict] package,
a working @tt{pdflatex}, Poppler, the requested document class, and every
package named by the preamble. Model construction, scene sampling, and empty
formula rendering do not run TeX. Exact output depends on those external tools
and their installed versions. Formula source and preamble are trusted input;
this library does not sandbox the TeX process.
}

@subsubsection{Making @tt{latex-pict} Available}

Use the same Racket installation for this library and for @tt{latex-pict}. For
example, to install the catalog package with Racket 9.3.0.2 on macOS:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  latex-pict
}

For a local checkout, link the checkout with that same @tt{raco} executable:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/raco" pkg install \
  --auto \
  --link \
  "/Users/soegaard/Dropbox/GitHub/latex-pict"
}

A one-command alternative is to add the checkout root to @tt{PLTCOLLECTS}:

@verbatim{
PLTCOLLECTS="/Users/soegaard/Dropbox/GitHub/latex-pict:" \
  "/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/formula-visuals.rkt \
  frames/formula-visuals \
  formula-visuals.mp4
}

The trailing colon is significant. It keeps Racket's ordinary collection paths
after the added checkout. A package linked with one Racket installation is not
automatically visible to another installation, so use matching @tt{racket} and
@tt{raco} executables.

@defproc[(formula-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in LaTeX formula Visual.
}

@defproc[(formula-visual-source [visual formula-visual?]) string?]{

Returns the immutable LaTeX source string without surrounding mathematical
delimiters.
}

@defproc[(formula-visual-mode [visual formula-visual?]) formula-mode?]{

Returns the stored formula display mode.
}

@defproc[(formula-visual-font-size [visual formula-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled semantic formula font size in local world units.
}

@defproc[(formula-visual-preamble [visual formula-visual?]) string?]{

Returns the immutable additional LaTeX preamble string.
}

@defproc[(formula-visual-document-class-options
          [visual formula-visual?])
         (listof latex-option?)]{

Returns the ordered document-class options. String options are immutable.
Ordering is significant.
}

@defproc[(formula-visual-preview-options [visual formula-visual?])
         (listof latex-option?)]{

Returns the ordered options passed to the LaTeX Preview package by
@racketmodname[latex-pict]. String options are immutable. The mode-specific
option used by @racketmodname[latex-pict] is added by that package separately.
}

@defproc[(formula-visual-horizontal-alignment [visual formula-visual?])
         text-horizontal-alignment?]{

Returns the horizontal formula-anchor alignment.
}

@defproc[(formula-visual-vertical-alignment [visual formula-visual?])
         text-vertical-alignment?]{

Returns the vertical formula-anchor alignment.
}

@defproc[(formula-visual-with-source [visual formula-visual?]
                                     [source string?])
         formula-visual?]{

Returns a new formula Visual with @racket[source] copied into immutable model
storage. Identity, affine transform, opacity, mode, font size, preamble,
ordered option lists, and alignment are preserved. The original Visual is
unchanged. Multiline and empty source are accepted.
}


@subsection[#:tag "tagged-formulas"]{Tagged Formula Layouts}

@defstruct*[formula-fragment ([name symbol?]
                              [source string?])
  #:transparent]{

Represents one author-declared contiguous TeX fragment. @racket[name] is the
local part name in a @racket[tagged-formula]; @racket[source] must be a nonempty
string. Names must be unique within each tagged formula.

Fragments are deliberately explicit. Animate does not parse arbitrary TeX into
tokens, so a fragment must be a valid piece of the complete math expression and
must produce visible ink.
}

@defproc[(tagged-formula
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size (and/c finite-real? positive?) 1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:color-map color-map (hash/c symbol? color-spec?) (hash)]
          [fragment formula-fragment?] ...)
         formula-assembly-visual?]{

Builds one full-layout formula from one or more @racket[formula-fragment]
values. Unlike @racket[formula-assembly], the fragments are typeset together.
Their positions, ordinary TeX spacing, kerning, scripts, and alignment come
from the complete formula rather than from manually supplied part positions.

Construction runs the external @tt{latex} and @tt{dvisvgm} executables once.
It wraps every fragment in a dvisvgm SVG group, measures the group, and returns
an ordinary formula assembly whose parts render as the resulting SVG fragments.
Those SVG fragments are renderer-cached, so sampling or rendering animation
frames does not run TeX again. Both executables must be available on
@tt{PATH} when this constructor is called.

All keyword options have the same validation and semantic meaning as for
@racket[latex-formula], except that Preview-package options and per-fragment
anchors are not applicable to a formula whose layout is computed as one unit.
The returned assembly can be moved, rotated, scaled, faded, addressed through
nested part paths, and used with the normal formula-correspondence operations.

@racket[color-map] maps declared fragment names to semantic colours. It is
applied after the complete TeX layout and SVG crops have been created, so it
does not alter kerning, scripts, or measurements. Every key must name a
declared fragment.
}

@defproc[(math-tex
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size (and/c finite-real? positive?) 1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:color-map color-map (hash/c symbol? color-spec?) (hash)]
          [#:source-map source-map (or/c 'none 'declared 'tokens) 'tokens]
          [#:parts parts (listof source-part?) '()]
          [source string?] ...)
         formula-assembly-visual?]{

Source-addressable construction for one complete formula. It accepts the same
layout and @racket[color-map] options as @racket[tagged-formula]. Use
@racket[tagged-formula] when the author needs explicit stable part names
without source queries.

@racket[math-tex] records a canonical source string and a conservative
token-to-rendered-part source map by default. Use @racket[formula-find] or
@racket[formula-source-select] to query rendered source material by a literal
string, regexp, source span, or occurrence. @racket['none] is the explicit
opt-out when no source queries are required. @racket['declared] requires
@racket[#:parts], a list of named @racket[source-part] declarations; it maps
only those author-declared ranges. The token scanner establishes safe TeX
boundaries, not algebraic meaning or a complete TeX parse: user macros,
category-code changes, and source that has no visible output may not be
selectable.
}

@defproc[(glyph-tex
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size (and/c finite-real? positive?) 1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:color-map color-map (hash/c symbol? color-spec?) (hash)]
          [source string?] ...)
         formula-assembly-visual?]{

Typesets one complete TeX expression and exposes each visible dvisvgm glyph
leaf as a formula part named @racket['glyph-0], @racket['glyph-1], and so on,
in painter order. The complete expression is still typeset as one unit, so its
ordinary TeX spacing, kerning, and script placement are retained. Construction
has the same external @tt{latex} and @tt{dvisvgm} requirements as
@racket[tagged-formula].

The generated glyph parts retain the complete author TeX source, but their
matching identity is the referenced dvisvgm path outline together with their
typesetting options. Consequently, exact unchanged glyphs can match between
two separately compiled expressions despite dvisvgm assigning different local
font-definition ids on each compilation. Use @racket[tagged-formula] or
@racket[math-tex] when several glyphs need one semantic identity: glyph leaves
are not TeX tokens, a superscript or accent can contain several leaves, and
repeated outlines match greedily in source order.

@racket[color-map] maps generated names such as @racket['glyph-0] to semantic
colours. Generated names are positional, so explicit tagged fragments are
usually preferable for durable pedagogical styling.
}

@subsection[#:tag "source-addressable-formulas"]{Source-Addressable Formulas}

Source selectors address character ranges in the canonical TeX source retained
by @racket[math-tex]. They complement named formula fragments; they do not
recognize algebraic roles or prove mathematical equivalence. Source indices are
Racket string-character indices in half-open ranges, so
@racket[(source-span 2 5)] selects characters 2 through 4.

@defstruct*[source-span ([start exact-nonnegative-integer?]
                         [end exact-nonnegative-integer?])]{

Represents one half-open source range. It is checked against the formula's
canonical source when used.
}

@defstruct*[source-occurrence ([selector source-selector?]
                               [index exact-nonnegative-integer?])]{

Selects the zero-based occurrence of a literal-string, regexp, or source-span
selector.
}

@defstruct*[source-part ([name symbol?] [selector source-selector?])]{

Gives a declared source selector one stable author-facing name. This is used by
@racket[math-tex] with @racket[#:source-map 'declared].
}

@defproc[(source-selector? [value any/c]) boolean?]{
Recognizes a literal string, regexp, @racket[source-span],
@racket[source-occurrence], or declared @racket[source-part] selector.
}

@defproc[(formula-source-match? [value any/c]) boolean?]{
Recognizes one immutable source-map unit. Its source span, canonical text,
stable name, and mapped leaf paths can be inspected with the corresponding
accessors.
}

@defproc[(visual-selection? [value any/c]) boolean?]{
Recognizes an immutable root-relative selection of existing Visual leaves.
Selections describe semantic paths; they are not synthetic group Visuals.
}

@defproc[(formula-source [formula formula-assembly-visual?]) string?]{

Returns the immutable canonical source string retained by a source-mapped
formula. For several @racket[math-tex] source arguments, arguments are joined
by one literal space; that separator is part of the documented coordinate
system. A formula constructed with @racket[#:source-map 'none] raises an error.
}

@defproc[(formula-find [formula formula-assembly-visual?]
                       [selector source-selector?])
         (listof formula-source-match?)]{

Returns every mapped source occurrence in source order. A string matches
non-overlapping occurrences from left to right; a regexp may not match an empty
range. An unmatched query produces the empty list.
}

@defproc[(formula-source-select [formula formula-assembly-visual?]
                                [selector source-selector?])
         visual-selection?]{

Returns the immutable selection of all leaves mapped by @racket[selector]. The
selection is a query result, not a new scene Visual. It may therefore be used
for read-only selection operations and formula styling, but not as a target for
replacement, removal, or arbitrary movement. It raises an error when no mapped
rendered leaf is selected.
}

@defproc[(formula-source-select-one [formula formula-assembly-visual?]
                                    [selector source-selector?])
         visual-selection?]{

Like @racket[formula-source-select], but requires exactly one matched source
occurrence.
}

@defproc[(plan-matching-strings [source formula-assembly-visual?]
                                [destination formula-assembly-visual?]
                                [#:matches matches (listof string-match?) '()]
                                [#:copies copies (listof string-copy?) '()])
         string-match-plan?]{

Plans a deterministic source-addressed correspondence without rendering it.
Explicit @racket[string-match] declarations take precedence; remaining equal
normalized source material is matched in source order. The resulting plan can
be inspected with @racket[string-match-plan->datum], then animated with
@racket[transform-matching-strings]. Changed material uses the requested fade
or fade-transform policy; unmatched material fades. This is syntactic matching,
not symbolic algebra or a general TeX parser.
}

@defproc[(string-match [source source-selector?]
                       [destination source-selector?]
                       [#:route route (or/c #f formula-route?) #f]
                       [#:mode mode (or/c 'auto 'rigid 'glyphwise 'cross-fade) 'auto])
         string-match?]{
Declares one source-addressed correspondence. Explicit declarations take
priority over automatic normalized-source matching.
}

@defproc[(string-copy [source source-selector?]
                      [destination source-selector?]
                      [#:route route (or/c #f formula-route?) #f]
                      [#:mode mode (or/c 'auto 'rigid 'glyphwise 'cross-fade) 'auto])
         string-copy?]{
Declares a moving copy: the source remains present while an otherwise unmatched
destination is introduced.
}

@defproc[(string-match? [value any/c]) boolean?]{Recognizes an explicit string correspondence.}
@defproc[(string-copy? [value any/c]) boolean?]{Recognizes an explicit string copy.}
@defproc[(string-match-plan? [value any/c]) boolean?]{Recognizes an immutable deterministic match plan.}
@defproc[(string-match-plan->datum [plan string-match-plan?]) immutable-hash?]{
Returns a transparent diagnostic representation of the planner's matches,
unmatched material, routes, and decision reasons.
}

@defproc[(transform-matching-strings
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:matches matches (listof string-match?) '()]
          [#:key-map key-map (listof string-match?) '()]
          [#:protect-source protect-source (listof source-selector?) '()]
          [#:protect-destination protect-destination (listof source-selector?) '()]
          [#:copies copies (listof string-copy?) '()]
          [#:on-ambiguity on-ambiguity (or/c 'left-to-right 'error) 'left-to-right]
          [#:path-arc path-arc finite-real? 0]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade])
         transform-formula-parts-request?]{

Plans source-addressed formula correspondences then compiles them into the
normal deterministic formula transition. It matches source structure, not
algebraic meaning or arbitrary rendered glyph similarity. The compiled plan is
retained for the preview String matching inspector.
}

@defproc[(formula-part-path [source-name symbol?]
                            [destination-name symbol?]
                            [route formula-route?])
         formula-part-path?]{
Declares an explicit route for one named formula-part correspondence.
}

@defproc[(formula-part-copy [source-name symbol?]
                            [destination-name symbol?]
                            [route formula-route?])
         formula-part-copy?]{
Declares a copy from one source part to an otherwise unmatched destination part.
}

@defproc[(formula-part-path? [value any/c]) boolean?]{Recognizes a formula-part route declaration.}
@defproc[(formula-part-copy? [value any/c]) boolean?]{Recognizes a formula-part copy declaration.}

@defproc[(formula-route? [value any/c]) boolean?]{
Recognizes a supported formula-motion route such as a circular
@racket[formula-arc] or a unit-chord @racket[formula-relative-path].
}

@defproc[(formula-arc [#:angle angle finite-real?]) formula-route?]{
Creates a circular formula-motion route. Positive angles travel
counter-clockwise in the formula's local coordinate system; zero is straight.
}

@defproc[(formula-relative-path [geometry path-geometry?]) formula-route?]{
Creates a custom route in unit-chord coordinates. The path must start at
@racket[(vec2 0 0)] and end at @racket[(vec2 1 0)].
}

@defproc[(tagged-formula-fragment-visual? [value any/c]) boolean?]{

Returns @racket[#t] for a generated fragment Visual inside a tagged formula.
The subtype is also a @racket[formula-visual?].
}

@defproc[(tagged-formula-fragment-visual-svg-source
          [visual tagged-formula-fragment-visual?])
         string?]{

Returns the immutable SVG source used to render one generated tagged fragment.
This is provided for inspection and renderer integration; construct fragments
through @racket[tagged-formula], not by manufacturing this renderer detail.
}

@defproc[(transform-matching-parts
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:matches matches (listof formula-part-match?) '()])
         transform-formula-parts-request?]{

Builds a correspondence transform in the style of Manim's matching formula
transitions. Explicit @racket[matches] have priority. Animate then automatically
pairs every remaining source fragment with the first still-unmatched destination
fragment that has exactly the same formula source and typesetting options, in
source order.

Exact matches render as one rigid SVG group that moves with its local transform.
Changed explicit matches are moving cross-fades, and unmatched fragments use the
normal fade-out/fade-in behavior. This operation does not infer algebraic
equivalence, parse TeX tokens, choose paths/arcs for the movement, or morph
glyph outlines.
}

@defproc[(transform-matching-glyphs
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:matches matches (listof formula-part-match?) '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:changed-mode changed-mode (or/c 'fade 'morph) 'fade])
         transform-formula-parts-request?]{

Builds the glyph-level counterpart to @racket[transform-matching-parts]. Both
assemblies must have been produced by @racket[glyph-tex]. Exact dvisvgm path
outlines pair automatically in source order; use @racket[matches] for a
deliberate changed glyph, such as mapping the generated plus-sign part to the
destination minus-sign part. The remaining keywords have the same meanings as
for @racket[transform-matching-parts].

This matches and moves whole rendered glyph leaves. @racket['fade] is the
default: changed matches use the ordinary moving cross-fade. With
@racket[#:changed-mode 'morph], a changed matched pair instead interpolates its
outline only when both cropped dvisvgm SVG fragments expand to one identically
painted path whose positive-length contours are all closed and compatible in
count. Animate globally pairs those destination contours with the source,
phase-aligns them without reversing their traversal, normalizes the resulting
paths to compatible cubic segments, and uses that path geometry only for
interior frames; the ordinary tagged SVG fragments remain exact endpoints.
Glyphs with multiple independently painted paths, open contours, incompatible
contour topology, changed paint, or unsupported geometry safely fall back to
the moving cross-fade.

This operation does not derive a mathematical operation, identify TeX
characters or terms, perform semantic grouping, or infer which changed glyphs
should be paired.
}

@defproc[(rewrite-formula
          [source formula-assembly-visual?]
          [destination formula-assembly-visual?]
          [#:anchor anchor (or/c symbol? formula-part-match?)]
          [#:matches matches (listof formula-part-match?) '()]
          [#:stationary stationary
                        (listof (or/c symbol? formula-part-match?))
                        '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade])
         transform-formula-parts-request?]{

Builds a matching formula transition with one fixed named anchor. Pass a symbol
such as @racket['equals] when the part has the same name at both endpoints, or
a @racket[formula-part-match] when its names differ. The anchor is made an
explicit match; a conflicting value in @racket[matches] raises an error.

When @racket[scene-play] compiles the request, Animate translates the complete
destination layout so the destination anchor coincides with the corresponding
part in the @italic{current} source formula. Consequently, a sequence of
rewrites keeps the anchor fixed even when the formula values passed as earlier
templates were constructed at their own default positions. The translation
preserves the target formula's TeX spacing and baselines.

Each @racket[stationary] entry names an additional matched pair: a symbol means
the same source and destination part name, while a @racket[formula-part-match]
permits different names. The pair is made explicit, and at clip compilation
the destination fragment receives the current source fragment's exact affine
transform. Thus several selected terms can remain fixed even if the rest of the
destination layout moves or reflows. This is an explicit presentation choice;
it does not infer which terms should remain still or maintain a general layout
constraint between them.

The remaining keywords have the same meaning as in
@racket[transform-matching-parts]: explicit matches take priority, routes and
copies select intentional term motion, and @racket['fade-transform] cross-fades
remaining unmatched parts while moving them. Like the lower-level operation,
this is whole-fragment correspondence rather than TeX parsing or glyph-outline
morphing.
}

@defproc[(formula-step
          [destination formula-assembly-visual?]
          [#:anchor anchor (or/c false/c symbol? formula-part-match?) #f]
          [#:stationary stationary
                        (listof (or/c symbol? formula-part-match?))
                        '()]
          [#:matches matches (listof formula-part-match?) '()]
          [#:path-arc path-arc finite-real? 0]
          [#:part-paths part-paths (listof formula-part-path?) '()]
          [#:copies copies (listof formula-part-copy?) '()]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:duration duration (and/c finite-real? positive?) 1]
          [#:pause pause (and/c finite-real? (>=/c 0)) 1/2]
          [#:explanation explanation (or/c false/c string?) #f])
         formula-derivation-step?]{

Describes one explicit rewrite endpoint for @racket[formula-derivation]. The
destination and rewrite keywords have the same meanings as @racket[rewrite-formula].
@racket[pause] is the amount of time to hold the optional explanation before
this step's transition begins. An explanation must be one line of plain text.

@racket[anchor] defaults to @racket[#f], which means that the derivation's
shared anchor is used. A step can override it with a same-name symbol or an
explicit @racket[formula-part-match]. @racket[stationary] has the same meaning
as in @racket[rewrite-formula] and makes additional matched parts fixed for
this one step. This data does not claim that the rewrite is algebraically valid;
it records the author's chosen presentation.
}

@defproc[(formula-derivation-step? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] was created by @racket[formula-step].
}

@defproc[(formula-derivation
          [scene scene?]
          [initial formula-assembly-visual?]
          [#:anchor anchor (or/c symbol? formula-part-match?)]
          [#:steps steps (listof formula-derivation-step?)]
          [#:explanation-position explanation-position
                                  (or/c false/c vec2?)
                                  #f]
          [#:explanation-id explanation-id symbol? 'derivation-note]
          [#:explanation-font-size explanation-font-size
                                    (and/c finite-real? positive?)
                                    1/4]
          [#:explanation-color explanation-color any/c "darkslategray"])
         scene?]{

Appends an ordered derivation to @racket[scene]. @racket[initial] must already
be present in the scene under its formula identity. For each @racket[steps]
entry, the builder first replaces its own optional explanation label, waits for
that step's @racket[pause], and then appends a @racket[rewrite-formula] clip
with the requested duration and correspondence options. The resulting endpoint
becomes the construction template for the next step, while every rewrite still
resolves its anchor from the current sampled scene formula.

When any step has an explanation, supply @racket[explanation-position]. The
builder creates plain text with @racket[explanation-id], which must be absent
from the initial scene. Later explanations replace only that generated Visual.
The final explanation remains visible unless a later step omits it.

This is immutable convenience syntax over existing scene and formula APIs. It
does not parse TeX, infer operations, prove a derivation, choose matches/routes,
or automatically lay out the explanation.
}

@subsection[#:tag "formula-parts"]{Named Formula Parts and Correspondence}

A formula assembly is a composite Visual made from independently typeset LaTeX
formula parts. Each part has a symbol name. That name is local to one assembly
and is also the identity of the part's formula Visual.

Part order is significant back-to-front drawing order. Part positions are local
to the assembly anchor. The library does not ask TeX to lay out several parts
as one document. The caller chooses each local position explicitly. Parts can
overlap when their local anchors are placed too close together.

@defstruct*[formula-part ([name symbol?]
                          [formula formula-visual?])
  #:transparent]{

Represents one named formula fragment.

The @racket[name] field is local to one formula assembly. The
@racket[formula] field contains the complete semantic formula Visual used to
render the fragment. The structure guard requires
@racket[(eq? name (visual-id formula))]. This rule gives each local name one
stable formula identity.

The formula transform and opacity are local to its containing assembly. The
structure is immutable and transparent.
}

@defproc[(latex-formula-part
          [source string?]
          [#:name name symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:mode mode formula-mode? 'display]
          [#:font-size font-size
                       (and/c finite-real? positive?)
                       1]
          [#:preamble preamble string? ""]
          [#:document-class-options document-class-options
                                    (listof latex-option?)
                                    '()]
          [#:preview-options preview-options
                             (listof latex-option?)
                             '()]
          [#:horizontal-alignment horizontal-alignment
                                  text-horizontal-alignment?
                                  'center]
          [#:vertical-alignment vertical-alignment
                                text-vertical-alignment?
                                'center])
         formula-part?]{

Creates a @racket[formula-part] and its formula Visual in one step.
@racket[name] becomes both @racket[formula-part-name] and the formula Visual
identity. Every other argument has the same meaning and validation as the
corresponding argument to @racket[latex-formula].

The @racket[center] value is local to the formula assembly that will contain the
part. Formula source, preamble, and string options are copied into immutable
model storage.

Example:

@racketblock[
(latex-formula-part "n(n+1)"
                    #:name 'numerator
                    #:center (vec2 0 1/2)
                    #:mode 'inline
                    #:font-size 1/3)
]
}

@defproc[(formula-assembly
          [parts (listof formula-part?)]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         formula-assembly-visual?]{

Creates a semantic formula assembly. The @racket[parts] list is stored in
significant back-to-front order. An empty list creates a valid empty assembly.

Part names must be unique within the assembly. Because every part name is also
its formula Visual identity, @racket[id] must differ from every part name.
Part names are local: two different assemblies may use the same names.

The assembly @racket[center] is its reference position in the containing
coordinate system. The assembly rotation is measured counter-clockwise in
radians. Its own scale must be uniform after normalization. This is the same
restriction used by @racket[group]; a non-uniform parent scale followed by a
rotated part can require shear, which the current transform model cannot
represent. Individual formula parts may still use non-uniform local scales.

The assembly implements @racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual]. Existing movement, rotation, uniform scale,
opacity, @racket[fade-in], and @racket[fade-out] operations therefore work on
the complete assembly.

Every nonempty part is typeset separately. The caller is responsible for local
part spacing. The Pict adapter passes the same explicit renderer list to every
part. A custom renderer placed before the defaults may instead support and
replace the complete assembly. An empty assembly renders as stable transparent
one-pixel local geometry without running TeX.
}

@defproc[(formula-assembly-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in formula assembly Visual.
}

@defproc[(formula-assembly-visual-parts
          [assembly formula-assembly-visual?])
         (listof formula-part?)]{

Returns the assembly's parts in significant back-to-front order. The returned
list is immutable model data.
}

@defproc[(formula-assembly-visual-with-parts
          [assembly formula-assembly-visual?]
          [parts (listof formula-part?)])
         formula-assembly-visual?]{

Returns a new assembly with @racket[parts] as its significant ordered part
list. Assembly identity, reference position, rotation, uniform scale, and opacity
are preserved. The same name and identity checks as
@racket[formula-assembly] are performed. The original assembly is unchanged.
}

@defproc[(formula-assembly-visual-part-names
          [assembly formula-assembly-visual?])
         (listof symbol?)]{

Returns local part names in significant back-to-front order.
}

@defproc[(formula-assembly-visual-has-part?
          [assembly formula-assembly-visual?]
          [name symbol?])
         boolean?]{

Returns @racket[#t] when @racket[assembly] contains a part named
@racket[name]. This operation searches the local part namespace; it does not
search the top-level scene state.
}

@defproc[(formula-assembly-visual-ref
          [assembly formula-assembly-visual?]
          [name symbol?])
         formula-part?]{

Returns the part named @racket[name]. An exception is raised when the local name
is absent. The result is a @racket[formula-part], so use
@racket[formula-part-formula] to obtain its formula Visual.
}

@defproc[(formula-select [formula formula-assembly-visual?]
                         [name symbol?])
         visual-path?]{

Returns the ordinary nested Visual path for a known named formula part. For an
assembly named @racket['equation], selecting @racket['x] returns
@racket['(equation x)]. The result can be passed directly to nested operations
such as @racket[indicate], @racket[circumscribe], and @racket[fill-color-to].
An exception is raised when @racket[name] is absent.
}

@defproc[(formula-style
          [formula formula-assembly-visual?]
          [selection (or/c symbol? (and/c pair? (listof symbol?)))]
          [#:color color (or/c false/c color-spec?) #f]
          [#:opacity opacity (or/c false/c opacity?) #f])
         formula-assembly-visual?]{

Immutably applies the supplied colour, opacity, or both to one named formula
part or a nonempty list of distinct names. At least one style keyword is
required. Every name is checked before any replacement is made, so a misspelled
name cannot produce a partially styled assembly.

The new assembly preserves its identity, part order, formula source, TeX/SVG
artifact, and ordinary transforms. Its selected formula leaves implement the
existing fill-colour and opacity protocols. Equal styles therefore retain
normal rigid matching motion; a paint change between formula-rewrite endpoints
uses the established cross-fade fallback.
}

@defproc[(formula-color [formula formula-assembly-visual?]
                         [selection (or/c symbol? (and/c pair? (listof symbol?)))]
                         [color color-spec?])
         formula-assembly-visual?]{

Colour-only shorthand for @racket[formula-style].
}

@defproc[(formula-color-map [formula formula-assembly-visual?]
                             [color-map (hash/c symbol? color-spec?)])
         formula-assembly-visual?]{

Applies one colour to each key named by @racket[color-map]. The empty map
returns an equivalent immutable assembly. This is also the operation used by
the @racket[#:color-map] keywords of @racket[tagged-formula],
@racket[math-tex], and @racket[glyph-tex].
}

@defstruct*[formula-part-match ([source-name symbol?]
                                [destination-name symbol?])
  #:transparent]{

Represents one manually chosen source-to-destination part match.

@racket[source-name] names a part in a source assembly.
@racket[destination-name] names a part in a destination assembly. The structure
itself checks only that both fields are symbols. A
@racket[formula-correspondence] checks that the names exist and are used
one-to-one.
}

@defstruct*[formula-correspondence
            ([source formula-assembly-visual?]
             [destination formula-assembly-visual?]
             [matches (listof formula-part-match?)])
  #:transparent]{

Represents a validated manual mapping between two formula assemblies.

The @racket[source] and @racket[destination] fields store the exact immutable
assembly values used when the correspondence is created. The @racket[matches]
field is stored in significant caller order.

Construction checks all of the following:

@itemlist[
 @item{Every source name exists in @racket[source].}
 @item{Every destination name exists in @racket[destination].}
 @item{A source name appears at most once.}
 @item{A destination name appears at most once.}
]

The match list may be empty. Equal names are not matched automatically. Parts
omitted from @racket[matches] remain explicitly unmatched. The list order is
also the order of matched transition layers created by
@racket[transform-formula-parts].
}

@defproc[(formula-correspondence-auto [source formula-assembly-visual?]
                                      [destination formula-assembly-visual?])
         formula-correspondence?]{

Builds a deterministic correspondence for unchanged formula parts. Each source
part is considered in source order and matches the first still-unmatched
destination part with the same LaTeX source and typesetting options. This allows
stable part names to change without losing unchanged semantic content. Parts
without a match remain unmatched and follow the ordinary fade-out/fade-in
transition behavior.
}

@defproc[(formula-correspondence-unmatched-source-names
          [correspondence formula-correspondence?])
         (listof symbol?)]{

Returns source part names that do not occur in any match. The result preserves
the source assembly's significant part order.
}

@defproc[(formula-correspondence-unmatched-destination-names
          [correspondence formula-correspondence?])
         (listof symbol?)]{

Returns destination part names that do not occur in any match. The result
preserves the destination assembly's significant part order.
}

A formula correspondence stores endpoint templates. It does not store sampled
transition layers. Those layers are compiled when
@racket[transform-formula-parts] is passed to @racket[scene-play], so the
operation can use the current formulas, local transforms, and local opacities
from the scene.

@subsection{Path Visuals}

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

@subsection{Bitmap Images}

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

@defproc[(image-visual-height [visual image-visual?])
         (and/c finite-real? positive?)]{

Returns the unscaled local world height.
}

@subsection{Full-Fidelity SVG Images}

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
@racketmodname[svg/svg] package. That renderer supports substantially more SVG
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

@subsection{Semantic SVG Import}

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


@subsection[#:tag "arrows-and-axes"]{Arrow and Cartesian Axes Visuals}

Arrow and axes values are semantic affine Visuals. They implement
@racket[gen:visual], @racket[gen:affine-visual], and
@racket[gen:opacity-visual]. Their raw structure constructors and internal local
geometry fields are not public.

@subsubsection{Arrows}

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

@subsubsection{Dynamic Endpoint Geometry}

SCENE-CN provides deterministic geometry relationships without mutable
updaters. Each endpoint accepted by the procedures below may be a literal
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
the SCENE-CN constructors.
}

@defproc[(line-between [start any/c] [end any/c]
                       [#:id id symbol?]
                       [#:opacity opacity opacity? 1]
                       [#:stroke stroke any/c "black"]
                       [#:stroke-width stroke-width stroke-width? 2])
         relation-visual?]{

Creates a finite line segment with independently sampled endpoints.
}

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

@subsubsection{Mathematical Annotations}

SCENE-CO supplies small semantic, path-backed marks for explanatory diagrams.
SCENE-ED additionally gives selected marks the same live endpoint protocol as
@racket[line-between]: a literal @racket[vec2], point-valued
@racket[scene-parameter], Visual ID/path (its semantic centre), or
@racket[anchor-of] description. Literal points return the same immediate
@racket[path-visual?] or @racket[group-visual?] values as before. Parameter and
centre-reference inputs create semantic relations; an edge/corner anchor creates
a layout relation. Both are deterministic from the sampled state. The layout
phase remains top-level in this release, and it uses complete renderer bounds
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

@defproc[(angle [first vec2?] [vertex vec2?] [second vec2?]
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
rejected instead of producing a deceptive zero-angle mark.
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

Creates @racket[angle] from three live endpoint descriptions. Literal
@racket[vec2] values return the same static path as @racket[angle]. Otherwise,
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

@subsubsection{Mathematical Shape Catalogue}

SCENE-DJ adds a compact family of path-backed shapes. Except for the two
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

@subsubsection{Axis Ranges}

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

@defproc[(axis-scale? [value any/c]) boolean?]{

Returns @racket[#t] for the supported scale symbols @racket['linear] and
@racket['log].
}

@subsubsection{Cartesian Axes}

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

@subsection[#:tag "linear-algebra-diagrams"]{Linear-Algebra Diagrams}

SCENE-CZ adds small, conventional linear-algebra diagrams without adding a
mutable diagram class. Each constructor below returns an ordinary immutable
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
the label through @racket[derived-visual] until SCENE-DE supplies general live
layout relationships.
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

@subsection[#:tag "complex-and-polar"]{Complex and Polar Coordinates}

SCENE-DA uses ordinary Racket complex numbers and converts only at the drawing
boundary. SCENE-DB follows the same approach for polar coordinate values and
paths. Both planes are normal immutable group trees, not special scene types.

@defproc[(complex->point [value complex?]) vec2?]{
Returns @racket[(vec2 (real-part value) (imag-part value))]. Both components
must be finite reals.
}

@defproc[(point->complex [point vec2?]) complex?]{
Returns the ordinary Racket complex number whose real and imaginary parts are
the x and y components of @racket[point].
}

@defproc[(complex-domain-color
          [value complex?]
          [#:saturation saturation (real-in 0 1) 3/4]
          [#:brightness brightness (real-in 0 1) 4/5]
          [#:radial? radial? boolean? #t])
         rgba-color?]{
Returns an opaque semantic colour whose hue is the argument of @racket[value].
When @racket[#:radial?] is true, its brightness also increases smoothly with
the modulus. This is a pure colour helper; it does not create a renderer-only
pixel effect.
}

@defproc[(complex-domain-coloring
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min finite-real? -3]
          [#:x-max x-max finite-real? 3]
          [#:y-min y-min finite-real? -2]
          [#:y-max y-max finite-real? 2]
          [#:columns columns exact-positive-integer? 24]
          [#:rows rows exact-positive-integer? 16]
          [#:saturation saturation (real-in 0 1) 3/4]
          [#:brightness brightness (real-in 0 1) 4/5]
          [#:radial? radial? boolean? #t]
          [#:opacity opacity (real-in 0 1) 1])
         group-visual?]{
Samples @racket[function] once at the centre of each rectangular complex cell
and returns a normal group of coloured rectangle Visuals. The function must
return finite complex values. Each cell has a stable name derived from
@racket[id], so the result remains ordinary semantic scene content rather than
a continuous raster shader.
}

@defproc[(complex-plane
          [#:id id symbol?]
          [#:x-range x-range axis-range? (axis-range -4 4 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:x-length x-length (and/c finite-real? positive?) 8]
          [#:y-length y-length (and/c finite-real? positive?) 6]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:grid? grid? boolean? #t]
          [#:labels? labels? boolean? #t]
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

Builds a Cartesian complex plane. Its direct @racket['coordinates] child is a
@racket[number-plane] tree; when @racket[#:labels?] is true, direct
@racket['real-axis] and @racket['imaginary-axis] text leaves label Re and Im.
The numeric labels are static construction-time labels.
}

@defproc[(apply-complex-function
          [target (or/c visual? symbol? visual-path?)]
          [function (procedure-arity-includes/c 1)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'error])
         apply-pointwise-request?]{

Creates @racket[apply-pointwise] with each sampled world point converted by
@racket[point->complex], passed to @racket[function], then converted back with
@racket[complex->point]. The function must return a complex number with finite
real and imaginary parts at every retained sampled point. The default strict
@racket['error] discontinuity policy makes an accidental bad function result
fail visibly. Use @racket['split] for an intentional pole or excluded domain:
failed samples then break the path rather than adding a long connecting chord.
This API does not infer branch cuts or normalize by an axes' numeric coordinate
scale.
}

@defproc[(apply-complex-homotopy
          [target (or/c visual? symbol? visual-path?)]
          [homotopy (procedure-arity-includes/c 2)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'error])
         apply-homotopy-request?]{

Creates @racket[apply-homotopy] with each source point converted by
@racket[point->complex], passed together with the current local phase to
@racket[homotopy], and converted back with @racket[complex->point]. The
homotopy must return a finite complex value at every retained sample. Its
strict default discontinuity policy matches @racket[apply-complex-function];
choose @racket['split] for an intentional pole or excluded domain.
}

@defproc[(polar-coordinate? [value any/c]) boolean?]{
Recognizes an immutable reading returned by @racket[point->polar].
}

@defproc[(polar-coordinate-radius [value polar-coordinate?])
         (and/c finite-real? (>=/c 0))]{
Returns the nonnegative radius of a polar reading.
}

@defproc[(polar-coordinate-angle [value polar-coordinate?]) finite-real?]{
Returns the angle of a polar reading in radians.
}

@defproc[(polar->point [radius finite-real?] [angle finite-real?]) vec2?]{
Returns @racket[(vec2 (* radius (cos angle)) (* radius (sin angle)))]. A
signed radius is accepted, which lets @racket[polar-graph] express conventional
rose curves.
}

@defproc[(point->polar [point vec2?]) polar-coordinate?]{
Returns a nonnegative-radius reading. The angle uses @racket[atan]'s interval
@tt{[-pi, pi]}; the origin is assigned angle zero.
}

@defproc[(polar-plane
          [#:id id symbol?]
          [#:radii radii (listof (and/c finite-real? positive?)) '(1 2 3)]
          [#:angles angles (listof finite-real?) (list 0 (/ pi 4) (/ pi 2))]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale (and/c finite-real? positive?) 1]
          [#:labels? labels? boolean? #t]
          [#:stroke stroke any/c "steelblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:grid-stroke grid-stroke any/c "lightsteelblue"]
          [#:grid-stroke-width grid-stroke-width
                               (and/c finite-real? (>=/c 0)) 1]
          [#:label-font-size label-font-size
                              (and/c finite-real? positive?) 1/4]
          [#:label-color label-color any/c "navy"])
         group-visual?]{

Builds a static polar grid. Its direct children are named @racket['rings] and
@racket['rays], plus @racket['labels] when requested. Ring children use
@tt{ring-0}, @tt{ring-1}, and so on; ray children use @tt{ray-0}, @tt{ray-1},
and so on. Labels are deliberately static and may overlap for dense choices.
}

@defproc[(polar-graph
          [radius-function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:start start finite-real? 0]
          [#:end end finite-real? (* 2 pi)]
          [#:samples samples (and/c exact-integer? (>=/c 2)) 240]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "crimson"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3]
          [#:fill fill any/c #f])
         path-visual?]{

Evenly samples @racket[(radius-function theta)] from @racket[start] through
@racket[end] and returns an ordinary open path. Each result must be a finite
real, but it may be negative. Sampling is uniform in angle, not adaptive or
arc-length parameterized.
}

@subsection[#:tag "coordinate-calculus-helpers"]{Coordinate and Calculus Helpers}

SCENE-CP provides static, axes-aware construction helpers for common teaching
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

@subsection[#:tag "coordinate-curves"]{Coordinate Curves and Plots}

The procedures in this section convert ordered numeric coordinates to semantic
path geometry. They use the local coordinate system of an @racket[axes] Visual.
They do not store a sampling procedure or a caller-owned point list in the
result.

@subsubsection{Interpolation Modes}

@defproc[(curve-interpolation? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is one of these symbols:

@itemlist[
 @item{@racket['linear] connects each accepted pair with a line segment.}
 @item{@racket['smooth] creates cubic Bézier segments that pass through all
       accepted samples in order.}
]

Every public coordinate-plot procedure uses @racket['linear] by default. An
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

@subsubsection[#:tag "sampled-function-graphs"]{Sampled Curves and Fields}

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

@subsection[#:tag "ode-flow"]{Deterministic ODE Flow and Streamlines}

SCENE-DC turns a two-dimensional vector field into reproducible integral-curve
geometry. A two-argument field is autonomous; a three-argument field receives
time first. Fixed-step fourth-order Runge--Kutta (RK4) remains the default,
with the caller selecting the step size and number of streamline steps. Neither
the direct numerical solver nor a prepared trajectory depends on a prior
rendered frame. @racket[prepare-ode-trajectory] stores immutable canonical RK4
checkpoints, so an animated particle does not recompute the complete
seed-to-time prefix for every frame. The renderer batches selected frame times
by checkpoint interval, sharing each interval's full RK4 suffix steps.

SCENE-DN adds an optional deterministic adaptive Dormand--Prince 5(4) backend.
It stores accepted endpoint derivatives for cubic Hermite dense lookup, accepts
time-dependent fields, can stop at one scalar sign-crossing event, and records
immutable diagnostics. Once an adaptive trajectory is prepared, dense lookup
and frame rendering never invoke the author field.

@defproc[(ode-flow-position
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [time finite-real?]
          [#:step-size step-size (and/c finite-real? positive?) 1/20])
         vec2?]{

Returns the RK4 solution beginning at coordinate-space @racket[seed] at time
zero and integrated through signed @racket[time]. A two-argument field receives
numeric coordinate x and y values; a three-argument field receives time, x,
and y. It must return one finite @racket[vec2] derivative. A positive time
advances the field; a negative time integrates it backwards.

The final partial step is included, so the requested time is reached exactly
in ordinary arithmetic rather than rounded to a step-grid endpoint. This is a
fixed-step solver, not an adaptive tolerance-controlled integrator.
}

@defproc[(adaptive-rk45
          [#:relative-tolerance relative-tolerance (and/c finite-real? positive?) 1e-6]
          [#:absolute-tolerance absolute-tolerance (and/c finite-real? positive?) 1e-8]
          [#:initial-step initial-step (and/c finite-real? positive?) 1/10]
          [#:minimum-step minimum-step (and/c finite-real? positive?) 1e-8]
          [#:maximum-step maximum-step (and/c finite-real? positive?) 1]
          [#:maximum-steps maximum-steps exact-positive-integer? 100000])
         adaptive-rk45?]{

Creates immutable configuration for the deterministic Dormand--Prince embedded
5(4) adaptive solver. The step bounds must satisfy
@racket[minimum-step <= initial-step <= maximum-step]. The relative and
absolute tolerances form the usual componentwise scale
@racket[atol + rtol * max(abs(previous), abs(candidate))].
}

@defproc[(adaptive-rk45? [value any/c]) boolean?]{
Recognizes immutable adaptive Dormand--Prince solver configuration.
}

@defproc[(ode-event
          [function (or/c (procedure-arity-includes/c 2)
                          (procedure-arity-includes/c 3))]
          [#:direction direction (or/c 'any 'increasing 'decreasing) 'any]
          [#:name name symbol? 'event])
         ode-event?]{

Creates one terminal scalar event for adaptive preparation. Like a field,
@racket[function] accepts either @racket[(x y)] or @racket[(time x y)] and
must return one finite real. A sign crossing ends the trajectory; increasing
and decreasing select the crossing orientation. The root is located by
deterministic bisection over the accepted step's cubic dense output.
}

@defproc[(ode-event? [value any/c]) boolean?]{Recognizes an adaptive terminal event declaration.}

@defproc[(ode-trajectory? [value any/c]) boolean?]{

Returns @racket[#t] for an immutable prepared fixed-RK4 or adaptive-RK45
trajectory.
}

@defproc[(prepare-ode-trajectory
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:time-range time-range (cons/c finite-real? finite-real?)]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:checkpoint-every checkpoint-every exact-positive-integer? 16]
          [#:solver solver (or/c false/c adaptive-rk45?) #f]
          [#:event event (or/c false/c ode-event?) #f])
         ode-trajectory?]{

Prepares a closed time range expressed as @racket[(cons start-time end-time)],
where @racket[start-time] is at most @racket[end-time]. The trajectory stores
immutable states at canonical multiples of @racket[step-size], spaced by
@racket[checkpoint-every] full steps in both the positive and negative
directions from the seed at time zero.

For a lookup, the trajectory begins at the preceding checkpoint between zero
and the requested time, takes fewer than @racket[checkpoint-every] full steps,
and then takes the usual final remainder step. It therefore preserves the
fixed-RK4 numerical meaning of @racket[ode-flow-position] without repeating a
long prefix for each frame.

The field must be pure and stable for the lifetime of the prepared value. The
library cannot determine whether an arbitrary Racket procedure's captured state
has changed.

When @racket[solver] is @racket[#f], this is the established fixed-RK4
checkpoint trajectory. @racket[event] is then rejected. With an
@racket[adaptive-rk45?] value, accepted Dormand--Prince endpoint positions and
derivatives are stored instead. @racket[event], when supplied, truncates the
actual supported range at its dense scalar root.
}

@defproc[(ode-trajectory-time-range [trajectory ode-trajectory?])
         (cons/c finite-real? finite-real?)]{

Returns the supported closed time range. For a trajectory stopped by an
adaptive event, the relevant endpoint is the detected dense root rather than
the original requested boundary.
}

@defproc[(ode-trajectory-step-size [trajectory ode-trajectory?])
         (or/c (and/c finite-real? positive?) false/c)]{

Returns the fixed RK4 step size, or @racket[#f] for an adaptive trajectory.
}

@defproc[(ode-trajectory-checkpoint-every [trajectory ode-trajectory?])
         (or/c exact-positive-integer? false/c)]{

Returns the number of full RK4 steps between stored canonical checkpoints, or
@racket[#f] for an adaptive trajectory.
}

@defproc[(ode-trajectory-solver [trajectory ode-trajectory?])
         (or/c 'fixed-rk4 adaptive-rk45?)]{

Returns @racket['fixed-rk4] for the established checkpoint backend or the
immutable @racket[adaptive-rk45?] value that prepared an adaptive trajectory.
}

@defproc[(ode-trajectory-diagnostics [trajectory ode-trajectory?])
         (or/c false/c ode-trajectory-diagnostics?)]{

Returns @racket[#f] for fixed RK4. An adaptive trajectory returns transparent
diagnostics containing solver name, accepted and rejected step counts,
termination time/reason, and the maximum componentwise scaled embedded error.
The error is a local control diagnostic, not a global proof of solution error.
}

@defproc[(ode-trajectory-diagnostics? [value any/c]) boolean?]{
Recognizes the immutable diagnostics returned for a prepared adaptive ODE
trajectory.
}

@defproc[(ode-trajectory-position [trajectory ode-trajectory?]
                                   [time finite-real?])
         vec2?]{

Returns the prepared position at @racket[time]. Fixed trajectories reproduce
the existing checkpoint/remainder RK4 path. Adaptive trajectories use stored
cubic Hermite dense output and do not call the field. The time must lie inside
the actual supported range, which may end early at an event root.
}

@defproc[(streamline-points
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120])
         (listof vec2?)]{

Returns the coordinate-space RK4 samples for one streamline. @racket['forward]
goes from time zero through positive time; @racket['backward] returns points in
increasing geometric order from negative time to the seed; @racket['both]
combines both directions without duplicating the seed.
}

@defproc[(streamline
          [axes axes-visual?]
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seed vec2?]
          [#:id id symbol?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         path-visual?]{

Converts @racket[streamline-points] through @racket[axes] into one ordinary
world-space path Visual. The axes conversion is captured when the streamline is
constructed. It does not clip, stop at axes bounds, or retain the field
procedure after construction.
}

@defproc[(streamlines
          [axes axes-visual?]
          [field (or/c (procedure-arity-includes/c 2)
                       (procedure-arity-includes/c 3))]
          [seeds (listof vec2?)]
          [#:id id symbol?]
          [#:direction direction (or/c 'forward 'backward 'both) 'both]
          [#:step-size step-size (and/c finite-real? positive?) 1/20]
          [#:steps steps exact-positive-integer? 120]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "royalblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2])
         group-visual?]{

Builds an ordinary group of streamline paths. Seed number @italic{n} becomes
the direct child named by @tt{id-n}; for example, the first child of
@racket['flow] is reachable at @racket['(flow flow-0)].
}

@defproc[(flow-particle
          [axes axes-visual?]
          [trajectory ode-trajectory?]
          [phase (or/c symbol? scene-parameter?)]
          [#:id id symbol?]
          [#:shape shape point-marker-shape? 'circle]
          [#:size size (and/c finite-real? positive?) 1/5]
          [#:fill fill any/c "crimson"]
          [#:stroke stroke any/c "black"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 1]
          [#:opacity opacity opacity? 1])
         derived-visual?]{

Creates a parameter-driven point marker. At every scene sample,
@racket[phase]'s finite real value selects a position from @racket[trajectory],
which is then converted through @racket[axes]. The phase must remain within the
trajectory's declared range.

Before @racket[render-frames!] creates frame workers, it samples all requested
phase values and freezes the corresponding particle coordinates in an immutable
table. The preparation pass walks each used checkpoint interval once, sharing
full RK4 suffix steps among its selected times. Workers only read those
coordinates; they never call the author field. Direct arbitrary-time scene
sampling remains deterministic through
@racket[ode-trajectory-position].

For an adaptive trajectory, the preparation pass instead reads its stored dense
output directly; no numerical integration or field call occurs after the
trajectory has been prepared.
}

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
          [#:interpolation interpolation curve-interpolation? 'linear])
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
          [#:interpolation interpolation curve-interpolation? 'linear]
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

@subsubsection{Parametric Curves}

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
          [#:interpolation interpolation curve-interpolation? 'linear])
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
          [#:interpolation interpolation curve-interpolation? 'linear]
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

@subsubsection{Ordered Data Plots}

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


@subsection{Group Visuals}

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

@defproc[(group-visual-with-children
          [group group-visual?]
          [children (listof (and/c visual? affine-visual?))])
         group-visual?]{

Returns a new group with @racket[children] as its significant back-to-front
child list. Identity, group transform, and opacity are preserved. The same
child and identity validation as @racket[group] is performed. The original
group is unchanged.
}


@section[#:tag "relation-visuals"]{First-Class Relation Visuals}

@declare-exporting[animate #:use-sources (animate/main)]

A relation is an immutable Visual whose concrete geometry is recomputed from
explicit dependencies in each sampled scene state. It replaces the former split
between pure endpoint geometry and renderer-aware endpoint wrappers. No relation
uses a mutable updater or needs the preceding frame.

@defproc[(relation-visual
          [template visual?]
          [#:depends-on dependencies (listof relation-dependency?) '()]
          [#:phase phase (or/c 'semantic 'layout) 'semantic]
          [#:structure structure (or/c 'root-only 'fixed) 'root-only]
          [#:space space (or/c 'world 'local) 'world]
          [#:cache-key cache-key any/c #f]
          [resolver (-> relation-context? visual? visual?)])
         relation-visual?]{

Creates a relation with the stable identity of @racket[template]. The resolver
receives a read-only @racket[relation-context?] and a local template, and must
return one concrete Visual with the same identity. Every value, Visual,
renderer-anchor, or semantic selection read through the context must be named
in @racket[dependencies]; undeclared reads fail descriptively.

The ordinary movement, rotation, scale, opacity, fill, stroke, and stroke-width
controls form an outer envelope. They are applied after the resolver has
computed the current geometry, so a relation may be animated concurrently with
its own changing dependencies. A requested style must be supported by both the
template and the concrete result. A @racket['fixed] relation preserves the
template's complete child-ID tree and may expose nested paths; a
@racket['root-only] relation deliberately exposes only its root ID.

A @racket['semantic] relation is resolved from model data. A @racket['layout]
relation may use @racket[relation-context-anchor-ref],
@racket[relation-context-layout-box], or selection boxes after the active
renderer has measured its targets. Layout relations are currently top-level
only, and their measurements are complete Pict boxes rather than tight visible
outlines.
}

@defproc[(relation-context-layout-box [context relation-context?]
                                      [visual visual?])
         layout-box?]{

Measures one resolver-local concrete Visual in the active renderer/camera
configuration. This operation is available only to layout relations. It is
intended for relations such as @racket[follow-anchor] that must align one anchor of
their own content to an anchor of another Visual.
}

@defproc[(relation-visual? [value any/c]) boolean?]{
Recognizes an immutable relation Visual.
}

@defproc[(relation-visual-dependencies [relation relation-visual?])
         (listof relation-dependency?)]{
Returns the relation's explicitly declared dependencies in author order.
}

@defproc[(relation-visual-cacheability [relation relation-visual?])
         (or/c 'serializable 'explicit-key 'disabled)]{
Reports whether the resolver can participate in a persistent cache. Built-in
transparent specifications are @racket['serializable]; an author procedure with
@racket[#:cache-key] is @racket['explicit-key]; an opaque procedure is
@racket['disabled].
}

@defproc[(relation-dependency? [value any/c]) boolean?]{
Recognizes a declared value, Visual, anchor, or selection dependency.
}

@defproc[(relation-context? [value any/c]) boolean?]{
Recognizes the read-only context supplied to a relation resolver.
}

@defproc[(relation-context-anchor-ref [context relation-context?]
                                      [target (or/c visual? symbol? visual-path?)]
                                      [anchor symbol?])
         vec2?]{
Returns a renderer-measured anchor for a layout relation after recording the
corresponding declared @racket[anchor-dependency].
}

@defproc[(value-dependency [target (or/c symbol? scene-parameter?)])
         relation-dependency?]{Declares one sampled scalar/value input.}

@defproc[(visual-dependency [target (or/c visual? symbol? visual-path?)])
         relation-dependency?]{Declares one semantic Visual input.}

@defproc[(anchor-dependency [target (or/c visual? symbol? visual-path?)]
                            [anchor symbol?])
         relation-dependency?]{Declares one renderer-measured anchor input.}

@defproc[(selection-dependency [selection visual-selection?])
         relation-dependency?]{Declares one semantic selection input.}

@defproc[(scene-validate-relations [state scene-state?]) immutable-hash?]{

Checks declared relation dependencies and reports missing targets or deterministic
dependency cycles before rendering.
}

@defproc[(scene-relation-report [state scene-state?]
                                [target (or/c #f visual? symbol? visual-path?) #f])
         any/c]{

Returns deterministic relation-resolution report data without invoking author
resolver procedures. It records full path, drawing order, phase, structure,
declared dependencies, cacheability, and warnings. Library-owned serializable
specifications are cacheable; generic resolver procedures remain opaque unless
the author supplies @racket[#:cache-key].
}

@defproc[(scene-relation-sample-report
          [state scene-state?]
          [target (or/c #f visual? symbol? visual-path?) #f])
         any/c]{

Returns the same report shape, but additionally resolves each selected
@racket['semantic] relation once for this sampled state. The report's
@racket['used-dependencies] and @racket['unused-dependencies] fields then
distinguish declared inputs that the resolver actually read from declared
inputs it did not read at this instant. This is an opt-in diagnostic operation:
it can run the author's resolver procedure, but does not alter the immutable
scene state or renderer cache.

For a @racket['layout] relation those fields are @racket[#f]. Determining its
actual reads requires the active renderer's measured layout boxes, which this
headless report intentionally does not invent.
}

Built-in @racket[line-between], @racket[arrow-between], @racket[ray-from],
@racket[parameter-display], and @racket[follow-anchor] use serializable relation
specifications. The live
angle, brace, and curved-arrow constructors use generic relations because their
builder procedure is author-specific; therefore they deliberately do not claim
automatic persistent-cache reuse.

@defproc[(follow-anchor
          [content visual?]
          [target (or/c visual? symbol? visual-path?)]
          [#:offset offset vec2? origin]
          [#:target-anchor target-anchor
                           (or/c 'bottom-left 'bottom 'bottom-right
                                 'left 'center 'right
                                 'top-left 'top 'top-right)
                           'center]
          [#:self-anchor self-anchor
                         (or/c 'bottom-left 'bottom 'bottom-right
                               'left 'center 'right
                               'top-left 'top 'top-right)
                         'center])
         relation-visual?]{

Creates one world-space relation whose selected content anchor follows the
selected sampled anchor of @racket[target], plus @racket[offset].
@racket[target] may be a top-level Visual, its symbol identity, or a nested
path. The default centre-to-centre form is a semantic relation: it follows the
target's sampled reference point without invoking a renderer. Choosing a
non-centre target or content anchor creates a layout relation, which measures
the relevant Pict box in the active camera and renderer configuration. Both
forms follow target motion without frame-mutating callbacks.

The content must be a concrete, non-frame-space Visual, and content and target
must have distinct identities. Attachments may be animated through the normal
relation envelope. One attachment may target another when the resulting
relation graph is acyclic; they neither avoid other labels nor inherit target
rotation. Layout attachments are top-level and renderer-dependent; a semantic
centre attachment can be queried directly from a sampled scene state.
}

@subsection[#:tag "live-layout"]{Acyclic Live Layout}

@declare-exporting[animate/main]

SCENE-DE gives the renderer-aware attachment model concise relationship names.
Their relation graph is resolved from a concrete target outward at each render.
A direct or indirect cycle raises an exception; no prior frame is consulted.

@defproc[(follow-above [content visual?]
                     [target (or/c visual? symbol? visual-path?)]
                     [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's bottom anchor at the target's top anchor plus @racket[gap].
}

@defproc[(follow-below [content visual?]
                     [target (or/c visual? symbol? visual-path?)]
                     [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's top anchor at the target's bottom anchor minus @racket[gap].
}

@defproc[(follow-left-of [content visual?]
                        [target (or/c visual? symbol? visual-path?)]
                        [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's right anchor at the target's left anchor minus @racket[gap].
}

@defproc[(follow-right-of [content visual?]
                         [target (or/c visual? symbol? visual-path?)]
                         [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's left anchor at the target's right anchor plus @racket[gap].
}
