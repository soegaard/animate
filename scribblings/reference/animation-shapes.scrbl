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

@title[#:tag "reference-animation-shapes"]{Replacing and matching shapes}

Replace objects or match the leaves of groups.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(transform-shape
          [source (or/c visual? symbol?)]
          [destination (and/c visual? affine-visual? opacity-visual?)]
          [#:mode mode (or/c 'auto 'morph 'cross-fade) 'auto]
          [#:correspondence correspondence (or/c 'auto 'perimeter 'path) 'auto]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         transform-shape-request?]{

Replaces the present top-level Visual named by @racket[source] with the fresh
top-level @racket[destination]. The source and destination identities must be
distinct; the source must be present, and the destination identity must be
absent, when @racket[scene-play] compiles the request. Both endpoints require
affine placement and global opacity. A nested @racket[visual-path?] is not
accepted because this operation removes the source structural identity at the
clip boundary.

The default @racket['auto] first tries a geometric transition when each endpoint
is one built-in @racket[path-visual?], @racket[circle-visual?], or
@racket[rectangle-visual?]. Circle/rectangle pairs use a canonical
eight-segment perimeter: both start at their right midpoint and correspond at
the cardinal and diagonal positions. This produces an evenly rounded
square-to-circle interior. Pass @racket['perimeter] to require that primitive
correspondence, or @racket['path] to use only the general stored-path policy.
Other geometric pairs use automatic topology-class pairing, including
closed-loop phase/direction and open-path direction; when counts differ, they
try deterministic birth/death preparation. The source and destination styles
are alpha layers over the same intermediate outline, so a fill/stroke change
fades naturally while the geometry moves. Their transforms are interpolated too.

If either endpoint is a group, image, text, formula, SVG tree, custom Visual,
or atomic geometry that cannot be prepared safely, @racket['auto] keeps the
exact endpoint trees and cross-fades them at their own positions. This is a
deliberate graceful fallback: it does not flatten a group or manufacture a
semantic mapping between its children. @racket['morph] requires the geometric
case and raises an exception otherwise. @racket['cross-fade] always selects the
fallback and ignores the correspondence controls.

At exact start, the source is unchanged. At interior samples it is hidden and a
temporary frontmost layer is drawn. At structural completion, regardless of the
easing result, the source is removed and the exact caller-supplied destination
Visual is installed. Temporary path conversions and normalized outlines are
therefore never retained in later clips.

The operation reserves all ordinary Visual components and presence for both
source and destination identities. It cannot be combined in one play clip with
another animation of either endpoint.
}

@defproc[(transform-shape-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[transform-shape].
}

@defproc[(transform-matching-visuals
          [source visual?]
          [destination (and/c visual? affine-visual? opacity-visual?)]
          [#:matches matches (listof visual-match?) '()]
          [#:mode mode (or/c 'auto 'morph 'cross-fade) 'auto]
          [#:mismatch-mode mismatch-mode (or/c 'fade 'fade-transform) 'fade]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count (and/c exact-integer? (>=/c 8)) 64])
         transform-matching-visuals-request?]{

Replaces the present top-level @racket[source] root with the fresh top-level
@racket[destination] root. The root identities must differ. At compilation, the
current source root is flattened through ordinary @racket[group] transforms
into leaf paths. The matching order is: explicit @racket[visual-match] pairs,
equal relative leaf paths, exact built-in path/circle/rectangle type and style,
identical local shape fingerprints, then nearest remaining compatible shape
geometry. This is deterministic and every leaf participates at most once.

For a matched path, circle, or rectangle that can use the existing
topology-aware outline preparation, @racket['auto] shares an intermediate
geometric morph. Other matched affine/opacity leaves move through an
interpolated affine transform while their source/destination content cross-fades.
Unmatched leaves fade in place; @racket['fade-transform] pairs the remaining
leaves by nearest position to give them the same moving cross-fade. Pass
@racket['morph] to require every matched pair to have geometric correspondence,
or @racket['cross-fade] to disable all geometric morphs.

This first general matcher is intentionally conservative. It does not infer
semantic matches for arbitrary SVG/text/custom leaves after renaming, preserve
one leaf through a split or merge, resolve occlusion/collisions, or replace the
formula APIs' TeX/glyph correspondence. At exact start the source is unchanged;
interior samples use a temporary frontmost overlay; at the clip boundary the
exact destination root is installed.
}

@defproc[(transform-matching-visuals-request? [value any/c]) boolean?]{

Recognizes a request created by @racket[transform-matching-visuals].
}
