# Standard construction library — plan and implementation record

## Goal and boundary

Promote the eight agreed constructions into a reusable, headless library, and
exercise them in all eight primary applications and the five additional
applications discussed. A construction returns geometry and carries exposition
and numerical postconditions. It does not hard-code colors, a frame rate, or an
output backend. No files outside `geometry/` are changed.

The implementation assumes a **transferable compass**: a measured segment can
supply the opening of a circle at another center. It does not claim that its
length-transfer operation is an expansion of the strictly collapsible-compass
construction in Euclid I.2.

## 1. Settle contracts

Use `bisect-segment` for the constructed midpoint; keep `midpoint` as a separate
kernel operation. `copy-segment` takes a Segment and a Ray and returns the copied
endpoint. The ray supplies both origin and direction, preventing inconsistent
origin arguments. `copy-angle` takes an Angle, a Ray, and a required Side and
returns a Ray. Erect/drop remain separate, as do the external-point parallel
construction and the trivial on-line case.

**Implemented:** `constructions.rkt`, `constructions/foundations.rkt`, eight typed
helpers with preconditions and numerical postconditions.

## 2. Add the missing elementary vocabulary

The algorithms need access to defining points, named angle descriptors, a
left/right choice, and a transferred compass opening. Add `Angle`, `Side`, and
`Relation` as nondrawable binding types; defining-point/angle accessors;
`side-of?`; and `(circle O #:radius distance)`. Do not add a hidden formula for
the answer to a construction.

**Implemented:** expression validation, evaluation, value accessors, and typed
helper argument remapping. Unit-direction relation checks no longer multiply a
dimensionless error by a world-space length. False relation values remain
inspectable until a Boolean test, precondition, assertion, or marker validates
them. Postconditions validate the selected realization rather than steering
layout toward a lucky candidate.

## 3. Make composition readable

Retain the exact mathematics under collapsed and expanded calls. Support
`(expand [answer (helper ...)] #:auxiliaries 'hide)` and `'deemphasize`; keep
`'keep` as the default. Cleanup targets only the new call-local drawable IDs,
never caller inputs or result aliases. It is an uncaptioned presentation action.
Preserve both surface names when one helper is imported under two prefixes.

**Implemented and exercised:** nested expansion, cleanup, hygienic names,
postconditions in collapsed helpers, and aliases of re-exported helpers.

## 4. Build the application suite

Primary: square, circumcenter/circumcircle, incircle, triangle midline, reflected
point, SAS triangle copy, division into five parts, and tangent at a circle point.
Additional: orthocenter, regular hexagon, equilateral-triangle chain, parallel at
a prescribed distance, and standalone angle copy. Include all eight helpers in
new gallery plates and use a manifest-driven batch renderer.

**Implemented:** thirteen headless-loadable example modules, lazy native scene
conversion, gallery plates, and `examples/render-library.sh`.

## 5. Verify mathematical and presentation contracts

Check transformed inputs, acute/right/obtuse angles, both target sides,
invalid inputs, repeated/nested helper calls, labels/marker plans, random-access
sampling, and the same sample grid split into ten shards. Compare results with
independent vector/projection/triangle-center oracles, not merely the helpers'
own assertions. Keep native rasterization tests separate from the pure checks.

**Executed here:** Racket CS 9.3.0.8, base-only library checks (see TESTING.md).
**Included but not executed here:** RackUnit wrappers and native Animate bitmap
and PNG tests. This environment has the minimal Racket runtime but not the
complete native Animate/pict/draw dependency set. Rendering quality on the
user's macOS installation remains a visual review, not a claimed test result.
