# Geometry authoring layer — changes in v0.9.5.1

This patch synchronizes the regression/audit suite with the v0.9.4/v0.9.5
compass reveal and mixed review-row semantics. It does not change the intended
visual behavior introduced in v0.9.5.

## Test coherence fixes

- `theme-test.rkt` now expects the current `compass-guide` defaults:
  stroke width `2`, dash pattern `(4 2)`, opacity `1`.
- `reveal-test.rkt` now samples the four-phase compass reveal at the actual
  transport-ready and half-sweep reveal positions (`0.335`, `0.45`, `0.725`).
- `compass-checks.rkt` no longer asks for circle strokes before the sweep begins,
  and its half-sweep check targets reveal progress `0.725`.
- `audit-checks.rkt` now validates either the ordinary
  `read/during/settled` sequence or the compass-specific
  `read/measure/transport/sweep/settled` sequence instead of requiring every
  row to be a triplet.

## Documentation / manifest

- Testing and audit documentation now describes mixed 3/5-sample review rows.
- Review manifests record geometry version `0.9.5.1`.
