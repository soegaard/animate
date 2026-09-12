# Changes in v0.9.1

This is a review-driven refinement of v0.9.0.

## Transformation example

- Reduced the fixed world width from 12 to 10.8 so the four transformation
  plates occupy more of the frame while preserving the required safe margin.
- Reflection now shows `AA′`, its midpoint on the mirror line, equal-half ticks,
  and a right-angle marker. This makes the equal perpendicular distances visible.
- Translation now shows the three corresponding displacement segments and an
  equal-length marker.
- Dilation now shows `OD = r` and `OD′ = 2r` before returning focus to doubled
  side lengths.

## Semantic labels

- Added the layout hint `(label-outside-of label point)` for length/segment
  Labels. It constrains the Label to the half-plane opposite the reference Point.
- This directly expresses the standard triangle convention:
  `a` on `BC` outside `A`, `b` on `CA` outside `B`, and `c` on `AB` outside `C`.
- The semantic-label demonstration uses this convention for symbolic and measured
  side labels. Its measured side/angle labels use smaller local clearances.
- Segment/length label candidate clearances were refined to include a closer
  first ring while retaining wider fallback rings.

## Review bundles

- Silent authored cleanup-only rows (`hide`, `hide-label`, `deemphasize`,
  `normalize`) and silent no-op/value-only rows are omitted by default.
- Silent steps that reveal/show/highlight something remain review-worthy.
- `geometry/review-examples.rkt --include-cleanup` restores all authored rows.
- Direct example runners use `--review-include-cleanup`.
- The review manifest records `include_cleanup_steps` and identifies geometry
  version `0.9.1`.

## Validation

Executed with the bundled minimal Racket CS runtime:

- transformation/semantic-label checks: 69 groups / 1,017 checks passed;
- review checks: 65 groups / 227,055 checks passed;
- standard-library checks: 68 groups / 2,552 checks passed;
- audit checks: 53 groups / 3,183 checks passed;
- example-refinement checks: 26 groups / 387 checks passed.

The minimal runtime does not contain the full `raco test`/native graphics stack,
so native PNG/font integration tests still need to run in the user's full Animate
checkout.
