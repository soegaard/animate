# Geometry authoring layer — changes in v0.9.4

This refinement release improves the construction-like compass circle reveal and
its sparse review workflow.

## Compass-circle reveal

- The reveal now has four presentation phases instead of three:
  1. **measure** the source length,
  2. briefly **hold** the full measured source,
  3. **transport** it to the new centre, and
  4. **sweep** the circle.
- The guide orientation is chosen more carefully when a view/caption band is
  known, preferring the orientation whose early sweep stays farther from the
  lower caption band and frame edges.
- Default guide styling is more visible in both themes: slightly heavier stroke,
  shorter dash rhythm, and full opacity.
- Fresh `reveal` actions that use an automatic/explicit compass circle now get a
  longer default action duration (`1.6s`) unless the caller already overrode the
  action duration globally or per step.

## Review bundles

- Ordinary steps still use three samples: `read`, `during`, `settled`.
- Steps containing a compass-circle reveal now use five samples:
  `read`, `measure`, `transport`, `sweep`, `settled`.
- `steps.txt`, `index.html`, the manifest, and contact sheets now handle mixed
  three-sample and five-sample rows.
- The gallery's compass-transfer plate benefits automatically from the richer
  review capture.

## Tests and docs

- Updated compass reveal checks for the new timing/styling.
- Updated review-plan checks for mixed sample counts.
- Updated the manual, review-bundle notes, compass reveal notes, and gallery
  documentation.
