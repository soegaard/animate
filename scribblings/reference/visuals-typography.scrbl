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
@title[#:tag "ref-visuals-typography"]{Semantic Text and Typography Styles}


@declare-exporting[animate/main]


A semantic text Visual retains a role and its explicit overrides; a
@racket[text-style] is a complete style, and a @racket[typography-theme] is an
immutable table of styles. @racket[text-treatment] adds padding, background,
and a cosmetic border. The contracts below distinguish an omitted property
(inherit or retain) from an explicit @racket[#f] (clear an optional property).

See also @secref["ref-visuals-text"], @secref["ref-visuals-numeric"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "semantic-text-visuals"]{Semantic Text and Typography}

Semantic text stores a presentation role instead of a resolved platform font.
It lowers to the ordinary @racket[text-visual?] protocol only when Animate
renders or measures it under an explicit typography snapshot. Raw
@racket[plain-text], @racket[paragraph], and @racket[rich-text] remain
independent of typography themes.

@subsection[#:tag "ref-visuals-typography-lookup-1"]{Backgrounds, Borders, and Padding}

@defproc[(text-treatment
          [#:background background (or/c false/c paint?) #f]
          [#:border-color border-color (or/c false/c color-spec?) #f]
          [#:border-width border-width (and/c finite-real? (>=/c 0)) 0]
          [#:padding-x padding-x (and/c finite-real? (>=/c 0)) 0]
          [#:padding-y padding-y (and/c finite-real? (>=/c 0)) 0])
         text-treatment?]{

Creates immutable optional presentation treatment for semantic text. Padding is
in ems of the resolved outer style. A border width is cosmetic device width:
semantic scaling changes the treatment box but not the visible pen thickness.
The treatment decorates the final text-content box, then that decorated box is
anchored, so its logical text anchor remains fixed. A border width of zero does
not draw a border.

A structured background paint uses the same local coordinates as every other
Paint: the semantic text anchor is the origin, positive @racket[x] points
right, and positive @racket[y] points up. Linear and radial gradients follow
text placement, scaling, and rotation rather than starting at the treatment
box's top-left corner. The current Pict backend draws a @racket[checker-pattern]
as a device-aligned tile, so checker cells do not yet fully follow scale or
rotation.

The built-in text renderer knows that content box exactly. A custom Pict
renderer for a semantic text value instead declares its own logical Pict box;
the treatment decorates that declared box. Animate does not inspect rendered
pixels to guess a tighter ink box for custom renderers. Its treatment anchor is
the center of the declared box, independently of the text alignment stored on
the Visual. Backgrounds and padding scale with the Pict; a treatment border is
added after that scale, so its width stays cosmetic (in device pixels).
}

@defproc[(text-treatment? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is an immutable semantic text
treatment.
}

@defproc*[([(text-treatment-background [treatment text-treatment?])
            (or/c false/c paint?)]
           [(text-treatment-border-color [treatment text-treatment?])
            (or/c false/c color-spec?)]
           [(text-treatment-border-width [treatment text-treatment?])
            (and/c finite-real? (>=/c 0))]
           [(text-treatment-padding-x [treatment text-treatment?])
            (and/c finite-real? (>=/c 0))]
           [(text-treatment-padding-y [treatment text-treatment?])
            (and/c finite-real? (>=/c 0))])]{

Returns one immutable treatment property. Padding values are em multipliers,
not world distances or pixels.
}

@defproc[(text-treatment-update
          [treatment text-treatment?]
          [#:background background (or/c false/c paint?)]
          [#:border-color border-color (or/c false/c color-spec?)]
          [#:border-width border-width (and/c finite-real? (>=/c 0))]
          [#:padding-x padding-x (and/c finite-real? (>=/c 0))]
          [#:padding-y padding-y (and/c finite-real? (>=/c 0))])
         text-treatment?]{

Returns a new treatment. Omit a keyword to keep its value from
@racket[treatment]. Supplying @racket[#f] explicitly removes a background or
border color.
}

@; visuals-reference-r1 example: typography-1
An explicit false border color clears it; an omitted padding value is retained.

@examples[#:eval reference-eval
  (define framed (text-treatment #:border-color "gray"
                                 #:border-width 1 #:padding-x 1/2))
  (define unframed (text-treatment-update framed #:border-color #f))
  (eval:check (text-treatment-border-color unframed) #f)
  (eval:check (text-treatment-padding-x unframed) 1/2)
]


@subsection[#:tag "ref-visuals-typography-lookup-2"]{Complete Styles}

@defproc[(text-style
          [#:font-family font-family text-font-family?]
          [#:font-size font-size (and/c finite-real? positive?)]
          [#:font-style font-style text-font-style?]
          [#:font-weight font-weight text-font-weight?]
          [#:color color color-spec?]
          [#:line-spacing line-spacing (and/c finite-real? positive?)]
          [#:line-alignment line-alignment text-horizontal-alignment?]
          [#:horizontal-alignment horizontal-alignment text-horizontal-alignment?]
          [#:vertical-alignment vertical-alignment text-vertical-alignment?]
          [#:font-face font-face (or/c false/c string?) #f]
          [#:treatment treatment (or/c false/c text-treatment?) #f])
         text-style?]{

Creates one complete typography style. Its color is a semantic color
specification, not resolved RGBA. @racket[text-style-update] returns a copy
that changes only explicitly supplied properties; an explicit @racket[#f] may
clear a font face or treatment.
}

@defproc[(text-style? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a complete immutable text style.
}

@defproc[(text-style-update
          [style text-style?]
          [#:font-face font-face (or/c false/c string?)]
          [#:font-family font-family text-font-family?]
          [#:font-size font-size (and/c finite-real? positive?)]
          [#:font-style font-style text-font-style?]
          [#:font-weight font-weight text-font-weight?]
          [#:color color color-spec?]
          [#:line-spacing line-spacing (and/c finite-real? positive?)]
          [#:line-alignment line-alignment text-horizontal-alignment?]
          [#:horizontal-alignment horizontal-alignment text-horizontal-alignment?]
          [#:vertical-alignment vertical-alignment text-vertical-alignment?]
          [#:treatment treatment (or/c false/c text-treatment?)])
         text-style?]{

Returns a new complete style. Omit a keyword to retain its value from
@racket[style]. For @racket[#:font-face] and @racket[#:treatment], supplying
@racket[#f] explicitly clears the optional value.
}

@defproc*[([(text-style-font-face [style text-style?]) (or/c false/c string?)]
           [(text-style-font-family [style text-style?]) text-font-family?]
           [(text-style-font-size [style text-style?]) (and/c finite-real? positive?)]
           [(text-style-font-style [style text-style?]) text-font-style?]
           [(text-style-font-weight [style text-style?]) text-font-weight?]
           [(text-style-color [style text-style?]) color-spec?]
           [(text-style-line-spacing [style text-style?]) (and/c finite-real? positive?)]
           [(text-style-line-alignment [style text-style?]) text-horizontal-alignment?]
           [(text-style-horizontal-alignment [style text-style?]) text-horizontal-alignment?]
           [(text-style-vertical-alignment [style text-style?]) text-vertical-alignment?]
           [(text-style-treatment [style text-style?]) (or/c false/c text-treatment?)])]{

Returns one complete property from an immutable typography style.
}

@defproc[(text-style->datum [style text-style?]) any/c]{

Returns the deterministic complete style datum used inside a typography theme.
}

@defproc[(datum->text-style [datum any/c]) text-style?]{

Validates and reads a datum produced by @racket[text-style->datum].
}

@subsection[#:tag "ref-visuals-typography-lookup-3"]{Typography Snapshots}

@defproc[(typography-theme
          [#:id id symbol?]
          [#:styles styles (or/c hash? (listof pair?)) #hash()]
          [#:extends parent (or/c false/c typography-theme?) #f]
          [#:display-name display-name string?]
          [#:provenance provenance (or/c false/c string? symbol?) #f])
         typography-theme?]{

Creates an immutable complete typography snapshot. A root theme must contain
the standard roles. A child copies its parent's complete table, then replaces
named complete styles. @racket[typography-ref] gets one style, and
@racket[typography-theme-fingerprint] identifies its appearance-relevant
contents. @racket[typography-theme->datum] and
@racket[datum->typography-theme] provide the deterministic versioned data
format used by project plans and preview workers. Serialization accounts for
the complete data tree, including styles, treatments, paints, and colors, and
rejects data beyond its generous resource limits. Decoding validates the
wrapper and style entries before it traverses their contents.
}

@defproc[(typography-theme? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is an immutable typography snapshot.
}

@defproc*[([(typography-theme-id [theme typography-theme?]) symbol?]
           [(typography-theme-display-name [theme typography-theme?]) string?]
           [(typography-theme-provenance [theme typography-theme?])
            (or/c false/c string? symbol?)]
           [(typography-style-keys [theme typography-theme?]) (listof symbol?)]
           [(typography-ref [theme typography-theme?] [style-key symbol?]) text-style?]
           [(typography-theme-fingerprint [theme typography-theme?]) bytes?]
           [(typography-theme->datum [theme typography-theme?]) any/c]
           [(datum->typography-theme [datum any/c]) typography-theme?])]{

Inspect, look up, fingerprint, and transport a typography snapshot.
@racket[typography-style-keys] is sorted deterministically. The fingerprint
describes appearance only: a theme's display name and provenance do not change
it. The datum procedures use the version reported by
@racket[typography-theme-schema-version].
}

@defthing[typography-theme-schema-version exact-positive-integer?]{

The version of the portable typography-theme datum format.
}

@defthing[animate-typography-theme typography-theme?]{

The standard immutable role table: @racket['title], @racket['subtitle],
@racket['section-heading], @racket['body], @racket['caption],
@racket['label], @racket['quotation], @racket['code], and
@racket['annotation].
}

@defthing[typography-standard-style-keys (listof symbol?)]{

The ordered standard role keys required by a root typography theme.
}

@subsection[#:tag "ref-visuals-typography-lookup-4"]{Role-Based Text}

@defproc*[([(title-text [content string?] [#:id id symbol?]
                         [#:center center vec2? origin]
                         [#:font-size font-size (and/c finite-real? positive?)] ...)
            semantic-text-visual?]
           [(subtitle-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(section-heading-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(body-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(caption-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(label-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(quotation-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(code-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?]
           [(annotation-text [content string?] [#:id id symbol?] ...)
            semantic-text-visual?])]{

Creates semantic text with the corresponding standard role. The common
keywords include placement and affine presentation plus explicit font, color,
alignment, width, line-spacing, and treatment overrides. In addition to a
whole @racket[#:treatment], @racket[#:background], @racket[#:border-color],
@racket[#:border-width], @racket[#:padding-x], and @racket[#:padding-y] can
change one treatment property while the other properties inherit. An omitted
property inherits from the role. A semantic text value retains that inheritance
data in the Scene.
}

@defproc[(styled-text [content string?]
                      [#:style style-key symbol?]
                      [#:id id symbol?]
                      ...)
         semantic-text-visual?]{

Creates semantic text using a standard or custom named style. The selected
theme must contain @racket[style-key] at the render or measurement boundary.
@racket[styled-rich-text] is the rich-span counterpart; it accepts ordinary
strings and @racket[text-span] values after its keywords.
}

@defproc[(styled-rich-text
          [#:style style-key symbol?]
          [#:id id symbol?]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:width width (or/c false/c (and/c finite-real? positive?)) #f]
          [piece (or/c string? text-span?)] ...)
         semantic-text-visual?]{

Creates semantic rich text with the same inherited style and optional override
keywords as @racket[styled-text]. The pieces retain the ordinary
@racket[rich-text] span semantics after late style resolution.
}

@defproc*[([(semantic-text-content [visual semantic-text-visual?]) string?]
           [(semantic-text-spans [visual semantic-text-visual?]) (listof text-span?)]
           [(semantic-text-overrides [visual semantic-text-visual?])
            semantic-text-overrides?]
           [(semantic-text-visual-width [visual semantic-text-visual?])
            (or/c false/c (and/c finite-real? positive?))])]{

Returns the retained source data and maximum wrapping width. These are authored
data, before style resolution.
}

@defproc[(semantic-text-override-inherited? [value any/c]) boolean?]{

Returns @racket[#t] when one property in @racket[semantic-text-overrides]
inherits from its named style rather than replacing it explicitly.
}

@defproc[(semantic-text-visual? [value any/c]) boolean?]{Recognizes a
semantic text Scene value.}

@defproc[(semantic-text-overrides? [value any/c]) boolean?]{

Recognizes the immutable record of explicit and inherited style properties
retained by a semantic text Visual.
}

@defproc[(semantic-text-style-key [visual semantic-text-visual?]) symbol?]{
Returns the retained role or custom style key.}

@; visuals-reference-r1 example: typography-2
A role-based constructor keeps its role in the model.

@examples[#:eval reference-eval
  (define heading (title-text "Velocity" #:id 'heading))
  (eval:check (semantic-text-style-key heading) 'title)
]


@defproc[(resolve-semantic-text-style [visual semantic-text-visual?]
                                      [theme typography-theme?])
         text-style?]{

Purely resolves a semantic text value against one explicit immutable
typography theme. It does not render, look up platform fonts, or resolve the
style's color specification.
}

@(close-eval reference-eval)
