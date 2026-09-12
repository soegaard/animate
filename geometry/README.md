# Geometry authoring for `animate` — v0.9.2


## New in v0.9.2 — zero-precision semantic labels

Measured semantic labels now normalize Racket's zero-precision decimal spelling,
so `#:precision 0` produces `90°` rather than `90.°` and `5` rather than `5.`.
Rounding at all precisions is otherwise unchanged. Regression checks cover both
angle and length labels.


## New in v0.9.1 — review refinements

The dark-theme review of the transformation and semantic-label examples led to
four refinements:

- the standalone transformation plates use a tighter camera and stronger
  correspondence geometry for reflection, translation, and dilation;
- measured labels in the semantic-label example sit closer to their geometry;
- triangle side labels can use `(label-outside-of label opposite-vertex)` so
  `a`, `b`, and `c` stay on the conventional outside of the triangle;
- review bundles omit silent cleanup/no-op authored rows by default. Use
  `--include-cleanup` (or direct-runner `--review-include-cleanup`) to restore
  them for debugging.

The movie timeline is unchanged by review-row filtering.

Executed in the minimal Racket CS runtime: **69 transformation/label groups /
1,017 checks**, **65 review groups / 227,055 checks**, **68 library groups /
2,552 checks**, **53 audit groups / 3,183 checks**, and **26 refinement groups /
387 checks** passed. Native PNG/font integration remains a local-checkout test.

## New: mathematical transformations and semantic labels

Reflect, rotate, translate and dilate Points, Segments, Lines, Rays, Circles,
Angles, Relations and Markers. Named `Transform` values support composition,
inversion, and typed helper arguments/results. These construct image geometry;
they do not animate a moving or morphing object.

```racket
;; Inside a construction:
[T (reflection mirror)]
[AB2 (transform T AB)]
[a2 (length-label AB2 "a′")]
[alpha (angle-label (angle A B C) #:precision 1)]
```

The new first-class `Label` type covers point names, segment notes, symbolic or
measured lengths, and symbolic or measured angles with optional arcs. Text is
placed by the shared annotation planner and remains upright. Named labels have
independent visibility; hide an existing automatic point name when replacing it
with an independent point-label.

Two new example videos, `transformations.rkt` and `semantic-labels.rkt`, plus new
gallery plates demonstrate the additions. The review registry contains **19
examples**; `--library` still selects the thirteen construction applications.
The v0.8.3 example corrections and the existing render/review paths are retained.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --transform-labels
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/review-examples.rkt --example transformations --both --output geometry-review-v091
"$RACKET" geometry/review-examples.rkt --example semantic-labels --both --output geometry-review-v091
```

Read the [implementation plan](docs/TRANSFORMATIONS-AND-LABELS-PLAN.md),
[reference guide](docs/TRANSFORMATIONS-AND-LABELS.md), and
[validation record](docs/TRANSFORM-LABEL-VALIDATION.md). The mathematical and
headless integration checks were executed on Racket CS 9.3.0.8. Native PNG/font
integration tests are supplied, but were **not executed** in the minimal build
runtime. The validation record distinguishes these explicitly.

---

A first implementation of the mathematical-authoring DSL: geometry, exposition,
presentation state, layout, and styling remain separate.

## New in v0.8.2.1 — static-frame reuse syntax fix

Full-frame geometry rendering now reuses semantically identical pause frames instead of rerasterizing them. This maintenance release fixes two delimiter errors in the first v0.8.2 package (`geometry/render.rkt` and its new native integration test). The full `geometry/` tree has been parsed successfully with the Racket 9.3.0.8 reader before packaging.


## New in v0.8.3 — refinements from the user's video notes

Distinctly scalene general-triangle examples, a same-side angle copy, closer
P₁...P₅ labels, P/Q/R/S-style helper names, a purple primary hexagon circle, and
gold edges protected from supporting-line overpainting. The new `label-offset`
hint fixes a label relative to a named point. Helper annotation hints now follow
caller-visible result aliases.

[All eleven example corrections](docs/EXAMPLE-REFINEMENTS.md) include the
validation results and rerender instructions. Static-frame reuse and all
v0.8.2.2 syntax/import fixes are retained unchanged. Process rendering, review
bundles, reading delay and accepted marker sizes are also retained.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --refinements
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/review-examples.rkt --all --both --output geometry-review-v083
```

