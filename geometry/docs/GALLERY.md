# Gallery review — v0.8.1

## Corrections from the uploaded contact sheets

The primitive-object introduction now clears the previous primitive before
introducing a different kind. Segment endpoints, ray origin, and the circle's
centre/circumference point are shown with their matching names. The first circle
has more room to be seen.

There are separate concurrent equal-angle groups with one, two, and three arcs,
in addition to the length groups with one, two, and three ticks. Each group is
mathematically checked; unrelated groups do not accidentally share a pattern.
The α angle label stays within its marked sector.

The reusable-helper plate leaves its caller's segment available. The later
angle-copy plate removes the earlier angle bisector and its arcs, so they do not
cross or visually divide the newly copied angle. Captions use the displayed
names, including helper-local substitutions, and still do not announce
highlighting or deemphasis.

The gallery currently has **66 review rows / 198 images per theme** with expanded
steps included. Synthetic setup/cleanup is not an extra review row. Step numbers
have changed relative to the input v0.8.0 bundle.

Native post-fix rendering still needs verification. In addition to the points
above, inspect the existing demonstrations below for regressions.

---

## Existing reveal/layout demonstrations

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


## Sparse gallery review (v0.8.0)

The gallery is included by `geometry/review-examples.rkt --all` and can be reviewed
individually:

```sh
"$RACKET" geometry/review-examples.rkt --example gallery --dark
```

Upload `geometry-review/dark/gallery.zip`. Its contact sheets are paginated at six
step rows per page; full-size Read / During / Settled PNGs are retained. The
library demonstrations include their expanded steps. For a smaller outer-step
overview, add `--top-level-only`. These options do not change the gallery's
narration or playback.
