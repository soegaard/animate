# 0.3.3 — cancellation separators and case handoff

- Preserve an additive separator when the same two adjacent surviving addends
  bracket it before and after cancellation. In particular, cancelling `+5-5`
  from `x^2+6x+5-5` now retains the `+` between `x^2` and `6x` throughout the
  retire/hold/compact choreography.
- Treat a replacement that atomically changes both operands of a root relation
  as one whole assertion. The relation glyph no longer remains alone between
  fade-out and fade-in (for example during the `single-root` quadratic case).
- At the first group of a parameter case, keep the case checkpoint as history
  and fade its working copy in directly at the destination row. This removes
  the transient bold/overlapped duplicate created by copy-then-move. Root
  non-case lessons retain their visible copy-and-move behavior.
- Suppress no-op native move requests for history rows whose position did not
  change.
- Added regressions for surviving additive separators, whole-relation atomic
  replacement, and destination-position case-start copies.
- Executed locally with Racket 9.3.0.8 [CS]: 1,815 core/property/contract checks
  and 986 house-style/reference checks, all passing. The actual macOS
  animate+dvisvgm rerender remains the pixel-level validation.

# 0.3.2 — transition safety after second dark-video review

- Changed square-root branch copies from visible source-to-branch motion to
  destination-position appearance. The semantic copy trace is retained, but the
  native adapter no longer sends the duplicated bases through intersecting paths.
- The split sequence now retires the old working line, reveals shared branch
  material at its final locations, then reveals the complete radical/relation
  material.
- Changed `reorder-addends` presentation to a conservative whole-focus
  replacement for each affected additive expression. Surrounding equation,
  fraction bar and denominator material remain independently preserved.
- Removed the old signed-term lane planner from the native lowering path; term
  permutation remains present in the mathematical trace but is not visualized as
  glyph motion until a collision-free term-motion planner exists.
- Added regressions proving that split-copy phases emit no move requests and that
  no token inside a reordered additive focus participates in a movement match.
- Executed locally with Racket 9.3.0.8 [CS]: 1,803 core/property/contract checks
  and 982 house-style/reference checks, all passing. The actual animate/dvisvgm
  rerender remains the final pixel-level validation.

# 0.3.1 — compiled-cache upgrade fix

- No mathematical or choreography semantics changed from 0.3.0.
- Documented that an in-place upgrade can leave newer `compiled/*.zo` files
  shadowing the replacement source files. Remove the old `math/` directory or
  recursively remove `compiled/` directories before testing a new drop-in tree.
- Added a source-vs-loaded-export guard to `run-style-checks.rkt`. When Racket
  loads stale bytecode, the audit now reports the likely compiled-cache problem
  and the exact cleanup command instead of only reporting a reference-index diff.
- Reissued the full `math/` tree so source timestamps and public facades are
  mutually consistent (`explain-math`, `plan-segment-shared?`, and
  `presentation-phase-annotation` are present in `main.rkt`).

# 0.3.0 — Semantic choreography after dark-video review

- Added a pure typed-transition planner driven by mathematical occurrence links,
  with explicit incoming/outgoing partitions and rigid copy/reorder units.
- Made evaluation and opaque rewrites whole-focus replacements with a strict
  outgoing/incoming visibility barrier; no partial new result beside old arithmetic.
- Removed SVG crop-size equality from identity matching. Preserved expressions
  no longer disappear merely because rasterized crop padding differs.
- Kept cancellation survivors stationary until compaction, and copied shared
  bases before revealing complete square-root branch right sides.
- Attached minus signs to reordered terms, including negative numeric literals,
  and used separated native motion lanes instead of independent glyph swapping.
- Added optional shared-prefix case presentation. The general quadratic now
  completes the square once and lasts 54.9 seconds with all six cases retained.
- Simplified headers without dropping restrictions from mathematical evidence.
- Added the held `explain-math` inset phase and motivated adding nine in the
  concrete quadratic. Insets are prepared once and do not advance checkpoints.
- Added dense dark native probes for every example, with active-phase manifest
  metadata and an optional checkpoint-only mode.
- Added defining reference entries for three new bindings, expanded TeX coverage,
  and preserved all four mathematical checkpoint trees exactly.
- Executed: 1,765 core/property/contract checks, 981 source/reference checks,
  and 70 real-TeX marked/unmarked PNG comparisons, all passing.
- Actual native rendering and revised MP4s remain unexecuted in this delivery
  environment; the contract model is not represented as the installed renderer.

# 0.2.0 — House-style revision

- Separated the pure `animate/math` facade from native rendering and CAS execution.
- Added explicit public exports, hidden invariant-bypassing internal constructors,
  and introduced guarded service, source-range and prepared-layout records.
- Renamed effectful entry points with `!` and migrated examples and current docs.
- Snapshotted substitution maps and verification metadata; rejected cyclic or
  opaque evidence resources and excluded raw backend handles from proof reports.
- Validated callback arities, proposition identity, scope flags, branch factories,
  selectors and choreography options at their boundaries.
- Replaced inexact default timing with rational values and made traversal,
  diagnostic, rule-check and native layer ordering explicit.
- Removed the native loader's global mutable cache and split prepared model,
  token layout, TeX preparation and native step compilation responsibilities.
- Preserved the keyword camera fix, strengthened the native contract test, added
  explicit renderer forwarding and preserved captured prepared themes.
- Distinguished invalid CAS callback results from timeouts and rejected decisions
  attached to failed query statuses.
- Added module/definition/field documentation, a defining Scribble reference for
  272 public bindings, a Rhombus example and a separate source/reference audit.
- Validation: 1,317 core/property/contract checks; 927 source/reference checks;
  59 real-TeX marker comparisons. Native/live-CAS/Scribble/Rhombus integrations
  remain unexecuted in the delivery environment; see `docs/validation.md`.

# 0.1.1 — 2026-09-13

Native integration compatibility fix.

- Updated every `scene-state->pict` call to pass the camera with the current
  `#:camera` keyword instead of the obsolete second positional argument.
- Updated the opt-in native integration probe and user-guide sampling example
  to the same API contract.
- Core/property regression suite remains 1,243 checks.

# 0.1.0 — 2026-09-13

Initial drop-in mathematical-animation implementation.

- Held scalar S-expressions, immutable contexts and occurrence sidecars.
- Explicit guarded operations, derivations and nested parameter cases.
- Exact local checking; unknown and refuted evidence are not treated as true.
- Source-domain preservation and original-problem candidate checks.
- Structural template rules with explicit copy/merge lineage.
- Presentation groups, anchored equations, retained-line copying, staged
  fade/hold/compact choreography, and a bounded visible-history window.
- Full-formula TeX/SVG semantic markers and content-addressed SVG assets.
- Native animate scene compilation with scalar checkpoint-index metadata.
- Programmatic inspection, optional bounded CAS adapters, and four examples.
- Base-only tests, a native-contract model, independent coefficient-grid tests,
  complete-formula TeX regression, and an opt-in actual native visual runner.

Compared with the design document, this implementation deliberately makes some
boundaries explicit: target rewrites are checked focused replacements rather
than automatically reconstructed elementary proofs; repeated case prefixes
are replayed rather than displayed in a decision-tree layout; logical alternatives
are shown with `or` rather than automatic plus/minus compaction; merge traces
have no dedicated many-to-one path morph; inspection is data/API, not a new GUI.
Full calculus/binder handling and automatic pedagogical solving remain outside
the stated initial real-algebra scope.
