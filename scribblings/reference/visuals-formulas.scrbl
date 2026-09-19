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
@title[#:tag "ref-visuals-formulas"]{Formula Construction and Layout}


@declare-exporting[animate/main]


Choose @racket[latex-formula] for one formula model value,
@racket[tagged-formula] for named fragments laid out together,
@racket[math-tex] for source-addressable construction, or @racket[glyph-tex]
for rendered glyph leaves. Jointly typeset constructors run the external TeX
and SVG tools during construction; plain LaTeX model construction does not.
For manual part placement, see @secref["formula-parts"].

See also @secref["ref-visuals-formula-parts"], @secref["ref-visuals-formula-matching"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "formula-visuals"]{LaTeX Formula Visuals}

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

Generic lines, paths, and ordinary shape outlines use semantic axis ink by
default; an explicit @racket["black"] remains literal black in every theme.
Formula source is different: raw TeX and imported SVG can contain an author's
own black or multicolour paint, and the adapters cannot reliably distinguish
that from implicit default ink without altering the artifact. They therefore
preserve unstyled formula paint. Use the explicit formula styling operations
with @racket[theme-foreground] when a formula must follow a theme; selected
formula parts continue to preserve all other source paint.

Rendering a nonempty formula requires the @racketmodname[latex-pict] package,
a working @tt{pdflatex}, Poppler, the requested document class, and every
package named by the preamble. Model construction, scene sampling, and empty
formula rendering do not run TeX. Exact output depends on those external tools
and their installed versions. Formula source and preamble are trusted input;
this library does not sandbox the TeX process.
}

@subsection[#:tag "ref-visuals-formulas-lookup-1"]{Inspecting and Updating Formula Models}

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

@; visuals-reference-r1 example: formulas-1
These model operations do not invoke TeX.

@examples[#:eval reference-eval
  (define original (latex-formula "x^2" #:id 'power))
  (define revised (formula-visual-with-source original "x^3"))
  (eval:check (formula-visual-source original) "x^2")
  (eval:check (formula-visual-source revised) "x^3")
]



@section[#:tag "tagged-formulas"]{Tagged Formula Layouts}

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

@section{Making @tt{latex-pict} Available}

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

@(close-eval reference-eval)
