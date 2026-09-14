# Validation report — 0.3.3

## 0.3.3 cancellation and case-handoff revision

This revision addresses two defects found in the 0.3.2 dark-video rerender:
the surviving `+` disappearing while cancelling `+5-5` in the concrete
quadratic, and overlapped duplicate formulas at the start of parameter cases.
It also makes whole-relation replacements atomic so no bare relation glyph is
left between old and new assertions. Mathematical derivations, checkpoints,
case structure and default durations are unchanged.

Runtime: **Racket 9.3.0.8 [CS]**, Linux, base-only installation.
Baseline: the supplied **0.2.0 house-style archive**. All native integration
interfaces remain those of `soegaard/animate@4fd00a9310d925669a95edb1b197c4bfe1e21998`.
No parent repository file was modified.

## Executed checks

| Check | Result |
|---|---|
| `racket math/run-tests.rkt` | **1,815 passed; 0 failed** |
| `racket math/run-style-checks.rkt` | **986 passed; 0 failed** |
| Mathematical checkpoint-tree comparison of all four solutions against 0.2.0 | **All identical**, including shared prefixes, branch guards and terminal results |
| All four example `--steps` entry points | **Passed** |
| General quadratic `--list-cases` | **Six terminal cases**, no artificial common-prefix case |
| General quadratic `--case quadratic/two-real-roots --steps` | **Complete original-equation prefix restored** |
| `racket math/tests/tex-layout-probe.rkt <directory>` | **70 byte-identical PNG pairs; 0 failed** |
| Native probe module load and `math/run-probes.rkt --help` | **Passed**, without claiming native rendering execution |

The mandatory suite retains exact algebra, domain guards, source exclusions,
occurrence identity, template rules, case coverage, candidate checking, CAS
service/transport/failure contracts, and independent grids of **125 linear**
and **175 quadratic** coefficient triples. Those tests check mathematical
behavior, not video aesthetics or formal proof completeness.

## Transition regressions

The new `tests/choreography-test.rkt` uses explicit deterministic geometry and
the native API contract model. Its fixture includes fraction bars, radicals,
signs, and deliberately different source/destination crop metrics.

It checks complete token accounting, unaffected right-hand-side preservation,
atomic numeric evaluation, source/result visibility barriers sampled inside
all replacement subclips, square-root copy provenance, destination-position copy appearance, whole-radical introduction,
atomic reorder-focus replacement, invalid choreography rejection, common-prefix presentation,
standalone case reconstruction, header filtering with genuine exclusions retained,
and explanation checkpoint stability/cleanup.

**These are native-interface contract tests, not the installed animate renderer.**
They record and sample ordinary requested movements and opacity operations and
would reject the old overlap choreography. They also reject any `move` request for branch-copy appearance, any token match inside an atomic reorder focus, retirement/recreation of a surviving additive separator, a bare root relation during two-sided replacement, and case-start copy movement. They do not establish exact native pixel placement or correctness
of dvisvgm extraction.

## Actual TeX execution

Real `latex` and `dvipng` executables rendered **140 TeX pages**: **70 complete
formulas**, each once unmarked and once with the semantic DVI/SVG markers.
Every PNG pair is byte-identical. The corpus includes the lesson checkpoints,
new completing-square inset, negative constants/sign forms, signed zero, and
fraction/radical/nested-power bases. This establishes marker-neutral typesetting
for the tested corpus in this environment; it is not a dvisvgm test.

## House style and public reference

The source audit checks declared headers, contract comments, immediate field
documentation, pure dependency closure, explicit public exports and defining
Scribble/index coverage. All **275 public bindings** are covered. This audit is
not a completed Scribble build, nor 986 mathematical proofs.

The new transition planner is pure. Typesetting, native view preparation and
external queries remain confined to their existing adapters. HOUSE_STYLE
reference: Git blob `8b5acb39ca016d523889bba38296e34dd665971b`.

Raw logs are retained in `test-results.txt`, `style-check-results.txt`,
`tex-test-results.txt`, and `checkpoint-comparison.txt` in this directory.

## Not executed here

**Actual animate + dvisvgm rendering and MP4 encoding.** The environment lacks
both dvisvgm and the installed animate dependency graph. The revised native
runner is implemented and its Racket module loads, but no real native probe
success is claimed. macOS fonts, actual SVG crops, native concurrent rendering,
final pixels and pacing still need the user's rerender.

**Live racket-cas and Calcura.** Existing injected transport and service tests
passed; no live backend query was executed or required by these four lessons.

**Scribble build, Rhombus example and repository-wide raco make.** Their source
and public reference coverage were audited. The base-only runtime lacks the
corresponding tools/packages, so those operations are not reported as executed.

## Commands in the checkout

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-probes.rkt --dark math-output/review-v0.3/probes
```

The last command renders actual dark PNGs from all four examples at checkpoints
and dense transition samples, tests seek-away/seek-back pixel equality, and
writes `manifest.json`. Missing native prerequisites fail explicitly. See
`video-review-revision.md` for the full ten-worker dark rerender command.

No runtime binaries, generated renders, platform fonts, or external assets are
bundled in the source archive.
