# Plan for better parallel rendering

## Problem

Thread-based full-frame rendering reported the requested worker count, but real CPU
usage stayed near one core and renders became slower with more workers. That points to
serialization in the expensive rasterization path (`pict` / `racket/draw`) rather than a
lack of worker creation.

## Strategy

1. Keep the existing single-process path for `--workers 1`.
2. For `--workers > 1`, switch the geometry example runner to **process-based sharding**.
3. Compute the total frame count once from the timeline duration and fps.
4. Launch `N` separate Racket processes, each re-running the same example module in a
   hidden `--worker-shard` mode.
5. Each worker reconstructs the same immutable timeline and renders only its shard of
   frame indices.
6. The parent waits for all workers, merges the `frame-*.png` files into the requested
   output directory, writes `narration.srt`, and optionally runs FFmpeg.
7. Print both the requested and actual worker count.

## Why this design

- It avoids relying on parallel threads for `racket/draw` rasterization.
- Each worker gets a separate Racket runtime and separate native drawing state.
- The geometry examples are deterministic, so reconstructing the timeline in each child
  process is safe and reproducible.
- The design does not require serializing an arbitrary `animate` scene with closures.

## Scope of the implementation

This implementation improves the geometry example runner (`geometry/examples/*.rkt`) and
keeps the outer `animate` repository untouched. It therefore gives a practical multicore
path immediately for the geometry-construction videos.

## Shard merge correctness

`render-frame-indices!` numbers files locally within each shard. During the parent
merge, local shard filenames are therefore remapped back to their assigned global
frame indices (`frame-000000.png`, `frame-000001.png`, ...). The merge verifies both
the per-shard file count and the final total frame count, and refuses accidental
filename replacement.

## Static-frame reuse for geometry timelines

After process-based sharding was working, the next bottleneck was repeated
rasterization of frames during `opening-pause`, `read-delay`, and `step-pause`.
Those spans often have no active geometry event, so many requested frame indices
sample the exact same geometry snapshot (and the same caption when captions are
shown).

The geometry renderer now performs a lightweight planning pass before native PNG
output:

1. Sample the immutable geometry timeline at each requested frame index.
2. Build a semantic key from the per-object appearances and, when captions are
   enabled, the visible narration text.
3. Keep only the first occurrence of each unique visual state.
4. Render those representative indices through the existing native renderer.
5. Materialize the full numbered frame sequence by copying the representative
   PNG to the remaining duplicate frame names.

This optimization is intentionally implemented in `geometry/render.rkt`, not in
Animate's generic scene renderer. General Animate scenes may depend on time in
arbitrary user-defined ways, while geometry timelines have explicit immutable
presentation events and narration cues, so semantic equality is cheap and safe
to detect here.

### Consequences

- Movie timing is unchanged.
- Output filenames remain `frame-000000.png`, `frame-000001.png`, ... .
- MP4 encoding and review tooling need no changes.
- Single-worker and shard-worker rendering both benefit automatically.
- Disk usage is still one PNG per numbered frame; the optimization saves CPU time
  by avoiding duplicate rasterization rather than by changing the output format.
