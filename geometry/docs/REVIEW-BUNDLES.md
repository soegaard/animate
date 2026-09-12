# Small review bundles — v0.8.1

Review mode produces **three PNG images per authored step** instead of a movie.
It reuses the native geometry renderer and the complete timeline's fixed camera,
font measurement, label/marker layout, color theme and reveal behavior.
It does not render all movie frames, invoke FFmpeg, or modify the construction.

## One example

From the `animate` repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/review-examples.rkt \
  --example square-on-segment --dark
```

This creates both:

```text
geometry-review/dark/square-on-segment/       extracted review files
geometry-review/dark/square-on-segment.zip    the file to upload
```

The ZIP has a single `square-on-segment/` folder. The theme is recorded in the
manifest and contact-sheet heading. Light and dark outputs have separate parent
directories, so the two runs do not overwrite one another.

## All examples, the library only, or a list

```sh
# All 19 examples: original three, thirteen applications, two new demonstrations,
# and gallery.
"$RACKET" geometry/review-examples.rkt --all --dark

# Both themes: one ZIP per example per theme (34 ZIPs, not one giant upload).
"$RACKET" geometry/review-examples.rkt --all --both

# Only the 13 standard-library application examples.
"$RACKET" geometry/review-examples.rkt --library --light

# List valid names without loading the graphics backend or writing files.
"$RACKET" geometry/review-examples.rkt --list
```

Choose exactly one of `--example NAME`, `--all`, or `--library`.
A name is the filename without `.rkt`, for example `incircle` or `gallery`.
`--list` is a separate listing mode. Omitting a selection does not accidentally
start a full batch. Example selection uses an explicit registry, not a glob that
might mistake `helpers.rkt` for a movie.

The default theme is light. `--light`, `--dark`, and `--both` are mutually
exclusive. Each selected example/theme runs in its own Racket process, in order.
A failure stops the batch and preserves the earlier successful bundles.

## Contents of each bundle

```text
square-on-segment/
  step-001-read.png
  step-001-during.png
  step-001-settled.png
  step-002-read.png
  step-002-during.png
  step-002-settled.png
  ...
  contact-sheet-001.png
  contact-sheet-002.png
  ...
  steps.txt
  manifest.json
  index.html
```

A short example has one `contact-sheet.png`; longer examples use numbered pages.
Each page contains at most six step rows, with Read / During / Settled columns.
Full narration is repeated above the thumbnails. Thumbnails are 384 pixels wide;
the separate step images retain full resolution. `index.html` is an offline
browser index with clickable full-size images and no external resources.

`steps.txt` contains the step text, source path, exact sample times and notes.
`manifest.json` adds machine-readable timing boundaries, action kinds/targets,
actual captions shown, dimensions and a complete file inventory. It records
`image_count` separately from the number of contact sheets.

## What the three samples mean

**Read:** the unchanged figure before this step's actions, normally at the middle
of the reading interval. The step's new narration is visible. Captions currently
appear immediately; review mode does not add a fictitious caption fade.

**During:** inside an actual animation event. The planner finds the midpoint of
accumulated action time, excluding reading intervals and pauses. If that midpoint
would fall exactly between two actions, it samples inside the next action
instead. Thus a step drawing two equal-duration segments does not yield a
misleading fully completed first segment with the second still absent.

**Settled:** the exact completed state of the step, normally at the middle of its
ending pause. It is taken before the next step can change the diagram or caption.

Times come from the timeline compiler's recorded step boundaries, not thirds of
a caption's duration and not rounded movie-frame indices. `--fps` records the
reference movie rate only; it does not change the number of review images.
`read` and `settled` use explicit boundary states, with the same frozen layout as
movie rendering. `during` uses ordinary timeline sampling.

A no-action/narration-only step intentionally has repeated geometry in its three
images. A zero-reading-delay or zero-ending-pause step uses the exact boundary
state, rather than borrowing a frame from the next step. An instantaneous step
still has a triplet, but its notes explicitly say there is no on-screen dwell
time. A construction with no authored steps gets one initial-diagram triplet.

Three images cannot capture every sub-action in a long step, every transient
highlight, or subtle motion jitter. Such rows are noted in the metadata. They
are a compact visual review aid, not a replacement for checking playback when
motion itself is in question.

## Silent cleanup rows

Silent authored steps whose visible effects are only cleanup operations such as
`hide`, `hide-label`, `deemphasize`, or `normalize` are omitted from review
bundles by default. Silent no-op/value-only steps are omitted as well. They still
run in the movie and still affect the state seen by following review rows; only
their redundant triplet is suppressed. A silent step that reveals, shows, or
highlights something remains review-worthy.

To inspect every authored row, including silent cleanup/no-op rows:

```sh
"$RACKET" geometry/review-examples.rkt \
  --example transformations --dark --include-cleanup
