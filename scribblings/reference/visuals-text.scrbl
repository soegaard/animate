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
@title[#:tag "ref-visuals-text"]{Text Content and Layout}


@declare-exporting[animate/main]


Use @racket[plain-text] for a single line, @racket[paragraph] for line
breaks or wrapping, and @racket[rich-text] for styled spans. These constructors
store explicit text properties. Use the role-based constructors in
@secref["semantic-text-visuals"] when properties should inherit from a typography
theme.

See also @secref["ref-visuals-typography"], @secref["ref-visuals-numeric"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "plain-text-visuals"]{Plain, Multiline, and Rich Text Visuals}

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
inline span.
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

@subsection[#:tag "ref-visuals-text-lookup-1"]{Constructing Text Visuals}

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
          [#:color color any/c theme-foreground]
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
          [#:color color any/c theme-foreground]
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
          [#:color color any/c theme-foreground]
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

@; visuals-reference-r1 example: text-1
Spans retain one combined source string.

@examples[#:eval reference-eval
  (define label
    (rich-text #:id 'label
               "x = " (text-span "2" #:font-weight 'bold)))
  (eval:check (text-visual-content label) "x = 2")
]


@subsection[#:tag "ref-visuals-text-lookup-2"]{Inspecting and Updating Text}

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

@; visuals-reference-r1 example: text-2
Changing content returns a new value.

@examples[#:eval reference-eval
  (define before (plain-text "x = 2" #:id 'value))
  (define after (text-visual-with-content before "x = 3"))
  (eval:check (text-visual-content before) "x = 2")
  (eval:check (text-visual-content after) "x = 3")
]


@defproc[(text-visual-with-spans [visual text-visual?]
                                 [spans (listof text-span?)])
         text-visual?]{

Returns a new text Visual with @racket[spans] installed atomically. Outer font
defaults and all layout/anchor settings are preserved. The content accessor of
the result is the immutable concatenation of the supplied spans.
}

@(close-eval reference-eval)
