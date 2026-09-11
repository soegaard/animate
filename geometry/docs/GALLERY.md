# Gallery review — v0.6.0

Render `geometry/examples/gallery.rkt` in both themes. The captions describe
mathematics; the code still exercises presentation-state changes.

Inspect these differences:

1. The three new segments draw left-to-right, right-to-left, and centre-out.
2. The three equal-radius circles start at their named circumference points:
   two fronts, clockwise, and counterclockwise. The separate fade-only circle
   appears as a complete boundary.
3. Squares, ticks, chevrons and angle arcs draw progressively. The square has
   the previous side length; ticks are still 20% shorter.
4. The Greek `α` label follows its angle arc. Labels of the dense triangle
   avoid marker strokes and one another where feasible; M's pinned label and
   C's preferred side demonstrate the overrides.
5. Unrelated, hidden gallery plates do not influence the current labels.
   Label positions remain fixed during hides, shows and temporary styling.
6. The caption panel prevents construction lines/circles passing through text.

`--describe` reports annotation warnings. A warning is a request for inspection,
not a claim that every dense arrangement has a collision-free solution.

## v0.7.0: standard-library plates

The existing object, marker, effect, reveal-direction and crowded-layout plates
are preserved. New plates at the end demonstrate all eight library helpers:

1. Constructed midpoint and perpendicular bisector, with half-length and
   right-angle markers.
2. Perpendicular at a point on a line, perpendicular from an external point,
   and the parallel through the external point.
3. Internal angle bisector, expanded segment copy onto a target ray, and copied
   angle with an explicit target side.

Expanded calls use `#:auxiliaries 'hide` when the next plate needs a clean view.
Check that cleanup removes only that call's aids, leaving the caller's points,
target rays and returned objects available. Captions describe mathematics rather
than explaining which objects are being emphasized. The old helper demonstration
now uses the public library via a re-export, exercising both helper import names
in one construction.

The standalone thirteen application videos are listed in CONSTRUCTIONS.md and
rendered by `examples/render-library.sh`. They are not stitched into the gallery.
