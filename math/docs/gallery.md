# Mathematical concept gallery — local review-repair update

The gallery is a visual catalogue, not a fifth equation-solving lesson. It contains

Version note: this local repair freezes measured header/body/footer geometry in the
parent preparation payload, keeps `1·x` target-relative through unit-factor
compaction, uses stationary left-anchored hierarchy markers, places candidate
checks beside the checked expression, and improves review labels/probes. It is not
a new algebraic API or renderer.

**25 independently selectable plates and 31 replays**, organized into five chapters.
The complete planned duration is **264.2 seconds (4 minutes 24.2 seconds)**. It
changed intentionally because the grouping/history demonstrations now use the
short shared four-checkpoint comparison derivation.

Every replay uses ordinary checked mathematical states, derivations, and presentations.
The gallery supplies a title, a short caption, optional API labels, and time to read the
result. Comparison plates replay the **same derivation value** with different presentation
settings. Unrelated plates are never encoded as mathematical cases or alternatives.

The implementation extends the tested v0.4.0 composite-moves library and retains the
shared-process renderer in Animate commit `525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`.
The archive replaces only `math/`; no parent files need patching.

## 1. Start with one plate

Run these commands from the Animate repository root after installing the replacement
`math/` folder:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" math/examples/gallery.rkt --list-plates
"$RACKET" math/examples/gallery.rkt --list-chapters
"$RACKET" math/examples/gallery.rkt --plate additive-cancellation --describe

"$RACKET" math/examples/gallery.rkt \
  --plate additive-cancellation \
  --dark --show-api --workers 10 \
  --mp4 math-output/gallery-v0.5/cancellation.mp4 \
  math-output/gallery-v0.5/cancellation-frames
```

The cancellation plate shows `x²+6x+5−5 → x²+6x`. Its survivor structure stays still
while the opposite constants retire, then the gap closes. The internal `+` is one
of the important visible regression targets.

The default output is a PNG sequence. `--mp4` additionally encodes the complete sequence
once, in the parent, after rendering has succeeded. The MP4 path is independent of
and must be outside the frame directory.

## 2. Render a chapter or the complete gallery

```sh
# Replay the hierarchy, recipes, and grouping demonstrations.
"$RACKET" math/examples/gallery.rkt \
  --chapter moves --dark --show-api --workers 10 \
  --mp4 math-output/gallery-v0.5/moves.mp4 \
  math-output/gallery-v0.5/moves-frames

# Render all 25 plates / 31 replays.
"$RACKET" math/examples/gallery.rkt \
  --dark --workers 10 \
  --mp4 math-output/gallery-v0.5/gallery.mp4 \
  math-output/gallery-v0.5/all-frames
```

Defaults are **1280×720, 30 fps, supersampling 1**, with light appearance unless
`--dark` is supplied. All selected replays use one normal Animate scene and one
shared executor. There is no outer pool of plate workers multiplied by an inner
pool of frame workers.

Selection is deterministic. Repeating `--plate` selects several plates in **catalogue
order**, irrespective of command-line order:

```sh
"$RACKET" math/examples/gallery.rkt \
  --plate distribution --plate checked-replacement \
  --dark --workers 10 math-output/gallery-v0.5/two-rewrites
