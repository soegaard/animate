# Geometry authoring for `animate` — v0.6.0

A first implementation of the mathematical-authoring DSL: geometry, exposition,
presentation state, layout, and styling remain separate.

**Installation:** place this entire `geometry/` directory in the root of the
`soegaard/animate` repository. No changes to the repository's existing files are
required. The adapter uses the public `main.rkt`, `colors.rkt`, and `render.rkt`
entry points of the containing checkout, not a separately installed copy.

This version extends the geometry sources from commit
`1e6610cd4fbe6e6224c87a9e55e4949a6ca54a05`. Its new rendering code uses Animate's
public text, path, camera and Visual APIs.

**Validation status:** Racket is not installed in this build environment. Source
structure, imports, constructor arities, baseline hashes and native API contracts
were reviewed, but the Racket tests and native renders have **not been executed**
here. The tests are included for the local run; see [testing](docs/TESTING.md).

## New in v0.6.0

Object-specific, direction-selectable reveals and progressive marker strokes;
measured-font, visibility-aware label/marker layout; placement hints and conflict
diagnostics; and a reserved narration band. Right-angle size, shorter ticks,
1-second read delay, light/dark modes, and process-based rendering are preserved.
The gallery includes direction and dense-annotation plates.

The [implementation plan](docs/REVEAL-AND-LAYOUT-PLAN.md) and
[manual](docs/MANUAL.md) describe the syntax and boundaries.

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

All four example runners (including `gallery.rkt`) accept `--frames`, `--mp4 FILE`, `--describe`,
`--no-captions`, `--light`, `--dark`, `--workers N`, `--fps N`, `--width N`,
`--height N`, `--supersample N`, and an
optional output directory. Use separate directories for stills and full frames:
the native renderer cleans its previous numbered frames in the chosen directory.
SRT files contain text and timing only; audio generation is not included.

## The three examples

| File | What it demonstrates |
|---|---|
| `examples/equilateral-triangle.rkt` | Direct construction, initially hidden givens, a selected intersection, sequential joins, semantic coloring and deemphasis. |
| `examples/perpendicular-bisector.rkt` | Free givens, layout preferences, an **expanded typed helper**, two intersections, midpoint, and dashed auxiliary circles. |
| `examples/perpendicular-through-point.rkt` | Anonymous supporting geometry, `choose`, `#:other-than`, global realization, and helper circles that may extend outside the view. |
| `examples/gallery.rkt` | Visual catalogue of drawable geometry, semantic markers, equality classes, presentation actions, and expanded reusable constructions. |

`examples/helpers.rkt` contains the reusable perpendicular-bisector construction.
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

The three construction examples, typed reusable helpers, expanded/collapsed use,
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


This version adds semantic diagram markers, including perpendicular markers and equality markers.


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
