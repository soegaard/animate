# Validation — v0.9.0 transformations and semantic labels

## Executed

The shipped mathematical/compiler/timeline/annotation/review code was executed
using a genuine minimal **Racket CS 9.3.0.8** runtime. These are not results from
substitute geometry implementations or renderer mocks.

| Command | Groups | Checks | Outcome |
|---|---:|---:|---|
| `racket geometry/run-tests.rkt --transform-labels` | 67 | 1,167 | Passed |
| `racket geometry/run-tests.rkt --library` | 68 | 2,552 | Passed |
| `racket geometry/run-tests.rkt --audit` | 53 | 3,391 | Passed |
| `racket geometry/run-tests.rkt --refinements` | 26 | 387 | Passed |
| `racket geometry/run-tests.rkt --review` | 64 | 272,122 | Passed |

The counts are assertion executions, including loops over frames, examples and
themes, not a claim of that many independent test scenarios. Each command's
complete output is in the corresponding `v090-*-results.txt` file.

All **79 Racket source modules** passed Racket's actual reader. The review
launcher's `--list` produced **19 names**, including the two new examples. Both
manual copies are identical. A source comparison against the v0.8.3 archive
confirmed that the old application sources, foundations library, static-frame
rendering module, and process example runner are unchanged. Gallery, shared
geometry integration modules and the review registry were intentionally updated.

## What the new checks cover

Independent reflection/projection and rotation oracles; mathematical composition
order; inverses and round trips across translated/rotated/reflected/scaled inputs;
negative dilation; preservation of types, distances, incidence and minor-angle
measure; signed sweep reversal; semantic mapping of current relations/markers;
source immutability; errors for singular maps and unsupported targets.

DSL arity/type/option checks; nondrawable Transform/Vector/Text values; typed
multi-result helpers returning image geometry and a Label; helper alias and
layout-hint propagation; symbolic and measured labels; fixed decimals and unit
suffixes; visibility independent of the target; pins, offsets, fractions and
angle sectors; optional arcs; new theme inheritance; view anchors; review
triplets and deterministic out-of-order sampling.

The new transformations/semantic-label examples and updated gallery were
realized and annotation-planned in both themes. The **estimated** annotation pass
reports no conflicts in those demonstrations. That is not a guarantee that native
font metrics or every possible user-authored diagram will be collision-free.

Existing suites were rerun because the shared type system, drawable lists,
annotation ordering and helper remapping changed. Higher review/library counts
reflect the larger gallery and two additional reviewable examples.

## Not executed

This runtime lacks RackUnit and the complete native Animate/Pict/Draw dependency
set. The full registered RackUnit suite, native text measurement, native bitmap
and PNG rendering, and macOS ten-process video output were **not executed here**.
No native screenshot or video is claimed as validation of this release.

`tests/transform-label-test.rkt` exposes the same base-only groups to RackUnit.
`tests/transform-label-render-test.rkt` supplies genuine native integration
checks for measured annotation plans, stable native Visual sampling, text and
arc children, and PNG dimensions/signatures in both themes. Those tests use the
real Animate APIs, not a replacement backend. They are registered in the normal
full test command.

## Local validation and focused reviews

From the Animate repository root after replacing `geometry/`:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/run-tests.rkt &&
for example in transformations semantic-labels gallery
do
  "$RACKET" geometry/review-examples.rkt \
    --example "$example" --both --output geometry-review-v090 || break
done
```

This creates one review ZIP per example/theme. Begin with the two short new
examples; the gallery includes all previous plates as well. Check upright
text, angle sectors, symbolic-to-numeric label changes, captions, new image
reveals and preservation of the source figure. The examples do not animate
an object moving through a geometric transformation.