```

Unknown IDs, duplicate IDs, and plates outside an explicitly selected chapter are
errors. Selecting a plate never silently drops an elementary mathematical step.
There is intentionally no gallery `--case`: mathematical cases belong inside the
parameter demonstrations, not between independent demonstrations.

## 3. Catalogue

| Chapter | Plate ID | Demonstration |
| --- | --- | --- |
| `held` | `held-arithmetic` | An unevaluated equation remains held. |
| `held` | `both-sides` | Prepare space, then introduce subtraction on both sides. |
| `held` | `additive-cancellation` | Retire opposite constants without losing a surviving separator. |
| `held` | `factor-cancellation` | Cancel `3` in `(3x)/3`, retaining `1·x` before removing the unit. |
| `held` | `focused-evaluation` | Compute a fraction's numerator, then its quotient. |
| `held` | `signed-reorder` | Replace `√Δ−b` by `−b+√Δ` without moving loose signs. |
| `selection` | `occurrence-selection` | Replace only the middle occurrence in `x+x+x`. |
| `selection` | `structural-selection` | Evaluate only the numerator of the equation's right side. |
| `selection` | `distribution` | A template witness records the duplicated `a` in `a(b+c) → ab+ac`. |
| `selection` | `checked-replacement` | Check a perfect-square target without inventing detailed motion provenance. |
| `conditions` | `domain-restriction` | `x/x → 1` retains the original `x≠0` exclusion. |
| `conditions` | `negative-inequality` | Dividing `−2x<6` by `−2` reverses the relation. |
| `conditions` | `zero-product` | A real zero-product equation introduces alternatives. |
| `conditions` | `square-roots` | A positive square equation retains both root alternatives. |
| `conditions` | `parameter-cases` | `ax=b` has ordinary, all-real, and no-solution parameter cases. |
| `conditions` | `candidate-check` | Check `x=4` against the original `3x+5=17`. |
| `conditions` | `implication` | Square `x=2` forward, then reject the extra candidate `−2` in a second replay. |
| `moves` | `named-moves` | A composite move retains its elementary operations; a small tree marks the current step. |
| `moves` | `nested-moves` | An outer move contains smaller moves and leaf operations. |
| `moves` | `reusable-recipe` | An ordinary Racket function supplies the same procedure for two equations. |
| `moves` | `grouping` | Replay the same derivation grouped by top-level moves and by leaves. |
| `presentation` | `history` | Replay the same derivation with replacement, completed-group, and all-checkpoint history. |
| `presentation` | `cancellation-timing` | Replay the same cancellation with an ordinary or longer pause before compaction. |
| `presentation` | `explanatory-inset` | Show `(6/2)²=9` separately before adding nine and completing the square. |
| `presentation` | `shared-prefix` | Do common work once, then continue through genuine parameter cases. |

The six extra replays are the second implication demonstration, the second recipe
application, the second grouping, two additional history policies, and the second
cancellation timing. There are no hidden CAS installation requirements for any plate.

Occurrence substitution is labeled as **specialization**, not as an identity.
Candidate checking proves membership or rejection, not completeness on its own.
The implication plate does not mislabel squaring as an equivalence. The negative
inequality uses an explicit safe whole-step `transition` to retire the changed
relation as well as introduce the divisions.

## 4. Inspect without rendering

```sh
"$RACKET" math/examples/gallery.rkt --chapter conditions --steps
"$RACKET" math/examples/gallery.rkt --chapter presentation --describe
```

`--list-plates`, `--list-chapters`, `--describe`, and `--steps` return before native
project loading, formula preparation, worker creation, output-directory creation,
or encoding. `--steps` prints held states and the relationship recorded for each
primitive step. `--describe` includes per-replay start/end times and relevant API
constructs.

`gallery-index.json`, placed next to a completed PNG sequence, records the same
catalogue, source files, captions, API names, and exact and numeric timestamps.
The mathematical plans retain their own checkpoint and hierarchical step addresses.

## 5. Native review bundles

Use sparse review before rendering the complete gallery:

```sh
"$RACKET" math/examples/gallery.rkt \
  --dark --show-api --review-stills \
  --review-zip math-output/gallery-v0.5/review.zip \
  math-output/gallery-v0.5/review
```

A bundle contains:

- `stills/`: full-size native PNGs at read, during, settled, and final-result times;
- numbered six-cell contact sheets and `index.html`;
- `manifest.json` linking each image to its plate, variant, exact time, phase,
  case path, step address, and last completed mathematical checkpoint;
- `gallery-index.json` with chronological selection metadata.

The review count follows the selected plates and current schedule; it is not a
fixed compatibility number. Intermediate `transition` probes sample at 25%, 45%,
50%, 55%, and 75%. `compact` and `reveal-created` also sample 5%, 15%, 25%, 50%,
75%, 85%, and 95%, so the unit-factor assembly is not hidden by a midpoint.
Every sample is checked for repeatable native pixels after seeking elsewhere and
back. Contact sheets use two label lines with the replay and semantic probe id.

Use `--checkpoints-only` for a smaller checkpoint-only review, or select a single
plate/chapter. Review is intentionally local; `--workers` does
not start a frame pool for stills. Review images use the requested camera size
without movie supersampling.

The checkpoint in a `during` record describes the last completed mathematical
state, not a claim that the partially faded intermediate frame is that exact
checkpoint. Review metadata is navigation/evidence, not a new evaluator.

## 6. Automated checks and real-process probes

```sh
"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-process-contracts.rkt

# Only the new gallery's dependency-light tests.
"$RACKET" math/run-gallery-tests.rkt

# Actual native stills: requires installed Animate/graphics and TeX/dvisvgm.
"$RACKET" math/run-gallery-probes.rkt \
  --dark math-output/gallery-v0.5/native-probes

# Actual direct/subprocess PNG comparison and a zero-worker cache-hit check.
# Use three representative plates first; the selected plates also get review stills.
"$RACKET" math/run-gallery-probes.rkt \
  --dark --plate additive-cancellation --plate nested-moves \
  --plate explanatory-inset --process-check --workers 2 \
  --fps 2 --width 640 --height 360 \
  math-output/gallery-v0.5/process-probes
