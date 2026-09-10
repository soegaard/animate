#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/project
                     animate/preview))

@title[#:tag "typography-and-text-styles"]{Typography and Text Styles}

@declare-exporting[animate/main]

Use semantic text for presentation text. For example, a title can say what it
is instead of repeating its font settings:

@racketblock[
(title-text "Solving a Linear Equation"
            #:id 'problem-title
            #:center (vec2 0 2))
]

The title's font, size, weight, color, alignment, and optional background box
come from a @racket[typography-theme]. The built-in
@racket[animate-typography-theme] contains these roles:

@itemlist[
 @item{@racket[title-text], @racket[subtitle-text], and
       @racket[section-heading-text] for headings.}
 @item{@racket[body-text], @racket[caption-text], @racket[label-text], and
       @racket[annotation-text] for ordinary explanatory text.}
 @item{@racket[quotation-text] and @racket[code-text] for quotations and code.}
]

@section{Raw text is still available}

@racket[plain-text], @racket[paragraph], and @racket[rich-text] are the
explicit, low-level text tools. Use them when the source itself should choose
the exact text appearance independently of a project's typography. They do
not consult a typography theme.

Use semantic text when the text has a presentation role. Its Scene value keeps
the role and any explicit overrides. The role is resolved only when Animate
renders or measures it, so the same immutable Scene can be rendered with a
different typography snapshot.

@section{Typography and color are different choices}

Typography chooses text properties such as a family, size, line spacing, and
treatment. A color theme resolves color roles such as
@racket[theme-foreground] and @racket[theme-muted]. Choose both explicitly for
a project:

@racketblock[
(render-spec #:theme animate-dark-theme
             #:typography lecture-typography)
]

Changing the color theme normally changes paint only. Changing typography can
also change text width, line breaks, and baseline. For construction-time layout
of semantic text, pass the same snapshot with @racket[#:typography]. Rendered
relations and preview rendering use their currently selected typography
snapshot automatically.

@section{Custom styles and one-off overrides}

Start a custom theme from the built-in complete style table. Each replacement
is a complete @racket[text-style], usually made with
@racket[text-style-update]:

@racketblock[
(define lecture-typography
  (typography-theme
   #:id 'lecture
   #:extends animate-typography-theme
   #:styles
   (hash 'title
         (text-style-update (typography-ref animate-typography-theme 'title)
                            #:font-family 'roman
                            #:font-size 1))))
]

Themes may also add a named style such as @racket['theorem-heading]. Use it
with @racket[styled-text]. A semantic constructor may override one property
without losing its role:

@racketblock[
(body-text "A one-off note" #:id 'note #:font-style 'italic)
(styled-text "Theorem" #:style 'theorem-heading #:id 'theorem-title)
]

The inspector shows the authored role, inherited and explicit properties, and
the style resolved from the selected typography snapshot.

@section{Treatments and animation}

A @racket[text-treatment] can add a background, border, and em-sized padding.
The original text anchor stays fixed while padding expands around it. In a
@racket[typewrite] effect, a semantic treatment box stays present while glyphs
are progressively revealed; it does not resize for every character. The exact
end of a text effect remains the original semantic text value, not a
font-resolved proxy. Linear and radial background paints use the text anchor
as their local origin, just like paints on shapes. The border is a cosmetic
output-pixel width, so making text larger does not make its outline thicker.
The Pict renderer currently draws checker backgrounds as device-aligned tiles,
so a checker does not yet fully follow text scaling or rotation.

@section{Migration cookbook}

@tabular[#:sep @hspace[2]
 (list (list @bold{Before} @bold{After})
       (list @racket[(plain-text "Chapter" #:id 'chapter
                                #:font-family 'swiss #:font-weight 'bold)]
             @racket[(title-text "Chapter" #:id 'chapter)])
       (list @racket[(paragraph explanation #:id 'body #:font-size 2/5)]
             @racket[(body-text explanation #:id 'body)])
       (list @racket[(plain-text "small note" #:id 'note #:font-size 1/4)]
             @racket[(annotation-text "small note" #:id 'note)])
       (list @racket[(paragraph source #:id 'code #:font-family 'modern)]
             @racket[(code-text source #:id 'code)]))]

Do not mechanically convert every raw text value. Axis ticks, numeric displays,
and imported SVG text have their own purposes and are intentionally left for
separate migrations.
