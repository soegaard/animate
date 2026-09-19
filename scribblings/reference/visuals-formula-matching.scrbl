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
@title[#:tag "ref-visuals-formula-matching"]{Formula Source Selection and Matching}


@declare-exporting[animate/main]


Source queries address retained TeX character ranges, named matches
address formula parts, and glyph matching addresses rendered outlines. None
of these APIs proves algebraic equivalence. Use selectors for lookup, a plan
for inspection, and a transition request for animation; the sections below
keep those roles separate.

See also @secref["ref-visuals-formulas"], @secref["ref-visuals-formula-parts"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "source-addressable-formulas"]{Source-Addressable Formulas}

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

@; visuals-reference-r1 example: formula-matching-1
Selector descriptions are model data; they do not typeset a formula.

@examples[#:eval reference-eval
  (eval:check (source-selector? (source-span 2 5)) #t)
  (eval:check (source-selector? (source-occurrence "x" 1)) #t)
]


@defproc[(formula-source-match? [value any/c]) boolean?]{
Recognizes one immutable source-map unit. Its source span, canonical text,
stable name, and mapped leaf paths can be inspected with the corresponding
accessors.
}

@defstruct*[visual-selection ([root visual-path?]
                              [paths (listof list?)])
  #:transparent]{An immutable root-relative selection of existing Visual
leaves. Each member of @racket[paths] is a relative path of symbols below
@racket[root]. Selections describe semantic paths; they are not synthetic
group Visuals.}

@subsection[#:tag "ref-visuals-formula-matching-lookup-1"]{Querying Retained Source}

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

@subsection[#:tag "ref-visuals-formula-matching-lookup-2"]{Planning String Correspondences}

@defproc[(plan-matching-strings [source formula-assembly-visual?]
                                [destination formula-assembly-visual?]
                                [#:matches matches (listof string-match?) '()]
                                [#:copies copies (listof formula-string-copy?) '()])
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
                       [#:mode mode (or/c 'auto 'rigid 'glyphwise 'cross-fade) 'auto]
                       [#:appearance-complete-at-x appearance-complete-at-x
                        (or/c #f source-selector?) #f]
                       [#:appearance-duration appearance-duration
                        (or/c #f (and/c finite-real? positive? (<=/c 1))) #f])
         string-match?]{
Declares one source-addressed correspondence. Explicit declarations take
priority over automatic normalized-source matching.

When both appearance keywords are supplied, the part keeps its ordinary route,
but its changed appearance completes when that route first reaches the current
x-coordinate of @racket[appearance-complete-at-x]. The duration is a fraction
of the enclosing transition: the old and new appearances cross-fade only in
the interval immediately preceding that deadline. This is useful for a moving
@tt{+} that should become @tt{-} exactly as it passes an equality sign.
}

@defproc[(formula-string-copy [source source-selector?]
                              [destination source-selector?]
                              [#:route route (or/c #f formula-route?) #f]
                              [#:mode mode (or/c 'auto 'rigid 'glyphwise 'cross-fade) 'auto])
         formula-string-copy?]{
Declares a moving copy: the source remains present while an otherwise unmatched
destination is introduced. Its @racket[formula-] prefix avoids colliding with
@racketmodname[racket/base]'s @racket[string-copy].
}

@defproc[(string-match? [value any/c]) boolean?]{Recognizes an explicit string correspondence.}
@defproc[(formula-string-copy? [value any/c]) boolean?]{
Recognizes an explicit source-addressed formula string copy.
}
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
          [#:copies copies (listof formula-string-copy?) '()]
          [#:on-ambiguity on-ambiguity (or/c 'left-to-right 'error) 'left-to-right]
          [#:path-arc path-arc finite-real? 0]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade])
         transform-formula-parts-request?]{

Plans source-addressed formula correspondences then compiles them into the
normal deterministic formula transition. It matches source structure, not
algebraic meaning or arbitrary rendered glyph similarity. The compiled plan is
retained for the preview String matching inspector.
}

@subsection[#:tag "ref-visuals-formula-matching-lookup-3"]{Part Routes and Copies}

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

@subsection[#:tag "ref-visuals-formula-matching-lookup-4"]{Generated SVG Fragments}

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

@subsection[#:tag "ref-visuals-formula-matching-lookup-5"]{Part and Glyph Transitions}

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

@subsection[#:tag "ref-visuals-formula-matching-lookup-6"]{Anchored Rewrites}

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

@subsection[#:tag "ref-visuals-formula-matching-lookup-7"]{Derivation Steps}

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

@(close-eval reference-eval)
