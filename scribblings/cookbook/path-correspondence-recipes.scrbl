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


@title[#:tag "cookbook-path-correspondence-recipes"]{Matching Path Outlines}

Choose direction, cyclic starting point, and subpath pairing before morphing path outlines.

API reference: @secref["reference-animation-path-correspondence"], @secref["path-geometry"].

@local-table-of-contents[]

@; recipe-redistribution begin: automatic-morph-correspondence
@section[#:tag "automatic-morph-correspondence"]{Automatic Closed-Loop Morph Correspondence}

Closed-loop alignment combines path reversal and cyclic-start selection with
the normalized morph engine. Given two single closed loops, align the destination
explicitly with:

@racketblock[
(define aligned-destination
  (path-geometry-align-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The alignment search uses total-arc-length point samples. It considers both
traversal directions by default, scores cyclic phases deterministically, and
prefers forward traversal on exact ties. Set @racket[#:allow-reverse? #f] when
orientation is semantically significant and only a cyclic phase may change.

For ordinary animation, the combined request is shorter:

@racketblock[
(scene-play scene
            (morph-to-aligned panel destination)
            #:duration 3)
]

The exact requested destination representation is still installed at eased
progress one. Automatic alignment is an interior correspondence choice; it does
not rewrite the caller's endpoint object permanently.

This operation handles one positive finite closed subpath per side. Equal-count
compound pairing is available separately, while topology-changing morphs add
controlled subpath birth/death when topology-class counts differ.

Render the canonical comparison example with:

@verbatim{
racket examples/automatic-morph-correspondence.rkt \
  frames/automatic-morph-correspondence \
  automatic-morph-correspondence.mp4

open automatic-morph-correspondence.mp4
}



@; recipe-redistribution end: automatic-morph-correspondence

@; recipe-redistribution begin: open-morph-correspondence
@section[#:tag "open-morph-correspondence"]{Automatic Open-Path Morph Correspondence}

Open-path alignment handles the endpoint-direction ambiguity of one open path. Prepare an
explicit destination traversal with:

@racketblock[
(define aligned-destination
  (path-geometry-align-open-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The two paths must each contain exactly one positive finite open subpath. The
algorithm samples corresponding total-arc-length fractions from both endpoints
and compares the stored destination traversal with its semantic reversal. A
strictly lower reverse score selects reversed correspondence; an exact tie keeps
the stored destination direction. There is no cyclic phase search because open
endpoints remain distinct.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-open-aligned panel destination)
            #:duration 3)
]

The aligned/reversed representation is interior correspondence only. Eased
progress zero uses the exact clip-start source path, and eased progress one
installs the exact destination object originally requested by the caller.

Render the canonical comparison example with:

@verbatim{
racket examples/open-morph-correspondence.rkt \
  frames/open-morph-correspondence \
  open-morph-correspondence.mp4

open open-morph-correspondence.mp4
}



@; recipe-redistribution end: open-morph-correspondence

@; recipe-redistribution begin: compound-morph-correspondence
@section[#:tag "compound-morph-correspondence"]{Automatic Compound-Path Morph Correspondence}

Compound closed-loop alignment handles paths whose subpath storage order
differs. Prepare explicit geometry with:

@racketblock[
(define aligned-destination
  (path-geometry-align-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

Every source/destination loop pair is scored with closed-loop phase/direction
correspondence. The procedure then chooses one global minimum-total-cost
assignment,
so a locally attractive early match cannot force a worse overall pairing.
Pairing is deterministic and independent of rendering, camera state, frame
rate, wall-clock time, or randomness.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-compound-aligned panel destination)
            #:duration 3)
]

The source and destination must contain equal nonzero counts of positive finite
closed subpaths. The exact requested destination representation, including its
original subpath order, is installed at eased progress one. Reordering and
per-loop alignment are interior correspondence only.

Render the canonical comparison example with:

@verbatim{
racket examples/compound-morph-correspondence.rkt \
  frames/compound-morph-correspondence \
  compound-morph-correspondence.mp4

open compound-morph-correspondence.mp4
}



@; recipe-redistribution end: compound-morph-correspondence

@; recipe-redistribution begin: open-compound-morph-correspondence
@section[#:tag "open-compound-morph-correspondence"]{Automatic Open-Compound Morph Correspondence}

Open-compound alignment applies endpoint-direction correspondence to equal-count
compound figures whose subpaths are all open. Prepare explicit geometry with:

@racketblock[
(define aligned-destination
  (path-geometry-align-open-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

Every source/destination open-subpath pair is scored with inclusive
total-arc-length forward/reverse correspondence. A global minimum-total-cost
assignment then uses the same deterministic assignment policy as closed
compound alignment. A locally attractive early match therefore cannot force a
worse total correspondence.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-open-compound-aligned panel destination)
            #:duration 3)
]

Pairing and per-pair reversal are interior correspondence only. Eased progress
zero uses the exact clip-start source path, and eased progress one installs the
exact caller-requested destination, including its original subpath order and
stored directions.

Render the canonical comparison example with:

@verbatim{
racket examples/open-compound-morph-correspondence.rkt \
  frames/open-compound-morph-correspondence \
  open-compound-morph-correspondence.mp4

open open-compound-morph-correspondence.mp4
}

The upper panel uses stored-order normalized correspondence and cross-pairs the
open curves. The lower panel pairs subpaths globally and chooses each endpoint
direction independently.



@; recipe-redistribution end: open-compound-morph-correspondence

@; recipe-redistribution begin: mixed-compound-morph-correspondence
@section[#:tag "mixed-compound-morph-correspondence"]{Automatic Mixed-Topology Compound Morph Correspondence}

Mixed-compound alignment combines the open and closed correspondence rules for
one compound path that may contain both topology classes. Prepare explicit geometry
with:

@racketblock[
(define aligned-destination
  (path-geometry-align-mixed-compound-for-morph source destination))

(define-values (normalized-source normalized-destination)
  (path-geometry-normalize-for-morph source aligned-destination))
]

The source and destination must be nonempty and every subpath must have positive
finite arc length. Open counts must match independently from closed counts. Open candidate pairs use forward/reverse endpoint correspondence and closed
candidate pairs use cyclic phase/direction correspondence. The same
deterministic global assignment policy is solved separately inside both classes,
then the selected destination subpaths are restored to source order.

For timeline use:

@racketblock[
(scene-play scene
            (morph-to-mixed-compound-aligned panel destination)
            #:duration 3)
]

Topology pairing/reordering and per-pair alignment are interior correspondence
only. Eased progress zero uses the exact clip-start source, and eased progress
one installs the exact caller-requested destination, including its original
interleaving and storage order.

Render the canonical comparison example with:

@verbatim{
racket examples/mixed-compound-morph-correspondence.rkt \
  frames/mixed-compound-morph-correspondence \
  mixed-compound-morph-correspondence.mp4

open mixed-compound-morph-correspondence.mp4
}

Every intended destination counterpart also changes geometry. The upper panel
uses normalized stored-order correspondence and sweeps identities across the
scene. The lower panel solves open and closed identities independently, so the
green paths visibly morph while staying with their spatially sensible
counterparts.



@; recipe-redistribution end: mixed-compound-morph-correspondence
