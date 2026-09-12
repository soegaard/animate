# Testing — v0.9.1

The v0.9.1 review refinements were exercised with the same genuine minimal Racket CS runtime used for v0.9.0. The five base-only suites pass: **69 transformation/label groups / 1,017 checks**, **68 standard-library groups / 2,552 checks**, **53 audit groups / 3,183 checks**, **26 refinement groups / 387 checks**, and **65 review groups / 227,055 checks**. The actual reader accepts all 79 source modules. Native font/PNG integration tests are included but cannot run in this minimal runtime.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --transform-labels
"$RACKET" geometry/run-tests.rkt
```

The `--transform-labels`, `--library`, `--audit`, `--refinements`, and `--review`
options run their real base-only check modules. `--core` runs RackUnit tests but
excludes native rendering modules. With no option, the runner includes all
registered core and native integration tests. Flags are mutually exclusive.

Current v0.9.1 base-only results are summarized in `CHANGES-0.9.1.md`. The v0.9.0 `v090-*-results.txt` files and earlier visual audit records below are retained as release history, not current native-render claims.

---

## Historical validation records

# Validation — v0.8.1 example audit

## Executed here

A real minimal **Racket CS 9.3.0.8** runtime was used. These are tests of the
shipped geometry, compiler, timeline, annotation planner, and review planner, not
an alternate geometry implementation:

| Command | Result |
|---|---|
| `racket geometry/run-tests.rkt --audit` | **49 groups, 3,053 checks passed** |
| `racket geometry/run-tests.rkt --library` | **68 groups, 2,484 checks passed** |
| `racket geometry/run-tests.rkt --review` | **60 groups, 215,848 checks passed** |

The audit checks exercise nested caption substitution and public display names;
invalid caption references; full-circle fit hints; radius-only circle anchors;
ray-based angle identity; one-arc α notation; the visible source chord and its
interior compass opening; helper-local name disambiguation; all three incircle
and orthocenter right-angle markers; the two offset-parallel right angles;
hexagon radius comparison; one/two/three gallery arc groups; angle-label sectors;
and every authored review step/final annotation in all 17 examples in both themes.

The library suite retains its independent mathematical oracles, transformed
inputs, invalid contracts, eight helper signatures, auxiliary ownership,
determinism, and all thirteen applications. The review suite covers exact
boundary states, nested steps, three samples per row, file safety, replacement,
rollback, and ZIP membership. Its file-output tests use a small PNG fixture;
passing those tests does not claim native image rendering.

Results are in `audit-check-results.txt`, `library-check-results.txt`, and
`review-check-results.txt`. Reader/import/archive checks are recorded in
`static-audit.json`. `estimated-layout-audit.json` lists the conservative pure
annotation results and remaining warnings. Actual native font metrics can differ.

## Visual material inspected

The uploaded archive contained 34 example/theme bundles, 564 step rows, 1,692
step PNGs, and 110 contact sheets. Every contact-sheet page in both themes was
inspected, and selected ambiguous details were inspected at full resolution.
These are **before-fix images supplied by the user**, not images rendered from
the revised source. The audit did not separately open every one of the 1,692 PNGs
at full resolution, and three samples per step cannot establish every property
of continuous motion.

## Not executed here

The minimal runtime lacks RackUnit and the full native Animate/Pict/Draw
dependency set. Consequently the full registered RackUnit suite, the post-fix
native font/bitmap/PNG/contact-sheet tests, and macOS video renders have **not**
been executed here. No new screenshot is claimed as pixel-level proof.

`tests/audit-render-test.rkt` adds real measured-font α-sector checks and native
bitmap endings for copy-angle, tangent-at-point, circumcenter, and orthocenter in
both themes. Existing native integration and review tests remain registered.
`tests/audit-test.rkt` registers the base audit groups with RackUnit.

## Run locally

From the Animate repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --audit
"$RACKET" geometry/run-tests.rkt
```

The normal command runs all registered core and native test modules with the
same Racket executable and preserves the nonzero status on failure. `--core`
requires RackUnit but omits native modules. `--library`, `--review`, and `--audit`
are separate base-only modes.

Regenerate a focused review, then the full set after the tests pass:

```sh
"$RACKET" geometry/review-examples.rkt --example copy-angle --dark
"$RACKET" geometry/review-examples.rkt --all --both --output geometry-review-v081
```

Check the native follow-up items in `EXAMPLE-AUDIT.md`, especially transient
helper-label/curve intersections. Estimated annotation costs are a finite
heuristic, not a guarantee of collision-free raster output.


## v0.8.3 example-refinement regression checks

`racket geometry/run-tests.rkt --refinements` executes
`tests/example-refinement-checks.rkt` with only Racket base. All 26 groups and 387
checks passed on Racket CS 9.3.0.8. They enforce clearly scalene/acute example
inputs, left-side angle copying, close division labels, helper-label/caption
agreement, supporting-line draw order, a distinct hexagon circle family and
relative label-pin typing/precedence/alias propagation.

The full RackUnit run includes the wrapper `example-refinement-test.rkt` and six
native cases in `example-refinement-render-test.rkt`. The native cases are not
claimed as executed in the build environment. Existing library/audit/review
base-only suites were rerun successfully; their current results are recorded
alongside `example-refinement-check-results.txt` and `reader-check-results.txt`.
