# animate/math — semantic mathematical animation

**Version 0.5.1 — mathematical concept gallery and named composite moves**

Held expressions → checked elementary steps → named mathematical moves →
independent presentations → ordinary Animate scenes.

This `math/` folder is a replacement subcollection for Animate commit
`525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`, including the completed process-rendering
update. No parent repository files are included or changed. Neither `racket-cas`
nor Calcura is mandatory for the supplied lessons.

## Explore the gallery

The new gallery contains **25 concept plates / 31 replays** across held operations,
selection/provenance, conditions, named moves, and presentation. Select one plate,
one chapter, or all of them. The complete planned duration is **245.6 seconds**;
the shorter total reflects both the four-checkpoint history/grouping comparison
fixture and the reduced gallery-only final settle hold after the 30-fps pacing review.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" math/examples/gallery.rkt --list-plates
"$RACKET" math/examples/gallery.rkt --plate additive-cancellation --describe

# Native review stills, contact sheets, HTML, and an optional ZIP.
"$RACKET" math/examples/gallery.rkt \
  --dark --show-api --review-stills \
  --review-zip math-output/gallery-v0.5/review.zip \
  math-output/gallery-v0.5/review

# Complete gallery using the shared process renderer.
"$RACKET" math/examples/gallery.rkt \
  --dark --workers 10 \
  --mp4 math-output/gallery-v0.5/gallery.mp4 \
  math-output/gallery-v0.5/all-frames
```

Use `--chapter moves`, repeatable `--plate`, and optional `--show-api` to narrow the
reel. The gallery adds no required CAS. All original v0.4 moves and the four reviewed
lessons remain available. Read **[the gallery guide](docs/gallery.md)** for the full
catalogue, native process probes, preparation boundaries, and output-safety rules.

The gallery is an example collection, not an extension of the public algebra API.
Its independent demonstrations are sequenced as ordinary scene clips, never fake
mathematical parameter cases.

## Start with the author's method

```racket
#lang racket/base
(require animate/math)

