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
@title[#:tag "ref-visuals-numeric"]{Numbers and Units}


@declare-exporting[animate/main]


The @racket[format-integer], @racket[format-decimal], and related formatters
return strings. Numeric label constructors return text Visuals. Live displays
instead read a scene value when sampled. Units are display data, not a
physical-dimension calculation system.

See also @secref["ref-visuals-text"], @secref["ref-visuals-relations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "numeric-displays"]{Numeric Displays}

Numeric displays provide number-shaped text and numerical transitions without
introducing a mutable value tracker. Static constructors return ordinary
@racket[text-visual?] values. @racket[parameter-display] and
@racket[rolling-number-display] format the current scalar scene parameter
independently at each sampled frame. Both are fixed-structure
@racket[relation-visual?] values with an explicit scalar dependency.

@defproc[(numeric-display-anchor? [value any/c]) boolean?]{

Recognizes @racket['left], @racket['center], @racket['right],
@racket['decimal], and @racket['sign].
}

@subsection[#:tag "ref-visuals-numeric-lookup-1"]{Formatting Strings and Units}

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

@; visuals-reference-r1 example: numeric-1
Formatting is independent of text rendering.

@examples[#:eval reference-eval
  (eval:check (format-integer -1234567 #:grouping? #t) "-1,234,567")
  (eval:check (format-decimal 5 #:decimal-places 2) "5.00")
]


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

@; visuals-reference-r1 example: numeric-2
Unit factors preserve their declared order.

@examples[#:eval reference-eval
  (eval:check
   (format-unit (unit-product (unit "m") (unit "s" #:power -2)))
   "m·s⁻²")
]


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

@subsection[#:tag "ref-visuals-numeric-lookup-2"]{Static Numeric Visuals}

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
The explicit @racket[#:kind] choices select the corresponding formatter.
}

@subsection[#:tag "ref-visuals-numeric-lookup-3"]{Parameter-Driven Displays}

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
decimal point. They are separate text runs, so kerning is not attempted across that join.
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

@(close-eval reference-eval)
