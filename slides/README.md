# animate/slides — themeable layouts

**Version 0.1.4.** Integrated into the Animate repository on 16 September 2026.

Immutable slides → prepared layout and timing → **Pict or ordinary native Scene**.
The public authoring vocabulary is unprefixed within Animate. `slide` is syntax;
`make-slide` is the procedural constructor. No second video encoder is introduced.

**Validation status:** all 36 named unit and integration tests pass, and the
repeat-2 visual review completed 158 Pict/Scene comparisons with zero probe
errors. See [validation.md](docs/validation.md).

## Use in this checkout

The implementation and its native integration are part of this repository. From
the checkout root, compile the public modules and run the suite directly:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make -l animate/slides -l animate/slides/pict \
  -l animate/slides/scene -l animate/slides/render -l animate/slides/math \
  -l animate/slides/geometry -l animate/slides/project
"$RACKET" slides/run-tests.rkt --math --geometry --media --project
```

No new package dependencies are needed. CI runs this complete command in its
headless Racket 9.3 lane.

The repository owns the three narrowly scoped native integrations:

- `private/pict-adapter.rkt`: render a generic prepared Pict or sampled native
  viewport using the normal renderer.
- `math/private/prepare.rkt`: accept explicit foreground/background colors and a
  minimum formula fitting scale; existing defaults are unchanged.
- `math/private/animate-adapter.rkt`: exposes an internal end-of-step callback
  for exact mathematical cue times.

## A first example

```racket
#lang racket/base
(require animate/slides animate/slides/pict animate/slides/scene)

(define welcome
  (slide #:layout 'title
    [title "Solving equations"]
    [subtitle "Keep both sides equal."]))

(define opening
  (build-slide welcome #:initial 'hidden
    (beat 'heading #:duration 1
      (reveal-slot 'title #:duration 0.4))
    (beat 'explanation #:duration 3
      (reveal-slot 'subtitle #:duration 0.5))))

(define still (slide->pict welcome))
(define animation (slide->scene opening))
```

A plain slide has no implicit movie duration. Its Pict is the populated static
composition; its Scene has duration zero. `hold-slide` or `build-slide` supplies
time. Both adapters consume the same prepared rectangles, opacity values, local
content clocks, and transition state.

**Naming refinement:** deferred slide paragraphs are `paragraph-content`, not
`paragraph`, because Animate already exports a concrete native `paragraph` Visual
constructor. All supplied combinations of slide, math, Scene, and project APIs
use ordinary imports without user-side renaming. Third-party Pict/Slideshow names
may still require `only-in` or `prefix-in` at their integration boundary.

## Examples and real rendering

The source modules in `examples/` only export descriptions. Rendering is explicit:

```sh
# Nineteen-and-six-tenths-second silent lesson, using ten subprocess workers.
"$RACKET" slides/render-example.rkt --workers 10 \
  slides/examples/function-lesson.rkt

# Narrated mathematical choreography: silent draft narration plus subtitles.
# Actual TeX and dvisvgm preparation happens once in the parent.
"$RACKET" slides/render-example.rkt --workers 10 \
  slides/examples/math-lesson.rkt

# Geometry embedding is native, but this release does not have its portable codec.
"$RACKET" slides/render-example.rkt --in-process \
  slides/examples/geometry-lesson.rkt

# PNG output without encoding.
"$RACKET" slides/render-example.rkt --frames --workers 10 \
  --output slides-output/frames slides/examples/native-scene.rkt
```

MP4 uses the existing H.264/AAC project path and requires FFmpeg. Recorded
narration additionally uses `ffprobe`; mathematical content requires the same
LaTeX/dvisvgm installation as `animate/math`. On macOS, add `/Library/TeX/texbin`
to PATH when that is where your TeX distribution exposes its programs.
The runner refuses existing output destinations according to the ordinary
project overwrite policy; choose a new `--output` root for another run.

## Validation and gallery

```sh
# Default suites: model, layout, timing, native output, and preparation codec.
"$RACKET" slides/run-tests.rkt

# Real optional integrations, not mocks.
"$RACKET" slides/run-tests.rkt --math --geometry --media --project

# All twelve layouts, light/dark, four formats; then timed examples in reverse
# seek order and immediately around beat/transition boundaries.
"$RACKET" slides/run-probes.rkt --repeat 2 slides-output/probes-v1

# Include mathematical and geometrical lessons in the same final review runner.
"$RACKET" slides/run-probes.rkt --repeat 2 --math --geometry \
  slides-output/probes-v1-full
```

The runner writes PNG pairs, `index.html`, `manifest.json`, and a sibling ZIP.
It refuses to mix a prior probe directory with a new run. The manifest records
actual per-channel differences and repeatability failures; matching semantics
does not promise identical antialiasing on every platform.

## Documentation

Read [the implementation guide](docs/user-guide.md) for short and medium examples,
theme inheritance, custom layouts, narration, native interoperability, and the
production workflow. [API reference](docs/api.md) lists the supported surface.
The previously agreed [revision-2 design](docs/design-v2.md) is retained as design
history, **not** as a claim that every proposed diagnostic or extension exists.

Current boundaries include fade/instant reveals, whole-slot crossfade replacement,
text-only bullet items, opaque-Pict matching by crossfade, and in-process-only
geometry preparation. Slot groups can receive native animation after conversion;
the interior of an embedded native viewport is not exposed as ordinary outer
Scene selection paths. Font-fallback/figure-resolution advisories and an
interactive layout editor are not implemented.
