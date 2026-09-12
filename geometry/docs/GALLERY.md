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

The gallery currently has **60 default review rows / 180 step images per theme** with expanded
steps included and silent cleanup rows omitted. Synthetic setup/cleanup is not an extra review row. Step numbers
have changed relative to the input v0.8.0 bundle.

Native post-fix rendering still needs verification. In addition to the points
above, inspect the existing demonstrations below for regressions.

---


## v0.9.3: compass-transfer plate

A later circle plate shows the radius provenance used by transferable-compass
constructions. A visible segment AB supplies the radius of a circle centred at O.
During the fresh reveal a temporary dashed copy is drawn on AB, transported to O,
and swept once while the circle is traced. The temporary carrier is gone in the
settled image and does not alter the underlying geometry graph.

Review bundles capture this plate with seven samples: `read`, `pickup`, `source-attention`, `transport`, `target-attention`, `sweep`, and `settled`. The two attention samples show the glow pulses before and after transport. `copy-segment` and `copy-angle` use the same behavior
automatically when their radius is a direct length/distance.

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


## v0.8.3 shared refinements

The standard-library plates inherit the P/Q/R/S-style helper names and the new
line/ray-behind-segment rendering order. Their deliberately equilateral/regular
figures remain regular: only the application examples described as arbitrary
triangles were reshaped. Review both themes with the existing gallery command.


## v0.9.0: transformations and semantic labels

The existing plates are retained. After the construction-library plates, the
gallery adds reflection, translation, rotation and dilation of segment geometry,
followed by a scalene triangle annotated using all four Label constructors.
Symbolic lengths/angles are replaced by computed measurements and restored.
Old objects and independent labels are explicitly hidden between plates.

Review these additions for:

1. Source segments remain in place while newly constructed image segments appear.
   The half-turn uses O as centre; the dilation multiplies lengths by one half.
2. Labels on the image remain upright and use the image's geometry. Optional angle
   arcs lie in the named angular sectors. Measured values and symbolic names are
   visibly distinct states, not overlapping duplicates.
3. Hiding a Label removes that annotation; hiding only its text retains its angle
   arc. Automatic point names are explicitly disabled when independent names are
   used. Supporting lines still draw behind finite gold segments.

The two focused examples are useful before rendering the complete gallery:

```sh
"$RACKET" geometry/review-examples.rkt --example transformations --both --output geometry-review-v090
"$RACKET" geometry/review-examples.rkt --example semantic-labels --both --output geometry-review-v090
```

The estimated annotation pass reports no conflicts in these two examples or the
updated gallery in either theme. Native font metrics may differ; the supplied
native integration tests and review renders still need to be run on the target
installation. This is not a claim of native visual validation.
