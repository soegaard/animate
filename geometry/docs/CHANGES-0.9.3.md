# Changes in v0.9.3

## Compass-transfer circle reveals

Radius-defined circles now show transferable-compass provenance when their
radius is directly a segment length or point-to-point distance. The reveal first
marks the source measure with a dashed copy, transports that copy to the new
centre, then rotates it while tracing the circle.

The feature is automatic for:

```racket
(circle O #:radius (length AB))
(circle O #:radius (distance A B))
```

and through Number/helper aliases. Literal and arbitrary arithmetic radii keep
the ordinary circle reveal. `(circle O P)` is unchanged by default.

The explicit reveal mode `compass` is also available. It may be used with a
two-point circle, in which case `OP` is the transferred measure. A forced
source-free compass reveal is diagnosed.

The transient carrier has its own `compass-guide` theme selector. It is
presentation-only and disappears at the settled endpoint, so later `show` never
replays the construction.

## Gallery and tests

The gallery contains a radius-transfer plate. A new base-only `--compass` test
suite covers provenance, transport geometry, sweep geometry, helper aliases,
fall-back behavior, and theme styling. Native integration tests verify that the
guide exists only during the reveal.
