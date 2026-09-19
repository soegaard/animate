#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "reference-animation-text"]{Writing and transforming text and formulas}

Use text- and formula-aware operations instead of guessing generic shape matches.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(typewrite
          [visual text-visual?]
          [#:unit unit (or/c 'grapheme 'run 'line 'span) 'grapheme]
          [#:cursor? cursor? boolean? #f]
          [#:cursor-style cursor-style (or/c #f color-spec?) #f])
         typewrite-request?]{

Introduces an absent @racket[text-visual?] by advancing a discrete semantic
front. The source is always retained as one immutable final layout; partial
samples clip that final shaped presentation instead of creating shorter text
prefixes. Thus a seek is a direct function of the requested clip time and the
endpoint restores the authored @racket[visual] exactly.

@racket[#:unit] controls whether the front advances by Unicode grapheme,
whitespace-preserving run, line, or rich-text span intervals. @racket['run]
means maximal whitespace/non-whitespace source runs; it is not Unicode word
segmentation, and @racket['word] is reserved for a future real word-boundary
mode. A renderer must
be able to associate those intervals with stable shaped fragments. The current
Pict renderer prepares one frozen whole layout for every text Visual, but it
exposes exact fragment masks only for a conservative unwrapped, single-run LTR
subset. It reports a contract error for interior partial samples of rich or
wrapped text, transformed text, bidirectional or complex-script text, and
common ligature/kerning-sensitive sequences. This deliberate refusal prevents
incorrect prefix re-layout or rectangular masks from being represented as exact
shaping. Exact start and final samples remain valid for every
@racket[text-visual?]. A future shaped-layout backend may advertise broader
fragment-mask capabilities.

With @racket[#:cursor? #t], the renderer adds a clip-local cursor at the
prepared-layout reveal frontier. @racket[#:cursor-style] selects its colour;
@racket[#f] uses the source text colour. The cursor is presentation only: it
does not add a scene Visual or cache entry, and it is absent at the exact final
sample that restores @racket[visual].
}

@defproc[(typewrite-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[typewrite].
}

@defproc[(erase-text
          [target (or/c text-visual? symbol? visual-path?)]
          [#:unit unit (or/c 'grapheme 'run 'line 'span) 'grapheme]
          [#:cursor? cursor? boolean? #f]
          [#:cursor-style cursor-style (or/c #f color-spec?) #f])
         erase-text-request?]{

Removes a present text Visual by moving the same discrete stable-layout front
in reverse. The exact source remains visible at local progress zero; the target
is removed at the exact endpoint, so no empty text Visual remains. Symbol and
path targets are resolved at the leaf's local clip start and must then identify
a @racket[text-visual?]. The renderer capability rule for interior partial
states is the same as @racket[typewrite].

@racket[#:cursor?] and @racket[#:cursor-style] have the same presentation
meaning as for @racket[typewrite]. The exact initial source and exact removal
endpoint do not contain a cursor; it appears only while an erasure has an
interior partial text state.
}

@defproc[(erase-text-request? [value any/c]) boolean?]{
Recognizes a request created by @racket[erase-text].
}

@defproc[(transform-formula-parts
          [correspondence formula-correspondence?])
         transform-formula-parts-request?]{

Creates a request that transforms the named parts described by
@racket[correspondence].

The identity of @racket[(formula-correspondence-source correspondence)] is the
top-level scene target. That identity must already name a
@racket[formula-assembly-visual] when @racket[scene-play] compiles the request.
The current assembly must have exactly the same local part names, in the same
order, as the correspondence source. The actual current formulas, local
transforms, and local opacities are used as the source values. This allows an
earlier clip to change those values before this request is compiled.

The correspondence destination is a part-layout template. Its exact ordered
part list becomes the structural endpoint. Its top-level identity, reference
position, rotation, scale, and opacity are not copied. The current source
assembly keeps those outer values unless simultaneous requests change them.

For every explicit match, the local translation, rotation, and x/y scale are
interpolated from the current source formula to the destination formula. The
part opacity is also interpolated.

A matched pair uses one moving layer when these typesetting values are equal:

@itemlist[
 @item{LaTeX source;}
 @item{formula mode and semantic font size;}
 @item{preamble;}
 @item{ordered document-class options and Preview-package options;}
 @item{horizontal and vertical anchor choices.}
]

Identity, local transform, and local opacity are not part of that equality
test. When one of the listed typesetting values differs, two layers move along
the same transform interpolation: the current source layer fades to zero, and
the destination layer fades in from zero. This is a moving cross-fade. The
library does not morph glyph outlines or TeX boxes.

An unmatched source part remains at its current local transform and fades to
zero. An unmatched destination part remains at its destination local transform
and fades in from zero.

Interior drawing order is deterministic:

@itemlist[#:style 'ordered
 @item{unmatched source parts in source part order;}
 @item{matched layers in explicit correspondence-match order;}
 @item{unmatched destination parts in destination part order.}
]

A changed matched pair contributes its source layer immediately before its
destination layer. Interior layers receive deterministic temporary local names
beginning with @tt{__formula-transition-}. The allocator avoids the top-level
assembly identity and every source and destination part name. Exact endpoint
samples use the original endpoint names, not the temporary names.

At eased progress zero, the exact current source part list is used. At interior
progress, the temporary layers are used. At structural completion, the exact
destination part list is installed even when the easing procedure does not map
one to one. Such an easing procedure can therefore cause a discontinuity at the
clip boundary.

The request may run simultaneously with @racket[move-to], rotation, scale, and
@racket[fade-to] requests for the same assembly because those operations change
separate components. It conflicts with another formula-part transformation.
It also reserves the presence component, so it conflicts with same-target
@racket[fade-in], @racket[fade-out], @racket[create], and @racket[uncreate].
Those operations add or remove the top-level identity, and combining their
structural endpoints would otherwise make completion order significant.

An empty source assembly, empty destination assembly, and empty match list form
a valid transformation.
}

@defproc[(transform-formula-parts-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[transform-formula-parts].
}

@defproc[(write-in
          [visual visual?]
          [#:order order (or/c 'document 'left-to-right) 'document]
          [#:lag-ratio lag-ratio (or/c #f nonnegative-real?) #f]
          [#:outline-stroke-width outline-stroke-width nonnegative-real? 2]
          [#:reveal reveal (or/c 'bezier 'arc-length) 'bezier]
          [#:reverse? reverse? boolean? #f]
          [#:rate-func rate-func (-> finite-real? finite-real?) linear])
         write-in-request?]{

Creates a Manim-like vector introduction for @racket[visual]. Every writable
path leaf first appears as a progressively traced outline. In the second half
of its local interval, the full outline transitions to the leaf's final fill,
stroke, and cosmetic stroke width. Path leaves overlap by a small default
stagger, @racket[(min 1/5 (/ 4 N))] for @racket[N] leaves. Pass
@racket[#:lag-ratio] to select another nonnegative overlap ratio.

The default @racket['bezier] reveal gives every ordered line or Bézier segment
equal writing time, matching Manim's partial-@tt{VMobject} behavior.
@racket['arc-length] retains constant-speed geometric progress as an explicit
alternative. @racket[#:reverse? #t] writes both leaves and their path traversal
in reverse. The scene easing and @racket[#:rate-func] are applied to each leaf
after its stagger offset, so nonlinear easing does not delay the start of later
leaves.

@racket['document] follows group/SVG path order. @racket['left-to-right] sorts
the path leaves by their resolved horizontal position before calculating the
same stagger. The supplied Visual must be absent from the scene at the clip
start. The endpoint is installed exactly as supplied, so semantic SVG circles
and rectangles, and tagged formula fragments rendered through their normal SVG
renderer, are restored without a proxy representation at completion.

Built-in path Visuals, groups whose leaves are writable, circles, rectangles,
and @racket[tagged-formula] assemblies are supported. Tagged formulas expand
dvisvgm's local glyph-path @tt{<defs>} and @tt{<use>} references only while the
request is constructed; sampling and rendering the clip never invoke TeX.
Arbitrary renderer Visuals, gradients, masks, filters, and SVG text are not
writable. The request reserves all target Visual components, so it cannot run
simultaneously with another same-target Visual animation.

The name is @racket[write-in], rather than @racket[write], so requiring the
library does not shadow Racket's ordinary output procedure.
}

@defproc[(unwrite
          [target (or/c visual? symbol? visual-path?)]
          [#:order order (or/c 'document 'left-to-right) 'document]
          [#:lag-ratio lag-ratio (or/c #f nonnegative-real?) #f]
          [#:outline-stroke-width outline-stroke-width nonnegative-real? 2]
          [#:rate-func rate-func (-> finite-real? finite-real?) linear])
         unwrite-request?]{

Removes a writable Visual already present in the scene. Its leaves and path
traversal are processed in reverse order; the endpoint structurally removes the
target. The current scene Visual supplies the writing proxy, so an @racket[unwrite]
uses the current geometry and style rather than a stale caller copy.
}

@defproc[(write-in-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[write-in].
}

@defproc[(unwrite-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[unwrite].
}

@section[#:tag "ref-animation-text-s01"]{Serializable Rate Functions}

Built-in easings are represented as transparent callable values. A
@racket[rate-function?] can therefore be supplied anywhere a one-argument
easing procedure is accepted, while its kind and parameters remain part of
the scene's serializable representation. Arbitrary one-argument procedures
remain supported; they are intentionally opaque to automatic authoring caches.

@defproc[(formula-part-targets [formula formula-assembly-visual?]
                               [selections (or/c list? vector?)])
         target-sequence?]{
Describes formula-part selections rooted at @racket[formula]. A selection with
multiple leaves produces one @racket[target-ref] per leaf; every reference
retains the originating semantic selection metadata.
}

@defproc[(reveal-formula-parts
          [formula formula-assembly-visual?]
          [selections (or/c list? vector?)]
          [make-request procedure?]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward]
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1/5])
         any/c]{

Creates a deferred formula target sequence and maps @racket[make-request]
over its local-start snapshot through @racket[stagger-map]. A selection
may be a named formula part symbol, a complete visual path beginning with the
supplied formula identity, or a nonempty root-relative @racket[visual-selection]
rooted at that formula. The template receives one @racket[target-ref?]; use
@racket[target-ref-path] for the resolved target and the other accessors for
source/scheduled indexes and formula-selection metadata.

This helper deliberately chooses no effect by name. For example, an author can
make an ordinary semantic formula-part cascade with:

@racketblock[
(reveal-formula-parts equation
                      '(x equals two)
                      (lambda (reference)
                        (indicate (target-ref-path reference) #:color "gold"))
                      #:lag-ratio 1/5)]

All normal target validation, timing, conflict checking, and random-access
sampling rules are inherited from the concrete requests returned by the template.
}
