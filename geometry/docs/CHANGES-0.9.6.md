# Geometry authoring layer — changes in v0.9.6

This release makes transferred-radius circle construction deliberately slower and
more legible, based on review of the `copy-triangle-sas` video.

## New compass-transfer choreography

A radius copied from visible geometry now uses a six-part presentation sequence:

1. draw a movable carrier directly over the source measure;
2. lift it slightly to a nearby parallel;
3. pulse a glow-like attention halo;
4. transport the carrier rigidly to the new centre;
5. pulse the attention halo again on arrival; and
6. sweep the carrier around the centre while tracing the circle.

The mathematical `Circle` node and radius provenance model are unchanged.

## Timing

Automatic compass reveals now get a default action duration of **4.0 seconds**
unless action duration is explicitly overridden. This gives substantially more
screen time to both the transport and the final sweep than v0.9.5.1.

## Presentation styling

- `compass-guide` is now a solid highlight-coloured movable segment.
- New `compass-attention` is a wide translucent highlight under-stroke.
- Attention strength follows a single pulse and is computed directly from reveal
  progress, preserving random-access rendering.

## Parallel offset and layout

Before transport, the temporary carrier moves a modest distance perpendicular to
the source, so it is visibly detached from the original segment while remaining
parallel to it. The offset side is selected using the realized view and caption
band, preferring the side that remains legible and in frame.

## Review bundles

Ordinary rows remain `read / during / settled`. Compass rows now use seven
samples:

`read / pickup / source-attention / transport / target-attention / sweep / settled`

The review planner continues to invert timeline smoothstep easing so semantic
phase samples land at the intended reveal progress.

## Tests

Base-only regression checks cover carrier length, parallel lift, both attention
pulse peaks, transport, sweep geometry, provenance, theme styling, and the new
seven-sample review rows. Native integration tests also check the transient
`compass-attention` visual when run inside the complete Animate repository.
