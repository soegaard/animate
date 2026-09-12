# Changes in v0.9.7

This is a timing-only refinement of the deliberate compass-transfer reveal.

- The automatic compass-transfer reveal is now **half as fast** as v0.9.6.
- The default action duration for automatic compass reveals increased from
  **4.0 seconds** to **8.0 seconds**.
- The choreography is otherwise unchanged:
  pickup, parallel lift, source attention, transport, target attention, sweep,
  and fade-out.

Any construction step with an explicit `#:action-duration` (or equivalent global
manual override) still keeps the author-specified timing.
