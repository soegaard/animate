# Slide gallery and transitions — v0.4.0

This update targets the integrated Animate checkout at commit
`0c5f863e8ccbfc4388123adce388a4443689323e` (16 September 2026).
It includes the gallery and transition families introduced in v0.2, plus recursive
semantic matching and four additional examples in v0.3. The existing
`slide`, `make-slide`, `slide->pict`, `slide->scene`, and storyboard interfaces
remain the foundation. No installer patches or new rendering engine are needed.

**Validation:** Racket 9.3.0.2 compiled the public gallery modules and passed
the complete 105-case suite. That run includes catalogue export, transition
sampling, a real two-worker geometry gallery MP4, and mixed math/geometry
subprocess coverage. It does not substitute for reviewing a full 42-entry visual
gallery on every target host; run the commands below when a release needs that
broader visual acceptance evidence.

## 1. Browse the gallery

From the repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

# Data-only listing: no TeX, geometry realization, or rendering.
"$RACKET" slides/run-gallery.rkt --list

# Build a browsable gallery with posters and timestamped frame strips.
"$RACKET" slides/run-gallery.rkt --dark slides-output/gallery-dark-v030

# Add playable videos using the normal project executor.
"$RACKET" slides/run-gallery.rkt --dark --videos --workers 10 \
  slides-output/gallery-dark-video-v030

open slides-output/gallery-dark-video-v030/index.html
```

`slides/examples/gallery.rkt` is also an executable entry point for the same
workflow. It retains the earlier `gallery-slides` and `gallery-film` specimen
exports used by the regression runner.

The 42 catalogue entries are divided into three sections:

| Section | Entries | What it demonstrates |
|---|---:|---|
| Layouts | 12 | All built-ins, semantic text roles, captions, figures, and incremental keyed bullets. |
| Transitions | 23 | Cut, crossfade, genuine title matching, all four directions for push/wipe/cover/uncover, zoom, fade-through, an easing comparison, and recursive named-part matching. |
| Integration | 7 | A native Scene, a TeX-backed derivation, an equilateral-triangle construction, and a mixed geometry/algebra explanation with two local clocks; three more examples demonstrate semantic domain continuity. |

A gallery directory contains `index.html`, `manifest.json`, reusable storyboard
modules under `sources/`, endpoint posters, timestamped samples, and optional
MP4s. HTML groups entries by purpose, displays their authoring snippets, and links
to the reusable source. No web server or JavaScript is required.

The sibling `.zip` contains the gallery, previews, source declarations, manifest,
and completed MP4s. Working render frames under `_work/` are deliberately excluded.
A missing optional tool produces a visible per-entry error, a manifest error,
and a nonzero exit status; it is never replaced with a pretend rendering.
Output directories must be new, so old previews cannot be mistaken for fresh ones.

### Selection and formats

```sh
# Only transitions; no TeX required.
"$RACKET" slides/run-gallery.rkt --category transitions --videos --workers 10 \
  slides-output/transitions-v030

# Select individual examples, preserving the requested order.
"$RACKET" slides/run-gallery.rkt --entry match --entry wipe-left --entry zoom \
  --videos --workers 10 slides-output/selected-v030

# Check the layout catalogue in portrait.
"$RACKET" slides/run-gallery.rkt --category layouts --format portrait --light \
  slides-output/portrait-v030

# Compare the reduced-motion policy without changing clip durations.
"$RACKET" slides/run-gallery.rkt --category transitions --reduced-motion --videos \
  slides-output/reduced-v030
```

Supported formats are `widescreen`, `standard`, `portrait`, and `square`.
`--width` requests an output width; the runner rounds it upward when needed to
preserve the exact aspect ratio and even H.264 pixel dimensions, and reports the
actual dimensions. Defaults are 960 pixels wide, 30 fps, and two pixel-repeat
checks per static sample. `--repeat`, `--fps`, `--width`, `--in-process`, and
`--no-zip` are available.

Geometry now uses the same project worker capacity as the other entries. A
parent-prepared geometry artifact freezes realization and annotation placement.
The console reports the actual execution mode and number of workers started;
manifest entries include `requested-workers`, `workers-started`, and
`workers-completing`. These fields are actual executor diagnostics, not a claim
of proportional speedup. `--in-process` remains an explicit one-worker override.
Temporary frame/cache paths are isolated beneath each gallery's `_work/cache/`
and are excluded from the review ZIP. See [Geometry workers](geometry-workers.md).

Draft narration supplies timing and subtitle text, not synthesized speech.
Static Pict previews remain visual-only; MP4 generation uses the existing authored
timeline and subtitle-track path. Embedded mathematical and geometry content is
native, not a video or screenshot imported into the slide.

## 2. Use the gallery programmatically

```racket
#lang racket/base
(require animate/slides
         animate/slides/gallery
         animate/slides/pict
         animate/slides/render
         animate/slides/scene)

