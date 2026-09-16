# animate/slides changes

## 0.4.0 — semantic gallery and geometry workers

- Add recursive named-part matching and witnessed math, geometry, and native
  Scene continuity for `match` transitions, with conservative fallback modes.
- Add the 42-entry public gallery catalogue, selectable HTML/poster/filmstrip
  reviews, and optional MP4s through the existing project executor.
- Add parent-prepared, versioned geometry render data so ordinary project
  workers reconstruct sampling without rerunning construction realization or
  annotation layout.
- Racket 9.3.0.2 passes all 105 named cases across 16 suite files, including a
  real two-worker geometry MP4 and mixed math/geometry subprocess coverage.

## 0.2.1 — project artifact report hotfix

- Treat `project-execution-report-artifact-paths` as the documented semantic
  hash. Gallery MP4 export now takes the encoded movie from `'primary` instead
  of attempting to iterate the report as a list.
- Fix the same stale assumption in `slides/render-example.rkt`; its output paths
  are flattened deterministically from `primary`, `frame-sequence`, and `frames`.
- Add a core regression for the artifact-report shape. The supplied suite now
  contains 64 named cases; Racket execution remains to be run on the target.

## 0.2.0 — gallery and transitions

- Add the 38-entry `animate/slides/gallery` catalogue, selective construction,
  a browsable HTML/poster/filmstrip gallery, optional MP4s through the ordinary
  project executor, reusable source modules, and a compact transition tour.
- Add directional push, wipe, cover, and uncover; centered zoom-crossfade;
  and fade-through-color. Carry backgrounds, decorations, crops, and local
  content times through the same shared frame representation.
- Add portable easing, strict option validation, public transition queries,
  and same-duration reduced-motion fallbacks.
- Preserve new transition configuration in version-two worker preparation
  payloads. Add codec and real subprocess regression cases.
- Add finite preferred intrinsic viewport aspects for math/geometry content,
  supporting the mixed portrait gallery without unbounded sizing preparation.
- Extend the existing test and visual-review runners. The initial v0.2 delivery
  supplied 63 named cases; later integrated validation is recorded under v0.4.0.

## 0.1.4

Integrated baseline: exact-cut clock canonicalization, compact portrait columns,
centered equation/annotation composition, 36 named cases, and the reviewed
158-comparison visual corpus. See the historical validation report for its evidence.