(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'lesson
        #:context (math-context #:real '(x))))

(define solution
  (derive problem
    [isolate-term
     (steps
       [subtract-five   (both-sides 'subtract 5)]
       [cancel-five     (cancel-addends #:at (lhs))]
       [evaluate-twelve (evaluate #:at (rhs))])]
    [isolate-x
     (steps
       [divide-three  (both-sides 'divide 3)]
       [reduce-left   (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
       [remove-one    (remove-unit #:at (lhs))]
       [evaluate-four (evaluate #:at (rhs))])]))

(define plan
  (present solution #:style classroom #:groups 'top-level))
```

`steps` retains every primitive checkpoint and its verification/occurrence trace.
It does not simplify, infer an unstated assumption, or replace the steps with an
opaque CAS answer. The outer names describe the method; presentation uses them
as default classroom groups. `#:groups 'steps` and explicit partitions remain
available.

Reusable recipes are ordinary Racket functions returning `steps`. Nested steps
have stable addresses, such as `'(isolate-term cancel-five)`:

```racket
(after solution 'isolate-term)
(derivation-step solution '(isolate-term cancel-five))
(derivation-tree solution)

(define tuned
  (choreograph plan
    [(isolate-term cancel-five)
     (retire-cancelled #:duration 2/5)
     (hold 1/2)
     (compact #:duration 2/5)]))
```

Read **[Named mathematical moves: design and guide](docs/composite-moves.md)**
for the complete implemented contract, including nested recipes, name resolution,
case-specific overrides, conservative relationship summaries, and migration.

## Module boundaries

| Module | Responsibility |
| --- | --- |
| `animate/math` | Pure held mathematics, recipes, derivations, cases, notation, and presentation descriptions |
| `animate/math/render` | Explicit formula/layout preparation and native scene/visual/pict conversion |
| `animate/math/cas` | Optional bounded CAS query and verification execution |

`(require animate/math)` performs no TeX, native rendering, or CAS execution.
The example modules also defer their native project adapter until rendering is
explicitly requested.

## Inspect, test, and render

From the repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" math/examples/linear-concrete.rkt --tree
"$RACKET" math/examples/linear-concrete.rkt --steps
"$RACKET" math/examples/quadratic-general.rkt --list-cases
"$RACKET" math/examples/quadratic-general.rkt --tree --case quadratic/two-real-roots

"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-process-contracts.rkt

# Actual native intermediate probes, with old-flat versus new-structured pixel comparison:
"$RACKET" math/run-probes.rkt --dark --compare-flat math-output/moves-v0.5/probes
```

The first three inspection modes create no frames or workers and do not typeset.
`run-process-contracts.rkt` checks fresh-process prepared-plan reconstruction with
**synthetic native geometry**, not actual rasterization. `run-probes.rkt` uses the
real installed Animate/LaTeX/dvisvgm pipeline; omit `--compare-flat` for the usual
standalone probes. `--checkpoints-only` is still supported.

Render the four actual videos with the shared process renderer:

```sh
mkdir -p math-output/moves-v0.5/videos

for example in linear-concrete linear-general quadratic-concrete quadratic-general
do
  "$RACKET" "math/examples/${example}.rkt" \
    --dark --workers 10 \
    --mp4 "math-output/moves-v0.5/videos/${example}.mp4" \
    "math-output/moves-v0.5/frames/${example}" || break
done
```

Defaults remain 1280×720, 30 fps, supersampling 1. `--fps`, `--width`, `--height`,
`--supersample`, `--light`, `--dark`, `--case`, `--workers`, and the independent
frame-directory/MP4 paths retain the updated renderer's behavior. FPS is an exact
positive integer, as in the supplied process-rendering baseline.

## The four lessons

| Source | Method and cases | Duration |
| --- | --- | ---: |
| `examples/linear-concrete.rkt` | `3x+5=17`; isolate the term, then isolate `x`, retaining `1·x` | 10.8 s |
| `examples/linear-general.rkt` | `ax+b=c`; ordinary, identity, and inconsistent cases | 18.0 s |
| `examples/quadratic-concrete.rkt` | Complete the square; retain the explanatory inset and both roots | 17.6 s |
| `examples/quadratic-general.rkt` | Shared completing-square derivation, all discriminant and degenerate cases | 51.9 s |

Each retains `problem`, `solution`, `plan`, `make-demo-scene`,
`math-render-preparer`, and `math-render-builder` exports. Candidate-check
exports remain in the concrete lessons. Existing flat elementary authoring is
still supported.

## Rendering support is retained

For each ordinary lesson, the parent prepares the complete mathematical plan exactly once. Workers consume
validated prepared layouts and staged SVG assets; they do not invoke TeX or redo
formula layout. More than one worker selects the shared generic subprocess
executor. One worker follows the ordinary local policy. No new worker pool or
frame evaluator is implemented by this revision.

The existing content-addressed SVG cache and stable glyph-definition ordering
are retained. Prepared artifacts remain under the generic integrity/lease
boundary. Portable math preparation now uses schema
`animate-math-prepared-plan-v2`, with explicit hierarchy and leaf-path identity.

Rendering needs the normal Animate dependencies, `latex`, and `dvisvgm`; MP4
encoding additionally needs `ffmpeg`. On macOS, ensure `/Library/TeX/texbin` is on
PATH when it is your TeX installation. The existing H.264/yuv420p encoder still
requires even encoded dimensions.

## Installation and upgrade

Back up the current folder outside the repository, then extract the archive in
the repository root. Do not overlay it onto old `compiled/` files. The archive
contains exactly a `math/` root, with no compiled caches or rendered artifacts.
Recompile dependent math modules with the matching Racket installation before
running tests:

```sh
RACO="/Applications/Racket v9.3.0.2/bin/raco"
"$RACO" make math/main.rkt math/render.rkt math/cas.rkt math/examples/*.rkt
```

Scheduled step and checkpoint accessors return a symbol for a flat root leaf,
a symbol list for a nested leaf, and `#f` for structural phases. Consumers that
previously assumed every scheduled step was a symbol should handle both forms.
`rewrite-step-name` remains the original local symbol.

## Documentation and validation

- [Concept gallery guide](docs/gallery.md)
- [Composite design and user guide](docs/composite-moves.md)
- [Full mathematical API guide](docs/user-guide.md)
- [Public reference](scribblings/math.scrbl)
- [Integration boundaries](INTEGRATION.md)
- [Executed validation and limitations](docs/validation.md)
- [Gallery review-repair record](docs/gallery-review-fix-progress.md)

The original `docs/proposal-v0.1.md` and earlier changelog/review records are
historical, not the specification of the new hierarchy. See `CHANGES.md` for the
version history.
