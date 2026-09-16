# Semantic continuity between slides

Version 0.4.0. This document describes the implemented behavior and its limits.
See `validation-v040.md` for the Racket 9.3.0.2 execution record; another
platform still needs its own visual acceptance evidence.

## The design decision

A `match` transition is a prepared correspondence plan, not a visual similarity
search. There are two complementary ways to preserve meaning inside a slot:

**Named parts.** `semantic-group` contains explicitly named children, including
nested groups. Child names establish correspondence within the matched outer slot.
A child can move without making the other children move as one rigid picture.

**Witnessed domain states.** `content-state` selects a point in an existing math,
geometry, or native Scene timeline. When two endpoints refer to the same source
and canonical viewport under the same appearance, the original domain timeline
is the witness for what happens between them. The bridge replays that interval
while the outer slot moves. It does not infer algebra from two strings or invent
intermediate geometry from unrelated drawings.

This is a deliberate refinement of the earlier design discussion. `math-content`
still takes a **presentation plan**, not an arbitrary `math?` expression. To show
two mathematical states, keep the presentation plan and select its checkpoints.
That retains the checked occurrence links and existing choreography instead of
trying to recover them from the two final pictures.

The responsibility boundary is:

```
slides: correspondence, outer placement, bridge duration, diagnostics
  -> named part: recursively scoped child identities and local placement
  -> content-state: an existing domain Scene and its named/time endpoints
       -> math: its existing semantic token/operation choreography
       -> geometry: its existing realization and presentation timeline
  -> ordinary native Scene or the same prepared composition as a Pict
```

No separate formula matcher, geometry solver, video encoder, or worker pool is
introduced. No correspondence search or TeX preparation runs during frame sampling.

## A short example: named parts

```racket
#lang racket/base
(require animate/slides animate/slides/pict animate/slides/scene)

(define (ideas reversed?)
  (semantic-group #:width 8 #:height 3
    (semantic-part 'observe "Observe"
                   #:x (if reversed? 4 0) #:y 0 #:width 4 #:height 1)
    (semantic-part 'explain "Explain"
                   #:x (if reversed? 0 4) #:y 2 #:width 4 #:height 1)))

(define a
  (slide #:layout 'figure+caption
    [figure #:key 'ideas (ideas #f)]
    [caption "First observe, then explain."]))

(define b
  (slide #:layout 'title+figure
    [title "Connect the ideas"]
    [body "The panel and its contents can move independently."]
    [figure #:key 'ideas (ideas #t)]))

(define film
  (storyboard
    (storyboard-shot 'a (hold-slide a #:duration 2))
    (slide-transition #:effect 'match #:keys '(ideas)
                      #:depth 'semantic #:duration 2 #:easing 'smooth)
    (storyboard-shot 'b (hold-slide b #:duration 3))))

(define midway (storyboard->pict film #:at 3))
(define movie-scene (storyboard->scene film))
```

The outer continuity key is `ideas`. Within it, `observe` corresponds to
`observe`, and `explain` to `explain`. Reordering the declarations does not change
that correspondence. Even two children displaying the same word are distinct if
they have different names.

A child present only at the source fades out; one present only at the destination
fades in. Other matched children continue moving. Changing a named child's text
produces a moving **appearance crossfade**, not a claimed glyph morph.

## A mathematical transition that retains the working

```racket
#lang racket/base
(require animate/math
         animate/slides
         animate/slides/math
         animate/slides/render
         animate/slides/pict
         animate/slides/scene)

(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'problem #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-rhs (evaluate #:at (rhs))]))

(define plan
  (present working #:style classroom
           #:groups '((subtract-five cancel-five evaluate-rhs))))

(define equation (math-content plan))
(define before-state
  (content-state equation #:at '(subtract-five start) #:viewport '(12 7)))
(define after-state
  (content-state equation #:at '(evaluate-rhs end) #:viewport '(12 7)))

(define a
  (slide #:layout 'title+figure
    [title "Solve the equation"]
    [figure #:key 'equation before-state]))
(define b
  (slide #:layout 'title+figure
    [title "Keep both sides equal"]
    [body "Subtract five. Cancel opposite terms. Calculate the right side."]
    [figure #:key 'equation after-state]))

(define film
  (storyboard #:theme lecture-dark
    (storyboard-shot 'problem (hold-slide a #:duration 2))
    (slide-transition #:effect 'match #:keys '(equation)
                      #:depth 'semantic #:duration 4 #:easing 'smooth)
    (storyboard-shot 'result (hold-slide b #:duration 3))))

;; One preparation scope shares the canonical native math plan between states.
(define prepared (prepare-storyboard! film))
(define midpoint (storyboard->pict prepared #:at 4))
(define timeline (storyboard->timeline prepared))
(storyboard-match-report prepared)
```

The math sequence is **not** guessed as “delete +5 and turn 17 into 12.” The
existing presentation plan supplies subtraction on both sides, cancellation, and
evaluation in their authored order. Whatever token preservation, copying, or
atomic replacement that plan supports is retained. The slides layer does not add
new algebraic equivalences or claim that an arbitrary intermediate visual state
is a standalone mathematical assertion.

