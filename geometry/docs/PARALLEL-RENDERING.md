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
