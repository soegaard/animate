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


@title[#:tag "cookbook-topology-morph-recipes"]{Growing and Removing Subpaths}

Control where unmatched subpaths grow or collapse and how the correspondence algorithm weighs replacement.

API reference: @secref["reference-animation-path-correspondence"], @secref["path-geometry"].

@local-table-of-contents[]

@; recipe-redistribution begin: topology-changing-morphs
@section[#:tag "topology-changing-morphs"]{Topology-Changing Morphs and Subpath Birth/Death}

Topology-changing morph preparation supports compounds whose open or closed
subpath counts differ. Prepare explicit interior geometry with:

@racketblock[
(define-values (prepared-source prepared-destination)
  (path-geometry-prepare-topology-changing-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph
   prepared-source prepared-destination))
]

Real open and closed subpaths are matched independently with the correspondence
open-path and closed-loop correspondence rules. Under the default forced-only policy, if
one class has extra real subpaths, only the forced count difference is unmatched.
A born subpath grows from a one-segment degenerate seed at its destination bounds
center; a dying subpath collapses to an analogous seed at its source bounds
center. Explicit local anchor points can override that placement without
changing the default, and numeric penalties can permit additional voluntary
unmatched slots.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-topology-changing panel destination)
            #:duration 3)
]

Prepared birth/death slots exist only in interior normalized geometry. Eased
progress zero is the exact source object and eased progress one is the exact
caller destination, so endpoint subpath counts and ordering remain exact.

Render the canonical example with:

@verbatim{
racket examples/topology-changing-morphs.rkt \
  frames/topology-changing-morphs \
  topology-changing-morphs.mp4

open topology-changing-morphs.mp4
}

The surviving open and closed paths visibly change shape, one unmatched open
curve collapses, and one unmatched closed loop grows. Destination storage also
scrambles surviving direction/phase so automatic correspondence remains visible
in the same movie.



@; recipe-redistribution end: topology-changing-morphs

