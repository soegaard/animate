# v0.9.0 — mathematical transformations and semantic labels

## Mathematics and type checking

- Added `Vector`, `Transform`, and `Text` nondrawable types.
- Similarity constructors: translation, rotation, reflection and nonzero dilation.
- Composition (rightmost first), inversion, scale/orientation inspection.
- `transform`, plus direct `translate`, `rotate`, `reflect`, and `dilate` forms.
- Supported geometry kinds, angles, relations and markers retain their types.
- Explicit degree conversion; negative dilation allowed; singular maps rejected.
- No implicit scene motion, camera movement, style copying, or proof generation.

## Semantic annotations

- Added drawable `Label` type, with point/segment/length/angle constructors.
- Fixed symbolic text or computed length/degree strings; bounded decimal precision.
- Optional angle arc; unit suffixes are labels, not dimensional conversions.
- Independent presentation state and typed helper inputs/results.
- Shared measured text/annotation solver integration and upright text rendering.
- New `label-position` hint and Label support in relative offsets/radius hints.
- Semantic-label and kind-specific theme rules; helper hints follow result aliases.

## Examples and testing

- New transformations and semantic-labels examples; new gallery plates.
- Review `--all` now selects 19 examples; `--library` remains 13.
- New base-only checks, RackUnit wrapper, and genuine native integration tests.
- Added `geometry/run-tests.rkt --transform-labels`.
- Updated the reference manual, gallery/review guides, and release validation notes.

## Preserved behaviour

The corrected v0.8.3 application source files (except the deliberately expanded
gallery), foundations library, static-frame renderer, and process example runner
are unchanged. Existing glyph sizes, one-second default reading pause, themes,
review bundle safety and video output conventions are retained.
