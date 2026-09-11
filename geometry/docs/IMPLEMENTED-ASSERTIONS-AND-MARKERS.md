# Implemented next steps: relations/assertions and richer markers

This delivery implements two follow-up improvements to `geometry`:

1. **First-class relation expressions plus `assert`**
   - Added relation expressions:
     - `(perpendicular ...)`
     - `(parallel ...)`
     - `(equal-length ...)`
     - `(equal-angle ...)`
     - `(collinear ...)`
     - `(midpoint-of point segment)`
   - Added top-level `(assert ...)` clauses.
   - `require` remains a pre-realization constraint; `assert` is checked after the whole realization is built.
   - Assertions may be either ordinary Boolean expressions or relation expressions.
   - Helper bodies can now contribute assertions, and these are remapped correctly when helpers are inlined.

2. **Richer built-in diagram markers**
   - Added marker rendering for:
     - `(marker (parallel ...))` using parallel-arrow glyphs.
     - `(marker (midpoint-of ...))` using equal-subsegment ticks.
   - Existing angle, equal-length, equal-angle, and perpendicular markers continue to work.

Also updated:
- compiler/type-checking support,
- realization checks,
- example constructions,
- and RackUnit coverage.
