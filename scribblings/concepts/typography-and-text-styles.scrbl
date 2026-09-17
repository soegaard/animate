#lang scribble/manual
@(require (for-label racket/base animate animate/project))

@title[#:tag "typography-and-text-styles"]{Text roles, fonts, and size}

A title and a footnote have different jobs. Give text a role when the theme
should choose its appearance. For example:

@racketblock[(title-text "Solving an equation" #:id 'heading #:center (vec2 0 2))]

The title role supplies a font family, size, weight, color, alignment, and any
text treatment. The text can keep its role when the theme changes.

@section{Roles and raw text}

Heading helpers include @racket[title-text], @racket[subtitle-text], and
@racket[section-heading-text]. Ordinary text helpers include @racket[body-text],
@racket[caption-text], @racket[label-text], and @racket[annotation-text].
@racket[quotation-text] and @racket[code-text] cover quotations and code.

Use @racket[plain-text], @racket[paragraph], or @racket[rich-text] when the source
should choose exact text settings without using a typography role. Do not convert
axis ticks or imported artwork to title/body roles just because they contain text.

The slide system uses its own lecture typography built on the same native text
styles. Its @tt{paragraph-content} is a description to measure later, not another
name for the native @racket[paragraph].

@section{World units become output pixels}

Font sizes are world lengths. The camera converts them to nominal pixel sizes:

@verbatim{pixel font size = world font size × pixel width / world width}

For a 16-unit-wide camera, a font size of 0.4 requests 32 pixels at an output
width of 1280, or 48 pixels at 1920. Visible letter height still depends on the
font. Scaling a Visual or group also scales its text.

Changing only output resolution makes the same composition larger. Changing a
font or its size can change measured widths, line breaks, and baselines. For a
prepared slide, make that change in the source and prepare again.

@section{Typography and color are separate choices}

Typography chooses text settings. A color theme resolves roles such as
foreground and muted. A project should use the same typography that was used
to measure its content. Otherwise a layout may be measured with one font and
drawn with another.

Use @racket[text-style-update] to change part of a complete style. Use
@racket[typography-theme] to collect those styles. A local override, such as
italic body text, can keep its semantic role. See
@secref["recipe-slide-theme"] for a complete slide-theme example.

@section{Backgrounds and borders}

A @racket[text-treatment] adds a background, border, and padding. Padding grows
around the text anchor. During @racket[typewrite], the treatment keeps the final
text's size rather than changing after each letter.

Border width is cosmetic output-pixel width, unlike the world-unit font size.
Checker treatments currently use device-aligned tiles in the Pict renderer;
they do not fully follow arbitrary text scaling and rotation. Exact treatment
and text-animation restrictions belong to the reference entries.

@section{Inspect the result}

The preview inspector distinguishes the authored role, explicit overrides, and
the style resolved from the selected theme. Use it to answer why a title has a
particular size. Looking only at a rendered pixel cannot tell you whether its
color came from a role or a fixed literal.