Executed in the minimal Racket CS 9.3.0.8 runtime: 26 refinement groups / 387
checks, 68 library groups / 2,484 checks, 49 audit groups / 3,051 checks and 60
review groups / 215,848 checks. All 72 Racket modules pass the actual reader.
The native RackUnit/PNG/font integration tests are included but have not been
executed here; no regenerated native frames are bundled.

## New in v0.8.1 — audit of the supplied review bundles

The 17 examples were reviewed in both themes using 110 contact sheets and
selected full-resolution frames. Fixes address helper names/captions, angle-copy
chords and α notation, cropped primary circles, missing perpendicular feet,
repeated-step pacing, and gallery plate cleanup. The complete findings are in
[EXAMPLE-AUDIT.md](docs/EXAMPLE-AUDIT.md).

Two small DSL additions support these corrections: `(caption "..." A "...")`
for helper-safe object names, and `(layout (fit-circle k))` for a primary circle
that must fit completely. See the [manual](docs/MANUAL.md). The accepted marker
sizes, one-second reading delay, light/dark modes, and 10-process video rendering
are preserved.

**Executed on Racket CS 9.3.0.8:** 49 audit groups / 3,053 checks; 68 library
groups / 2,484 checks; 60 review groups / 215,848 checks. These exercise the real
headless geometry implementation. The full RackUnit suite and post-fix native
Animate PNG/font/contact-sheet tests have **not** been run in this minimal
runtime. Additional native tests are included for the user's installation.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --audit
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/review-examples.rkt --example copy-angle --dark
```

**Installation:** place this entire `geometry/` directory in the root of the
`soegaard/animate` repository. No changes to the repository's existing files are
required. The adapter uses the public `main.rkt`, `colors.rkt`, and `render.rkt`
entry points of the containing checkout, not a separately installed copy.

This audited release extends the delivered v0.8.0 package used to produce the
uploaded review images. It preserves the review tooling as well as the standard
library. See [source notes](docs/SOURCE.md) for the baseline and input hashes.

## Standard construction library

Eight reusable compass-and-straightedge constructions, thirteen application
videos, and gallery plates using the new library. Helpers have typed arguments,
postconditions, expanded/collapsed use, and optional auxiliary cleanup. The
library uses a transferable compass; see the [construction reference](docs/CONSTRUCTIONS.md).

```racket
(require "geometry/core.rkt"
         (prefix-in c: "geometry/constructions.rkt"))

