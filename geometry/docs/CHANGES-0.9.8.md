# Changes in v0.9.8

This release makes the deliberate compass-transfer choreography slower again and
uses it repeatedly in the five-part segment-division example.

## Compass timing

- The automatic compass-transfer action now defaults to **10.0 seconds**.
- Explicit per-step or global action-duration overrides still win.
- The choreography itself is unchanged from v0.9.7: pickup, parallel lift,
  source attention, transport, target attention, sweep, and fade-out.

## `divide-segment-five`

The example now demonstrates the same copied unit repeatedly instead of using the
full compass-transfer animation only for the first division point.

- `c1` through `c5` are explicit radius-defined construction circles.
- Every circle takes its radius from the visible source segment `unit`, so all
  five use the deliberate compass-transfer reveal automatically.
- Each circle remains visible after its point is marked, making the repeated
  equal-radius construction visible as a whole.
- After `P5` and the fifth unit interval have appeared, `c1` through `c5` fade
  out together before the intercept-theorem part continues.
- The layout fits the full circumferences of all five construction circles.

Regression checks verify the five circle centres/radii, compass provenance, and
the final collective hide action.