;; Catalogue selection alone has no optional preparation effects.
(define entries
  (select-slide-gallery-entries #:category 'transitions))

(define film
  (make-slide-gallery
   #:entries '(crossfade match push-left wipe-left zoom)
   #:theme lecture-dark
   #:format widescreen))

(define prepared (prepare-storyboard! film))
(define picture (storyboard->pict prepared #:at 2))
(define scene (storyboard->scene prepared))
(define timeline (storyboard->timeline prepared))
```

`slide-gallery-entries` is the ordered immutable catalogue.
`slide-gallery-categories` is `'(layouts transitions integration)`.
`select-slide-gallery-entries` accepts optional `#:entries` and `#:category`.
It rejects unknown IDs, duplicates, and an explicit selection inconsistent with
the chosen category rather than silently omitting entries.

Each entry has public accessors for `id`, `category`, `title`, `description`,
`requirements`, `example`, and `source`, all prefixed `slide-gallery-entry-`.
`make-slide-gallery` accepts the same selection keywords plus `#:theme`, `#:format`,
and `#:motion`. It returns an ordinary immutable storyboard, not a renderer.
Native/domain modules are loaded only when their entries are constructed;
external preparation remains explicit.

`slides/examples/gallery-tour.rkt` exports a compact 35-second transition tour
covering all nine families, counting cut. Render it with the existing runner:

```sh
"$RACKET" slides/render-example.rkt --workers 10 \
  --output slides-output/tour-v030 slides/examples/gallery-tour.rkt
```

## 3. Transition controls

```racket
(slide-transition
 #:effect 'push
 #:direction 'left
 #:duration 0.8
 #:easing 'smooth)
```

The complete animated-transition interface is:

```racket
(slide-transition
 #:effect    effect       ; default 'crossfade
 #:duration  seconds      ; default 0.6; strictly positive
 #:keys      keys         ; default '(); only for 'match
 #:direction direction    ; default 'left for directional effects
 #:easing    easing       ; default 'linear
 #:scale     scale        ; default 0.85 for 'zoom
 #:color     color)       ; default "#000000" for 'fade-through
```

Irrelevant options are rejected. For example, supplying `#:keys` for a wipe or
`#:direction` for a crossfade is an authoring error. `#f` means “not supplied”
for direction, scale, and color. All configuration is immutable data and is
preserved through parent preparation and worker reconstruction.

| Effect | Behavior |
|---|---|
| Cut | `(storyboard-cut)` switches instantly; it is not an animated `slide-transition` effect. |
| `crossfade` | Fade between the two endpoint compositions without moving them. |
| `match` | Move compatible keyed prepared assets between their resolved rectangles; unmatched content crossfades. |
| `push` | Both panels move together; the destination enters as the source leaves. |
| `wipe` | Content stays fixed while a moving boundary reveals the destination. |
| `cover` | The destination moves over the stationary source. |
| `uncover` | The source moves away from the stationary destination. |
| `zoom` | Centered zoom-crossfade: the source expands while fading out and the smaller destination expands to its final size while fading in. |
| `fade-through` | Fade the source to a solid color, then that color to the destination. |

### Direction

`left`, `right`, `up`, and `down` describe travel, not the entering edge.
For a leftward push or cover, the destination enters from the **right**.
For a leftward wipe, the reveal boundary moves from right to left while both
compositions remain stationary. The default direction is `left`.

Directional effects transform or mask the complete composition, including
backgrounds, title/footer rules, existing figure crops, and native viewports.
The source and destination masks partition the canvas. Directional transitions
require opaque slide backgrounds; transparent backgrounds are diagnosed during
preparation instead of creating ambiguous stacking.

### Easing

Available easing names are `linear`, `smooth`, `ease-in`, `ease-out`, and
`ease-in-out`. They are bounded and monotone, with exact zero/one endpoints:
`linear` is identity, `smooth` is cubic smoothstep, and the ease-in/out family
uses quadratic ramps. Arbitrary procedures, overshooting springs, and custom
core rate-function values are not accepted by this portable slide interface.

### Zoom and fade-through

```racket
(slide-transition #:effect 'zoom #:scale 0.82 #:duration 1 #:easing 'smooth)

(slide-transition #:effect 'fade-through #:color "#101820" #:duration 0.8)
```

Zoom's scale must be strictly between zero and one. It sets the destination's
initial scale; the source's final scale is its reciprocal. Both scale around
the full canvas center. Existing crops are transformed and intersected with the
canvas, so zooming cannot expose content that was intentionally cropped.

The fade-through color may be a literal or an Animate semantic color specification.
Semantic colors resolve in the **destination** slide's color theme. The resolved
color must be opaque. At halfway through eased progress, the composition is
exactly that solid color. A non-symmetric easing shifts the wall-clock time at
which that midpoint occurs.

### Timing and reduced motion

Transitions still occupy their own intervals:

```text
outgoing clip | bridge | incoming clip
```

The outgoing clip is sampled at its exact endpoint; the incoming clip at its
exact start. Neither embedded clock advances during the bridge, and no child
audio is replayed. Total duration remains the sum of clip and bridge durations.

`(storyboard #:motion 'reduced ...)` replaces spatial effects—including matched
movement—with same-duration, same-easing crossfades. Cuts remain cuts and
fade-through remains a fade-through. Timing and narration alignment do not shift.
The global storyboard policy governs bridges; a clip's local motion override
applies to its own within-slide actions.

### Matching is still explicit

```racket
(slide-transition #:effect 'match #:keys '(topic) #:duration 1 #:easing 'smooth)
```

A key must occur and be visible at both endpoints. Matching uses the prepared
asset's identity and content time, not merely equal strings or slot names.
Different line wrapping, color themes, or incompatible crops can prevent a true
match; those parts crossfade rather than receive a fabricated text/formula morph.
The gallery's `match` example deliberately keeps its prepared text layout
identical and varies only slot placement.

New query operations are `slide-transition?`, `slide-transition-effect`,
`slide-transition-duration`, `slide-transition-keys`, `slide-transition-direction`,
`slide-transition-easing`, `slide-transition-scale`, and `slide-transition-color`.
They also recognize the value returned by `storyboard-cut`.

## 4. Math and geometry in content-sized regions

`math-content` and `geometry-content` now accept `#:aspect`, default `16/9`:

```racket
(slide #:layout 'title+two-column
  [title "From a figure to an equation"]
  [left  (geometry-content construction #:aspect 16/9)]
  [right (math-content perimeter-plan #:aspect 16/9)])
```

This is the **preferred intrinsic viewport aspect** used when a layout asks for
natural height, such as compact portrait columns. It does not stretch the
mathematics or geometry. Final preparation uses the actual assigned region.
Previously this sizing query could accidentally construct an effectively
unbounded native viewport. The new query is finite and does not execute the
unprepared domain payload.

## 5. Acceptance commands

From the integrated repository root, rebuild the changed preparation schemas
before running the complete suite:

```sh
find slides -type d -name compiled -prune -exec rm -rf {} +

"$RACO" make \
  -l animate/slides \
  -l animate/slides/gallery \
  -l animate/slides/pict \
  -l animate/slides/scene \
  -l animate/slides/render \
  -l animate/slides/math \
  -l animate/slides/geometry \
  -l animate/slides/project &&
"$RACKET" slides/run-tests.rkt --math --geometry --media --project
```

There are 105 named cases in 16 suites. The default eight suites cover the model,
layout, timing, native, codec, transition, gallery, and semantic-match layers;
the optional flags add the real math, geometry, media, worker, mixed-gallery, and
semantic-domain checks. Existing CI invokes the complete command, so it picks up
this coverage without a separate gallery-specific workflow.

All visual regression probes remain in one final runner:

```sh
"$RACKET" slides/run-probes.rkt --repeat 2 --gallery --math --geometry \
  slides-output/layout-review-v040
```

`--gallery` adds the new catalogue in light/dark and widescreen/portrait, sampled
in reverse time order. It includes interior transition times, exact boundaries,
neighboring frames, and mid-action native content—not just posters. The manifest
records the new probes' entry, category, theme, format, and exact requested time.
Pict/Scene mean channel difference retains the 0.05 failure threshold; deterministic
repeats must be byte-identical within each rendering path.

The preparation payload schema is now `animate-slides-preparation-v5`; older
payloads are rejected and must be prepared again. Recorded drawing artifacts
still use their unchanged version-one format.


## Semantic examples

Select `semantic-parts`, `semantic-math`, `semantic-geometry`, or
`semantic-math-geometry`. These add recursive named children and witnessed domain
checkpoint playback to `match`; see [Semantic matching](semantic-matching.md).
All four can use the normal module-backed project worker path.