```

The direct example-runner spelling is `--review-include-cleanup`. The manifest
records whether cleanup rows were requested.

## Expanded helpers

The default includes outer authored steps **and** the steps inside `(expand ...)`,
recursively. A parent step containing an expansion is marked *expanded overview*;
its during image may legitimately show a child's narration. The child rows show
their own individual triplets. Compiler-generated initialization, result exposure
and auxiliary cleanup do not become spurious narrated review steps; their effects
are included in the enclosing overview's state.

The manifest's `source_path` is the outer step number followed by pairs of
expansion-action index and helper-step index. This retains a stable route back to
the elaborated source. Display row numbers and image filenames are contiguous;
internal paths can have gaps where generated helper steps were omitted.

For a smaller overview without separate helper rows:

```sh
"$RACKET" geometry/review-examples.rkt \
  --example incircle --dark --top-level-only
```

This changes only which review rows are selected, not the construction's actual
expansion, geometry, timing, or movie.

## Size and output options

The default image dimensions are **1280×720**, matching the existing video runner.
That keeps the camera's pixel scale and cosmetic stroke sizes consistent when
reviewing the eventual video. For smaller images:

```sh
"$RACKET" geometry/review-examples.rkt \
  --example incircle --dark \
  --width 960 --height 540 \
  --output compact-review
```

Changing dimensions can affect pixel-level font metrics and cosmetic stroke
appearance. Use the same dimensions as the intended movie for final typography
and spacing checks.

Other options are `--supersample N`, `--fps N`, `--no-captions`,
`--no-contact-sheet`, `--include-cleanup`, and `--output DIR` (default
`geometry-review`).
`--no-captions` removes captions and their reserved space from the images, but
`steps.txt`, the manifest, and the contact-sheet headings still carry the text.

Review mode renders only the sparse selected images, sequentially, and keeps one
image or one contact-sheet page in memory at a time. The existing `--workers`
option remains a full-frame/movie rendering option; it is not used to create ten
processes for a small review. No external `zip` utility is required.

## Direct example-runner options

Every one of the 19 examples also supports the review mode directly:

```sh
# Images, metadata and contact sheets; no ZIP unless requested.
"$RACKET" geometry/examples/incircle.rkt \
  --dark --review-stills review/incircle

# Images plus ZIP. The image directory defaults to the ZIP path without .zip.
"$RACKET" geometry/examples/incircle.rkt \
  --dark --review-zip review/incircle.zip

# Specify the two destinations independently.
"$RACKET" geometry/examples/incircle.rkt \
  --dark --review-stills review/incircle \
  --review-zip uploads/incircle-dark.zip