The full lesson ends at `3x = 12`. Division by three would be another authored
operation, not something the slide matcher adds automatically.

### Snapshot versus poster

`(math-content plan #:poster 'end)` is an animated component whose chosen static
preview is its endpoint. In an ordinary `build-slide`, its local clock can still
begin at zero and be advanced with `play-content`.

`(content-state (math-content plan) #:at cue)` is different: it is a **static
snapshot** of that domain state throughout its containing shot. Its slide-asset
duration is zero. `play-content` on it is rejected. A semantic bridge between two
snapshots deliberately replays the witnessed domain interval.

Only that bridge replay advances. The outgoing and incoming shot clocks remain
frozen at their endpoints, exactly as for the other slide transitions.

## Geometry

The same mechanism works with a geometry program or a prebuilt geometry timeline:

```racket
(define component (geometry-content equilateral-triangle))
(define start-view
  ;; In this construction, step 1 reveals the given points A and B.
  (content-state component #:at '(1 end) #:viewport '(12 7)))
(define completed-view
  (content-state component #:at 'end #:viewport '(12 7)))
```

Put these values in slots with a common continuity key, and connect the shots
with `#:effect 'match`. The original construction timeline controls entity
visibility, curve reveals, labels, highlights, and its supported transformations.
All of those retain the original construction's realization; the matcher does
not independently tween point pictures, segment pictures, and label pictures.

The gallery deliberately starts this example at the end of step 1 rather than
at global `start`, because the construction initially hides A and B; this keeps
the source slide visibly informative. Global `start` remains a valid snapshot.

Geometry snapshots also expose `(step-id start)`, `(step-id action-start)`,
`(step-id action-end)`, and `(step-id end)` cues from the actual compiled step
spans. Ambiguous IDs are not usable shortcuts. `start`, `end`, and numeric times
are available without knowing step IDs.

**Limit:** this release does not solve a new path between independently realized
constructions, interpolate changed free-point assignments, or select intersection
branches during a morph. A shared name such as `A` in two unrelated constructions
is insufficient evidence. Such endpoints fall back or are rejected in strict mode.
Use an authored domain timeline when the intervening geometric change matters.

Geometry checkpoints now support the shared subprocess route. Their frozen
base plan is staged once and reused by the snapshot references; worker decoding
preserves the original cue map and checkpoint times. No realization, annotation
placement, or fitting is repeated in workers. See [Geometry workers](geometry-workers.md).

## Combining domains recursively

A semantic group can contain both domain snapshots:

```racket
(semantic-group #:width 16 #:height 8
  (semantic-part 'equation before-state
                 #:x 0 #:y 0 #:width 7.8 #:height 6.7)
  (semantic-part 'construction start-view
                 #:x 8.2 #:y 0 #:width 7.8 #:height 6.7)
  (semantic-part 'caption "Keep the explanation connected."
                 #:x 0 #:y 7 #:width 16 #:height 0.8 #:fit 'natural))
```

The next state can swap the two component regions and change each snapshot's
checkpoint. Matching the enclosing slot recursively plans two independent domain
replays and a stable caption. Each replay uses its own source/destination times,
while all three children share the outer slide transition's progress.

Names are scoped by their ancestry: `(work left label)` and `(work right label)`
are distinct, even though both local children are named `label`. Duplicate sibling
names are constructor errors. There is no global mutable registry of IDs.

### Coordinate composition

A group's first transform places its viewport in the outer slot. Each nested
transform is normalized relative to its parent viewport. During a match, the
system interpolates the outer placement, then composes the interpolated local
placements. It does not interpolate a flattened collection of already-transformed
world coordinates and then apply the parent motion a second time.

For example, when a parent shrinks and a child also moves right inside it, the
world-space path includes both changes. Exact endpoints reproduce the prepared
source and destination boxes. Viewport preparation is fixed before playback;
there is no per-frame line wrapping or formula measurement.

## Choosing how strict matching should be

```racket
(slide-transition #:effect 'match #:keys '(work) #:depth 'auto)
(slide-transition #:effect 'match #:keys '(work) #:depth 'semantic)
(slide-transition #:effect 'match #:keys '(work) #:depth 'slot)
```

`auto` is the new default for `match`. It uses named child correspondence and
witnessed domain replay when available, preserves compatible prepared assets
otherwise, and falls back to a crossfade when no supported correspondence exists.

`semantic` requires supported correspondence for the requested keys. Incompatible
opaque content, different domain sources/appearance/viewports, and backward domain
intervals raise `semantic-match-unavailable`. Within an explicit named tree,
created and removed children are intentional, and a named appearance replacement
is an explicit crossfade rather than an unsupported mathematical morph.

`slot` disables the new semantic domain replay and recursive named-tree policy;
it retains the former conservative prepared-asset matching behavior, including
its existing keyed-bullet handling. In particular, two different content-state
snapshots do not replay in slot mode.

