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


@title[#:tag "cookbook-path-motion-recipes"]{Following Paths, Tangents, and Offsets}

Move along a path, orient to its tangent, construct an offset route, or change traversal direction.

API reference: @secref["reference-animation-motion"], @secref["path-geometry"].

@local-table-of-contents[]

@; recipe-redistribution begin: path-following
@section[#:tag "path-following"]{Arc-Length Path Following}

@racket[move-along-path] makes semantic path traversal a first-class translation request.
The new point lookup operation and timeline request use the same deterministic
arc-length model as path reveal and partial extraction.

Sample a route by total ordered arc length:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 4))))

(path-geometry-point-at route 3/7) ; (vec2 3 0)
(path-geometry-point-at route 1/2) ; (vec2 3 1/2)
]

The unequal three-unit and four-unit edges demonstrate that fractions describe
arc length, not segment indexes. Under @racket[linear] easing,
@racket[move-along-path] therefore gives constant speed in route units:

@racketblock[
(scene-play scene
            (move-along-path marker route)
            #:duration 7)
]

Use @racket[#:start] and @racket[#:end] for partial or reverse traversal:

@racketblock[
(move-along-path marker route #:start 1/4 #:end 3/4)
(move-along-path marker route #:start 1 #:end 0)
]

A path Visual route is resolved by stable identity from the prepared clip-start
state and transformed to world coordinates before its arc length is measured.
Raw path geometry is instead interpreted directly in the target's containing
coordinate system. In both forms the route is a clip-start snapshot rather than
a live observer of later path deformation.

Motion routes require exactly one positive-length continuous subpath. This is
stricter than @racket[path-geometry-point-at], which can traverse general
compound geometry in stored order. The stricter timeline rule prevents an
animated Visual from teleporting across a gap between drawn subpaths.

Camera following now samples that actual path-motion state:

@racketblock[
(scene-play scene
            (move-along-path marker route)
            (camera-follow marker)
            (camera-zoom-by 3/2)
            #:duration 3)
]

The followed marker keeps its clip-start frame position even when the route
bends. This also corrects the old endpoint-only assumption for any future
nonlinear translation animation.

Render the canonical path-following example with:

@verbatim{
racket examples/path-following.rkt \
  frames/path-following \
  path-following.mp4

open path-following.mp4
}


@; recipe-redistribution end: path-following

@; recipe-redistribution begin: path-orientation-offsets
@section[#:tag "path-orientation-offsets"]{
  Path Tangents, Orientation, and Normal Offsets}

Arc-length traversal also provides semantic tangent and normal information.
Tangent and normal lookup use the same measured route fractions as
@racket[path-geometry-point-at].

For an unequal polyline:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 4))))

(path-geometry-tangent-at route 1/7) ; (vec2 1 0)
(path-geometry-normal-at route 1/7)  ; (vec2 0 1)
(path-geometry-tangent-at route 1/2) ; (vec2 0 1)
(path-geometry-normal-at route 1/2)  ; (vec2 -1 0)
]

At an exact edge boundary, the preceding positive edge owns the tangent. This
matches the point boundary rule. Cubic paths use the derivative at the
arc-length-selected parameter. A stationary endpoint or cusp uses a
deterministic one-sided fallback when the geometric direction remains
recoverable.

