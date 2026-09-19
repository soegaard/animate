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

@title[#:tag "scenes"]{Scenes and sampling}

Use these operations to build a Scene and ask for its state at a time.
For a short first program, see @secref["quick-start"].

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(scene? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a scene timeline.
}

@defproc[(make-scene
          [initial-state scene-state? empty-scene-state]
          [#:camera camera camera? default-camera])
         scene?]{

Creates a zero-duration scene whose current semantic state is
@racket[initial-state] and whose current camera is @racket[camera]. The new
scene contains no clips.
}

@defproc[(scene-add [scene scene?] [visual visual?] ...) scene?]{

Returns a scene with each supplied Visual added instantaneously at the current
scene time. No clip is appended and duration does not change.

Visuals are added in argument order. Each later argument is placed in front of
earlier Visuals. Adding a top-level identity already present as a Visual or named scalar in the current
state raises an exception. A group is added as one top-level Visual; its child
order remains internal to the group. A @racket[derived-visual?] is likewise
stored as one top-level identity and is resolved only when concrete geometry is
requested.

An instantaneous addition at the exact end of a scene is not normally included
in frame sampling. Follow it with @racket[scene-wait] or @racket[scene-play]
when it must be visible in rendered output. Supplying no Visuals returns an
equivalent scene.
}

@defproc[(scene-remove [scene scene?]
                       [target (or/c visual? symbol? visual-path?)] ...)
         scene?]{

Returns a scene with each addressed target removed instantaneously from the
current state. No clip is appended and duration does not change. Removing a
nested path rebuilds only its ancestor groups; top-level drawing order is
preserved. Removing an absent target raises an exception. Supplying no targets
returns an equivalent scene.
}

@defproc[(scene-ref [scene scene?]
                    [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the concrete addressed Visual from the scene's current endpoint state.
}

@defproc[(scene-visual-at [scene scene?]
                          [target (or/c visual? symbol? visual-path?)]
                          [time (and/c finite-real? (>=/c 0))])
         visual?]{

Samples @racket[scene] at @racket[time] and returns the concrete addressed
Visual. Nested child transforms remain local to their containing group.
}

@defproc[(scene-set-value [scene scene?]
                          [id (or/c symbol? scene-parameter?)]
                          [value any/c]) scene?]{
Adds or replaces one named interpolable semantic value instantaneously at the
current scene time. No clip is appended and duration does not change. A value ID
may not collide with a top-level Visual ID. Earlier clips retain their stored
value snapshots.

The two-argument shorthand @racket[(scene-set-value scene parameter)] accepts
a @racket[scene-parameter?] and installs its declared initial value.
}

@defproc[(scene-remove-value [scene scene?]
                             [id (or/c symbol? scene-parameter?)]) scene?]{
Removes one named semantic value instantaneously. Removing an absent value raises an
exception and does not append a timeline clip.
}

@defproc[(scene-current-value [scene scene?]
                              [id (or/c symbol? scene-parameter?)]) any/c]{
Returns one named interpolable semantic value from the scene's stored endpoint state.
}

@defproc[(scene-value-at [scene scene?]
                          [id (or/c symbol? scene-parameter?)]
                          [time (and/c finite-real? (>=/c 0))]) any/c]{
Samples one named interpolable semantic value directly at absolute scene @racket[time]. The same
closed timeline bounds as @racket[scene-sample] apply.
}

@defproc[(scene-set-camera [scene scene?]
                            [camera camera?])
         scene?]{

Returns a scene whose current camera is @racket[camera]. The replacement is
instantaneous: no clip is appended and duration does not change. Earlier clips
keep their stored cameras.

An instantaneous replacement at the exact end of a scene is not normally
included in frame sampling. Follow it with @racket[scene-wait] or
@racket[scene-play] when the replacement must appear in rendered output.
}

@defproc[(scene-play
          [scene scene?]
          [request (or/c timed-animation-request?
                         succession-animation-request?
                         animation-group-animation-request?
                         lagged-start-animation-request?
                         style-to-animation-request?
                         value-to-request?
                         move-to-request?
                         move-along-path-request?
                         orient-along-path-request?
                         rotate-to-request?
                         rotate-by-request?
                         scale-to-request?
                         scale-by-request?
                         stroke-width-to-request?
                         fill-color-to-request?
                         stroke-color-to-request?
                         fade-to-request?
                         fade-in-request?
                         fade-out-request?
                         enter-request?
                         leave-request?
                         morph-to-request?
                         morph-to-normalized-request?
                         morph-to-aligned-request?
                         morph-to-open-aligned-request?
                         morph-to-open-compound-aligned-request?
                         morph-to-mixed-compound-aligned-request?
                         morph-to-topology-changing-request?
                         morph-to-compound-aligned-request?
                         transform-formula-parts-request?
                         create-request?
                         uncreate-request?
                         write-in-request?
                         unwrite-request?
                         camera-pan-to-request?
                         camera-pan-by-request?
                         camera-zoom-to-request?
                         camera-zoom-by-request?
                         camera-follow-request?
                         camera-fit-request?)] ...
          [#:duration duration
                      (or/c false/c (and/c finite-real? positive?))
                      #f]
          [#:easing easing (procedure-arity-includes/c 1) linear])
         scene?]{

Appends one play clip. When no @racket[timed], @racket[succession],
@racket[animation-group], or @racket[lagged-start] value is present, Visual/scalar and
camera @racket[request] values run simultaneously and share
@racket[duration] and @racket[easing].

When @racket[#:duration] is omitted, ordinary requests default to one second. A direct @racket[write-in] uses Manim's default instead:
one second for fewer than fifteen writable leaves and two seconds for fifteen
or more. An explicit positive duration always takes precedence.

When at least one timing/composition value is present, every Visual, scalar, or
camera request resolves to one or more concrete local intervals. A top-level
@racket[timed] value uses literal second-based start and duration and may wrap
either one leaf or one composition. An ordinary unwrapped top-level Visual or
camera request spans the complete enclosing clip.

Inside compositions, unwrapped direct children contribute one timing unit and a
timed direct child contributes @racket[(+ start duration)] units. A succession
places those spans consecutively, an animation group starts them together and
scales against the longest span, and a lagged start offsets raw starts by its lag
ratio before scaling the complete envelope. Bare nested compositions remain
one-unit direct children unless explicitly wrapped by @racket[timed]. All three
composition forms may nest arbitrarily with timed Visual/camera composition
children.

Equal-start Visual leaves are compiled together against one prepared local start
state. A later start batch is compiled against the exact semantic state sampled
at that local boundary, so a touching relative request starts from the previous
request's exact endpoint rather than the enclosing clip start. Sampling remains
direct and does not depend on rendering prior frames.

Structural introduction requests are installed only at their local start. A
@racket[create] request adds an empty-path placeholder, @racket[fade-in] adds
the complete Visual at opacity zero, and @racket[enter] adds an affine/opacity
appearance proxy. Requests beginning at that same local time
share the prepared state, so movement, rotation, scaling, opacity, and compatible
geometry changes can compose with an introduction. A @racket[fade-out], @racket[uncreate], or
@racket[leave] removal
may not end while another animation of that target remains active; reintroduction
at the exact removal boundary is allowed.

Positive-measure overlap on the same Visual component is rejected. Touching
intervals are not overlap and are legal. Requests for disjoint components may
overlap freely.

Camera requests use the same local intervals. A later pan, zoom,
fit, or follow compiles from the exact camera view at its local start.
@racket[camera-pan-by] therefore adds to that local center, and
@racket[camera-zoom-by] divides that local visible width by its magnification
factor. A @racket[camera-follow] captures its target's frame offset at the
start of its own interval, samples the target's actual local Visual state while
active, and holds the resulting endpoint view after it ends. A camera-fit
request remains a concrete center/width snapshot measured when it was
constructed. Camera and Visual requests may appear in any order.

A single list of requests can be supplied in place of separate request
arguments:

@racketblock[
(scene-play scene
            (list (move-to 'a (vec2 2 0))
                  (rotate-by 'a 1)
                  (camera-pan-to (vec2 1 0))
                  (camera-zoom-by 2))
            #:duration 2)
]

At least one request is required. Each composition value itself also requires
at least one child. In the full-clip case, two
simultaneous requests may target the same Visual when every component they
change is disjoint. With local timing, the same rule applies only where the
request intervals overlap. The components in
this version are translation, rotation, scale, opacity, path geometry, formula
parts, and scene presence. Both @racket[move-to] and
@racket[move-along-path] reserve translation. @racket[orient-along-path],
@racket[rotate-to], and @racket[rotate-by] reserve rotation. A request can
change more than one component:
@racket[fade-in] and @racket[fade-out] change opacity and presence;
@racket[enter] changes presence plus only its nonidentity affine/opacity
components; @racket[leave] does the same and reserves presence when it removes;
@racket[create] and @racket[uncreate] change path geometry and presence, and
@racket[transform-formula-parts] changes formula parts and reserves presence.

Two overlapping requests may not change the same component for the same
identity. Exact endpoint touching is allowed. Thus overlapping opacity requests
conflict. Strict morphing, normalized morphing, creation, and
uncreation conflict on path geometry. Two formula-part transformations conflict
on formula parts. A formula-part transformation also conflicts with a
same-target structural introduction or removal because both reserve presence.
Requests for different identities do not conflict.

The camera center and visible world width are separate camera components. Pan
and follow requests change the center. Zoom requests change visible width. A fit
request changes both. One follow request and one zoom request may run together.
Overlapping requests that reserve the same camera component raise an exception,
so fit conflicts with pan, follow, zoom, or another fit for the same local
interval. Touching camera intervals are legal and hand off exactly. Camera
components do not conflict with Visual components.

Before easing is called, progress is clamped to the closed unit interval. The
easing result must be a finite real and is also clamped to that interval. A
normal easing procedure should map @racket[0] to @racket[0] and @racket[1] to
@racket[1]. Transform component endpoints follow the easing result.

Introduction, removal, and formula-part transformation requests have
structural endpoint rules. For an untimed request the structural endpoint is the
play-clip boundary; for a timed request it is the local interval endpoint. At
that endpoint, a completed
@racket[create] contains the complete original path, a completed
@racket[fade-in] contains the supplied final opacity, a completed
@racket[enter] contains its exact authored Visual, and a completed
@racket[transform-formula-parts] contains the exact destination part list. A
completed @racket[uncreate], @racket[fade-out], or removing @racket[leave]
removes its target. These rules
apply even when easing does not map one to one. Such an easing procedure can
therefore cause a discontinuity at the request endpoint.

A @racket[fade-to], @racket[morph-to], @racket[morph-to-normalized],
@racket[morph-to-aligned], @racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], or @racket[morph-to-compound-aligned] request has no
structural endpoint override. Like
movement, rotation, scale, camera pan, camera zoom, camera fit, and camera
follow, its final sampled value follows the easing result. A normalized morph
preserves the exact source at eased progress zero and the exact requested
destination at eased progress one. Camera animation preserves pixel dimensions
and background throughout the clip.
}

@defproc[(scene-wait [scene scene?]
                     [duration (and/c finite-real? positive?)])
         scene?]{

Appends a wait clip that holds the current Visual state and current camera
unchanged for @racket[duration] seconds.
}

@defproc[(scene-sample [scene scene?]
                       [time (and/c finite-real? (>=/c 0))])
         scene-state?]{

Returns the complete scene state at absolute @racket[time]. Time must lie in
the closed interval from @racket[0] through @racket[(scene-duration scene)].

Clip intervals are half-open. Sampling the exact total duration returns
@racket[scene-current-state]. This procedure samples only the Visual state; it
does not apply camera animations. Camera values are sampled separately with
@racket[scene-camera-at].
}

@defproc[(scene-animation-inspections-at
          [scene scene?]
          [time (and/c finite-real? (>=/c 0))])
         (listof animation-inspection?)]{

Returns the immutable inspection records retained for active animation leaves
at @racket[time]. Inspection describes semantic planning data only: it never
exposes renderer-private mutable resources. At an exact final scene endpoint,
the final clip's retained records remain available even though its visual
structural cleanup has already occurred.
}

@defproc[(animation-inspection? [value any/c]) boolean?]{
Recognizes an immutable animation-inspection record.
}

@defproc[(animation-inspection-kind [inspection animation-inspection?]) any/c]{
Returns the request-family symbol, such as @racket['enter], @racket['leave],
@racket['reveal-in], @racket['reveal-out], or @racket['pulse].
}

@defproc[(animation-inspection-data [inspection animation-inspection?]) any/c]{
Returns immutable semantic explanation data. For @racket[enter] and
@racket[leave], the data records the target, lifecycle, authored relative
factors, written components, collapse flag, and exact removal action.
For hard-clip reveals, it records the target, lifecycle, immutable front,
written components, and exact removal action; the renderer-private clip wrapper
and frozen layout measurement are never exposed.
For @racket[pulse], it records the target, cycle count, written components, and
the exact source-restoration endpoint action.
For @racket[confetti], it records the resolved launch origin, explicit seed,
generated count, overlay identity, and deterministic helper IDs; no mutable
renderer or random-generator state is exposed.
}

@defproc[(scene-camera-at [scene scene?]
                          [time (and/c finite-real? (>=/c 0))])
         camera?]{

Returns the complete camera at absolute @racket[time]. Time must lie in the
same closed interval accepted by @racket[scene-sample]. Clip intervals are
half-open. Sampling the exact total duration returns
@racket[scene-current-camera]. This procedure samples only the camera. For a
follow request, the timeline internally samples the followed target's semantic
Visual state at the same absolute time, including local timing and
sequential/parallel/lagged composition. It
never depends on earlier rendered frames.
}

@defproc[(scene-duration [scene scene?])
         (and/c finite-real? (>=/c 0))]{

Returns the total duration in seconds.
}

@defproc[(scene-current-state [scene scene?]) scene-state?]{

Returns the state after all operations currently in the timeline. This is also
the state returned by sampling the exact scene duration. A completed
@racket[create], @racket[fade-in], or @racket[enter] contributes its complete
Visual. A completed @racket[uncreate], @racket[fade-out], or removing
@racket[leave] contributes no Visual for its target identity. A retained
@racket[leave] contributes its exact relative final appearance.
}

@defproc[(scene-current-camera [scene scene?]) camera?]{

Returns the camera after all operations currently in the timeline. This is also
the camera returned by @racket[scene-camera-at] at the exact scene duration.
An unusual easing procedure can leave the current camera before a requested pan,
zoom, fit, or follow endpoint, just as it can leave a moved Visual before its
destination.
}

@defproc[(scene-clip-count [scene scene?]) exact-nonnegative-integer?]{

Returns the number of play and wait clips. Instantaneous Visual additions,
Visual removals, and camera replacements do not increase this count.
}
