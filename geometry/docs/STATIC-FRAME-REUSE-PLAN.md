# Geometry semantic static-frame reuse

## Goal

Avoid rerasterizing geometry frames whose visible content is unchanged during
`opening-pause`, `read-delay`, and `step-pause`, without teaching Animate's
generic renderer how to sample a geometry timeline.

## Domain-owned planning

`geometry/private/frame-reuse.rkt` is pure and owns the semantic relation. For
each requested source-frame index, it samples the immutable geometry timeline
and maps that index to the first matching representative using:

1. the complete per-object appearance map; and
2. visible narration text only when captions are enabled.

Subtitle metadata is intentionally absent from this key. Captions therefore
prevent reuse across a narration change, while turning captions off permits
reuse when appearances are otherwise equal.

The geometry module builder runs this planning once during project preparation.
It sends a bounded, versioned frame-reuse witness with the source construction
fingerprint to the generic project planner. Workers receive only the frozen
preparation and the representative jobs; they reconstruct the same timeline but
do not recompute the semantic witness.

## Generic execution and observable result

The generic executor validates the witness against the selected source frame
grid, rasterizes each representative once, and materializes the remaining
numbered output slots as aliases. Persistent cache hits are accounted for before
worker sizing. Its report distinguishes cache hits, representative raster jobs,
aliases, and materialized output frames.

The public result remains a complete ordinary PNG sequence with the original
frame numbering and timing. Subtitle generation, MP4 muxing, stills, and review
presentation remain separate parent/local operations.

## Direct local API

`geometry/render.rkt` retains its local timeline-value rendering helpers and
uses the same pure relation for their direct reuse behavior. Those helpers do
not themselves infer a restartable source from an arbitrary captured timeline.
Use an example module's explicit builder/preparer pair when a full-frame render
needs generic subprocess execution.
