# Validation and local test procedure

## What was and was not executed

A Racket/raco executable was not available in the build environment. Therefore:

- **Racket compilation was not executed.**
- **The RackUnit suite was not executed.**
- **Native PNG/MP4 rendering and visual inspection were not executed.**

Do not interpret the presence of test files, source review, or a structural audit
as a report that those runtime tests passed.

The checks actually performed on the delivered source were delimiter balancing,
structural inspection of module and test forms, local relative-import existence,
and review of the native API signatures against the pinned repository source.
`static-audit.json` records the structural/import audit. It is not Racket's reader
or expander and cannot establish that a binding is available in every phase.

## Included RackUnit coverage

There are **74 test cases** across seven test files, containing multiple
assertions per case:

| File | Cases | Coverage |
|---|---:|---|
| `math-test.rkt` | 10 | Euclidean constructions, intersections, transforms, tangency, empty/overlapping loci, selectors, clipping. |
| `dsl-test.rkt` | 19 | Checked graph, type/arity/reference errors, free/derived distinction, typed helpers, hygiene, multi-results, expansion, cardinality and preconditions. |
| `layout-test.rkt` | 9 | Three classical constructions, deterministic choices, overrides, pins, fixed views, semantic fitting rather than full-circle bounds. |
| `theme-test.rkt` | 9 | Units, family/state composition, exact overrides, nested stroke rules, inheritance, paint channels, invalid properties. |
| `timeline-test.rkt` | 14 | Initial state, labels, no label flash, persistent state, transient highlights, seeking, no-ops, helper narration. |
| `drawing-test.rkt` | 5 | Dash runs, clipping, deterministic labels, explicit label placement, helper display names. |
| `animate-test.rkt` | 8 | Native tokens, exact colors, scene clock, arbitrary-time sampling, cosmetic widths, aspect checks, all distributed examples, PNG/subtitle/still-index output. |

The native integration tests use temporary output directories and clean them
up. They do not invoke FFmpeg or construct TeX formulas. They still require the
ordinary dependencies of the containing `animate` checkout.

## Run locally from the repository root

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Compile the public modules and all examples.
"$RACKET" -l raco/main -- make \
  geometry/main.rkt geometry/render.rkt \
  geometry/examples/equilateral-triangle.rkt \
  geometry/examples/perpendicular-bisector.rkt \
  geometry/examples/perpendicular-through-point.rkt \
  geometry/examples/gallery.rkt

# Instantiate and exercise all geometry test modules.
"$RACKET" geometry/run-tests.rkt

# Render the step-by-step visual probes.
"$RACKET" geometry/examples/equilateral-triangle.rkt
"$RACKET" geometry/examples/perpendicular-bisector.rkt
"$RACKET" geometry/examples/perpendicular-through-point.rkt
"$RACKET" geometry/examples/gallery.rkt
```

For just the pure layer:

```sh
racket geometry/run-tests.rkt --core
```

Equivalent direct full-suite invocation:

```sh
raco test geometry/tests
```

No changes to the outer project's test runner are required. These are additional
geometry tests, not a claim to replace or rerun the existing `animate` suite.

## Visual review targets

Check that circles reveal smoothly from their through-points; mathematical lines
extend to the view boundary; important intersection points stay inside the view;
labels remain stable and readable; same-step hidden labels do not flash; helper
circles become subdued/dashed rather than disappearing; and highlighting returns
to the prior style. The gallery should exercise every drawable type and built-in marker. The bisector example should visibly expand the typed helper,
while hidden helper details in collapsed calls should remain absent.

Compare selected frames in both chronological and reverse order through the
native sampling API. The included integration test exercises repeated sampling
at the same time after other times have been visited.

The layout and label-placement algorithms are intentionally heuristic. Adjust a
`layout` pin, a realization override, the explicit view, or `#:labels` when a
particular diagram needs authorial placement.


The example runner now uses process-based sharding for full-frame rendering when `--workers` is greater than 1.
