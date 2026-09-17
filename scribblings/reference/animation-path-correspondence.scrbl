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

@title[#:tag "reference-animation-path-correspondence"]{Matching compound path outlines}

These lower-level operations choose correspondence between path outlines.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(morph-to-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-aligned-request?]{

Creates a closed-loop path morph that first calls
@racket[path-geometry-align-for-morph] on the target's current path and
@racket[destination], then applies the existing
@racket[path-geometry-normalize-for-morph] preparation to the aligned pair.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Both source and destination must each contain exactly one
positive finite closed subpath. @racket[allow-reverse?] and
@racket[sample-count] have the same meaning as for
@racket[path-geometry-align-for-morph].

At interior eased progress values, interpolation uses the automatically aligned
and normalized destination. At eased progress zero, the exact original source
path is used. At eased progress one, the exact @emph{requested}
@racket[destination] object is used, not the phase-shifted or reversed internal
working representation. The endpoint therefore preserves caller-requested
semantic storage while the visible closed loop has the correspondence selected
for the interior morph.

The request changes the path-geometry component. It may run simultaneously
with movement, rotation, scaling, or opacity changes, and conflicts with strict,
normalized, or another aligned morph plus @racket[create] and
@racket[uncreate] on the same target. Like the other morph requests, it follows
the easing result and has no structural endpoint override.
}

@defproc[(morph-to-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-aligned].
}

@defproc[(morph-to-open-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-open-aligned-request?]{

Creates an open-path morph that first calls
@racket[path-geometry-align-open-for-morph] on the target's current path and
@racket[destination], then applies @racket[path-geometry-normalize-for-morph]
to the direction-aligned pair.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must each contain exactly one
positive finite open subpath. @racket[allow-reverse?] and @racket[sample-count]
have the same meanings as for @racket[path-geometry-align-open-for-morph].

Interior eased progress uses the selected endpoint direction and normalized
geometry. Eased progress zero uses the exact clip-start source path. Eased
progress one installs the exact caller-requested @racket[destination] object,
including its original stored direction. Direction selection is therefore an
interior correspondence choice rather than an endpoint rewrite.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, closed-loop aligned, compound-aligned, another open-aligned morph,
@racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-open-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-open-aligned].
}

@defproc[(morph-to-open-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-open-compound-aligned-request?]{

Creates an equal-count open-compound morph that first calls
@racket[path-geometry-align-open-compound-for-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the globally paired and
direction-aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must contain the same nonzero number
of positive finite open subpaths. @racket[allow-reverse?] and
@racket[sample-count] have the same meanings as for
@racket[path-geometry-align-open-compound-for-morph].

Interior eased progress uses global subpath pairing, per-pair endpoint direction,
and normalized geometry. Eased progress zero uses the exact clip-start source
path. Eased progress one installs the exact caller-requested
@racket[destination] object, including its original subpath order and stored
traversal directions. Pairing and reversal are therefore interior correspondence
choices rather than endpoint rewrites.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, closed-compound aligned, another open-compound
aligned morph, @racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-open-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-open-compound-aligned].
}

@defproc[(morph-to-mixed-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-mixed-compound-aligned-request?]{

Creates a topology-aware compound morph that first calls
@racket[path-geometry-align-mixed-compound-for-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the reordered/aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must be nonempty positive-finite
compound paths with matching counts of open subpaths and matching counts of
closed subpaths. @racket[allow-reverse?] and @racket[sample-count] have the same
meaning as for @racket[path-geometry-align-mixed-compound-for-morph].

Interior eased progress uses topology-class global pairing, per-open endpoint
direction, per-closed phase/direction, and normalized geometry. Eased progress
zero uses the exact clip-start source. Eased progress one installs the exact
caller-requested @racket[destination] object, including its original interleaving,
subpath order, and stored traversal representations.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, open-compound aligned, closed-compound aligned,
another mixed-compound aligned morph, @racket[create], or @racket[uncreate] on
the same target.
}

@defproc[(morph-to-mixed-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-mixed-compound-aligned].
}

@defproc[(morph-to-topology-changing
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64]
          [#:birth-anchor birth-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:death-anchor death-anchor (or/c symbol? vec2?) 'bounds-center]
          [#:birth-anchor-map birth-anchor-map hash? #hash()]
          [#:death-anchor-map death-anchor-map hash? #hash()]
          [#:birth-penalty birth-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:death-penalty death-penalty (or/c symbol? (and/c finite-real? (>=/c 0))) 'forced]
          [#:birth-penalty-map birth-penalty-map hash? #hash()]
          [#:death-penalty-map death-penalty-map hash? #hash()]
          [#:match-penalty-map match-penalty-map hash? #hash()])
         morph-to-topology-changing-request?]{

Creates a topology-aware normalized morph that permits open/closed subpath count
changes. When @racket[scene-play] compiles the request, it calls
@racket[path-geometry-prepare-topology-changing-morph] on the target's current
path and @racket[destination], then applies
@racket[path-geometry-normalize-for-morph] to the two prepared equal-count
paths.

Matched real open/closed subpaths use the same correspondence rules as SCENE-AG.
Unmatched destination subpaths grow from deterministic degenerate bounds-center
seeds by default, while unmatched source subpaths collapse to their own
bounds-center seeds. @racket[birth-anchor] and @racket[death-anchor] may instead
be explicit finite local @racket[vec2] values shared by all unmatched subpaths on
the corresponding side. SCENE-AK's @racket[birth-anchor-map] and
@racket[death-anchor-map] may sparsely override those shared values by original
destination/source subpath index. Missing keys inherit the shared anchor and an
explicit @racket['bounds-center] entry opts that subpath back into its own center.
The request snapshots both hashes immutably; index range is checked against the
actual clip-start source and caller destination when the request is compiled. By
default @racket[birth-penalty] and @racket[death-penalty] are both
@racket['forced], preserving SCENE-AH/AI matching. Supplying both as finite
nonnegative real costs enables SCENE-AJ voluntary death+birth replacement when
that lowers the global correspondence cost; exact cost ties prefer fewer topology
changes. SCENE-AL's @racket[birth-penalty-map] and
@racket[death-penalty-map] may sparsely override those shared numeric costs by
original destination/source subpath index. Missing keys inherit the shared cost.
The request snapshots both endpoint penalty maps immutably, and nonempty endpoint
maps require numeric shared penalty mode. SCENE-AM's @racket[match-penalty-map]
may be used in either forced or numeric mode. Its keys are
@racket[(cons source-index destination-index)] pairs in original caller storage
order and its finite nonnegative values add to real-edge geometric scores only.
The request snapshots this map immutably as well. Pair-key range and topology
validation occurs when the request is compiled against the clip-start source and
stored destination. Empty source or destination geometry is legal; any real
subpath that is present must have positive finite arc length.

Interior eased progress uses the prepared/normalized geometry. Eased progress
zero uses the exact clip-start source path, with no synthetic birth slots
present. Eased progress one installs the exact caller-requested
@racket[destination], with no synthetic death slots present. Birth/death seeds,
reordering, reversal, and closed-loop phase are therefore interior
correspondence only.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation and conflicts with strict,
normalized, aligned, compound-aligned, another topology-changing morph,
@racket[create], or @racket[uncreate] on the same target.
}

@defproc[(morph-to-topology-changing-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-topology-changing].
}

@defproc[(morph-to-compound-aligned
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         morph-to-compound-aligned-request?]{

Creates a compound closed-path morph that first calls
@racket[path-geometry-align-compound-for-morph] on the target's current path and
@racket[destination], then applies @racket[path-geometry-normalize-for-morph]
to the paired/aligned geometry.

The target must be a present built-in path Visual when @racket[scene-play]
compiles the request. Source and destination must have the same nonzero number
of positive finite closed subpaths. @racket[allow-reverse?] and
@racket[sample-count] have the same meaning as for
@racket[path-geometry-align-compound-for-morph].

Interior eased progress uses globally paired, phase/direction-aligned, normalized
geometry. Eased progress zero uses the exact clip-start source path. Eased
progress one uses the exact caller-requested @racket[destination] object,
including its original subpath order and storage representation. Pairing is
therefore an interior correspondence choice rather than an endpoint rewrite.

The request changes the ordinary path-geometry component. It may compose with
movement, rotation, scaling, or opacity animation, and conflicts with strict,
normalized, one-loop aligned, another compound-aligned morph, @racket[create],
or @racket[uncreate] on the same target.
}

@defproc[(morph-to-compound-aligned-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-compound-aligned].
}
