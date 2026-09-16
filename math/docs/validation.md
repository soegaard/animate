# Validation — animate/math 0.5.0 gallery

## Baseline and delivery scope

This revision extends the delivered `animate-math-v0.4.0-composite-moves.zip` that
passed the user's tests. The parent Animate baseline is
`525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`, including shared-process rendering.
The predecessor archive's SHA-256 is recorded in `BUILD-INFO.json`.

The delivery contains only a replacement `math/` folder. It includes no parent
repository edits, precompiled `.zo` files, generated SVG/preparation caches,
review images, movie frames, videos, or font files.

The four original lesson source files are byte-identical to v0.4.0. The public
`math/main.rkt`, `math/render.rkt`, and `math/cas.rkt` facades are unchanged, as
are the mathematical operations, derivation/presentation models, transition planner,
formula typesetter/preparer, and v2 portable math codec.

The only existing runtime modules refactored are `private/animate-adapter.rkt`
(private scene-appending helper with preserved public defaults) and
`private/native.rkt` (explicit lazy module scopes). All other new functionality
lives in gallery examples/adapters and their tests. Old composite design and
validation evidence remain in `docs/composite-moves.md` and
`docs/validation-v0.4.0.md` respectively.

## Executed validation

The delivery environment used **Linux Racket CS v9.3.0.8**. It does not have the
installed parent Animate/Pict/SVG/dvisvgm stack used on the user's Mac.

| Executed command/check | Result |
| --- | --- |
| `racket math/run-tests.rkt` | **4,718 checks passed; 0 failed** |
| `racket math/run-gallery-tests.rkt` | **2,619 checks passed; 0 failed** (included in the total above) |
| `racket math/run-style-checks.rkt` | **1,279 checks passed; 0 failed** |
| `racket math/run-process-contracts.rkt` | **6 contracts passed**, using 12 independent Racket producer/consumer processes |
| Compilation of the new gallery, native-probe entry, file codec, and fixtures | Passed using `compiler/cm` / `managed-compile-zo` |
| Real CLI inspection/preflight | 13 independent CLI invocations; no output directory, preparation event, or typeset event on inspection/rejected requests |
| Original four lesson source comparison | All four byte-identical to v0.4.0 |

The mathematical, source-audit, and fresh-process checks were repeated from a
clean extraction of the delivered archive. The detailed test outputs are in
`docs/test-results.txt`, `docs/style-check-results.txt`, and
`docs/process-contract-results.txt`.

## What the tests establish

The registry has exactly 25 plates and 31 replays, with chapter counts 6/4/7/4/4.
Independent endpoint expectations check held arithmetic, cancellation, focused
rewrites, square roots, inequality reversal, and candidate checking. Every
ordinary derivation segment retains established evidence; the deliberately bad
candidate has a refuted candidate verdict rather than an invented equivalence.

Tests specifically cover the nonzero exclusion after `x/x`, the specialization
relationship of replacing one `x`, copy lineage in distribution, the one-way
squaring relationship, exhaustive parameter conclusions, and genuine shared-prefix
structure. Grouping/history comparisons reuse the same derivation object.

The review schedule has 565 dense sample records and 197 checkpoint-only records.
Every record is linked to an existing mathematical phase/checkpoint and lies within
its replay's global interval. Independent view offsets are exact.

All 31 views compile individually and as one gallery through the **synthetic native
contract model**. Each isolated view's complete clip/request representation matches
its corresponding interval in the assembled gallery after subtracting its time
offset. Visual and scalar IDs are cleaned between replays. Hierarchy indicators
mark existing step paths. The combined duration is exactly `2991/10` seconds in
that model.

Real-file tests check content-addressed payload stability, missing/altered byte
counts and digests, path containment, incompatible options and colors, worker
reconstruction with the preparer and typesetter explicitly forbidden, and
forwarding to the correct shared-project declaration/execution modules. Lazy and
native runtime dependency closures are explicitly requested from the existing
manifest builder.

The fresh-process suite covers the four original lessons plus the entire gallery
in both themes. Gallery producers write real verified replay files; independent
consumers rebind worker-local states and produce the same complete synthetic
scene signature without preparing or typesetting. These are **not** real Animate
frame-worker processes or pixel tests.

Real CLI subprocess tests verify listing, description, hierarchical steps, bad
selectors/counts/modes, incompatible output flags, and refusal to replace a
directory containing unrelated files. A sentinel file survives the rejected
replacement.

The existing v0.4 flat-versus-structured lesson tests also remain green. They check
all original elementary rewrite data, checkpoints, schedules, selected cases, and
synthetic native animation requests.

## What has not been executed here

**No actual native gallery PNGs or MP4s were rendered in this environment.**
Native fonts, SVG metrics, contact-sheet painting, real shared-process gallery
rendering/cache reuse, FFmpeg gallery output, and the Scribble build require the
user's installed parent dependencies. Passing the synthetic contracts is not
visual approval or a claim of those native results.

The optional `run-gallery-probes.rkt` runner performs real native random-access
pixel checks and writes review material. With `--process-check`, it additionally
requires direct/subprocess SHA-256 equality, multiple children completing work,
expected parent preparation accounting, and a zero-worker complete cache hit.
That runner was compiled here but was **not** passed off as executed native
validation.

Recommended local acceptance commands are in `docs/gallery.md`. Existing
`run-probes.rkt --compare-flat` remains available for the four original lessons.
Live `racket-cas`/Calcura, Rhombus, and the parent repository's whole release check
were not run for this gallery delivery. They are not prerequisites for the
catalogue's mathematical examples.
