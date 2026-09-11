# Geometry v0.6.0: reveal and annotation layout

Baseline: `soegaard/animate` commit `1e6610cd4fbe6e6224c87a9e55e4949a6ca54a05`.
The implementation is a replacement `geometry/` folder; no other repository
files are changed.

## A. Shared, object-specific reveal geometry

1. Represent animated curves as pure polylines and circular arcs evaluated at a
   normalized progress value. Keep the sampler independent of frame history.
2. Draw finite segments from their actual mathematical endpoints, then clip.
   Support forward, reverse and centre-out directions. A ray starts at its
   origin; a line grows from its defining midpoint, clamped onto the visible
   interval when that midpoint is offscreen.
3. Retain the default two-front circle construction from its through-point.
   Add clockwise/counterclockwise alternatives. Render solid circular arcs as
   cubic Beziers rather than resolution-dependent polygons.
4. Use the same stroke geometry for markers and collision tests. Reveal each
   glyph by arclength, with corresponding ticks/arcs appearing simultaneously.
5. Add forward-reference-friendly `(reveal [object mode] ...)` metadata. Keep
   `(show ...)` as a fade of an existing complete object, not a redraw. Remap
   helper-local metadata and let caller metadata take precedence.

Implemented in `private/reveal.rkt`, `private/marker-shapes.rkt`, the compiler,
and the native adapter. Right-angle size remains unchanged; ticks keep their
accepted 20% reduction.

## B. Shared, visibility-aware annotation placement

1. Derive object and label co-visibility masks from immutable presentation states
   and transitions. Objects on unrelated gallery plates are not obstacles.
2. Measure label strings using Animate's public `plain-text`/`visual->pict`
   path and the output camera. Keep a pure conservative-estimate mode for core
   tests and non-rendering clients.
3. Build deterministic candidates: label sides and distances; tick/parallel-mark
   locations; valid right-angle quadrants; angle-arc radii. Respect finite arms.
4. Register pinned labels first; alternate marker and label placement for three
   bounded sweeps. Penalize annotation intersections, labels crossing geometry,
   and view/caption-boundary violations. Never shrink the square as a collision
   workaround. Choices remain fixed throughout playback.
5. Expose label-side/text/position and marker-position/quadrant/radius hints.
   Report unresolved conflicts instead of promising a perfect packing solver.
6. Allocate matching glyph counts by shared geometric members and co-visibility.
   Hidden aliases must not consume counts; unrelated simultaneously visible
   equality groups must not receive identical notation.
7. Reserve a measured caption band and paint it with the selected background,
   preventing helper circles or lines from running through narration.

Implemented in `annotations.rkt`, the compiler, themes, and native adapter.

## C. Gallery, manual and regression coverage

The gallery retains the original primitive/marker/helper plates and adds three
segment directions, three circle directions, a fade-only reveal, a Greek angle
label, and a crowded diagram with both automatic and explicit placement.
Narration describes geometry rather than highlighting/deemphasis operations.

New tests cover endpoint/clipping behavior, circle fronts, progressive markers,
metadata inheritance, label metrics, co-visibility, caption reserves, pinned
conflicts, deterministic sampling, and native adapter/gallery integration.

## Deliberate boundaries

This is a finite candidate layout heuristic, not an optimal global solver.
It keeps one position per label/marker over that object's full lifetime. It does
not animate givens, move the camera, draw a physical compass, or prove geometric
relations. Very dense diagrams can still need explicit placement or a wider view.
Font metrics may differ between operating systems. Workers on the same system
use the same fixed inputs and placement order; no layout is done per frame.