@; recipe-redistribution begin: explicit-topology-morph-anchors
@section[#:tag "explicit-topology-morph-anchors"]{Explicit Birth/Death Anchors}

The @racket[#:birth-anchor] and @racket[#:death-anchor] options make seed
placement configurable while leaving correspondence policy unchanged. Bounds-center behavior remains the default. To use one local
hub for both sides:

@racketblock[
(define hub (vec2 0 0))

(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-anchor hub
             #:death-anchor hub)
            #:duration 3)
]

An explicit anchor is a point in the path Visual's local coordinate system. The
Visual's translation, rotation, and scale apply afterward. The anchor is used
only for unmatched subpaths; matched real correspondence remains governed by
the open/closed geometric scoring and the existing topology-class assignments.

The only symbolic value accepted by either keyword is @racket['bounds-center].
Each side has one shared anchor point. Numeric penalties may create additional
voluntary unmatched slots. Sparse per-subpath anchor overrides select individual
seed positions, while sparse numeric cost overrides independently influence
which subpaths become unmatched.

Render the canonical example with:

@verbatim{
racket examples/anchored-topology-changing-morphs.rkt \
  frames/anchored-topology-changing-morphs \
  anchored-topology-changing-morphs.mp4

open anchored-topology-changing-morphs.mp4
}

The movie marks the explicit hub with a red diamond. One lower curve collapses
into that hub while a new lower loop grows from it; a surviving upper curve
visibly morphs at the same time.



@; recipe-redistribution end: explicit-topology-morph-anchors

@; recipe-redistribution begin: per-subpath-topology-morph-anchors
@section[#:tag "per-subpath-topology-morph-anchors"]{Per-Subpath Birth/Death Anchors}

The per-subpath anchor maps keep the shared anchors as fallbacks and add sparse
overrides for individual endpoint subpaths:

@racketblock[
(define left-hub (vec2 -5 -1))
(define right-hub (vec2 5 -1))

(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-anchor origin
             #:death-anchor origin
             #:birth-anchor-map (hash 1 left-hub 2 right-hub)
             #:death-anchor-map (hash 1 left-hub 2 right-hub))
            #:duration 3)
]

A birth-map key names the exact original subpath index in the caller's
@racket[destination]. A death-map key names the exact original subpath index in
the clip-start source path. Topology partitioning, global assignment, source-order
reconstruction, destination reversal, and closed-loop phase alignment do not
change those key meanings.

Each map value is either @racket['bounds-center] or a finite local @racket[vec2].
If a key is absent, the corresponding shared @racket[birth-anchor] or
@racket[death-anchor] is used. An explicit @racket['bounds-center] entry therefore
lets one subpath use its own center even when the shared fallback is a custom hub.
Matched real subpaths ignore anchor maps.

The same lookup applies to voluntary unmatched slots selected by numeric penalties. Anchor maps never alter real-pair costs or assignment policy.
Timeline requests copy the maps into immutable hashes when the request is
constructed, so later mutation of the caller's input hash has no effect. Direct
geometry preparation validates key ranges immediately; request compilation checks
them against the clip-start source and stored destination.

Render the canonical example with:

@verbatim{
racket examples/per-subpath-topology-anchors.rkt \
  frames/per-subpath-topology-anchors \
  per-subpath-topology-anchors.mp4

open per-subpath-topology-anchors.mp4
}

The two lower source paths collapse into separate marked hubs while two new
closed loops grow from those corresponding hubs. A surviving upper curve morphs
at the same time.



@; recipe-redistribution end: per-subpath-topology-morph-anchors

@; recipe-redistribution begin: penalized-topology-morph-correspondence
@section[#:tag "penalized-topology-morph-correspondence"]{Penalized Topology-Changing Correspondence}

The birth and death penalty options make forced real correspondence optional
when the caller supplies an explicit cost for both sides of a replacement. The default remains unchanged:

@racketblock[
(path-geometry-prepare-topology-changing-morph
 source destination
 #:birth-penalty 'forced
 #:death-penalty 'forced)
]

To let the global matcher reject a poor source/destination pair, provide finite
nonnegative local path-unit costs:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-penalty 2
             #:death-penalty 2)
            #:duration 3)
]

A real edge keeps the existing geometric correspondence score. A
death costs @racket[death-penalty], and a birth costs @racket[birth-penalty].
The assignment is solved globally within each open/closed topology class. Thus a
good nearby pair can remain matched while a distant pair is represented by one
local collapse and one local regrowth. This is not a greedy threshold applied
independently to each candidate.

The assignment minimizes two objectives lexicographically. First it minimizes total
geometric/penalty cost. If that primary cost ties exactly, it minimizes the total
number of birth/death edges. A real correspondence whose score equals death plus
birth cost is therefore retained. Remaining exact ties use the same deterministic
index ordering as the existing assignment machinery.

Both penalty keywords must use one mode: either both are the exact symbol
@racket['forced], or both are finite nonnegative real numbers. Anchor selection is
independent. Every unmatched slot---whether forced by a count difference or
selected voluntarily by numeric penalties---uses the configured birth/death anchor policy. Synthetic slots remain interior correspondence only; exact source and
caller destination representations are preserved at the clip endpoints.

Render the canonical comparison with:

@verbatim{
racket examples/penalized-topology-changing-morphs.rkt \
  frames/penalized-topology-changing-morphs \
  penalized-topology-changing-morphs.mp4

open penalized-topology-changing-morphs.mp4
}

The upper path uses forced correspondence and sweeps between distant locations.
The lower path uses numeric penalties and instead collapses locally on the left
while its destination grows locally on the right.



@; recipe-redistribution end: penalized-topology-morph-correspondence

@; recipe-redistribution begin: per-subpath-topology-morph-penalties
@section[#:tag "per-subpath-topology-morph-penalties"]{Per-Subpath Birth/Death Penalties}

@racket[#:birth-penalty-map] and @racket[#:death-penalty-map] keep the shared
numeric costs as fallbacks and add sparse original-index overrides:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:birth-penalty 2
             #:death-penalty 2
             #:birth-penalty-map (hash 1 20)
             #:death-penalty-map (hash 0 20))
            #:duration 3)
]

@racket[birth-penalty-map] keys address the caller destination's original
subpath indexes. @racket[death-penalty-map] keys address the clip-start source's
original subpath indexes. Topology partitioning, global assignment, destination
reordering, open-path reversal, and closed-loop phase selection do not renumber
these keys.

Every map value is a finite nonnegative real cost. A missing key inherits the
corresponding shared @racket[birth-penalty] or @racket[death-penalty]. Sparse
values change only source-to-dummy death costs and dummy-to-destination birth
costs in the augmented assignment. Real-pair geometric scores and the
lexicographic exact-tie preference for fewer topology changes are unchanged.

Nonempty maps require numeric shared penalty mode; they are rejected when both
shared penalties are @racket['forced]. Anchor policy remains independent:
The shared and per-subpath anchor settings determine where any unmatched
subpath selected by the cost policy collapses or grows. Timeline requests copy penalty maps into immutable hashes so
later mutation of caller hashes has no effect. Direct preparation validates map
ranges immediately; request compilation validates them against the clip-start
source and stored destination.

Render the canonical comparison with:

@verbatim{
racket examples/per-subpath-topology-penalties.rkt \
  frames/per-subpath-topology-penalties \
  per-subpath-topology-penalties.mp4

open per-subpath-topology-penalties.mp4
}

The upper panel uses shared low costs and replaces both distant pairs. The lower
panel raises the death cost of original source index 0 and the birth cost of
original destination index 1; that upper pair remains a real morph while the
lower pair still collapses and regrows.



@; recipe-redistribution end: per-subpath-topology-morph-penalties

@; recipe-redistribution begin: per-pair-topology-match-penalties
@section[#:tag "per-pair-topology-match-penalties"]{Per-Pair Real-Match Penalties}

@racket[#:match-penalty-map] adds sparse, deterministic semantic costs to
individual real assignment edges while retaining the geometric correspondence
score:

@racketblock[
(scene-play scene
            (morph-to-topology-changing
             panel destination
             #:match-penalty-map
             (hash (cons 0 0) 20
                   (cons 1 1) 5))
            #:duration 3)
]

Each key is @racket[(cons source-index destination-index)] in the original caller
subpath order. The value is a finite nonnegative additive cost. Missing pairs add
zero. Topology partitioning, global assignment, destination reordering, open-path
reversal, and closed-loop phase selection never renumber the indexes.

The map affects real source/destination edges only. In forced mode it can change
which same-topology real subpaths pair without enabling optional birth/death. In numeric penalty mode the increased real-edge score also competes with the
resolved death and birth costs. Exact primary-cost ties retain the secondary
preference for fewer topology changes.

Direct geometry preparation rejects out-of-range and open-to-closed keys. Timeline
requests validate key shape/value at construction, snapshot the hash immutably,
and validate range/topology at clip compilation. Anchor maps and endpoint penalty maps remain independent.

Render the canonical comparison with:

@verbatim{
racket examples/per-pair-match-penalties.rkt \
  frames/per-pair-match-penalties \
  per-pair-match-penalties.mp4

open per-pair-match-penalties.mp4
}

The upper panel uses geometry alone and both curves visibly morph locally. The
lower panel penalizes original pair @racket[(cons 0 0)], so the global assignment
swaps the two real destination identities and the curves cross.



@; recipe-redistribution end: per-pair-topology-match-penalties
