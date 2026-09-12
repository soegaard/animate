# Plan: avoid rendering identical geometry frames

## Goal

Reduce render time for geometry videos by avoiding repeated rasterization of
frames whose visual content is unchanged during `opening-pause`, `read-delay`,
and `step-pause`.

## Observations

1. Geometry timelines are immutable and random-access.
2. During static spans, `sample-geometry-timeline` returns the same per-object
   appearances at every sampled time.
3. When captions are enabled, narration text must be included in the equality
   test; with captions disabled, narration can be ignored.
4. The generic Animate renderer should remain unchanged because arbitrary scenes
   may depend on time in author-defined ways.

## Implementation strategy

1. Add a geometry-specific planning pass in `geometry/render.rkt`.
2. For a requested list of frame indices, sample the geometry timeline first.
3. Build a semantic key from:
   - the `geometry-frame` appearances, and
   - the visible narration text when captions are on.
4. Keep only the first occurrence of each unique visual state.
5. Render those representative frame indices through the existing native
   `render-frame-indices/report!` API.
6. Materialize the full requested numbered frame sequence by copying the
   representative PNGs to the duplicate destination names.
7. Return ordinary render diagnostics and preserve subtitle writing and MP4
   assembly.
8. Reuse the same optimization for shard-local rendering, so multi-process
   `--workers` mode benefits too.

## API / behaviour

- No DSL change.
- No change to frame numbering.
- No new command-line flag required.
- Captions still determine whether narration changes affect frame equality.
- `render-geometry-frame-indices!` remains the shard boundary used by the
  example runner.

## Validation

1. Add a render integration test with nonzero opening/read/hold pauses.
2. Confirm that:
   - the full set of frame files is still produced,
   - the reported frame count is unchanged,
   - some per-frame render durations are zero because those frames were reused.
3. Re-run the example workflow and compare wall-clock render times.
