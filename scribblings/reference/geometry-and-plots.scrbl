#lang scribble/manual
@(require (for-label (except-in racket/base angle string-copy)
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

@section[#:tag "geometry"]{Geometry}

@declare-exporting[animate #:use-sources (animate/main)]

@defstruct*[vec2 ([x finite-real?]
                  [y finite-real?])
  #:transparent]{

Represents either a point or a displacement in two-dimensional world
coordinates.

The constructor checks both fields. Infinite values and NaN values are
rejected. The structure is immutable and transparent. The public bindings
created for this structure include @racket[vec2], @racket[vec2?],
@racket[vec2-x], and @racket[vec2-y].
}

@defproc[(finite-real? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a finite real number. Exact and
inexact finite real numbers are accepted. Complex numbers, infinities, and NaN
values are rejected.
}

@defproc[(finite-complex? [value any/c]) boolean?]{
Returns @racket[#t] for a non-real complex number whose real and imaginary
components are both finite.  It is an interpolable scene-value scalar.
}

@defthing[origin vec2? #:value (vec2 0 0)]{

The origin of world coordinates.
}

@defproc[(real-lerp [from finite-real?]
                    [to finite-real?]
                    [progress finite-real?])
         finite-real?]{

Returns the linear interpolation
@racket[(+ from (* progress (- to from)))]. A progress value of @racket[0]
returns @racket[from], and a progress value of @racket[1] returns @racket[to].
Values outside the unit interval perform linear extrapolation.
}

@defproc[(interpolable? [value any/c]) boolean?]{

Returns @racket[#t] for a semantic scene value that supports
@racket[interpolate-value]. In this version, finite real numbers,
@racket[vec2] coordinates, and @racket[rgba-color] values are interpolable.
}

@defproc[(interpolate-value [from any/c]
                            [to any/c]
                            [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         any/c]{

Interpolates two values of the same interpolable semantic kind over the closed
unit interval. A progress of @racket[0] returns the original @racket[from]
value and a progress of @racket[1] returns the original @racket[to] value.
Mixed kinds and noninterpolable values raise an exception.
}

@subsection{Scene Parameters}

@defproc[(parameter [id symbol?] [initial-value any/c]) scene-parameter?]{

Creates an immutable declaration for one named interpolable scene value. This
is a scene-timeline convenience handle, not a Racket dynamic parameter. Its
identity and initial value are immutable, and it has no mutable current value.
Pass it to @racket[scene-set-value] to install its initial value or wherever a
scene-value API accepts an ID.
}

@defproc[(scene-parameter? [value any/c]) boolean?]{
Returns @racket[#t] when @racket[value] is a scene parameter declaration.
}

@defproc[(parameter-id [value scene-parameter?]) symbol?]{
Returns the stable named scene-value identity carried by @racket[value].
}

@defproc[(parameter-initial-value [value scene-parameter?]) any/c]{
Returns the interpolable initial semantic value carried by @racket[value].
}

@defproc[(vec2+ [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise sum of @racket[a] and @racket[b].
}

@defproc[(vec2- [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise difference @racket[a] minus @racket[b].
}

@defproc[(vec2-scale [scalar finite-real?] [value vec2?]) vec2?]{

Multiplies both components of @racket[value] by @racket[scalar].
}

@defproc[(vec2* [a vec2?] [b vec2?]) vec2?]{

Returns the componentwise product of @racket[a] and @racket[b]. This operation
is used for non-uniform scale factors.
}

@defproc[(vec2-lerp [from vec2?]
                    [to vec2?]
                    [progress finite-real?])
         vec2?]{

Interpolates the x and y components independently. Like @racket[real-lerp],
this procedure permits extrapolation when @racket[progress] is outside the
unit interval.
}

@section[#:tag "path-geometry"]{Path Geometry}

@declare-exporting[animate #:use-sources (animate/main)]

Path geometry describes outlines and filled regions without using Pict. It
supports straight line segments and cubic Bézier segments. Both kinds are
semantic model values. They do not contain drawing-context commands or a
rendered approximation.

A path may contain several subpaths. Subpath order is significant. Within each
subpath, the start point comes first and segments follow in traversal order.
Each segment begins where the preceding segment ended. A closed subpath
reconnects its final endpoint to its start when it is rendered and measured.
That implicit closing edge is straight.

Length, partial extraction, and morphing use local coordinates before a
Visual's scale, rotation, or translation is applied. Compound paths traverse
one subpath fully before continuing with the next one. Morphing pairs subpaths
and segments by their stored order; it does not reorder them automatically.

@defstruct*[line-path-segment ([end vec2?])
  #:transparent]{

Represents one straight segment. The segment starts at the previous point in
its containing @racket[path-subpath] and ends at @racket[end].

The structure is immutable and transparent. Its public bindings include
@racket[line-path-segment], @racket[line-path-segment?],
@racket[line-path-segment-end], and @racket[struct:line-path-segment].
}

@defstruct*[cubic-bezier-path-segment ([control1 vec2?]
                                       [control2 vec2?]
                                       [end vec2?])
  #:transparent]{

Represents one cubic Bézier segment. The segment start is the previous point
in its containing @racket[path-subpath]. The structure therefore stores only
the two control points and the endpoint.

The curve starts in the direction from its start toward @racket[control1]. It
approaches @racket[end] from the direction of @racket[control2]. Control points
usually do not lie on the visible curve. They may lie outside the curve's
actual bounds.

The structure is immutable and transparent. Its public bindings include
@racket[cubic-bezier-path-segment],
@racket[cubic-bezier-path-segment?], the three field accessors, and
@racket[struct:cubic-bezier-path-segment].
}

@defproc[(path-segment? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a supported semantic path segment.
The supported values are @racket[line-path-segment] and
@racket[cubic-bezier-path-segment] values.
}

@defstruct*[path-subpath ([start vec2?]
                          [segments (listof path-segment?)]
                          [closed? boolean?])
  #:transparent]{

Represents one connected figure in a path.

The @racket[start] field is the first local point. The @racket[segments] list
contains segment values in significant traversal order. Each segment begins
where the preceding segment ended. An empty segment list represents one point.

When @racket[closed?] is true, rendering reconnects the last endpoint to
@racket[start] with an implicit straight edge. The edge is not stored as an
extra segment. It participates in bounds, length, partial extraction, and
rendering. A closed subpath can be filled. An open subpath is only stroked by
the built-in Pict renderer.

The structure is immutable and transparent. Its public bindings include its
constructor, predicate, three field accessors, and structure descriptor.
}

@defstruct*[path-geometry ([subpaths (listof path-subpath?)])
  #:transparent]{

Represents zero or more subpaths. Subpath order is significant for traversal,
creation, morphing, and filling. The built-in renderer combines all closed
subpaths with the odd-even fill rule, so an inner closed subpath can form a
hole.

An empty list is valid and represents geometry that draws nothing. The
structure is immutable and transparent. Its public bindings include its
constructor, predicate, field accessor, and structure descriptor.
}

@defthing[empty-path-geometry path-geometry?]{

A path-geometry value containing no subpaths. It is the semantic invisible
geometry used at the beginning of @racket[create] and at the visible end of
@racket[uncreate]. It is not a blank Pict.
}

@defproc[(path-geometry-empty? [geometry path-geometry?]) boolean?]{

Returns @racket[#t] when @racket[geometry] contains no subpaths. A geometry
value containing a point-only subpath is not empty.
}

@defproc[(path-subpath-points [subpath path-subpath?])
         (listof vec2?)]{

Returns @racket[subpath]'s start point followed by every segment endpoint. The
returned list is in significant traversal order. Cubic control points are not
included; use the cubic segment accessors to obtain them. The implicit closing
edge of a closed subpath does not repeat the start point at the end.
}

@defproc[(path-geometry-subpath-points [geometry path-geometry?])
         (listof (listof vec2?))]{

Returns one traversal-ordered start-and-endpoint list for each subpath. The
outer list preserves subpath order. Cubic control points are omitted in the
same way as by @racket[path-subpath-points].
}

@defproc[(path-geometry-map-points
          [geometry path-geometry?]
          [transform-point (procedure-arity-includes/c 1)])
         path-geometry?]{

Calls @racket[transform-point] once for every stored point and returns new path
geometry with the same subpath, segment, and closure structure. Stored points
include each subpath start, every line endpoint, and every cubic control point
and endpoint. The procedure must return a @racket[vec2] for every input point.
The original geometry is not changed.

This operation transforms local geometry only. It does not change a Visual's
reference position, rotation, or scale.
}

@defproc[(path-geometry-translate [geometry path-geometry?]
                                  [displacement vec2?])
         path-geometry?]{

Returns new geometry with @racket[displacement] added to every stored local
point. Segment kinds, subpath order, and closure are preserved.
}

@defproc[(path-geometry-reverse [geometry path-geometry?])
         path-geometry?]{

Returns path geometry with every subpath traversed in the opposite direction.
Subpath order is preserved. Line segments reverse their endpoints. Cubic
Bézier segments reverse their endpoints and exchange their first and second
control points, preserving the exact traced curve.

For an open subpath, the former final endpoint becomes the new start. For a
closed subpath, the original stored start is preserved so the loop changes
direction without also changing phase. When the original implicit closing line
has positive length, that line is materialized as the first explicit reversed
segment; the resulting synthetic closing edge is then zero length. This
representation detail can change segment count, but it does not change the
visible or measured loop.

For a positive finite closed loop, point lookup on the reversed result follows
the original loop at fraction @racket[(- 1 fraction)] (subject to the same
deterministic cubic arc-length approximation as @racket[path-geometry-point-at]).
Tangent direction is reversed correspondingly away from corner one-sided
boundaries.

The operation is purely semantic and does not apply a containing Visual
transform. Empty geometry and zero-length subpaths are valid.
}

@defproc[(path-geometry->cubic [geometry path-geometry?])
         path-geometry?]{

Converts every stored line segment in @racket[geometry] to an exactly
equivalent cubic Bézier segment. A line from @racket[start] to @racket[end]
becomes a cubic with these control points:

@racketblock[
(vec2-lerp start end 1/3)
(vec2-lerp start end 2/3)
]

The resulting cubic traces the same straight line in the same direction. An
existing cubic segment is kept unchanged. Subpath starts, subpath order,
segment order, endpoints, and closure values are preserved. Point-only
subpaths and empty geometry are valid.

Only stored line segments are converted. The implicit straight closing edge of
a closed subpath remains implicit and is not added to the segment list.

When @racket[geometry] already contains no stored line segments, the procedure
returns @racket[geometry] itself. Otherwise it returns new immutable geometry.
}

@defproc[(path-geometry-morph-normalizable?
          [from path-geometry?]
          [to path-geometry?])
         boolean?]{

Returns @racket[#t] when @racket[from] and @racket[to] can be made strictly
morph-compatible by the limited normalization performed by
@racket[path-geometry-normalize-for-morph].

The paths are normalizable when all of the following hold:

@itemlist[
 @item{They contain the same number of subpaths.}
 @item{Corresponding subpaths have the same closure value.}
 @item{Each pair of corresponding subpaths is either point-only on both sides
       or contains at least one stored segment on both sides.}
]

Stored segment counts and line-versus-cubic kinds may differ. Coordinates and
path lengths do not affect this predicate. The predicate does not change either
path.
}

@defproc[(path-geometry-align-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] with an automatically selected closed-loop cyclic
start and, when @racket[allow-reverse?] is true, traversal direction that gives
a low-distance geometric correspondence to @racket[source]. Both arguments
must contain exactly one positive-length finite closed subpath.

Correspondence is measured in total-arc-length coordinates. The procedure
samples @racket[source] at @racket[sample-count] evenly spaced fractions, scores
candidate destination phases by mean Euclidean point distance, and chooses the
lowest score deterministically. Candidate phases include a uniform full-loop
grid and every stored positive-edge boundary of the destination. A fixed number
of local refinement rounds then improves the best phase. The algorithm does not
depend on frame rate, camera scale, rendering, wall-clock time, or randomness.

When reverse traversal is allowed, the same search is performed on
@racket[(path-geometry-reverse destination)]. An exact score tie prefers the
original forward traversal. Exact phase ties prefer the smaller phase. An
already aligned destination therefore remains unchanged rather than being
reversed or split gratuitously.

The returned value is ordinary semantic path geometry. Use it before
@racket[path-geometry-normalize-for-morph] when a caller wants explicit access
to the chosen correspondence, or use @racket[morph-to-aligned] to perform both
steps during timeline compilation.

This operation deliberately handles one closed loop on each side. It does not
pair multiple subpaths, add or remove subpaths, change closure, solve arbitrary
global shape correspondence, or guarantee a globally optimal continuous phase
for every pathological curve. Increasing @racket[sample-count] makes the fixed
deterministic geometric score finer.
}

@defproc[(path-geometry-align-open-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] with the traversal direction that best matches one
open @racket[source] path. Both paths must contain exactly one open subpath with
positive finite total arc length.

The procedure samples @racket[source] and @racket[destination] at
@racket[sample-count] evenly spaced total-arc-length fractions including both
endpoints and scores mean Euclidean point distance. When
@racket[allow-reverse?] is true, the same score is computed for
@racket[(path-geometry-reverse destination)]. Reverse traversal is selected only
when its score is strictly lower; an exact score tie keeps the caller's stored
forward destination. There is no cyclic phase search for an open path.

When forward traversal wins, the exact @racket[destination] object is returned.
When reverse traversal wins, the returned geometry traces the same destination
from its former endpoint toward its former start. The operation is pure semantic
geometry and does not inspect Visual transforms, renderers, camera state, frame
rate, pixels, or output files.

Use the result before @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-open-aligned] for timeline compilation.
This operation deliberately handles one open subpath on each side; it does not
select cyclic phases, pair compound subpaths, change closure, or add/remove
subpaths.
}

@defproc[(path-geometry-align-open-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns compound @racket[destination] geometry reordered and direction-aligned
so its open subpaths correspond to the open subpaths of @racket[source]. The two
paths must contain the same nonzero number of subpaths, and every subpath must be
open with positive finite arc length.

For every source/destination subpath pair, the procedure uses the SCENE-AE
endpoint-direction score from @racket[path-geometry-align-open-for-morph]: both
paths are sampled at @racket[sample-count] inclusive total-arc-length fractions,
and destination reversal is selected only when its score is strictly lower.
One source subpath's samples are cached while every destination candidate for
that assignment row is evaluated.

After all pair costs are known, the same deterministic minimum-total-cost
assignment policy as SCENE-AD chooses one distinct destination subpath for every
source subpath. Pairing is global rather than greedy. Exact assignment ties use
the deterministic destination-index policy of
@racket[path-geometry-align-compound-for-morph], while exact per-pair direction
ties preserve the caller's stored forward traversal.

The returned value is ordinary immutable @racket[path-geometry] whose subpath
order matches source correspondence. A destination subpath whose stored
direction wins is reused exactly. When pairing and direction alignment change
nothing, the exact @racket[destination] object is returned.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-open-compound-aligned] for timeline
compilation. This specialized operation deliberately requires all subpaths to be open and
counts to match. Use @racket[path-geometry-align-mixed-compound-for-morph] when
matching-count open and closed topology is combined in one compound. Use
@racket[path-geometry-prepare-topology-changing-morph] or
@racket[morph-to-topology-changing] when topology-class counts differ.
}

@defproc[(path-geometry-align-mixed-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns @racket[destination] reordered/aligned to the topology and subpath
correspondence of @racket[source]. The paths must be nonempty; every subpath must
have positive finite arc length; source/destination open-subpath counts must
match; and source/destination closed-subpath counts must match.

The procedure partitions both paths by @racket[path-subpath-closed?]. Open
candidates are evaluated with the SCENE-AE endpoint-direction rule used by
@racket[path-geometry-align-open-for-morph]. Closed candidates are evaluated
with the SCENE-AC phase/direction rule used by
@racket[path-geometry-align-for-morph]. The deterministic global assignment
policy is then solved independently inside the open and closed classes. An open
subpath is therefore never paired with a closed loop merely because it is
spatially nearby.

After both assignments, selected destination subpaths are placed in the exact
subpath order of @racket[source]. Each open pair may reverse only for a strictly
lower score; each closed pair may choose cyclic phase and optional reversal under
SCENE-AC's deterministic tie rules. Unchanged destination subpath objects are
reused, and when the entire correspondence is already a no-op the exact
@racket[destination] object is returned.

When one topology class is absent, this operation reduces to the corresponding
SCENE-AF all-open or SCENE-AD all-closed behavior. Use
@racket[path-geometry-prepare-topology-changing-morph] when either topology-class
count differs.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-mixed-compound-aligned] for timeline
compilation.
}

@defproc[(path-geometry-prepare-topology-changing-morph
          [source path-geometry?]
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
         (values path-geometry? path-geometry?)]{

Returns two equal-count interior correspondence paths suitable for
@racket[path-geometry-normalize-for-morph] even when @racket[source] and
@racket[destination] contain different numbers of open or closed subpaths. The
first result is the prepared source and the second is the aligned/prepared
destination.

Every real subpath on either side must have positive finite arc length. The
whole source or destination may nevertheless be empty, allowing pure birth from
empty geometry and pure death to empty geometry. Open and closed topology
classes are handled independently and are never paired directly with one
another.

Within each topology class, real open pairs use the SCENE-AE
forward/reverse endpoint score and real closed pairs use the SCENE-AC
phase/direction score. With the default @racket['forced] value for both penalty
keywords, the rectangular assignment pads only the forced class-count difference
with zero-cost dummy slots; matching topology counts therefore reduce exactly to
SCENE-AG as before.

SCENE-AJ adds an optional numeric policy. When both @racket[birth-penalty] and
@racket[death-penalty] are finite nonnegative reals, the procedure solves an
augmented global assignment. A real source/destination edge costs its geometric
correspondence score, a source-to-dummy edge costs @racket[death-penalty], a
dummy-to-destination edge costs @racket[birth-penalty], and unused dummy pairs
cost zero. A poor real pair may therefore be replaced by death plus birth even
when topology counts match. Exact primary-cost ties minimize the number of
birth/death edges as a secondary objective, so equal-cost replacement does not
occur. The two penalty keywords must either both be @racket['forced] or both be
finite nonnegative real numbers. SCENE-AL additionally accepts sparse
@racket[birth-penalty-map] and @racket[death-penalty-map] hashes in numeric mode.
Birth-map keys are exact nonnegative original destination subpath indexes;
death-map keys are exact nonnegative original source subpath indexes. Map values
are finite nonnegative real costs and missing keys fall back to the corresponding
shared numeric penalty. Nonempty penalty maps are rejected in @racket['forced]
mode. The sparse costs replace dummy-edge costs only. SCENE-AM additionally
accepts @racket[match-penalty-map] in both forced and numeric modes. Each key is
@racket[(cons source-index destination-index)] using original caller subpath
indexes, and each finite nonnegative value is added to that real edge's existing
geometric correspondence score. Missing pairs add zero. Pair penalties do not
change topology classes or direction/phase alignment; they bias the global
assignment after those per-edge geometric choices are scored. In numeric mode a
penalized real edge also competes against death plus birth, while AJ's exact-tie
preference for fewer topology changes remains unchanged. Direct preparation
rejects out-of-range pair indexes and keys that name impossible open/closed
correspondence edges. @racket[allow-reverse?] and @racket[sample-count] retain
their existing correspondence meanings.

A destination subpath assigned to a dummy source is a birth. By default its
prepared source is a one-line-segment degenerate subpath at the exact
axis-aligned bounds center of that destination subpath. A source subpath assigned
to a dummy destination is a death and receives the analogous prepared destination
seed at its own bounds center. Each seed preserves the real subpath's
@racket[path-subpath-closed?] value. The controlled seeds have zero arc length;
pre-existing zero-length real subpaths are rejected before assignment.

SCENE-AI extends this placement with @racket[birth-anchor] and
@racket[death-anchor]. Each accepts exactly @racket['bounds-center] or a finite
@racket[vec2]. An explicit point is local path geometry and is shared by every
unmatched subpath on that side. SCENE-AK additionally accepts sparse
@racket[birth-anchor-map] and @racket[death-anchor-map] hashes. Birth-map keys are
exact nonnegative original destination subpath indexes; death-map keys are exact
nonnegative original source subpath indexes. Map values use the same anchor
syntax. A missing key falls back to the corresponding shared anchor, while an
explicit @racket['bounds-center] map value may override a shared @racket[vec2].
Direct preparation rejects out-of-range keys. Anchor selection affects seed
placement only; real-pair scores, direction/phase correspondence, penalties, and
slot ordering are unchanged. In numeric SCENE-AJ penalty mode the selected
assignment may contain additional voluntary unmatched slots, and those slots use
the same original-index map lookup.

All slots corresponding to real source subpaths remain first in exact source
order. Birth-only slots are appended in exact caller destination order. When
open and closed class counts already match under the default forced-only policy,
the operation reduces exactly to
@racket[path-geometry-align-mixed-compound-for-morph], returning the original
@racket[source] as the first value. Numeric penalties may intentionally produce
additional interior slots even when endpoint counts match.

Use the two results with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-topology-changing] for timeline
compilation. This stage does not infer semantic holes, pair an open subpath
directly with a closed loop, use appearance-aware scores, or accept arbitrary
per-pair scoring callbacks beyond SCENE-AM sparse numeric additions.
}

@defproc[(path-geometry-align-compound-for-morph
          [source path-geometry?]
          [destination path-geometry?]
          [#:allow-reverse? allow-reverse? boolean? #t]
          [#:sample-count sample-count
                          (and/c exact-integer? (>=/c 8))
                          64])
         path-geometry?]{

Returns compound @racket[destination] geometry reordered and aligned so its
closed subpaths correspond to the subpaths of @racket[source]. The two paths
must contain the same nonzero number of subpaths, and every subpath must be
closed with positive finite arc length.

The procedure computes every source/destination pair cost with the SCENE-AC
closed-loop algorithm used by @racket[path-geometry-align-for-morph]. Thus each
candidate pair may choose a cyclic phase and, when @racket[allow-reverse?] is
true, reverse traversal. One source loop's score samples are cached while all
destination candidates for that source are evaluated.

After all pair costs are known, a deterministic minimum-total-cost assignment
selects one distinct destination subpath for every source subpath. Pairing is
global rather than greedy. Exact assignment ties preserve earlier source-row
matches when an equally good free destination exists and then prefer the lower
destination index. Per-pair direction and phase ties retain the SCENE-AC rules.

The returned value is ordinary immutable @racket[path-geometry] whose subpath
order matches source correspondence. When pairing and per-loop alignment change
nothing, the exact @racket[destination] object is returned. Otherwise untouched
destination subpath objects are reused whenever possible.

Use the result with @racket[path-geometry-normalize-for-morph] for explicit
preparation, or use @racket[morph-to-compound-aligned] for timeline compilation.
This stage does not add/remove subpaths, pair open subpaths, infer semantic hole
nesting, or support topology changes.
}

@defproc[(path-geometry-normalize-for-morph
          [from path-geometry?]
          [to path-geometry?])
         (values path-geometry? path-geometry?)]{

Returns two path-geometry values that trace the same figures as @racket[from]
and @racket[to] but have corresponding structure suitable for
@racket[path-geometry-lerp]. The first result is the normalized source, and the
second result is the normalized destination.

Normalization works independently on corresponding subpaths:

@itemlist[
 @item{Every stored line segment is converted to an equivalent cubic Bézier
       segment using @racket[path-geometry->cubic].}
 @item{The target segment count is the larger of the two stored segment counts.}
 @item{The side with fewer segments repeatedly splits its longest current
       cubic at parameter @racket[1/2] until the counts match.}
 @item{Segment length is the same deterministic approximate cubic arc length
       used by @racket[path-subpath-length]. When lengths tie, the earliest
       segment in traversal order is split.}
]

De Casteljau subdivision preserves the exact cubic curve. Splitting therefore
changes representation and correspondence, not the traced source or
destination figure. Both returned paths contain only cubic stored segments,
and @racket[path-geometry-morph-compatible?] returns @racket[#t] for them.
Point-only corresponding subpaths remain point-only.

The implicit closing edge of a closed subpath is not stored, converted, or
split. Closure remains represented by @racket[path-subpath-closed?]. Subpath
order and stored starting points are preserved.

This is deliberately limited normalization. It does not add or remove
subpaths, change closure, turn a point-only subpath into a drawn path, reverse
traversal, rotate the starting point of a closed path, reorder subpaths, or
choose a geometric best match. A difference requiring one of those operations
raises an exception that identifies the first unsupported subpath difference.
Reported indexes start at zero.

Example:

@racketblock[
(define triangle
  (polygon-path
   (list (vec2 -3 -1)
         (vec2 3 -1)
         (vec2 0 2))))

(define rectangle
  (polygon-path
   (list (vec2 -3 -2)
         (vec2 3 -2)
         (vec2 3 2)
         (vec2 -3 2))))

(define-values (normalized-triangle normalized-rectangle)
  (path-geometry-normalize-for-morph triangle rectangle))

(path-geometry-morph-compatible? normalized-triangle
                                 normalized-rectangle)
]
}

@defproc[(path-geometry-morph-compatible?
          [from path-geometry?]
          [to path-geometry?])
         boolean?]{

Returns @racket[#t] when @racket[from] and @racket[to] have corresponding
structure for pointwise path morphing.

Compatibility requires all of the following:

@itemlist[
 @item{The paths contain the same number of subpaths.}
 @item{Each corresponding subpath has the same @racket[closed?] value.}
 @item{Each corresponding subpath contains the same number of segments.}
 @item{Each corresponding segment has the same kind: line with line, or cubic
       Bézier with cubic Bézier.}
]

Subpaths and segments are paired by their stored order. Only stored segments
are counted. A closed subpath's implicit closing edge is represented by its
@racket[closed?] value, not by another stored line segment. Coordinates, path
lengths, and style do not affect compatibility. Empty geometry is compatible
with empty geometry. Point-only subpaths are compatible when their closure
values correspond.

The procedure remains strict. It does not insert segments, convert lines to
cubics, reverse a path, rotate a closed path's starting point, or reorder
subpaths. Use @racket[path-geometry-morph-normalizable?] and
@racket[path-geometry-normalize-for-morph] for the limited explicit
normalization provided by this version.
}

@defproc[(path-geometry-lerp [from path-geometry?]
                             [to path-geometry?]
                             [progress (real-in 0 1)])
         path-geometry?]{

Interpolates the stored points of two morph-compatible paths. The subpath
start points are interpolated pairwise. Line endpoints are interpolated
pairwise. For cubic segments, both control points and the endpoint are
interpolated pairwise. Subpath order, segment order, segment kind, and closure
are preserved.

@racket[progress] must be a finite real in the closed unit interval. A value of
@racket[0] returns @racket[from] itself. A value of @racket[1] returns
@racket[to] itself. An interior value returns new path geometry.

The interpolation uses local mathematical coordinates. It does not change a
Visual's identity, reference position, rotation, scale, fill, stroke, stroke
width, or drawing order. Use @racket[morph-to] to place this interpolation on a
timeline.

When the paths are incompatible, the procedure raises an exception describing
the first mismatch in deterministic traversal order. The diagnostic identifies
a subpath-count, closure, segment-count, or segment-kind mismatch. Reported
subpath and segment indexes start at zero. The procedure remains strict and
does not normalize incompatible paths automatically. Normalize explicitly or
use @racket[morph-to-normalized] for the limited supported cases.

Example:

@racketblock[
(define rectangle-path
  (polygon-path
   (list (vec2 -2 -1)
         (vec2 2 -1)
         (vec2 2 1)
         (vec2 -2 1))))

(define diamond-path
  (polygon-path
   (list (vec2 0 -2)
         (vec2 3 0)
         (vec2 0 2)
         (vec2 -3 0))))

(path-geometry-lerp rectangle-path diamond-path 1/2)
]
}

@defproc[(path-geometry-bounds [geometry path-geometry?])
         (values finite-real? finite-real? finite-real? finite-real?)]{

Returns four values: minimum x, minimum y, maximum x, and maximum y over the
visible path. Coordinates are local world units.

Line bounds come from their endpoints. Cubic bounds include their endpoints
and every interior parameter where the x or y derivative is zero. The result
therefore follows the curve itself instead of using the usually larger box of
its control points. The result is mathematically tight subject to the ordinary
numeric behavior of the supplied coordinates.

The implicit straight closing edge of a closed subpath is included. Empty
geometry has no bounds and raises an exception.
}

@defproc[(path-geometry-center [geometry path-geometry?]) vec2?]{

Returns the center of @racket[geometry]'s axis-aligned local bounding box. It
is the midpoint of the minimum and maximum x values and of the minimum and
maximum y values. Cubic extrema are included. Empty geometry raises an
exception.
}

@defproc[(path-subpath-length [subpath path-subpath?])
         (and/c real? (>=/c 0))]{

Returns the local arc length of @racket[subpath] in world units. A line
segment contributes the Euclidean distance from its start to its endpoint. A
cubic segment contributes a deterministic approximation of its curve length.
When the subpath is closed, the implicit straight edge from the final endpoint
back to @racket[(path-subpath-start subpath)] is included.

Cubic length is computed by repeatedly splitting the curve in half. For each
piece, the implementation compares the control-polygon length with the chord
length. Subdivision stops when their difference is at most the larger of
@racket[1e-10] world units and @racket[1e-8] times the original cubic's
control-polygon length, or after 20 subdivisions. The piece estimate is the
average of its chord and control-polygon lengths. These constants are part of
the current numeric behavior, but they are not a formal error guarantee.

A point-only subpath has length zero. Repeated adjacent points and completely
degenerate cubics contribute zero. The affine transform of a containing Visual
is not applied. The line distance calculation avoids unnecessary overflow,
but a true distance beyond the inexact number range can produce
@racket[+inf.0].
}

@defproc[(path-geometry-length [geometry path-geometry?])
         (and/c real? (>=/c 0))]{

Returns the sum of the local arc lengths of all subpaths in
@racket[geometry]. Empty geometry has length zero. Line portions use Euclidean
length, and cubic portions use the deterministic approximation described for
@racket[path-subpath-length].

This is a geometric model operation. A non-uniform scale on a path Visual can
change the displayed world-space length, but it does not change the value
returned here. The result can be @racket[+inf.0] when an inexact distance is
too large to represent. @racket[create], @racket[uncreate], and non-full
partial extraction require a finite result.
}

@defproc[(path-geometry-point-at [geometry path-geometry?]
                                 [fraction (real-in 0 1)])
         vec2?]{

Returns the point at @racket[fraction] of @racket[geometry]'s total ordered arc
length. @racket[fraction] must be a finite real in the closed unit interval, and
the computed total path length must be positive and finite.

Traversal uses the same significant edge order and length model as
@racket[path-geometry-partial]. Line portions use exact Euclidean distance. A
point inside a cubic uses the same deterministic adaptive arc-length table
described for @racket[path-subpath-length] to approximate the corresponding
curve parameter. The returned value is a semantic local point; no containing
Visual transform is applied.

Compound path geometry is traversed subpath by subpath in stored order.
Zero-length edges consume no positive fraction. The implicit closing edge of a
closed subpath is included. Exact @racket[0] returns the start of the first
positive-length edge, and exact @racket[1] returns the endpoint of the final
positive-length traversal edge. At an exact boundary between positive subpaths,
the endpoint of the preceding subpath is selected.

Empty geometry, zero-total-length geometry, or a non-finite computed total
length raises an exception. @racket[move-along-path] adds a stricter continuity
rule and accepts only one positive-length subpath as a motion route.
}

@defproc[(path-geometry-tangent-at [geometry path-geometry?]
                                   [fraction (real-in 0 1)])
         vec2?]{

Returns the forward unit tangent at @racket[fraction] of
@racket[geometry]'s total ordered arc length. The fraction, positive finite
length requirement, edge order, zero-length-edge handling, implicit closing
edge, and compound-subpath traversal rules match
@racket[path-geometry-point-at]. At an exact positive-length edge boundary, the
preceding traversal edge owns both the point and the tangent.

Line tangents are normalized directed edge vectors. Cubic tangents are computed
from the cubic derivative at the parameter selected by the same adaptive
arc-length table used for point lookup. When that derivative is zero at a
stationary endpoint or cusp, deterministic one-sided curve probes recover the
forward traversal direction when one exists. The result is semantic local
geometry; no containing Visual transform is applied.

Empty geometry, zero-total-length geometry, a non-finite computed total length,
or a selected positive-length cubic point with no recoverable traversal
direction raises an exception.
}

@defproc[(path-geometry-normal-at [geometry path-geometry?]
                                  [fraction (real-in 0 1)])
         vec2?]{

Returns the left unit normal corresponding to
@racket[path-geometry-tangent-at] at @racket[fraction]. For tangent
@racket[(vec2 tx ty)], the result is @racket[(vec2 (- ty) tx)]. The operation
therefore has the same domain and error behavior as tangent lookup.
}

@defproc[(path-geometry-offset
          [geometry path-geometry?]
          [distance finite-real?]
          [#:join join (or/c 'miter 'bevel 'round) 'miter]
          [#:miter-limit miter-limit (and/c finite-real? (>=/c 1)) 4])
         path-geometry?]{

Returns a continuous signed parallel offset of straight-segment subpaths in
@racket[geometry]. Positive @racket[distance] is to the left of stored traversal
direction; negative distance is to the right. A zero distance returns
@racket[geometry] unchanged. The result is ordinary immutable semantic path
geometry and can be passed directly to @racket[make-path-visual],
@racket[move-along-path], @racket[orient-along-path], and other path operations.

For an outside corner, @racket[join] selects how adjacent shifted edge lines are
connected. @racket['miter] extends them to their intersection. The distance from
the original vertex to that intersection is divided by the absolute offset
distance; when the ratio exceeds @racket[miter-limit], the outside corner falls
back to bevel. @racket['bevel] connects the shifted edge endpoints with one
straight segment. @racket['round] uses one or more cubic Bézier circular-arc
approximations centered at the original vertex, with no cubic spanning more than
a quarter turn.

Inside corners always use the natural intersection of the two shifted lines,
independent of @racket[join]. This keeps the offset path traversing forward along
both adjacent lines; the short centered arc on the inside would have the wrong
endpoint tangents. Collinear same-direction edges share their shifted point.

Open subpath endpoints are shifted by their endpoint edge normals. Closed
subpaths are joined cyclically, including the stored start vertex. Every edge
participating in a nonzero offset must be a positive-length
@racket[line-path-segment]. A zero-length edge, an exact 180-degree reversal, or
a cubic source segment raises an exception in this stage. Cubic segments may
still appear in the @emph{result} as round-join pieces.

The construction is geometric rather than renderer-dependent: camera scale,
stroke width, and output resolution do not affect the generated path. The result
has its own arc length, so @racket[move-along-path] with @racket[linear] easing
moves uniformly along the joined offset route itself.
}

@defproc[(path-geometry-partial [geometry path-geometry?]
                                [start (real-in 0 1)]
                                [end (real-in 0 1)])
         path-geometry?]{

Returns the interval from fraction @racket[start] through fraction @racket[end]
of @racket[geometry]'s total local arc length. Both fractions must be finite,
and @racket[start] must not be greater than @racket[end].

Fractions apply to the whole compound path. Traversal completes each subpath
before beginning the next. A cut inside a line is inserted by linear
interpolation. A cut inside a cubic uses the same deterministic adaptive
length table as @racket[path-subpath-length] to approximate the corresponding
curve parameter. The selected cubic interval is then extracted with de
Casteljau subdivision. The result remains a cubic segment; it is not replaced
by a polyline or a Pict command.

A partially selected closed subpath becomes open. Its implicit closing edge is
part of the traversal and may itself be returned as an open line segment. A
closed subpath keeps its closure only when its complete traversal is selected.
This rule prevents a partial prefix from being filled as if it were complete.

When @racket[start] and @racket[end] are equal, the result is
@racket[empty-path-geometry]. The exact interval from @racket[0] through
@racket[1] returns @racket[geometry] unchanged. This preserves segment types,
control points, point-only subpaths, and other zero-length structure. For a
zero-length path, every other interval returns empty geometry.

Zero-length edges and subpaths do not consume a positive portion of the arc
length. They can therefore disappear from a non-full partial result. Any
non-full partial extraction requires the computed total path length to be
finite. Extremely large inexact coordinates whose distance overflows raise an
exception here.

Examples:

@racketblock[
(define mixed-path
  (path-geometry
   (list
    (path-subpath
     origin
     (list (line-path-segment (vec2 2 0))
           (cubic-bezier-path-segment (vec2 3 2)
                                      (vec2 4 2)
                                      (vec2 5 0)))
     #f))))

(path-geometry-partial mixed-path 0 1/2)
]
}

@defproc[(path-geometry-cycle-start [geometry path-geometry?]
                                    [fraction (real-in 0 1)])
         path-geometry?]{

Moves the stored start of one closed loop to @racket[fraction] of that loop's
total arc length while preserving its forward traversal direction and traced
geometry. The fraction uses the same deterministic line/cubic length model as
@racket[path-geometry-point-at].

@racket[geometry] must contain exactly one closed subpath with positive finite
length. Exact @racket[0] and @racket[1] return @racket[geometry] unchanged. For
any other fraction, the selected point becomes both fraction zero and fraction
one of the returned closed loop.

When the selected point lies inside a line, the line is split by interpolation.
When it lies inside a cubic, the arc-length table chooses the deterministic
curve parameter and de Casteljau subdivision splits the curve. The tail from
the selected point through the original closing edge is followed by the old
prefix back to the selected point. The returned subpath remains closed; its
final synthetic closing edge has zero length.

The operation deliberately handles one closed subpath rather than assigning one
phase to every subpath of compound geometry. Automatic per-subpath phase
selection is a separate correspondence problem. The returned value is ordinary
path geometry and can be used directly by @racket[make-path-visual],
@racket[move-along-path], @racket[orient-along-path], camera following, partial
extraction, and normalized morph preparation.
}

@defproc[(polyline-path [points (listof vec2?)]) path-geometry?]{

Creates path geometry containing one open line-segment subpath. At least two
points are required. Points are stored in the supplied order and adjacent
points are connected by @racket[line-path-segment] values.

The points are local coordinates. Use @racket[make-path-visual] to choose the
reference position in the Visual's containing coordinate system. That system is
world space at the top level and group-local space for a child.
}

@defproc[(polygon-path [points (listof vec2?)]) path-geometry?]{

Creates path geometry containing one closed line-segment subpath. At least
three points are required. The closing edge from the final point to the first
point is represented by the subpath's @racket[closed?] field and is not stored
as a repeated endpoint.

Point order determines traversal direction and can affect later path
operations. The built-in renderer uses the odd-even fill rule, so clockwise
and counter-clockwise order produce the same simple fill in this version.
}

@defproc[(cubic-bezier-path
          [start vec2?]
          [segments (and/c pair?
                           (listof cubic-bezier-path-segment?))]
          [#:closed? closed? boolean? #f])
         path-geometry?]{

Creates path geometry containing one subpath made from one or more cubic
Bézier segments. The subpath begins at @racket[start]. Segment order is
significant, and each segment begins at the preceding segment's endpoint.

When @racket[closed?] is true, the subpath also has an implicit straight edge
from its final endpoint back to @racket[start]. A smooth closed cubic shape
normally includes a final cubic whose endpoint is @racket[start] and also sets
@racket[closed?] to true so that the built-in renderer fills it. In that case,
the implicit closing edge has length zero.

Example:

@racketblock[
(define arch
  (cubic-bezier-path
   (vec2 -2 0)
   (list
    (cubic-bezier-path-segment (vec2 -2 2)
                               (vec2 2 2)
                               (vec2 2 0)))))
]
}

@subsection{General Boolean Path Geometry and Clipping}

SCENE-DY extends the immutable Boolean path operations to simple concave and
compound closed paths. Each cubic contour is uniformly sampled into
@racket[#:curve-samples] line pieces before clipping, so curve results are
deterministic polygonal approximations rather than exact Bézier intersections.
Each input contour must still be simple and closed.

The default @racket['odd-even] fill rule matches the path renderers: nested
contours alternate between filled regions and holes regardless of their
orientation. @racket['nonzero] additionally supports ordinary oriented,
nonintersecting contour nests, where reversing an inner loop makes it a hole.
The implementation triangulates internally but reconstructs exterior and hole
loops before returning a @racket[path-geometry?], so applying a cosmetic stroke
does not reveal triangulation seams.

@defproc[(path-union [first path-geometry?]
                     [second path-geometry?]
                     [#:curve-samples curve-samples exact-positive-integer? 16]
                     [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

Returns the filled union of @racket[first] and @racket[second].
}

@defproc[(path-intersection [first path-geometry?]
                            [second path-geometry?]
                            [#:curve-samples curve-samples exact-positive-integer? 16]
                            [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

Returns the filled region common to @racket[first] and @racket[second]. A
touching-without-area intersection is @racket[empty-path-geometry].
}

@defproc[(path-difference [first path-geometry?]
                          [second path-geometry?]
                          [#:curve-samples curve-samples exact-positive-integer? 16]
                          [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

Returns the filled portion of @racket[first] outside @racket[second].
}

@defproc[(path-xor [first path-geometry?]
                   [second path-geometry?]
                   [#:curve-samples curve-samples exact-positive-integer? 16]
                   [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

Returns points covered by exactly one operand.
}

@defproc[(cutout [outer path-geometry?]
                 [inner path-geometry?]
                 [#:curve-samples curve-samples exact-positive-integer? 16]
                 [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

A readable alias for @racket[path-difference], intended for a filled outer
shape from which @racket[inner] is removed.
}

@defproc[(clip-to [subject path-geometry?]
                  [clip path-geometry?]
                  [#:curve-samples curve-samples exact-positive-integer? 16]
                  [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

With two paths, returns the geometry-level clipping of @racket[subject] to
@racket[clip]. It is a readable alias for @racket[path-intersection].

@racket[clip-to] also accepts an affine Visual as @racket[subject] and a local
@racket[path-geometry?] as @racket[clip]. In that form, supply @racket[#:id]
to receive a @racket[clipped-visual?]: a normal affine/opacity Visual that
clips the complete vector content at render time. Its content and clip path
move, rotate, scale, and fade together. The optional Boolean quality and fill
rule keywords apply only to the two-path form.
}

@defproc[(mask-with [subject path-geometry?]
                    [mask path-geometry?]
                    [#:curve-samples curve-samples exact-positive-integer? 16]
                    [#:fill-rule fill-rule (or/c 'odd-even 'nonzero) 'odd-even])
         path-geometry?]{

With two paths, returns the geometry-level mask of @racket[subject] by
@racket[mask]. Its filled-region semantics are the same as @racket[clip-to].
The affine-Visual-plus-path overload constructs the same vector-preserving
wrapper, but uses masking terminology.
}

@defproc[(clip-visual [content affine-visual?]
                      [path path-geometry?]
                      [#:id id symbol?]
                      [#:center center vec2? origin]
                      [#:rotation rotation finite-real? 0]
                      [#:scale scale scale-factor? 1]
                      [#:opacity opacity opacity? 1])
         clipped-visual?]{

Constructs the low-level clipping wrapper used by the Visual overloads above.
Normally @racket[clip-to] is clearer.
}

@defproc[(clipped-visual? [value any/c]) boolean?]{
Recognizes the vector-preserving clipping wrapper returned by the Visual
overloads of @racket[clip-to], @racket[mask-with], and @racket[clip-visual].
}

@bold{Current limits:} @racket['odd-even] repairs contours with proper
self-crossings, but rejects touching or overlapping segments;
@racket['nonzero] rejects crossing contour boundaries; and cubic input is
flattened rather than preserved as cubic output.


@section[#:tag "affine-transforms"]{Affine Transforms}

@declare-exporting[animate #:use-sources (animate/main)]

Affine-transform values are created through @racket[make-affine-transform].
The raw structure constructor is not part of the public API.

@defproc[(affine-transform? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is an affine-transform value.
}

@defproc[(affine-transform-translation [transform affine-transform?]) vec2?]{

Returns the translation component of @racket[transform] in its containing
coordinate system. A top-level Visual normally uses world coordinates. A child
Visual normally uses coordinates local to its group.
}

@defproc[(affine-transform-rotation [transform affine-transform?])
         finite-real?]{

Returns the counter-clockwise rotation of @racket[transform] in radians.
}

@defproc[(affine-transform-scale [transform affine-transform?]) vec2?]{

Returns the positive x and y scale factors of @racket[transform]. A uniform
scale is stored with equal components.
}

@defproc[(scale-factor? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is either a positive finite real number
or a @racket[vec2] whose two components are positive. A number represents
uniform scale. A @racket[vec2] represents separate x and y scale.
}

@defproc[(scale-factor->vec2 [value scale-factor?]) vec2?]{

Converts a scale factor to two components. A numeric value @racket[s] becomes
@racket[(vec2 s s)]. A @racket[vec2] value is returned unchanged.
}

@defproc[(make-affine-transform
          [#:translation translation vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1])
         affine-transform?]{

Creates a validated decomposed transform. Translation is measured in the
coordinate system that contains the transformed value. Translation is applied
last, rotation is counter-clockwise, and scale is normalized with
@racket[scale-factor->vec2].
}

@defthing[identity-affine-transform affine-transform?]{

The transform with zero translation, zero rotation, and scale
@racket[(vec2 1 1)]. It leaves every point unchanged.
}

@defproc[(affine-transform-with-translation
          [transform affine-transform?]
          [translation vec2?])
         affine-transform?]{

Returns a new transform with @racket[translation] installed. Rotation and
scale are preserved.
}

@defproc[(affine-transform-with-rotation
          [transform affine-transform?]
          [rotation finite-real?])
         affine-transform?]{

Returns a new transform with @racket[rotation] installed. Translation and scale
are preserved.
}

@defproc[(affine-transform-with-scale
          [transform affine-transform?]
          [scale scale-factor?])
         affine-transform?]{

Returns a new transform with @racket[scale] installed. Translation and
rotation are preserved. Numeric scales are normalized to a @racket[vec2].
}

@defproc[(affine-transform-lerp
          [from affine-transform?]
          [to affine-transform?]
          [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         affine-transform?]{

Interpolates translation, rotation, and scale componentwise. Progress must be
between @racket[0] and @racket[1], inclusive.

Rotation is interpolated as an ordinary number. The procedure does not choose
the shortest path around a circle. For example, interpolation from
@racket[0] to @racket[(* 2 pi)] describes one full turn.
}

@defproc[(affine-transform-apply-vector
          [transform affine-transform?]
          [vector vec2?])
         vec2?]{

Applies scale and rotation to a displacement vector. Translation is ignored,
because a displacement has no fixed position.
}

@defproc[(affine-transform-apply-point
          [transform affine-transform?]
          [point vec2?])
         vec2?]{

Applies scale, rotation, and translation to a point, in that order.
}

@subsection{General Affine Maps}

SCENE-CY-A keeps @racket[affine-transform] as the established decomposed
placement protocol and adds @racket[linear2] and @racket[affine2] for general
mathematical maps. A @racket[linear2] value represents the matrix

@centered{@tt{| a  b |   | c  d |}}

acting on column vectors. Matrix entries may be negative or form a singular
matrix. In particular, entry-wise interpolation toward a reflection normally
passes through a singular map.

The public constructor follows the displayed row order, which keeps matrix
literals readable when split across lines:

@racketblock[
(linear2 a b
         c d)
]

An @racket[affine2] adds the translation column in the same order:

@racketblock[
(affine2 a b h
         c d k)
]

This represents @racket[(values (+ (* a x) (* b y) h)
                         (+ (* c x) (* d y) k))].

@defproc[(linear2? [value any/c]) boolean?]{

Returns @racket[#t] for a general two-dimensional linear map.
}

@defproc[(linear2 [a finite-real?]
                  [b finite-real?]
                  [c finite-real?]
                  [d finite-real?])
         linear2?]{

Constructs the matrix @tt{| a  b |   | c  d |}. The arguments are in row
order.
}

@defproc[(make-linear2 [a finite-real?]
                        [b finite-real?]
                        [c finite-real?]
                        [d finite-real?])
         linear2?]{

Convenience constructor for the matrix @tt{| a  b |   | c  d |}. Its arguments
have the same row order as @racket[linear2].
}

@defthing[identity-linear2 linear2?]{

The identity matrix.
}

@defproc[(linear2-a [map linear2?]) finite-real?]{Returns the @racket[a] entry.}
@defproc[(linear2-b [map linear2?]) finite-real?]{Returns the @racket[b] entry.}
@defproc[(linear2-c [map linear2?]) finite-real?]{Returns the @racket[c] entry.}
@defproc[(linear2-d [map linear2?]) finite-real?]{Returns the @racket[d] entry.}

@defproc[(linear2-determinant [map linear2?]) finite-real?]{

Returns @racket[(- (* a d) (* b c))] for @racket[map].
}

@defproc[(linear2-invert [map linear2?]) (or/c linear2? #f)]{

Returns the inverse of @racket[map], or @racket[#f] when its determinant is
zero. This is useful when converting a world-space affine request to a mapped
child's local coordinate system.
}

@defproc[(linear2-compose [outer linear2?] [inner linear2?]) linear2?]{

Returns @racket[outer] composed after @racket[inner].
}

@defproc[(linear2-apply-vector [map linear2?] [vector vec2?]) vec2?]{

Applies @racket[map] to one displacement vector.
}

@defproc[(affine2? [value any/c]) boolean?]{

Returns @racket[#t] for a general linear map followed by translation.
}

@defproc[(affine2 [a finite-real?]
                  [b finite-real?]
                  [h finite-real?]
                  [c finite-real?]
                  [d finite-real?]
                  [k finite-real?])
         affine2?]{

Constructs the affine map @racket[(values (+ (* a x) (* b y) h)
                                  (+ (* c x) (* d y) k))]. The entries are in
augmented-row order: @racket[(affine2 a b h c d k)].
}

@defproc[(make-affine2
          [#:linear linear linear2? identity-linear2]
          [#:translation translation vec2? origin])
         affine2?]{

Constructs a general affine map. The linear map acts first and translation is
added afterward. Use this keyword form when the linear and translation parts
are already available separately; use @racket[affine2] for a matrix literal.
}

@defthing[identity-affine2 affine2?]{

The identity general affine map.
}

@defproc[(affine2-linear [map affine2?]) linear2?]{

Returns @racket[map]'s linear component.
}

@defproc[(affine2-translation [map affine2?]) vec2?]{

Returns @racket[map]'s translation component.
}

@defproc[(affine2-a [map affine2?]) finite-real?]{Returns the @racket[a] entry.}
@defproc[(affine2-b [map affine2?]) finite-real?]{Returns the @racket[b] entry.}
@defproc[(affine2-h [map affine2?]) finite-real?]{Returns the x translation @racket[h].}
@defproc[(affine2-c [map affine2?]) finite-real?]{Returns the @racket[c] entry.}
@defproc[(affine2-d [map affine2?]) finite-real?]{Returns the @racket[d] entry.}
@defproc[(affine2-k [map affine2?]) finite-real?]{Returns the y translation @racket[k].}

@defproc[(affine2-with-linear [map affine2?] [linear linear2?]) affine2?]{

Returns @racket[map] with a replacement linear component.
}

@defproc[(affine2-with-translation [map affine2?] [translation vec2?]) affine2?]{

Returns @racket[map] with a replacement translation.
}

@defproc[(affine2-invert [map affine2?]) (or/c affine2? #f)]{

Returns the inverse of @racket[map], or @racket[#f] when its linear component
is singular.
}

@defproc[(affine2-compose [outer affine2?] [inner affine2?]) affine2?]{

Returns @racket[outer] composed after @racket[inner].
}

@defproc[(affine2-lerp [from affine2?]
                        [to affine2?]
                        [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         affine2?]{

Interpolates the four matrix entries and translation componentwise. It does
not preserve invertibility.
}

@defproc[(affine2-apply-vector [map affine2?] [vector vec2?]) vec2?]{

Applies only @racket[map]'s linear component to @racket[vector].
}

@defproc[(affine2-apply-point [map affine2?] [point vec2?]) vec2?]{

Applies both the linear component and translation to @racket[point].
}

@defproc[(affine-transform->affine2 [transform affine-transform?]) affine2?]{

Converts the established scale-then-rotate-then-translate representation to an
exact general affine map.
}

@section[#:tag "cameras"]{Cameras}

@declare-exporting[animate #:use-sources (animate/main)]

A camera is an immutable orthographic view. Its pixel dimensions, visible
world width, center, and background are explicit values. The raw camera
constructor is not public; use @racket[make-camera]. A scene can store and
animate camera values without mutating them.

@defproc[(camera? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a camera value.
}

@defproc[(camera-width [camera camera?]) exact-positive-integer?]{

Returns the output width in pixels.
}

@defproc[(camera-height [camera camera?]) exact-positive-integer?]{

Returns the output height in pixels.
}

@defproc[(camera-world-width [camera camera?])
         (and/c finite-real? positive?)]{

Returns the visible width in world units.
}

@defproc[(camera-center [camera camera?]) vec2?]{

Returns the world point placed at the center of the output frame.
}

@defproc[(camera-background [camera camera?]) any/c]{

Returns the background style stored in the camera. The built-in Pict adapter
passes this value to Pict as a color. A color name string is the usual choice.
The value is not checked until an adapter uses it.
}

@defproc[(make-camera
          [#:width width exact-positive-integer? 1280]
          [#:height height exact-positive-integer? 720]
          [#:world-width world-width
                         (and/c finite-real? positive?)
                         14]
          [#:center center vec2? origin]
          [#:background background any/c "white"])
         camera?]{

Creates an immutable orthographic camera value. The aspect ratio comes from
@racket[width] and @racket[height]. The visible world height is derived from
that aspect ratio and @racket[world-width].
}

@defthing[default-camera camera?]{

The default camera: 1280 by 720 pixels, 14 world units wide, centered at
@racket[origin], with a white background.
}

@defproc[(camera-scale [camera camera?])
         (and/c real? positive?)]{

Returns the number of pixels per world unit. It is
@racket[(/ (camera-width camera) (camera-world-width camera))].
}

@defproc[(camera-world-height [camera camera?])
         (and/c real? positive?)]{

Returns the visible height in world units. It preserves the camera's pixel
aspect ratio.
}

@defproc[(camera-length->pixels [camera camera?]
                                [length finite-real?])
         real?]{

Converts a signed world-space length to pixels. The procedure multiplies by
@racket[camera-scale]. It does not take an absolute value.
}

@defproc[(camera-world->pixel [camera camera?]
                              [point vec2?])
         (values real? real?)]{

Returns two values: the pixel x coordinate and the pixel y coordinate of
@racket[point]. The camera center maps to the center of the output frame.
World y increases upward, while pixel y increases downward.
}

@defproc[(camera-pan-to [center vec2?]) camera-pan-to-request?]{

Creates an absolute camera-center request for @racket[scene-play]. At eased
progress one, @racket[center] is the world point in the middle of the frame.
The camera's pixel dimensions, visible width, aspect ratio, and background are
unchanged.
}

@defproc[(camera-pan-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-pan-to].
}

@defproc[(camera-pan-by [delta vec2?]) camera-pan-by-request?]{

Creates a relative camera-center request. When @racket[scene-play] compiles the
request, it adds @racket[delta] to the camera center at the beginning of that
clip. The request does not capture a camera when it is constructed.
}

@defproc[(camera-pan-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-pan-by].
}

@defproc[(camera-zoom-to
          [world-width (and/c finite-real? positive?)])
         camera-zoom-to-request?]{

Creates an absolute camera zoom request. @racket[world-width] is the requested
visible frame width in world units. A smaller width shows less of the world and
therefore appears more magnified. During a clip, visible world width is
interpolated linearly after easing; interpolation is not logarithmic. Pixel
width, pixel height, center, and background remain unchanged unless another
request changes the center.
}

@defproc[(camera-zoom-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-zoom-to].
}

@defproc[(camera-zoom-by [factor (and/c finite-real? positive?)])
         camera-zoom-by-request?]{

Creates a relative magnification request. The target visible width is the
clip-start camera width divided by @racket[factor]. Thus @racket[2] zooms in by
two, @racket[1] leaves magnification unchanged, and @racket[1/2] zooms out by
two. The resulting target width is interpolated linearly from the clip-start
width after easing.

Compilation raises an exception if the division produces a nonpositive or
non-finite visible width.
}

@defproc[(camera-zoom-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-zoom-by].
}

@defproc[(camera-follow [target (or/c visual? symbol?)])
         camera-follow-request?]{

Creates a clip-local request that keeps the reference position of
@racket[target] at its clip-start pixel position. The target is resolved as a
current top-level scene Visual when @racket[scene-play] compiles the request.
Nested group children are not searched.

Frame-space Visuals are not valid follow targets; camera following is defined
only for world-space top-level Visuals. A SCENE-AW derived target is resolved
against the same sampled scalar state before its world-space position is read.

At each scene sample, following reads the target's actual sampled
@racket[visual-position] at the same eased progress as its Visual animations.
The pre-removal motion state is retained for camera completion, so the request
can follow a Visual introduced by @racket[fade-in] or @racket[create], and it
can follow a Visual until a same-clip @racket[fade-out] or @racket[uncreate]
removes it at the structural endpoint. The sampled @racket[visual-position]
result must be a @racket[vec2].

Following preserves normalized horizontal and vertical frame position. When a
zoom request runs in the same clip, the camera adjusts its world-space offset
as the visible width changes, so the target remains at the same pixel
coordinates. Because the sampled Visual state supplies the position, the camera
also follows nonlinear motion such as @racket[move-along-path] through a bend or
curve rather than interpolating only between clip endpoints. The request changes
the camera-center component and may run with one zoom request. It conflicts with
pan, fitting, or another follow request.

Following tracks only @racket[visual-position], not the target's rendered box,
rotation, scale, or shape. It lasts for one play clip. It does not install a
persistent observer. Camera-only clips without following do not require scene
state sampling.
}

@defproc[(camera-follow-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-follow].
}

@defproc[(camera-fit-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a camera-fit request created
by @racket[camera-fit-layout-box], @racket[camera-fit-visuals], or
@racket[camera-fit-scene], including the @racket[camera-focus] specialization.
A fit request changes camera center and visible world width together. It
therefore reserves both camera components in one play clip.
}

@defproc[(camera-fit-request-center [request camera-fit-request?]) vec2?]{

Returns the immutable measured center stored in @racket[request]. This is most
useful when inspecting a fit or passing it to a secondary camera; ordinary
scene code normally supplies the complete request directly to
@racket[scene-play] or @racket[camera-view-fit].
}

@defproc[(camera-fit-request-world-width [request camera-fit-request?])
         (and/c finite-real? positive?)]{

Returns the immutable measured visible world width stored in @racket[request].
}

@defproc[(camera-fit-layout-box
          [box layout-box?]
          [#:camera camera camera? default-camera]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a camera-fit request for @racket[box]. The target camera center is
@racket[(layout-box-center box)]. The target visible width is the larger of:

@itemlist[
 @item{the box width plus @racket[padding] on both horizontal sides; and}
 @item{the width needed to contain the padded box height while preserving the
       pixel aspect ratio of @racket[camera].}]

Padding is measured in world units and is applied equally on all four sides
before aspect-ratio correction. Pixel width, pixel height, and background are
preserved. A zero-size box with zero padding is rejected because it would
produce a nonpositive visible width.

The result is a snapshot request. It stores only the concrete target center and
visible width; it does not retain @racket[box] or recompute it during animation.
Use a camera with the same pixel aspect ratio as the scene camera that will run
the request. The stored fit is not recomputed for a different aspect ratio.
}

@defproc[(camera-fit-visuals
          [visuals (and/c (listof visual?) pair?)]
          [#:camera camera camera? default-camera]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Measures the complete rendered union of @racket[visuals] with
@racket[visuals-layout-box], then creates the corresponding fit request.
The list must be nonempty, every Visual must use the same containing
coordinate system, and every supplied Visual must belong to world space.
Frame-space overlays and callouts are not camera-fit geometry.

Measurement uses @racket[camera] and the first-supporting renderer rule from
@racket[renderers]. Custom renderer padding therefore participates in fitting.
A standalone @racket[derived-visual?] cannot be measured here because this
function has no scene-state scalar context; use @racket[camera-fit-scene] for a
derived top-level target.
Measuring a nonempty formula through the built-in formula renderer can invoke
LaTeX and Poppler. Opacity does not change the measured Pict dimensions.

The values are measured when this function is called. Geometry or renderer
changes later in the same clip do not cause automatic remeasurement. The fit is
also not recomputed at its target zoom. A custom renderer whose Pict has a fixed
pixel size can therefore occupy a different world-space size at the endpoint.
To fit a planned endpoint in the same clip, supply Visual values and a
measurement camera that describe the intended view as closely as possible.
}

@defproc[(camera-fit-scene
          [scene scene?]
          [#:targets targets
                     (or/c false/c
                           (and/c pair?
                                  (listof (or/c visual? symbol? visual-path?))))
                     #f]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a fit request from @racket[scene]'s current endpoint state and current
camera. When @racket[targets] is @racket[#f], all current top-level
@emph{world-space} Visuals are measured in back-to-front order; frame-space
overlays and callouts are ignored. Otherwise, @racket[targets] must be a
nonempty list of Visual values, symbols, or explicit nonempty Visual paths, and
every resolved target must be a world-space Visual. A top-level target is
resolved by stable identity against @racket[(scene-current-state scene)], so a
stale constructor value still selects the current scene value. A nested path is
resolved with every enclosing group/formula transform and opacity composed into
an independently measurable world-space Visual. SCENE-AW derived definitions
are additionally evaluated against the current endpoint scalar values before
measurement.

A scene with no world-space Visuals, an empty target list, a missing target, or
an explicitly selected frame-space target raises an exception. The result is a
snapshot of the current endpoint state and does not follow later scene changes.
}

@defproc[(camera-focus
          [scene scene?]
          [focus (or/c visual? symbol? visual-path?)]
          [#:context context
                     (listof (or/c visual? symbol? visual-path?))
                     '()]
          [#:renderers renderers
                       pict-renderer-list?
                       default-pict-renderers]
          [#:padding padding
                     (and/c finite-real? (>=/c 0))
                     1/2])
         camera-fit-request?]{

Creates a renderer-aware fit around one explanatory subject and zero or more
explicit context Visuals. @racket[focus] and every value in @racket[context]
may be a current top-level Visual, its symbol identity, or an explicit nested
Visual path. The request is equivalent to a @racket[camera-fit-scene] selection
whose first target is the focus, but its named @racket[#:context] argument makes
the pedagogical framing decision clear at the call site.

All selected targets are measured in fully composed world coordinates. This
makes an imported SVG element or formula/group child a useful focus subject
without rebuilding its parent. Frame-space targets are rejected. The request is
a current-scene snapshot: it does not choose context automatically, remeasure
during the clip, or live-follow later subject/context motion.
}

@section[#:tag "frame-space"]{Frame-Space Overlays and Callouts}

@declare-exporting[animate #:use-sources (animate/main)]

Frame-space Visuals are semantic wrappers, not cached Picts. They remain
ordinary top-level Visuals with stable identity and can participate in
@racket[move-to], rotation, scale, opacity, structural fade, and ordinary scene
ordering. Their reference positions are interpreted in frame coordinates by
the adapter rather than world coordinates.

@defproc[(frame-space-visual? [value any/c]) boolean?]{

Returns @racket[#t] for the built-in @racket[fixed-in-frame],
@racket[camera-view], and @racket[callout] wrapper values.
}

@defproc[(frame-space-visual-frame-width [visual frame-space-visual?])
         (and/c finite-real? positive?)]{

Returns the visible width of @racket[visual]'s captured frame coordinate
system. This is normally the @racket[camera-world-width] of the camera supplied
when the wrapper was constructed.
}

@defproc[(frame-space-camera
          [camera camera?]
          [frame-width (and/c finite-real? positive?)])
         camera?]{

Returns an origin-centered camera with the pixel width, pixel height, and
background of @racket[camera], but with visible world width
@racket[frame-width]. The Pict adapter uses this derived camera for frame-space
measurement, local rendering, and frame-coordinate placement. The input
camera's center and visible world width are deliberately ignored.
}

@defproc[(fixed-in-frame
          [content visual?]
          [#:camera camera camera? default-camera]
          [#:at position (or/c vec2? false/c) #f]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1])
         fixed-in-frame-visual?]{

Wraps @racket[content] as a frame-space overlay. The wrapper preserves
@racket[(visual-id content)] as its top-level identity. The content remains
semantic model data and is rendered locally at the frame-space origin; its own
geometry, rotation, scale, style, and opacity remain significant. The wrapper's
rotation, scale, and opacity are additional outer transforms.

The wrapper snapshots @racket[(camera-world-width camera)]. If @racket[position]
is @racket[#f], its initial frame position is
@racket[(vec2- (visual-position content) (camera-center camera))]. Therefore a
Visual wrapped with the camera through which it is currently being viewed keeps
the same pixel position and size at the moment it becomes fixed. An explicit
@racket[position] is interpreted directly in the captured origin-centered frame
coordinate system.

Later world-camera pan and zoom do not change the overlay's frame position or
local rendering scale. Animated output pixel dimensions are not supported by
the camera model, but a static rendering override with different pixel
dimensions scales frame content with the output frame. Frame-space wrappers
cannot be nested inside one another and must remain top-level scene Visuals.
For a compound overlay, construct an ordinary @racket[group] first and wrap the
complete group.
}

@defproc[(fixed-in-frame-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a fixed-in-frame wrapper.
}

@defproc[(fixed-in-frame-visual-content
          [visual fixed-in-frame-visual?])
         visual?]{

Returns the semantic content stored by @racket[visual]. The returned content is
not a scene-state child and cannot be targeted directly while it is wrapped.
}

@defproc[(camera-view
          [target (or/c false/c visual? symbol? visual-path?) #f]
          [#:id id symbol?]
          [#:targets targets
                     (or/c false/c
                           (and/c pair?
                                  (listof (or/c visual? symbol? visual-path?))))
                     #f]
          [#:camera camera camera?]
          [#:frame-camera frame-camera camera? default-camera]
          [#:at position vec2? origin]
          [#:width width (and/c finite-real? positive?) 3]
          [#:clip clip (or/c 'rectangle 'rounded 'rounded-frame) 'rectangle]
          [#:opacity opacity opacity? 1])
         camera-view-visual?]{

Creates a frame-fixed viewport onto live world-space Visuals.
@racket[camera] is the immutable orthographic camera used inside the inset.
@racket[frame-camera] supplies the captured origin-centered frame coordinate
system for @racket[position] and @racket[width], just as @racket[#:camera]
does for @racket[fixed-in-frame]. The default position is the frame origin.

Supply either positional @racket[target] or a nonempty @racket[#:targets] list,
not both. A target may be a Visual, top-level symbol, or built-in group/formula
@racket[visual-path?]. If both target arguments are omitted, the view uses every
top-level world-space layer in ordinary drawing order. Frame-space overlays,
including other views, are deliberately excluded from this all-layer form so an
inset cannot recursively render itself. Each explicit target must resolve to
world space.

At scene rendering time, selected Visuals are resolved against the same sampled
state as ordinary Visuals and painted in order onto the complete inset camera
canvas. Their complete world transforms and opacity are therefore synchronized
between main view and inset. @racket[#:clip] chooses a rectangle or rounded
rectangle viewport border; @racket['rounded-frame] is a compatibility alias for
@racket['rounded]. The viewport itself is an affine/opacity frame-space Visual
and can be moved, rotated, scaled, faded, or structurally removed.

Unlike a fixed overlay, the viewport cannot be converted by
@racket[visual->pict] by itself because resolving its live targets needs a
sampled scene state. Use complete scene rendering such as
@racket[scene-state->pict] or @racket[render-frames!] instead.
}

@defproc[(camera-view-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a @racket[camera-view] wrapper.
}

@defproc[(camera-view-visual-target [visual camera-view-visual?])
         (or/c false/c symbol? visual-path?)]{

Compatibility accessor for a one-target view. It returns the normalized world
target for a positional target, but @racket[#f] for a multi-target or all-layer
view. Use @racket[camera-view-visual-targets] for the general selection.
}

@defproc[(camera-view-visual-targets [visual camera-view-visual?])
         (or/c false/c (listof (or/c symbol? visual-path?)))]{

Returns the normalized explicit target list in declaration order. It returns
@racket[#f] when @racket[visual] represents an all-world-layers view.
}

@defproc[(camera-view-visual-camera [visual camera-view-visual?]) camera?]{

Returns the immutable world-space camera used to render the inset.
}

@defproc[(camera-view-visual-with-camera [visual camera-view-visual?]
                                          [camera camera?])
         camera-view-visual?]{

Returns @racket[visual] with only its immutable secondary camera replaced.
The helper preserves its identity, fixed frame pose, target selection, clip,
and opacity. It is also the semantic operation used by sampled view-camera
animations.
}

@defproc[(camera-view-visual-width [visual camera-view-visual?])
         (and/c finite-real? positive?)]{

Returns the inset's width in its captured frame coordinate system.
}

@defproc[(camera-view-visual-clip [visual camera-view-visual?])
         (or/c 'rectangle 'rounded)]{

Returns the normalized viewport clip shape. A constructor's
@racket['rounded-frame] value is normalized to @racket['rounded].
}

@defproc[(camera-view-pan-to [view (or/c symbol? camera-view-visual?)]
                              [center vec2?])
         camera-view-pan-to-request?]{

Creates an absolute center transition for the named secondary camera. The
ordinary scene camera is unaffected.
}

@defproc[(camera-view-pan-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-pan-to].
}

@defproc[(camera-view-pan-by [view (or/c symbol? camera-view-visual?)]
                              [delta vec2?])
         camera-view-pan-by-request?]{

Creates a clip-start-relative secondary-camera center transition.
}

@defproc[(camera-view-pan-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-pan-by].
}

@defproc[(camera-view-zoom-to [view (or/c symbol? camera-view-visual?)]
                               [world-width (and/c finite-real? positive?)])
         camera-view-zoom-to-request?]{

Creates an absolute secondary-camera visible-width transition. A smaller width
appears more magnified.
}

@defproc[(camera-view-zoom-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-zoom-to].
}

@defproc[(camera-view-zoom-by [view (or/c symbol? camera-view-visual?)]
                               [factor (and/c finite-real? positive?)])
         camera-view-zoom-by-request?]{

Creates a relative magnification transition: a factor of @racket[2] divides
the clip-start secondary-camera width by two.
}

@defproc[(camera-view-zoom-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-zoom-by].
}

@defproc[(camera-view-follow [view (or/c symbol? camera-view-visual?)]
                             [target (or/c visual? symbol? visual-path?)])
         camera-view-follow-request?]{

Creates one clip-local follow. At each sample the request first samples
ordinary world motion, then reads @racket[target]'s world-space reference
position and updates the inset center to retain that target's clip-start
offset. This remains a random-access computation; it retains no previous
frame. Follow may run with a view zoom, but conflicts with another view-center
request for the same inset.
}

@defproc[(camera-view-follow-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-follow].
}

@defproc[(camera-view-fit [view (or/c symbol? camera-view-visual?)]
                          [fit camera-fit-request?])
         camera-view-fit-request?]{

Creates a joint center/width secondary-camera transition to a prior measured
@racket[fit]. Build it with @racket[camera-fit-layout-box],
@racket[camera-fit-visuals], or @racket[camera-fit-scene] using a camera with
the inset's pixel aspect ratio. The fit remains a snapshot: it is not
remeasured while the clip runs.
}

@defproc[(camera-view-fit-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[camera-view-fit].
}

@defproc[(callout
          [content visual?]
          [target (or/c visual? symbol? visual-path? vec2?)]
          [#:camera camera camera? default-camera]
          [#:at position (or/c vec2? false/c) #f]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:target-anchor target-anchor
                           (or/c 'bottom-left 'bottom 'bottom-right
                                 'left 'center 'right
                                 'top-left 'top 'top-right)
                           'center]
          [#:connector-stroke connector-stroke any/c "black"]
          [#:connector-width connector-width
                             (and/c finite-real? (>=/c 0))
                             2])
         callout-visual?]{

Creates a fixed frame-space annotation with a leader line to a world-space
target. The frame placement and outer transform use the same semantics as
@racket[fixed-in-frame]. A Visual target is stored by stable identity. A symbol
is already a top-level target identity, and a nonempty @racket[visual-path?]
selects a built-in group/formula descendant. A @racket[vec2] is a fixed
world-space point.

Visual-path targets are resolved against each sampled scene state when a
complete scene is converted to a Pict. A nested result has every enclosing
group/formula transform and opacity composed before its world position is read.
This makes the connector follow ordinary movement of a target or its parent
without adding observer state to the timeline. SCENE-AW derived targets are
resolved from the same sampled scalar state. The resolved Visual must belong to
world space. A missing target or a frame-space target raises an exception at
scene rendering.

The connector is drawn beneath the annotation from the target's current world
pixel position to the edge of the complete annotation Pict box. For a Visual
target, @racket[target-anchor] selects the target's live renderer-box center,
edge, or corner; it is measured as each scene sample is rendered, so it follows
target size changes as well as movement. A literal @racket[vec2] target accepts
only the default @racket['center] anchor. Its width is a cosmetic pixel width.
A false @racket[connector-stroke] or a zero @racket[connector-width] suppresses
the line. The callout's outer opacity also applies to the connector.

@racket[visual->pict] on a callout returns only its local annotation Pict,
because resolving a symbolic connector target requires a complete sampled scene
state. @racket[scene-state->pict] and higher-level frame rendering include both
the leader and the annotation.
}

@defproc[(callout-visual? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a built-in callout Visual.
}

@defproc[(callout-visual-content [visual callout-visual?]) visual?]{

Returns the semantic annotation content stored by @racket[visual].
}

@defproc[(callout-visual-target [visual callout-visual?])
         (or/c symbol? visual-path? vec2?)]{

Returns the normalized callout target. Visual-valued constructor targets appear
here as their stable symbol identity; an explicit nested path is preserved;
fixed world points remain @racket[vec2] values.
}

@defproc[(callout-visual-target-anchor [visual callout-visual?]) symbol?]{

Returns the selected live renderer-box anchor for a Visual target.
}

@defproc[(callout-visual-connector-stroke [visual callout-visual?]) any/c]{

Returns the opaque connector stroke style stored by @racket[visual]. A false
value disables the connector during built-in scene rendering.
}

@defproc[(callout-visual-connector-width [visual callout-visual?])
         (and/c finite-real? (>=/c 0))]{

Returns the cosmetic connector width in output pixels.
}

Renderer-aware relative layout recognizes frame-space coordinates. Layout of a
single frame-space Visual uses its captured frame scale, so the result is
independent of later world-camera pan or zoom. Pair and list layout operations
may combine frame-space Visuals only when they have the same captured frame
width. Mixing world and frame coordinate domains in one relative-layout
calculation raises an exception. A callout layout box measures its fixed
annotation Pict only; the cross-space connector is deliberately not part of
frame-space layout.

World-camera operations deliberately exclude frame-space content:
@racket[camera-fit-visuals] rejects it, @racket[camera-fit-scene] ignores it for
implicit all-scene fitting and rejects it when explicitly selected, and
@racket[camera-follow] cannot follow a frame-space target.

@section[#:tag "semantic-colors"]{Semantic Colors and Paints}

@declare-exporting[animate #:use-sources (animate/main)]

SCENE-AT introduces a small renderer-independent color representation for style
interpolation. Existing Visual constructors still accept their historical color
strings; semantic RGBA values are needed only when an animation is sampled in
its interior or when callers choose to construct one explicitly.

@defstruct*[rgba-color ([red (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [green (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [blue (and/c finite-real? (>=/c 0) (<=/c 255))]
                        [alpha opacity?])
  #:transparent]{

Represents one semantic sRGB color. Red, green, and blue are channel values from
zero through 255; alpha is in the closed unit interval. The constructor rejects
infinities, NaN values, and out-of-range components. The value has no dependency
on @racketmodname[racket/draw].
}

@defproc[(rgb-color [red (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [green (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [blue (and/c finite-real? (>=/c 0) (<=/c 255))])
         rgba-color?]{

Constructs an opaque @racket[rgba-color] whose alpha component is one.
}

@defproc[(color-spec? [value any/c]) boolean?]{

Returns @racket[#t] for an @racket[rgba-color] or a supported textual color.
Text accepts X11-style names from Racket's drawing color family case-insensitively
(common spaces, hyphens, and underscores are ignored), @tt{#RGB}, @tt{#RGBA}, @tt{#RRGGBB}, and
@tt{#RRGGBBAA}. @tt{transparent} is the zero-alpha black semantic color.
}

@defproc[(color-spec->rgba-color [value any/c]
                                 [who symbol? 'color-spec->rgba-color])
         rgba-color?]{

Resolves @racket[value] to semantic RGBA channels. An existing
@racket[rgba-color] is returned unchanged. Unsupported strings and other values
raise an argument error attributed to @racket[who].
}

@defproc[(rgba-color-lerp [from rgba-color?]
                          [to rgba-color?]
                          [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         rgba-color?]{

Interpolates red, green, blue, and alpha componentwise in sRGB value space.
This is intentionally a deterministic semantic interpolation rather than a
color-managed or perceptual color-space conversion.
}

@subsection{Semantic fill paints}

SCENE-EC extends a fill from a solid @racket[color-spec?] to an immutable
semantic @racket[paint?]. These values contain neither a drawing-context brush
nor a bitmap. The Pict/racket-draw adapter creates a native vector gradient
brush only when it renders a supported Visual, so a paint remains ordinary scene
data through sampling, affine transforms, and clipping.

@defstruct*[paint-stop ([offset (and/c finite-real? (>=/c 0) (<=/c 1))]
                        [color color-spec?])
  #:transparent]{

One ordered gradient stop. Stop offsets are positions along the unit gradient
range. A gradient requires at least two stops in nondecreasing offset order.
}

@defstruct*[linear-gradient-paint ([start vec2?]
                                  [end vec2?]
                                  [stops (listof paint-stop?)])
  #:transparent]{

An immutable local-coordinate linear gradient description. Use
@racket[linear-gradient] rather than constructing the structure directly in
ordinary code.
}

@defproc[(linear-gradient [start vec2?]
                           [end vec2?]
                           [stops (and/c list? pair?)])
         linear-gradient-paint?]{

Creates a linear gradient from @racket[start] to @racket[end]. Both points are
in the receiving Visual's local coordinate system, rather than video pixels or
world coordinates. The same gradient therefore follows the Visual when it is
moved, rotated, or scaled.
}

@defstruct*[radial-gradient-paint ([focal-center vec2?]
                                  [focal-radius nonnegative-real?]
                                  [center vec2?]
                                  [radius nonnegative-real?]
                                  [stops (listof paint-stop?)])
  #:transparent]{

An immutable two-circle radial gradient description. A zero focal radius gives
the ordinary point-focused form.
}

@defproc[(radial-gradient [center vec2?]
                           [radius nonnegative-real?]
                           [stops (and/c list? pair?)]
                           [#:focal-center focal-center vec2? center]
                           [#:focal-radius focal-radius nonnegative-real? 0])
         radial-gradient-paint?]{

Creates a radial gradient. Centre, focal centre, and radii are local to the
receiving Visual. The focal keywords select a general focal circle; by default
it is the zero-radius point at @racket[center].
}

@defstruct*[checker-pattern-paint ([first color-spec?]
                                   [second color-spec?]
                                   [cell-size positive-real?])
  #:transparent]{

An immutable two-colour checker pattern description.
}

@defproc[(checker-pattern [first color-spec?]
                          [second color-spec?]
                          [#:cell-size cell-size positive-real? 1])
         checker-pattern-paint?]{

Creates a local square checker pattern whose individual cells have side length
@racket[cell-size].
}

@defproc[(paint? [value any/c]) boolean?]{

Returns @racket[#t] for a supported solid @racket[color-spec?], a linear or
radial gradient, or a checker pattern. @racket[#f] is the existing absent-fill
sentinel and is deliberately not a paint.
}

@defproc[(paint-lerp [from paint?]
                      [to paint?]
                      [progress (and/c finite-real? (>=/c 0) (<=/c 1))])
         paint?]{

Interpolates compatible paints, retaining @racket[from] and @racket[to]
exactly at progress zero and one. Solid colours interpolate in sRGB value
space. Gradient endpoints, radii, stop offsets, and stop colours interpolate
componentwise, but corresponding gradients must have the same number of stops.
Checker colours and cell size interpolate similarly.

Paint kinds must agree. In particular, this function does not invent a
meaningless halfway value between a solid fill and a gradient; use a deliberate
cross-fade of two Visuals for that visual change.
}

The built-in Pict renderer supports paints on the fills of paths, circles, and
rectangles; a structured paint on a circle or rectangle is sent through its
vector path equivalent. Strokes remain solid colours. Gradients are native
vector brushes. The checker implementation is a deterministic device-aligned
stipple and does not yet follow an enclosing affine transform. Formula, SVG,
image, and custom renderer paint support remains renderer-specific.