;; Within a construction:
(step "Construct the midpoint."
  (expand [M (c:bisect-segment A B)] #:auxiliaries 'hide))
```

The earlier object-specific reveals, measured-font annotation layout, one-second
read delay, right-angle size, shorter ticks, light/dark modes, and process-based
rendering are preserved. The [implementation plan](docs/STANDARD-LIBRARY-PLAN.md)
and [manual](docs/MANUAL.md) describe the changes.

## Standard-library applications

The first eight videos are square-on-segment, circumcenter, incircle,
triangle-midline, reflect-point, copy-triangle-sas, divide-segment-five, and
tangent-at-point. Five more cover the orthocenter, regular hexagon,
equilateral-triangle-chain, parallel-at-distance, and a standalone copy-angle.

Run the base-only checks, then render all thirteen in both themes:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --library
RACKET="$RACKET" WORKERS=10 sh geometry/examples/render-library.sh both
```

The batch script renders videos sequentially, using ten worker processes for
each one's frames. `light` or `dark` selects just one theme; `GEOMETRY_OUTPUT`
changes the output root. The gallery and the three original examples remain
separately runnable. See [all examples and contracts](docs/CONSTRUCTIONS.md).

## Small review bundles

Capture three images per step—**read**, **during**, **settled**—with captions,
paginated contact sheets, an offline browser index, and one uploadable ZIP per
example/theme. Expanded helper steps are included by default. No movie or full
frame sequence is rendered.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Start with a single example.
"$RACKET" geometry/review-examples.rkt --example square-on-segment --dark

# All 19 examples (including the gallery), in both themes.
"$RACKET" geometry/review-examples.rkt --all --both

# Only the 13 library applications, or a list of names.
"$RACKET" geometry/review-examples.rkt --library --light
"$RACKET" geometry/review-examples.rkt --list
```

Upload `geometry-review/dark/square-on-segment.zip` for the single-example run.
See [review bundles](docs/REVIEW-BUNDLES.md) for direct example flags, size options,
exact sampling behavior, and safe reruns. The review and full-video rendering
paths are preserved; the audited examples intentionally have revised steps and
timings. Regenerate their reviews from this release.

## Start here

Run these commands **from the `animate` repository root**, after installing the
repository's ordinary dependencies:

```sh
racket geometry/run-tests.rkt

racket geometry/examples/equilateral-triangle.rkt
racket geometry/examples/perpendicular-bisector.rkt
racket geometry/examples/perpendicular-through-point.rkt
racket geometry/examples/gallery.rkt
```

The examples default to **step stills**, not hundreds of full-animation frames.
Outputs go to separate directories under `geometry-output/`. Each directory
contains numbered PNG files, a `stills.tsv` index, and `narration.srt`.

To use your explicit Racket installation instead of the executable on `PATH`:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/examples/equilateral-triangle.rkt
```

The test runner uses the same Racket executable that launched it. Its exit status
is the `raco test` exit status. To test the mathematical/compiler/layout layer
without loading `animate`:

```sh
racket geometry/run-tests.rkt --core
```

## Render an animation

```sh
# All numbered PNG frames, at 30 fps by default.
racket geometry/examples/equilateral-triangle.rkt --frames

# Full animation plus an MP4. Encoding requires FFmpeg.
racket geometry/examples/equilateral-triangle.rkt \
  --mp4 equilateral-triangle.mp4 geometry-output/equilateral-video

# Change output dimensions and frame rate without changing the construction.
racket geometry/examples/perpendicular-bisector.rkt \
  --frames --width 1920 --height 1080 --fps 30 geometry-output/bisector-video

# Inspect the deterministic realization without writing images.
racket geometry/examples/perpendicular-through-point.rkt --describe
```

All example runners accept `--frames`, `--mp4 FILE`, `--describe`,
`--no-captions`, `--light`, `--dark`, `--workers N`, `--fps N`, `--width N`,
`--height N`, `--supersample N`, and an
optional output directory. Use separate directories for stills and full frames:
the native renderer cleans its previous numbered frames in the chosen directory.
SRT files contain text and timing only; audio generation is not included.

## Original examples and gallery

| File | What it demonstrates |
|---|---|
| `examples/equilateral-triangle.rkt` | Direct construction, initially hidden givens, a selected intersection, sequential joins, semantic coloring and deemphasis. |
| `examples/perpendicular-bisector.rkt` | Free givens, layout preferences, an **expanded typed helper**, two intersections, midpoint, and dashed auxiliary circles. |
| `examples/perpendicular-through-point.rkt` | Anonymous supporting geometry, `choose`, `#:other-than`, global realization, and helper circles that may extend outside the view. |
| `examples/gallery.rkt` | Visual catalogue of drawable geometry, semantic markers, equality classes, presentation actions, and expanded reusable constructions. |

`examples/helpers.rkt` re-exports the standard perpendicular-bisector construction.
The example runners' shared implementation is included in
`examples/private/run-example.rkt`; they do not depend on a missing runner in the
outer repository's examples directory.

## Author a construction

For a file placed in the repository root:

```racket
#lang racket/base
(require "geometry/main.rkt")

(construction triangle-demo
  (given [A (point -2 0)] [B (point 2 0)])
  (require (distinct? A B))
  (layout (focus A B C))
  (style [cA [color-family blue]]
         [cB [color-family aqua]])
  (step "Join the given points." [AB (segment A B)])
  (step "Circle centred at A through B." [cA (circle A B)])
  (step "Circle centred at B through A." [cB (circle B A)])
  (step "Choose the intersection on the left of A to B."
    [C (intersection cA cB #:side-of AB 'left)])
  (step "Join C to the endpoints."
    [AC (segment A C)] [BC (segment B C)])
  (step "The triangle is equilateral."
    (deemphasize cA cB) (highlight AB AC BC)))

(define scene (construction->scene triangle-demo))
```

`scene` is an ordinary `animate` scene. A file inside `geometry/examples/` uses
`(require "../main.rkt")` instead. An installed collection may use
`(require animate/geometry/main)`; **do not abbreviate this to
`animate/geometry`**, because this drop-in contains no root `geometry.rkt` file.
When also importing the ordinary `animate` API, prefix one import to distinguish
mathematical `circle`/`line` from the native Visual constructors:

```racket
(require (prefix-in a: "main.rkt") "geometry/main.rkt")
```

## Themes and units

```racket
(define lesson-theme
  (geometry-theme
    (stroke [width 2.5])
    (point [radius 0.055])
    (label [font-size 0.30])
    (circle [color-family aqua]
      (deemphasized (stroke [dash (7 5)])))
    (deemphasized [color-variant b] [opacity 0.45])
    (highlighted (stroke [width 4.5]))))

(define scene
  (construction->scene triangle-demo #:theme lesson-theme))
```

**Radius, font size, label offset, and geometric coordinates are local world
lengths.** For example, `0.30` is 0.30 world units, not automatically 30% of the
view width. **Stroke width and dash lengths are cosmetic dimensions.** Stroke
width is applied through `animate`'s native `visual-with-stroke-width` protocol.
The geometry theme does not reinterpret all dimensions as pixels or percentages.

Color families resolve to native `animate/colors` tokens such as `blue-a` and
`aqua-b`. Native color themes are selected at the rendering boundary; no copy of
the `animate` RGB palette is embedded here.

## Module map

`core.rkt` supplies the headless DSL, geometry kernel, realization, themes, and
timeline sampling. `main.rkt` adds conversion to native `animate` scenes and
Visuals. `render.rkt` adds PNG/MP4 and subtitle output. `private/` contains the
compiler, expression evaluator, numerical geometry, and drawing preparation.
`docs/MANUAL.md` documents the implemented language rather than every future
feature in the design proposal.

## Scope of this version

The original examples, eight standard constructions, thirteen application examples,
expanded/collapsed use,
visibility and label controls, themes, deterministic finite-candidate layout,
explicit pins/overrides, native scenes, and output helpers are implemented.
Geometry remains fixed after realization while its exposition animates. Layout
and label placement are heuristics, not a complete constraint solver or a proof
engine. See the manual for explicit limitations and escape hatches.


## Theme selection

Each example runner accepts `--light` (default) or `--dark`. The runner selects both the matching native Animate color theme and a matching geometry theme, so the same construction stays legible on white and dark backgrounds.


## Timing

Timing belongs in the construction DSL:

```racket
(timing
  [opening-pause 0.6]
  [read-delay 1.0]
  [action-duration 0.9]
  [step-pause 0.5])
```

A step's narration becomes current first, then the timeline waits for
`read-delay`, performs its action(s), and rests for `step-pause`. Individual
steps can override these defaults with `#:read-delay`, `#:duration`, and
`#:pause`.


Semantic diagram markers include right-angle squares, parallel arrows, and length/angle equality marks.


### Parallel rendering

Full frame/video rendering now uses **process-based parallel rendering** when
`--workers` is greater than 1. The example runner launches separate Racket
processes, each rendering a disjoint shard of the frame numbers, and then merges
the finished PNG files before optional MP4 encoding. This avoids the limited CPU
scaling seen with Racket parallel threads plus `racket/draw` rasterization.

Override the worker count with:

```sh
--workers 10
```

The runner prints both the requested and actual worker count. The worker setting
applies to full frame rendering (`--frames` and `--mp4`); selected step stills
remain a small sequential render.


The default narrated-step read delay is now 1.0 second.


## Gallery example

`examples/gallery.rkt` is a visual regression reel for the geometry layer. It
shows the primitive drawable types, midpoint/perpendicular/parallel/equality/angle
markers, label state changes, lighter auxiliary styling, restoration, temporary
highlights, hide/show transitions, simultaneous actions, and an expanded helper.

Render it like the other examples:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/examples/gallery.rkt --dark --workers 10 --frames /tmp/geometry-gallery
"$RACKET" geometry/examples/gallery.rkt --dark --workers 10 \
  --mp4 geometry-gallery.mp4 /tmp/geometry-gallery-video
```

Equal-length and midpoint ticks are now 20% shorter than in v0.5.4. The
right-angle square keeps its previous size.
