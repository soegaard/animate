# Calculus validation record

This record separates implementation evidence from release approval. It is
updated with the calculus source so a passing headless suite is never mistaken
for native, process, or human-review evidence.

## Recorded environment

- Repository checkout: this workspace
- Required process-rendering toolchain: Racket 9.3.0.2
- Native still sizes exercised: 1280×720 and 1920×1080

## Executed evidence

| Layer | Command | Result |
| --- | --- | --- |
| Core declarations, mathematics, timeline, Guide fixtures, exports | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --core` | Passed |
| Native preparation/raster and review-bundle contract | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --native` | Passed. Includes counted opaque-provider regressions: a graph with no writable-parameter dependency is sampled during preparation and is not resampled while an unrelated point moves; a tighter native curve tolerance increases bounded preparation sampling; and a writable function-family parameter redraws its graph rather than reusing static geometry. A static Formula row's text/font assets remain stable across a neighboring moving graph while a Formula `value` leaf remains live. |
| Reconstructible project render | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --process --workers 10` | Passed: complete PNG parity between one in-process render and ten subprocess workers; reverse, sparse, repeated, cold, and warm requests agree with the all-frame oracle. A calculus-owned worker-boundary regression also verifies that invalid child source loading and scheduler cancellation publish no public frames, close worker resources, and allow an immediate retry in the same output directory. |
| Standalone calculus reference | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --docs` | Passed. Its standalone Scribble invocation reports only unresolved external Racket/Pict index links. |
| Strict integrated Animate manual | `/Applications/Racket\ v9.3.0.2/bin/racket tools/check-documentation.rkt` | Passed with no unresolved Animate-owned documentation tags. |
| Complete calculus gate | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/run-tests.rkt --all` | Passed. |
| Full sparse-review bundle | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/review-examples.rkt --all --profiles light,dark,textbook --workers 10 --clips --output NEW-DIRECTORY` | Produced 285 full-resolution stills, 24 paginated contact sheets, and 18 fixed-cadence MP4 clips across the three profiles, with local HTML index and manifest. Representative reading, secant/tangent, derivative, discontinuity, accumulation, and moving-reading states were inspected at full resolution, along with a mid-transition secant/tangent clip (H.264, 1280×720, 8 fps). |
| Full workload baseline | `/Applications/Racket\ v9.3.0.2/bin/racket calculus/benchmark.rkt --iterations 3 --profiles light,dark,textbook --width 1280 --height 720 --output NEW-BENCHMARK.rktd` | Passed after final cache work: 54 complete lesson/profile plans prepared, 162 headless snapshots sampled, and 54 native bitmaps forced. Median complete-set timings were 0.830 ms compilation, 23.290 ms preparation, 0.195 ms sampling, and 171.931 ms native rasterization. Raw repeat values are emitted in the report; no cross-machine speedup is claimed. |

## Outstanding release evidence

- The generated stills and clips are not a substitute for human approval of
  every required review state. Any resulting presentation fixes remain release
  work.
- The recorded workload baseline supplies counters and raw timing evidence,
  but it is not a cross-machine performance claim or an optimization comparison.
- The broad repository command `raco animate check-repo` was attempted. It
  completed with 19 failures across its 13,678-test phase, all in existing
  version/documentation-structure, 3D documentation, color-value, or Pict
  identity expectations. Its package-install phase then included unrelated
  archived/untracked slide and math directories whose source modules are
  intentionally incomplete. The calculus-focused suite and strict integrated
  manual above pass independently, and the packaged calculus public modules
  compile before those unrelated setup failures. A clean repository-wide
  release still requires the unrelated root failures and package-input hygiene
  to be resolved.