Offset a target to the left of its actual traversal direction with
@racket[#:normal-offset]:

@racketblock[
(move-along-path marker route #:normal-offset 1)
]

The sign is relative to motion, not merely the stored path direction. Reversing
the path therefore reverses the normal:

@racketblock[
(move-along-path marker route
                 #:start 1
                 #:end 0
                 #:normal-offset 1)
]

Normal offset is segment-local. A sharp polyline corner can jump between the
two adjacent offset edge lines. Use smooth cubic geometry when a continuous
offset trajectory is required.

Tangent orientation is a separate rotation request:

@racketblock[
(scene-play scene
            (move-along-path pointer route)
            (orient-along-path pointer route)
            #:duration 3)
]

The translation and rotation components remain independent. This lets the two
requests compose on one target while preserving ordinary component conflict
rules. Same-target @racket[rotate-to], @racket[rotate-by], or another
@racket[orient-along-path] conflicts with the orientation request.

@racket[#:rotation-offset] accommodates a Visual whose natural forward axis is
not local positive x:

@racketblock[
(orient-along-path pointer route #:rotation-offset (/ pi 2))
]

Reverse orientation points in the reverse traversal direction. A path Visual
route is resolved by stable identity from the prepared clip-start scene and
transformed into world coordinates before arc length or tangent evaluation.
Raw path geometry remains in the target's containing coordinate system. As with other path Visual routes, route geometry is a clip-start snapshot
rather than a live deforming constraint.

Camera following sees the final sampled Visual position, including any normal
offset, so a followed offset rider remains fixed at its captured frame offset.

Render the canonical path-orientation example with:

@verbatim{
racket examples/path-orientation-and-offsets.rkt \
  frames/path-orientation-and-offsets \
  path-orientation-and-offsets.mp4

open path-orientation-and-offsets.mp4
}


@; recipe-redistribution end: path-orientation-offsets

@; recipe-redistribution begin: joined-offset-paths
@section[#:tag "joined-offset-paths"]{Continuous Joined Offset Paths}

@racket[path-geometry-offset] turns segment-local normal offsets into reusable
semantic geometry for straight paths. Construct a signed parallel route with an explicit
outside-corner policy:

@racketblock[
(define route
  (polyline-path
   (list origin
         (vec2 3 0)
         (vec2 3 -2))))

(define lane
  (path-geometry-offset route 1 #:join 'round))
]

Positive offset is left of the stored path direction. In this right-turn example
that side is outside the corner, so the round policy inserts a cubic quarter
circle between the two shifted lines. Miter and bevel policies are selected the
same way:

@racketblock[
(path-geometry-offset route 1 #:join 'miter)
(path-geometry-offset route 1 #:join 'bevel)
]

Inside corners use the natural shifted-line intersection for every policy. This
is not merely an implementation shortcut: the short centered arc on the inside
would leave the incoming offset edge with the opposite tangent.

Outside miters use a default limit of four times the absolute offset distance. A
longer miter falls back to bevel; choose another finite limit of at least one with
@racket[#:miter-limit]. Round joins are stored as deterministic cubic Bézier arc
pieces, subdivided so each piece spans at most 90 degrees.

The output is ordinary path geometry, so no new animation request is needed:

@racketblock[
(scene-play scene
            (move-along-path pointer lane)
            (orient-along-path pointer lane)
            #:duration 3)
]

The rider now traverses the joined route continuously and tangent orientation
uses the line/cubic geometry of that route. Camera following likewise sees the
actual sampled rider position. Under @racket[linear] easing the speed is constant
in the joined route's own total arc length.

Nonzero path-geometry offsets deliberately accept straight source segments only. A
zero-length edge, 180-degree reversal, or cubic source segment is rejected. A
zero offset is an identity operation. Exact cubic-source parallel curves and
self-intersection cleanup remain future work.

The @racket[#:normal-offset] option of @racket[move-along-path] remains segment-local. It is useful for smooth
routes or when that exact normal rule is intended; use
@racket[path-geometry-offset] when a polyline corner must be continuous.

Render the canonical joined-offset-path example with:

@verbatim{
racket examples/joined-offset-paths.rkt \
  frames/joined-offset-paths \
  joined-offset-paths.mp4

open joined-offset-paths.mp4
}



@; recipe-redistribution end: joined-offset-paths

@; recipe-redistribution begin: reversed-cyclic-paths
@section[#:tag "reversed-cyclic-paths"]{Path Reversal and Cyclic Starts}

Path geometry provides traversal-order operations for reversal and cyclic starts. Reverse an
open or closed route with:

@racketblock[
(define reverse-route
  (path-geometry-reverse route))
]

Open routes begin at their former endpoint. Closed routes keep the same stored
start and traverse the loop in the opposite direction. This is useful when two
objects should start together and move around the same loop in opposite
directions:

@racketblock[
(scene-play scene
            (move-along-path forward-pointer route)
            (orient-along-path forward-pointer route)
            (move-along-path reverse-pointer reverse-route)
            (orient-along-path reverse-pointer reverse-route)
            #:duration 4)
]

A closed loop can instead keep its direction while changing phase:

@racketblock[
(define phased-route
  (path-geometry-cycle-start route 3/10))
]

The selected fraction is measured by total arc length and need not coincide
with a stored vertex. The operation splits a line or cubic when necessary, so the new
route begins exactly at the selected semantic path point under the existing
deterministic arc-length model. Fractions zero and one preserve the original
immutable object.

Cyclic start adjustment accepts exactly one positive-length closed subpath.
This keeps compound-path correspondence explicit. A phase-shifted path can be
passed to @racket[path-geometry-normalize-for-morph] or
@racket[morph-to-normalized] when the caller knows the desired closed-loop
correspondence. Use @racket[path-geometry-align-for-morph] or
@racket[morph-to-aligned] when a closed loop's phase or direction should be
selected automatically. Use @racket[path-geometry-align-compound-for-morph] or
@racket[morph-to-compound-aligned] when multiple equal-count closed subpaths
must also be paired. For open paths, use
@racket[path-geometry-align-open-for-morph] or @racket[morph-to-open-aligned]
to choose endpoint direction, and use
@racket[path-geometry-align-open-compound-for-morph] or
@racket[morph-to-open-compound-aligned] to pair multiple equal-count open
subpaths globally.

Render the canonical reversal-and-cyclic-start example with:

@verbatim{
racket examples/reversed-and-cyclic-paths.rkt \
  frames/reversed-and-cyclic-paths \
  reversed-and-cyclic-paths.mp4

open reversed-and-cyclic-paths.mp4
}



@; recipe-redistribution end: reversed-cyclic-paths