```

`--process-check` uses the **real** project renderer, fresh frame caches for the
direct and subprocess runs, SHA-256 comparisons, and an identical same-cache
repeat that must start zero workers. It checks inherited preparation/typesetter
entry counts against the number expected from parent preparation, writes
`process-check.json`, and removes only its scratch frame/cache directories.
The 2-fps probe setting is a correctness smoke test, not a scaling benchmark.

`run-process-contracts.rkt` is different: it uses **12 independent Racket processes**
to round-trip the four original lessons and both full-gallery themes, but its
native geometry is synthetic. It verifies real file transfer, identity/rebinding,
complete clip/request structure, and forbidden consumer-side preparation; it does
not claim native raster or process-renderer validation.

See [validation.md](validation.md) for the checks actually executed in this delivery.

## 7. Rendering, preparation, and cache ownership

The gallery is an example collection plus thin adapters, not another renderer.
Its restartable contract matches the existing project loader exactly:

```text
gallery-render-preparer: context options -> source-preparation
gallery-render-builder:  context options payload -> scene
```

One generic parent preparer invocation prepares each selected replay **once**.
For the whole gallery that means 31 math-plan preparations in the parent, not
31 preparations in each worker. Each replay is fitted independently; a wide
expression on one plate cannot shrink an unrelated simple plate. Tree plates
reserve a separate inspector column. Caption/API space is reserved before output.

The existing v2 portable math codec represents each mathematical replay inside the
versioned `animate-math-gallery-view-v2` wrapper. Large replay data is stored in a
bounded, content-addressed `.gallery.rktd` file instead of
inflating every worker message. The generic preparation manifest registers these
files alongside all referenced SVG assets; it verifies and leases them. Workers
verify the files, reconstruct local math states/layouts, and append their clips
through the same math compiler. They do not typeset, refit formulas, or construct
another process pool.

The inspector is compiled from the move hierarchy at leaf boundaries. It is not
a mutable per-frame updater. All formula views, captions, tree lines, and numeric
checkpoint values are removed before the next independent replay.

Caches retain the existing ownership boundaries:

| Cache | Purpose | Deletion rule |
| --- | --- | --- |
| Normal `animate-math/svg-v1` preference cache | Content-addressed formula SVGs | Do not clear while a render may read it. |
| `math/examples/.animate-math-preparation-artifacts-v1/` | Verified SVG mirrors and gallery `.rktd` files | Delete only when no render/session uses them; the parent can rebuild them. |
| `.animate-math-gallery-render-cache` beside the requested output | Generic persistent frame cache | Owned by the generic project cache policy, not by the gallery's algebra. |

Rendering uses the existing worker policy: `auto` with one worker is local;
`auto` above one worker uses restartable subprocesses. `--worker-mode` can
explicitly select `auto`, `in-process`, or `subprocess`. Worker count is a
concurrency limit, not a CPU-utilization promise, and does not enter the
mathematical/source options.

Both the lazy gallery adapter's import closure and the native renderer's import
closure are explicitly declared to the existing input manifest builder. Lazy
loading for inspection must not cause a renderer-code change to be missed by
cache identity. These are local declared-input integrity checks, not a sandbox
for arbitrary source code or a claim of hermetic execution.

## 8. Output safety and limitations

By default, rendering and review require a new output directory. `--replace` is
allowed only for a previous gallery PNG directory with a valid `gallery-index.json`
and no unrelated files or links. It is rejected for review bundles. MP4s must be
outside the frames directory; an existing MP4 needs explicit `--replace`.

MP4 encoding writes a temporary sibling and publishes the requested file only
after FFmpeg succeeds. No video encode runs inside a frame worker. This is not a
claim of an atomic transaction across an entire movie, frame directory, and all
metadata under sudden machine or process failure.

`--supersample N` produces PNGs at `width*N` by `height*N`; the gallery MP4 preserves
those actual dimensions. H.264/yuv420p requires even output dimensions. PNG-only
rendering accepts the native renderer's ordinary size range.

Review failure may leave its new, owned incomplete directory for diagnosis;
choose another directory on retry. Existing user output is never silently cleaned.

There are no simultaneous multi-column case layouts, glyph-path morph promises,
CAS-dependent plates, narration generation, or adaptive worker-count tuning in
this revision. The comparisons are consecutive replays by design.

## 9. Extend the gallery

The chapter sources are small, ordinary Racket examples in `examples/gallery/`.
They import `../../main.rkt` and the gallery's pure `model.rkt` and `common.rkt`.
A single-view plate is created with:

```racket
(one-view-plate
  'my-example 'held "A short title"
  "One sentence explaining the mathematical action."
  (present
    (derive (gallery-state 'my-example '(/ (+ 8 4) 3))
      [numerator (evaluate #:at (numerator))]
      [quotient (evaluate)])
    #:style replace-style)
  '(numerator evaluate))
```

Add the plate to its chapter's ordered list; the catalogue, selection CLI,
preparation, movie, and review schedules then use it automatically. Comparison
plates use `make-gallery-plate` with several `make-gallery-view` records. Reuse
one derivation value when the intended comparison varies only presentation.
Do not add a gallery item as a fake branch of another item's mathematics.

From a Racket program, the example facade also supports direct scene construction:

```racket
(require (prefix-in gallery: "math/examples/gallery.rkt"))

(define scene
  (gallery:make-demo-scene #:plates '(distribution checked-replacement)
                           #:theme 'dark #:show-api? #t))
```

That call performs preparation and returns an ordinary native scene. To retain
restartable subprocess rendering, use the gallery CLI/source contract rather
than pass this already constructed opaque scene to an automatic process renderer.
