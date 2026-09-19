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


@title[#:tag "cookbook-animation-timing-recipes"]{Combining and Timing Animations}

Start with local intervals, then combine requests in sequence, in parallel, or with staggered starts.

API reference: @secref["reference-animation-timing"].

@local-table-of-contents[]

@; recipe-redistribution begin: local-animation-timing
@section[#:tag "local-animation-timing"]{Local Visual Animation Timing}

@racket[timed] adds local animation intervals without changing the immutable
scene model. @racket[timed] attaches a local interval to one existing Visual
animation request:

@racketblock[
(scene-play
 scene
 (timed (move-to 'a (vec2 4 1))
        #:start 0
        #:duration 2)
 (timed (move-to 'b (vec2 4 -1))
        #:start 1
        #:duration 2)
 #:duration 3)
]

Local times are seconds from the enclosing clip start. A leaf has no effect
before its start, uses its own normalized progress while active, and holds its
compiled endpoint afterward. Omitting local easing inherits the enclosing
@racket[scene-play] easing.

Compilation is performed at semantic event boundaries. Requests with the same
start share one prepared state, preserving @racket[fade-in] and @racket[create]
placeholder semantics. Later requests compile against the exact state at their
local start, which makes touching relative requests deterministic:

@racketblock[
(scene-play
 scene
 (timed (rotate-by 'marker 1) #:start 0 #:duration 1)
 (timed (rotate-by 'marker 1) #:start 1 #:duration 1)
 #:duration 2)
]

The second rotation is compiled from the first rotation's boundary state. Two
requests that change the same target component may touch at an endpoint but may
not overlap with positive duration. Different components may overlap.

Structural endpoint ordering is explicit. At one event time, previously active
component values are sampled first, then completed removals/introductions are
resolved, then same-time new requests begin. This permits deterministic same-ID
reintroduction and prevents request-order-dependent failures when, for example,
movement and @racket[fade-out] end together.

Camera requests remain full-clip requests. In particular,
@racket[camera-follow] receives the actual locally timed sampled Visual state,
so it holds during a delayed target start and follows only when that target
moves. The same scheduler also handles timed Visual/composition children and
composite duration scaling; timed camera requests are not supported.


@; recipe-redistribution end: local-animation-timing

@; recipe-redistribution begin: successive-animation-composition
@section[#:tag "successive-animation-composition"]{Successive Visual Animation Composition}

@racket[succession] provides first-class sequential composition. A
succession occupies the interval assigned by its enclosing @racket[scene-play],
then divides that interval equally among its direct children:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'card origin)
  (rotate-by 'card 1)
  (scale-by 'card 2))
 #:duration 3)
]

The move runs during local seconds zero through one, the rotation during one
through two, and the scale during two through three. Each leaf sees normalized
progress from zero to one inside its own interval, and the enclosing easing is
applied independently to each leaf.

Compilation occurs at the same semantic event boundaries introduced for
@racket[timed]. The rotation above is compiled from the exact state after the
move, and the scale is compiled from the exact state after rotation. This also
makes repeated relative requests deterministic:

@racketblock[
(scene-play
 scene
 (succession
  (rotate-by 'marker 1)
  (rotate-by 'marker 1))
 #:duration 2)
]

The final rotation is exactly two radians relative to the clip-start value,
because the second @racket[rotate-by] starts from the first child's exact
endpoint rather than recompiling from clip start.

Nested successions receive one direct-child share and recursively subdivide it:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'marker origin)
  (succession
   (rotate-by 'marker 1)
   (scale-by 'marker 2)))
 #:duration 4)
]

The move receives the first two seconds. The nested succession receives the
second two seconds and assigns one second to each of its children.

Top-level ordinary Visual requests still span the complete enclosing clip, and
top-level @racket[timed] leaves keep their explicit intervals. Conflict checking
runs after succession expansion, so a full-clip sibling that changes the same
component as a succession leaf conflicts only because their concrete intervals
overlap. Different components and different targets compose normally.

The same structural semantics apply. A @racket[fade-in] or
@racket[create] child may introduce a target for a later child, while an exact
boundary may remove and reintroduce the same identity deterministically. Camera
requests remain full-clip; @racket[camera-follow] samples the actual target state
through every succession child.

Unwrapped direct children receive equal shares. Parallel groups, lagged starts,
and timed Visual/composition children use their own allocation rules while
preserving one-unit shares for unwrapped direct children. Camera requests remain
invalid composition children.


@; recipe-redistribution end: successive-animation-composition

@; recipe-redistribution begin: parallel-animation-composition
@section[#:tag "parallel-animation-composition"]{Parallel Visual Animation Composition}

@racket[animation-group] provides first-class parallel composition.
A group occupies the interval assigned by its enclosing @racket[scene-play] or
parent composition, and every direct child receives that same interval:

@racketblock[
(scene-play
 scene
 (animation-group
  (move-to 'card origin)
  (rotate-by 'card 1)
  (fade-to 'label 0))
 #:duration 3)
]

All three children run from local second zero through three. Ordinary leaves see
normalized progress from zero to one across that common interval, with the
enclosing easing applied independently to each leaf. Existing component rules
apply after expansion, so the move and rotation may target one Visual while two
parallel movement requests for that identity remain a conflict.

Parallel groups and successions can nest in either direction. A group can occupy
one child slice of a succession:

@racketblock[
(scene-play
 scene
 (succession
  (animation-group
   (move-to 'card origin)
   (rotate-by 'card 1))
  (animation-group
   (scale-by 'card 2)
   (fade-to 'label 0)))
 #:duration 4)
]

Each group receives two seconds; every leaf inside that group receives the same
two seconds. Conversely, a succession inside an animation group receives the
group's complete interval and subdivides that interval among its own children:

@racketblock[
(scene-play
 scene
 (animation-group
  (succession
   (move-to 'a origin)
   (rotate-by 'a 1))
  (succession
   (move-to 'b origin)
   (scale-by 'b 2)))
 #:duration 4)
]

Both successions run in parallel for four seconds, while each branch performs
its own two-second children sequentially. Nested groups simply reuse their
assigned interval recursively.

The implementation does not introduce a group-specific clip or sampling path.
Composition trees expand to the scheduled Visual-leaf representation.
Equal-start leaves are compiled together against one exact prepared state; later
starts compile against exact semantic boundary states. Structural event ordering, succession boundaries, overlap validation, easing,
and direct arbitrary-time sampling therefore compose without frame-by-frame accumulation.

Camera requests remain top-level and full-clip. @racket[camera-follow] samples
the actual Visual motion produced by the mixed composition tree. Timed Visual/composition children are permitted inside nested compositions,
while cameras remain top-level.

Render the canonical parallel-composition example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/parallel-animation-groups.rkt \
  frames/parallel-animation-groups \
  parallel-animation-groups.mp4

open parallel-animation-groups.mp4
}


@; recipe-redistribution end: parallel-animation-composition

@; recipe-redistribution begin: lagged-animation-composition
@section[#:tag "lagged-animation-composition"]{Lagged Visual Animation Composition}

@racket[lagged-start] provides staggered composition. For an
assigned interval of duration @italic{D}, @italic{n} direct children, and lag
ratio @italic{r}, each child receives
@racket[(/ D (+ 1 (* (sub1 n) r)))], and consecutive starts are separated by
@italic{r} child durations. For example:

@racketblock[
(scene-play
 scene
 (lagged-start
  (move-to 'a (vec2 4 2))
  (move-to 'b (vec2 4 0))
  (move-to 'c (vec2 4 -2))
  #:lag-ratio 1/2)
 #:duration 4)
]

The three children last two seconds each and start at local seconds zero, one,
and two. The first two overlap from one through two; the last two overlap from
two through three. The final child ends exactly at local second four.

The ratio connects the earlier composition forms cleanly. A zero lag ratio gives
every child the complete interval, matching @racket[animation-group] timing. A
unit lag ratio gives equal touching intervals, matching @racket[succession]
timing. Ratios greater than one insert gaps while preserving the assigned outer
duration. The default ratio is @racket[1/4].

Lagged starts may contain successions, animation groups, or nested lagged starts,
and those composition forms may contain lagged starts in return. Every direct
child receives one computed lagged interval; the child then recursively expands
inside that interval according to its own rule. No lag-specific clip or renderer
exists. The final leaves use the same scheduled-leaf representation as the other
composition forms.

Because validation runs after expansion, overlapping same-component leaves are
rejected according to their concrete intervals. A unit lag ratio therefore makes
touching relative requests legal, while a half lag ratio for two moves of the
same Visual is a conflict. Different components and different targets may overlap
normally. Structural introduction/removal and @racket[camera-follow] likewise
consume the expanded staggered schedule directly.

Timed Visual/composition children are permitted inside nested compositions,
while camera requests remain top-level/full-clip.

Render the canonical lagged-start example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/lagged-start-animations.rkt \
  frames/lagged-start-animations \
  lagged-start-animations.mp4

open lagged-start-animations.mp4
}


@; recipe-redistribution end: lagged-animation-composition

@; recipe-redistribution begin: duration-scaled-animation-composition
@section[#:tag "duration-scaled-animation-composition"]{Duration-Scaled Visual Animation Composition}

@racket[timed] is compositional. A timed wrapper may appear as a direct child of @racket[succession], @racket[animation-group], or
@racket[lagged-start], and it may wrap any one of those composition values in
addition to an ordinary Visual animation request.

Inside a composition, every unwrapped direct child contributes one intrinsic
timing unit. A timed direct child contributes @racket[(+ start duration)] units.
The parent maps those intrinsic spans into the concrete interval assigned by its
own parent or by @racket[scene-play]. Composition trees without nested timing keep their ordinary allocation.

For a succession, direct spans are consecutive. The following spans are one,
two, and one:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'a (vec2 4 2))
  (timed (move-to 'b (vec2 4 0)) #:duration 2)
  (move-to 'c (vec2 4 -2)))
 #:duration 8)
]

The concrete child durations are therefore two, four, and two seconds. A timed
child's @racket[start] is part of its intrinsic span: for example
@racket[(timed request #:start 1 #:duration 1)] has span two. If that child is
allocated four seconds, it contributes two seconds of delay followed by two
seconds of active animation.

For an animation group, all direct children start at the group start and their
spans are scaled against the longest direct span. Thus in a four-second group a
plain one-unit child beside @racket[(timed request #:duration 2)] runs for two
seconds while the timed two-unit child runs for all four seconds; the shorter
child then holds its endpoint.

For a lagged start, let a direct child's intrinsic span be @italic{s}. The first
raw start is zero, and each following raw start is the previous raw start plus
@italic{r} times the previous child's span, where @italic{r} is the lag ratio.
The complete raw envelope is then scaled to the assigned concrete duration. With
all spans equal to one this is the ordinary lagged-start schedule. With unequal spans,
lag ratio zero still equals duration-scaled parallel timing, while lag ratio one
still equals duration-scaled succession timing.

A bare nested composition remains one direct parent-level unit regardless of
its internal child count. This preserves the earlier rule that a nested
composition is one child. Wrap the nested composition itself with @racket[timed]
when it should reserve an explicit larger, smaller, or delayed parent-level span:

@racketblock[
(scene-play
 scene
 (succession
  (move-to 'a origin)
  (timed
   (succession
    (rotate-by 'b 1)
    (scale-by 'b 2))
   #:duration 2)
  (fade-to 'c 0))
 #:duration 8)
]

The outer direct spans are one, two, and one, so the timed nested succession
receives four seconds and divides those four seconds according to its own direct
children.

At top level, @racket[timed] retains its original literal-second meaning. It may
now wrap a whole composition:

@racketblock[
(scene-play
 scene
 (timed
  (succession
   (move-to 'dot (vec2 4 0))
   (rotate-by 'dot 2))
  #:start 1
  #:duration 4)
 #:duration 6)
]

The wrapped succession is inactive before local second one, fills seconds one
through five, and then holds its exact semantic endpoint through second six. A
@racket[#:easing] supplied by the timed composite becomes the inherited easing
for its descendant leaves. A nested timed child may override that easing; timing
allocation itself is never eased.

This composition model does not add a new clip or sampling engine. All timing
trees still expand to scheduled Visual leaves before conflict and structural-removal
validation, then compile against exact local boundary states. Exact endpoint
sampling, same-component overlap rules, structural event ordering,
@racket[camera-follow], and arbitrary-time reconstruction therefore continue to
use the existing scheduler.

Camera requests remain top-level/full-clip, and @racket[timed] does not wrap
another timed wrapper.

Render the canonical duration-scaled-composition example with:

@verbatim{
"/Applications/Racket v9.3.0.2/bin/racket" -c \
  examples/duration-scaled-compositions.rkt \
  frames/duration-scaled-compositions \
  duration-scaled-compositions.mp4

open duration-scaled-compositions.mp4
}


@; recipe-redistribution end: duration-scaled-animation-composition