```

The direct-runner spelling of `--top-level-only` is `--review-top-level-only`;
the spelling of `--include-cleanup` is `--review-include-cleanup`.
`--no-contact-sheet` has the same spelling in both commands. Contact sheets are
on by default; no separate flag is needed to enable them.

Review mode cannot be mixed with `--frames`, `--mp4`, `--describe`, or internal
worker-shard modes. Existing movie/still commands keep their earlier behavior.

## Safe reruns

A review is rendered and validated in a sibling staging directory before it
replaces an older review. Every image is checked for a PNG header and the expected
pixel dimensions; the final file inventory must match the manifest. ZIP entries
use relative paths under one named folder, never absolute local filesystem paths.
The ZIP is built from the same verified inventory. Failed rendering or archive
creation leaves the previous successful review in place.

The output directory must be new, empty, or a managed review directory whose file
inventory still matches its manifest. A movie frame directory, a symbolic link,
or a directory containing additional hand-written notes is refused rather than
deleted. Keep notes outside generated files: edits to a generated `steps.txt` or
PNG are overwritten on a successful rerun. The ZIP must be outside the image
directory so it cannot accidentally include itself.

## Racket API

```racket
(require "geometry/review.rkt"
         (prefix-in color: "colors.rkt"))

(define report
  (render-geometry-review! timeline "review/incircle"
    #:name "incircle"
    #:width 1280 #:height 720
    #:color-theme color:animate-dark-theme
    #:theme-name "dark"
    #:expanded? #t
    #:include-cleanup? #f
    #:contact-sheet? #t
    #:zip "review/incircle.zip"))

(geometry-review-result-step-count report)
(geometry-review-result-image-count report)
(geometry-review-result-contact-sheets report)
(geometry-review-result-zip report)
```

`geometry/review-plan.rkt` provides `make-geometry-review-plan` and
`geometry-review-samples` without importing the native drawing backend.
`make-geometry-review-plan` accepts `#:include-cleanup?`; it defaults to `#f`. A review
step records its source span, caption, samples, and notes. Each sample contains
its phase, timestamp, filename and immutable `geometry-frame` snapshot.

`geometry-timeline-steps` exposes the compiler's ordered `geometry-step-span`
records. The timeline record now has an eighth `steps` field; callers should
normally obtain timelines through `construction->timeline` or
`make-geometry-timeline` instead of calling the record constructor directly.

The adapter's `geometry-timeline->visual-sampler` prepares fonts/annotations once
and returns a sampler accepting either a time or a `geometry-frame` from that
same timeline. Review rendering uses this to preserve the full video's layout
while rendering exact step boundaries.

## Tests

```sh
# Planning, all 19 example timelines in both themes, file safety and ZIP contents.
# Requires Racket base only; PNG-fixture tests are not native geometry renders.
"$RACKET" geometry/run-tests.rkt --review

# Includes the new checks and native PNG/contact-sheet integration tests.
"$RACKET" geometry/run-tests.rkt
```

See `docs/TESTING.md` for the execution status of this delivery.


## Reviewing the audited examples

v0.8.1 changes the examples' authored steps and some layouts. Rebuild the bundles
after replacing `geometry/`; old step filenames do not identify the same action
in the new source. Historical v0.8.1 bundles recorded `geometry_version: "0.8.1"`; current bundles record `0.9.1`. All-example
and single-example selection, both-theme output, and three samples per step are
unchanged.

Use a separate root when retaining both old and new reviews:

```sh
"$RACKET" geometry/review-examples.rkt --all --both --output geometry-review-v081
```

The input-based audit and follow-up checklist are in `EXAMPLE-AUDIT.md`.


## Transformation and semantic-label reviews (v0.9.1)

`--example transformations` and `--example semantic-labels` select the
standalone demonstrations. In v0.9.1 the default review omits their silent
cleanup/no-op rows; add `--include-cleanup` when those state transitions are the
subject of the audit. Both also belong to `--all`; neither changes the
thirteen-example `--library` selection. The gallery retains the previous plates
and adds transformation and label plates. All use the same read/during/settled
snapshot machinery and preserve per-example/theme ZIP isolation.

Transformation objects are realized before review sampling. The review does not
animate a geometric rotation or reflection: it records the normal reveal of the
resulting image. Label strings and placements are fixed for that realization.
The ordinary visibility commands control their review states.
