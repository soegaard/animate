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
@title[#:tag "ref-visuals-formula-parts"]{Formula Assemblies and Named Parts}


@declare-exporting[animate/main]


A @racket[formula-assembly] stores manually placed, named formula parts.
Use @racket[formula-select] to obtain a part's scene path, styling operations
to change selected parts immutably, and a @racket[formula-correspondence] to
record a mapping between endpoint assemblies. Joint TeX layout is documented
separately in @secref["tagged-formulas"].

See also @secref["ref-visuals-formulas"], @secref["ref-visuals-formula-matching"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "formula-parts"]{Named Formula Parts and Correspondence}

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

@; visuals-reference-r1 example: formula-parts-1
A selected named part is an ordinary nested scene path.

@examples[#:eval reference-eval
  (define equation
    (formula-assembly
     (list (latex-formula-part "x" #:name 'x))
     #:id 'equation))
  (eval:check (formula-select equation 'x) '(equation x))
]


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

@(close-eval reference-eval)
