# Geometry authoring layer — changes in v0.9.5

This maintenance release fixes the issues found in the v0.9.4 dark review.

## Review sampling now targets reveal progress correctly

The timeline eases action progress through smoothstep before storing an object's
`geometry-appearance-reveal` value. v0.9.4 selected the compass review stills as
raw event fractions, so the nominal `measure` and `transport` images were sampled
too early.

The review planner now deterministically inverts smoothstep before converting the
requested semantic reveal progress to a timestamp. The five compass stills target:

- `measure`: reveal progress `0.06`
- `transport`: reveal progress `0.335`
- `sweep`: reveal progress `0.725`

The inversion uses a bounded bisection on `[0,1]`; no frame-grid rounding or
numeric root-finder dependency is introduced.

## Mixed contact sheets no longer have misleading global headings

Pages can contain both ordinary three-sample rows and five-sample compass rows.
A page-wide heading row therefore cannot name columns consistently. The global
phase headings have been removed. Every thumbnail retains its own phase/time
label immediately below the image.

## Construction-circle fitting

The standard `copy-segment` helper now declares its transferred-radius circle as
a `fit-circle`, and `copy-angle` does the same for its three construction
circles. Radius-defined circles otherwise contribute only their centre to camera
fitting because their eastward internal through-point is synthetic.

This lets the camera account for the full pedagogically visible auxiliary
circumferences, providing the clearance needed in constructions such as
`copy-triangle-sas` where a large copied circle previously entered the caption
band.

## Tests

- review tests now assert that the three dedicated compass samples have the
  intended *post-easing* reveal progress;
- existing library/example checks exercise the helper `fit-circle` hints and
  their expansion through callers.
