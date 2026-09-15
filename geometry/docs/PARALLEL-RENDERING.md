# Geometry full-frame rendering through the shared executor

## What `--workers` does

The standard geometry example commands use Animate's generic project executor
for full-frame output (`--frames` and `--mp4`). The command declares a
restartable module source rather than manually launching another copy of the
example.

- With `--workers 1`, the executor's `auto` policy selects its normal local
  renderer.
- With more workers, the same policy selects the shared subprocess service
  when the module-backed source is supported. The parent reports the requested
  capacity, started workers, and workers that completed work.
- The worker service owns process launch, protocol validation, source loading,
  deadlines, logging, staging, and shutdown. Geometry does not have hidden
  worker command-line flags or a shard merger.

Each worker reconstructs the same explicit example builder from its module
path and frozen options (dimensions, FPS, light/dark mode, and caption mode).
It does not receive an in-memory scene or geometry timeline from the parent.

## Output and publication

The generic executor first publishes a complete PNG sequence into a generated,
private sibling directory. Only after that succeeds does the geometry command
move the numbered PNGs into the requested public directory:

```
frame-000000.png
frame-000001.png
...
```

The command removes only these managed frame names (and its managed still/SRT
sidecars) from a reused public directory. The private generic directory is
created for one invocation and removed afterward. Its persistent frame cache
is deliberately retained in `.animate-geometry-render-cache` beside the public
output directory; it can make an otherwise identical later render start zero
workers.

Subtitles and MP4 muxing remain parent-side operations. Sparse still and review
commands remain local geometry operations and do not request a full movie
worker session.

## Geometry's semantic reuse boundary

`geometry/private/frame-reuse.rkt` owns the meaning of two geometry frames
being visually identical: per-object appearances, plus narration only while
on-screen captions are enabled. Its preparer supplies that versioned witness to
the generic project planner. The generic executor validates, schedules, caches,
and materializes representatives and aliases, but it does not inspect a
geometry timeline or subtitle format.

Low-level APIs accepting an already captured geometry timeline, such as
`render-geometry-frame-indices!`, remain local renderer APIs. They are useful
for direct library callers; use an example command or a restartable project
source when subprocess execution is required.
