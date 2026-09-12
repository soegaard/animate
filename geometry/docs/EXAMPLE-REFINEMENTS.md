# Example refinements — v0.8.3

These changes address the user's example-by-example notes from 2026-09-12.
They extend the delivered v0.8.2.2 package; static-frame reuse, its two syntax
fixes, the `racket/path` import fix, review bundles and process rendering remain.

## Changes to the eleven named examples

| Example | Change |
|---|---|
| Circumcenter | Moved C to make a clearly scalene acute triangle. The circumcenter is no longer visually close to the equilateral special case. |
| Copy angle | The copy lies to the **left** of the target ray, matching C's side of directed BA. The step caption and side assertion agree. The reusable helper still supports both sides. |
| Copy triangle by SAS | Uses a distinctly scalene source triangle. Its copy still preserves both side lengths, the included angle and the resulting third side. |
| Divide a segment into five | P₁ through P₅ are placed at a fixed, nearby offset from their own points, on the left and slightly below. Point size, label font size, and subscript text are unchanged. |
| Incircle | Uses a distinctly scalene acute triangle; the three contact points, perpendicular radii and equal-radius checks remain. |
| Orthocenter | Uses a distinctly scalene acute triangle, keeping the three feet on the sides and H inside. H's label is placed clear of the altitude strokes. |
| Parallel at a distance | Its expanded perpendicular helper uses Q, R, S, while P remains the constructed endpoint in the application. No X/Y helper label remains in this example. |
| Regular hexagon | The primary circumcircle k has the **purple** family. The auxiliary circles retain **aqua**. This distinction follows both light/dark palettes. |
| Square on a segment | AB stays gold while the supporting line is shown and animated. The line is still drawn in its own color outside AB; it no longer paints over the finite segment. |
| Tangent at a point | The perpendicular helper now uses Q, R, S, not X. The given O/P labels are unchanged. |
| Triangle midline | Uses a distinctly scalene acute triangle. Both midpoint constructions, equal-half markers and the parallel/half-length conclusion remain valid. |

## General-position triangles

The apex coordinates were changed, not the algorithms. The five examples remain
acute rather than silently becoming right or obtuse cases. Their measured angles
(in degrees at A, B, C) are:

| Example | A | B | C |
|---|---:|---:|---:|
| Circumcenter | 60.1 | 37.6 | 82.3 |
| Copy triangle SAS | 60.9 | 39.3 | 79.8 |
| Incircle | 60.4 | 37.3 | 82.3 |
| Orthocenter | 60.3 | 41.2 | 78.6 |
| Triangle midline | 61.6 | 37.6 | 80.8 |

Regression checks require the longest side to exceed 1.45 times the shortest,
each pair of adjacent sorted side lengths to differ by more than 10% of the
longest side, and the largest/smallest angle to differ by more than 35 degrees.
These are example-quality tests, not restrictions imposed on the library.

## Nearby labels without guessing absolute coordinates

A new layout hint pins a point's label relative to that point:

```racket
(layout
  (label-offset P1 (point -0.54 -0.08)))
```

The vector is a fixed local-world offset from the realized point to the label
centre. It does not alter the point, font size, or point marker. Unlike a weak
`label-side` preference, the planner cannot push it farther away to escape an
auxiliary line. Absolute `label-at` positions and adapter `#:labels` overrides
have higher precedence. Only named Points accept this hint; finite literal
coordinates are required. Offscreen or colliding pinned labels still produce
layout warnings rather than being silently moved.

The five division labels all use the offset above. Their label-centre distance
from the point is about 0.546 world units, with each label closer to its own Pᵢ
than to any other Pⱼ. In the conservative estimated-font pass, no division
label intersects a point, the auxiliary ray, or a parallel. One short-lived
compass circle can still intersect P₁'s conservative text box; native font/PNG
review remains relevant.

Helper-local annotation hints now follow the public result aliases, just as
styles and reveal hints already do. Caller hints still take precedence. This
also fixes an existing alias-mapping omission for the other annotation hints.

## Drawing order and color preservation

The fixed rendering order is now:

```text
lines and rays
segments and circles
markers
points
```

Within each group, source order is preserved. This puts construction lines and
rays behind finite edges even when introduced later in an expanded helper. It
fixes the square's gold AB without hiding its support, recoloring the whole
infinite line, or changing the step timing. The layer order is prepared once,
not recomputed according to which frame happened to be rendered previously.

## Helper names and captions

The standard perpendicular-bisector uses P/Q for its intersections; the erected
perpendicular uses Q/R/S; the target intersections in the angle-copy helper use
P/Q. Hygienic names remain unique, and structured captions resolve to the same
names used by the labels. Literal public names such as the X₁...X₄ division
points are not globally renamed.

The gallery inherits these helper and rendering changes. Its intentionally
regular triangles and polygons are not changed into scalene ones.

## Validation and rerendering

Executed using Racket CS 9.3.0.8:

- **26 refinement groups / 387 checks**: all the changes above, both themes,
  relative-pin validation/precedence and helper-result aliases.
- **68 standard-library groups / 2,484 checks**: independent mathematical
  oracles, transformed helper inputs, both copy directions and all applications.
- **49 audit groups / 3,051 checks**: all 17 examples in both themes, captions,
  sampled step boundaries and primary-circle fitting.
- **60 review groups / 215,848 checks**: sparse reviews, timing and bundle safety.
- The actual Racket reader accepts all **72 Racket modules** in the package.

The full RackUnit/native Animate/Pict/Draw suite has **not** been executed in the
minimal build runtime. Six new native integration cases cover the square's
layering, measured division labels and the hexagon's palette/render. This release
does not contain freshly rendered native review images or claim pixel-level
verification on macOS.

From the repository root, after replacing `geometry/`:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/run-tests.rkt &&
"$RACKET" geometry/review-examples.rkt \
  --all --both --output geometry-review-v083
```

For just the new headless regression checks:

```sh
"$RACKET" geometry/run-tests.rkt --refinements
```

Existing full-video commands and `--workers 10` are unchanged. The new review
output directory keeps prior bundles available for comparison.