`#:depth` is valid only for `match`. Missing continuity keys, wholly invisible
matched endpoints, and duplicate visible child identities remain errors. The
system does not use proximity or hash iteration to break an ambiguous tie.

Backward domain intervals are not automatically replayed. In particular, reversing
a mathematical presentation is not assumed to justify a reverse implication.
A separately authored reverse explanation can be supplied as its own timeline.

## Timing, accessibility, and media

The bridge still reserves its own positive duration. Easing produces progress
`p` in `[0,1]`; a domain replay samples its original timeline at
`start + p * (end - start)`. Thus changing bridge duration explicitly retimes the
visual presentation. It does not alter the underlying mathematical operations.

Choose enough duration for the intervening working to be legible. A three-step
explanation compressed into 0.3 seconds is still a poor explanation; matching is
not a pacing oracle.

With storyboard `#:motion 'reduced`, a semantic match becomes a same-duration,
same-easing crossfade between the **frozen** endpoint snapshots. No domain replay
runs inside that reduced-motion bridge.

`content-state` is visual-only. An embedded authored timeline must use
`#:media 'visual-only`; importing its audio through a snapshot is rejected.
Bridge playback therefore does not secretly duplicate, reverse, or stretch speech.
Author narration separately, or keep the narrated operation in a normal slide
clip driven by `play-content`.

## Inspecting the actual plan

```racket
(storyboard-match-report prepared)
```

This returns ordinary immutable Racket data: source/destination shot IDs, selected
depth, reduced-motion policy, and one report per requested continuity key. Pair
modes are `preserve`, `replace`, or `replay`; replay reports include the domain and
its actual local start/end times. Outgoing and incoming paths are listed separately.
There are no Picts, closures, or live native handles in this report.

Call it on a prepared storyboard for complete information. The function does not
silently invoke TeX for an unprepared mathematical source. Unavailable automatic
matches are visible as fallback reasons rather than pretending that a crossfade
was a successful semantic morph.

## Public constructors

```racket
(semantic-group #:width positive-real #:height positive-real part ...)
(semantic-part id content #:x 0 #:y 0
               #:width positive-real #:height positive-real
               #:align 'center #:valign 'center #:fit 'contain)
(content-state native-content #:at cue #:viewport '(16 9))
```

These are exported by `animate/slides`, with `semantic-group?`, `semantic-part?`,
and `content-state?`. `storyboard-match-report` is exported by `animate/slides/render`.
`slide-transition-depth` is the read-only accessor for the transition policy.

Part geometry uses positive-down local coordinates. Parts must lie inside their
group's declared viewport. Groups are nonempty, with unique sibling IDs. Text,
Picts, images, native Visuals, nested groups, and frozen domain states can be
children, but a playing child must first be wrapped in `content-state`. The
existing `reveal-slot`/`conceal-slot` selectors can address child paths, such as
`'(figure ideas observe)`. Native Scene slot handles still address outer slots;
this release does not expose arbitrary domain-internal Visuals as stable public
Scene selection aliases.

Groups support `contain` and `natural` fitting, not `cover`. A clipped standalone
domain state is not eligible for domain replay. Unsupported crop interpolation
is reported rather than silently discarded.

## Preparation, workers, and compatibility

A per-resolution preparation cache shares a canonical domain asset across its
snapshots under an identical source, viewport, appearance, and fitting policy.
It is scoped to one preparation operation, not retained as a mutable global cache.

The existing math artifact codec transfers the prepared mathematical plan; workers
do not invoke TeX. Named-part ancestry and the transition depth are transferable
data. Workers rebuild the same correspondence plan from the verified endpoint
assets. Native Scene snapshots reconstruct from the existing source-module route.

The private preparation schema is now `animate-slides-preparation-v3`. Older
payloads are rejected, not interpreted with missing semantic fields. Source
programs without the new options remain valid. The safe update script merges
changed files individually, backs up originals, and clears generated slide
bytecode; it does not replace the `slides/` directory.

## Gallery and regression review

The gallery adds `semantic-parts`, `semantic-math`, `semantic-geometry`, and
`semantic-math-geometry`. The latter visibly combines the two mechanisms.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" slides/run-gallery.rkt \
  --entry semantic-parts --entry semantic-math \
  --entry semantic-geometry --entry semantic-math-geometry \
  --videos --workers 10 --dark \
  slides-output/gallery-v030-semantic-dark
```

All four entries support the existing subprocess renderer. Geometry is no
longer a reason to force one in-process worker; use `--workers 10` normally.

All visual probes remain in the final combined runner:

```sh
"$RACKET" slides/run-probes.rkt --repeat 2 --gallery --math --geometry \
  slides-output/layout-review-v030
```

The supplied tests check explicit/duplicate IDs, recursive addition and removal,
composed coordinates, static snapshots, native timeline replay, fallback and
strict modes, reduced motion, direct seeking, Pict/Scene agreement, transferable
ancestry, real mathematical preparation reuse, and real two-worker rendering.
Execution results must be recorded separately from those supplied test cases.
