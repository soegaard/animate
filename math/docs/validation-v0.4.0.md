# Validation — animate/math 0.4.0

## Baseline and scope

The baseline is `soegaard/animate` commit
`525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`, with mathematical subtree Git tree
`28cc6aa392806c9859bc9d62a6d93735dfe47e7b`. The downloaded/reconstructed baseline
was verified against that exact recursive Git-tree identity before editing.
It includes the completed process-rendering update and stable SVG definition
ordering; this is not based on an earlier standalone 0.3.x zip alone.

The archive contains only `math/`. It contains no parent repository edits,
compiled bytecode, worker output, formula caches, or rendered movies.

## Executed checks

The delivery environment used **Linux Racket CS v9.3.0.8**, not the user's macOS
Racket v9.3.0.2 installation. Its native Animate dependency stack is unavailable.
The following are actual results, not proposed acceptance criteria:

| Check | Result |
| --- | --- |
| `racket math/run-tests.rkt` | **2,099 checks passed; 0 failed** |
| `racket math/run-style-checks.rkt` | **1,131 checks passed; 0 failed** |
| `racket math/run-process-contracts.rkt` | **4 fresh-process contracts passed**, using eight real Racket producer/consumer processes and synthetic native geometry |
| CLI tree/checkpoint/case inspection | Completed without native project loading, TeX, or output-directory creation |

The same mathematical/source tests and fresh-process contracts are run again
from a clean extraction of the actual delivered zip.

## What the comparisons establish

`tests/fixtures/flat-*.rkt` freeze the original four lesson declarations from the
pinned baseline. They import only the mathematical API and are test references,
not an alternate production rendering path.

The new tests compare every lesson and every selectable terminal case against
those declarations. They establish equality of:

* Elementary `rewrite-step?` records, including before/after states, contexts,
  evidence, bindings, paths, occurrence lineage, and trace.
* Every elementary checkpoint and its commit time.
* Phase kinds, durations, group indices, explanations, and ordering after
  removing only the new address prefix for comparison.
* The complete synthetic native scene/clip/request representation produced by
  the adapter, not merely the final equation.

The preserved lesson durations are 10.8, 18.0, 17.6, and 51.9 seconds. Composite
nodes do not create extra checkpoints or animation time.

Additional tests cover nested reusable recipes, procedural construction,
nonempty/duplicate/invalid entry rejection, repeated child names under distinct
moves, exact and ambiguous addresses, extension without mutation, guard
inheritance, strict/draft evidence, conservative relationship summaries,
explicit group expansion and partition errors, shared-prefix grouping,
case-specific override priority, and selected-case restoration.

## Portable preparation and fresh processes

The portable schema is `animate-math-prepared-plan-v2`. Existing corruption tests
remain, and new tests cover structured plans and their original explanations.

`run-process-contracts.rkt` runs one producer and a separate consumer process for
each lesson. The producer serializes the real portable prepared-plan format using
synthetic measured layouts. The consumer reloads the actual lesson module,
reconstructs worker-local mathematical states, validates/rebinds the payload,
and compiles the scene contract. Its preparation observer and typesetter are
configured to fail immediately if called. Every reconstructed scene contract
matches the producer's canonical representation.

This proves fresh-process data/identity reconstruction for the fixture. It does
**not** claim to exercise actual Animate subprocess PNG workers, TeX, SVG
rasterization, GPU rendering, or MP4 encoding.

## Not executed here

Actual native pixel probes and multi-worker movie rendering require the user's
installed Animate/LaTeX/dvisvgm environment. Native raster tests, the parent
repository's root/process-rendering suites, live CAS integrations, and a complete
Scribble documentation build were **not executed** in this delivery environment.
Defining public-reference coverage and Racket source syntax were audited; that
is not a substituted documentation-build claim.

The optional native parity mode is implemented for the configured checkout:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make math/main.rkt math/render.rkt math/cas.rkt math/examples/*.rkt
"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-process-contracts.rkt
"$RACKET" math/run-probes.rkt --dark --compare-flat math-output/moves-v0.4/probes
```

The last command uses actual installed native snapshots. It compares the current
structured and frozen flat lessons at all ordinary checkpoint/dense intermediate
probe times, including arithmetic replacement barriers, and writes the standard
PNG/JSON probe set. A pixel mismatch is a failed check, not merely a warning.

After those probes, the usual four-example render loop in `README.md` exercises
the retained shared process renderer. No performance or native-pixel result is
claimed for this revision before that real run.
