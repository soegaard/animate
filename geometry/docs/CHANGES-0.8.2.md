# Changes in v0.8.2

## Static-frame render reuse

Full-frame geometry rendering now avoids rerasterizing semantically identical
frames during `opening-pause`, `read-delay`, and `step-pause`.

- `geometry/render.rkt` now samples requested frame indices first.
- Frames are deduplicated by their geometry appearances and, when captions are
  enabled, their visible narration text.
- Only representative unique frame states are passed to Animate's native PNG
  renderer.
- The ordinary numbered `frame-*.png` sequence is then materialized from those
  representative renders.
- This applies automatically to `render-geometry-frames!`,
  `render-geometry-frames/report!`, and shard-local `render-geometry-frame-indices!`.

## Tests

- Added a native render integration test checking that duplicated static frames
  appear as zero-cost reuse entries in the render diagnostics.

## Documentation

- Updated `docs/MANUAL.md`.
- Extended `docs/PARALLEL-RENDERING.md` with the static-frame reuse strategy.
