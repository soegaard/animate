# Standard construction library — v0.7.0

Import from an authoring file in the repository root:

```racket
(require "geometry/core.rkt"
         (prefix-in c: "geometry/constructions.rkt"))
```

For a file inside `geometry/examples/`, the corresponding paths are
`"../core.rkt"` and `"../constructions.rkt"`. An installed collection uses
`animate/geometry/constructions`. The prefix is a convention, not a requirement.
`constructions.rkt` exports exactly the eight helper descriptors below.

## Contracts

| Helper | Typed inputs | Result | Conditions |
|---|---|---|---|
| `perpendicular-bisector` | `A : Point`, `B : Point` | `Line` | A and B distinct. |
| `bisect-segment` | `A : Point`, `B : Point` | `Point` | A and B distinct. |
| `erect-perpendicular` | `l : Line`, `P : Point` | `Line` | P lies on l. |
| `drop-perpendicular` | `l : Line`, `P : Point` | `Line` | P does not lie on l. |
| `angle-bisector` | `A : Point`, `B : Point`, `C : Point` | `Ray` | A, B, C noncollinear; B is the vertex. |
| `parallel-through-point` | `l : Line`, `P : Point` | `Line` | P does not lie on l. |
| `copy-segment` | `source : Segment`, `target : Ray` | `Point` | Source and target have distinct defining points. |
| `copy-angle` | `source : Angle`, `target : Ray`, `side : Side` | `Ray` | Source is nondegenerate, neither zero nor straight; side is `'left` or `'right`. |

These are `define-construction` values, not ordinary functions that accept
geometric values outside the DSL. Their inputs/results are checked during
elaboration; geometric preconditions and postconditions are numerical checks
on a realization. They are not formal proofs for every possible input.

## Basic use

```racket
(construction segment-lesson
  (given [A (point -2 0)] [B (point 2 0)])
  (step "Join A to B." [AB (segment A B)])
  (step "Construct the midpoint."
    (expand [M (c:bisect-segment A B)] #:auxiliaries 'hide))
  (step "The two parts have equal length."
    [halves (marker (midpoint-of M AB))])
  (assert (midpoint-of M AB))
  (result M))
```

Remove `expand` to use the subconstruction without explaining its method again:

```racket
(step "Construct the midpoint." [M (c:bisect-segment A B)])
```

Collapsed use reveals only the result. Expanded use shows narrated helper steps
and local geometry. Neither changes the mathematical result or drops helper
postconditions. `#:auxiliaries 'hide` removes that call's local aids at the end;
`'deemphasize` keeps them subdued, and the default `'keep` preserves the helper's
own final presentation. Caller givens and the returned result remain untouched.
The cleanup takes an ordinary action duration, with no extra reading pause or
caption of its own.

## Algorithms and useful conventions

### Perpendicular bisector and midpoint

Two circles centered at A and B, each through the other point, supply two
intersections. Their joining line is the perpendicular bisector. `bisect-segment`
uses that construction and intersects its result with AB. It does **not** compute
the answer with the kernel's `midpoint` function. The kernel function remains
available for calculations or an independent assertion/test oracle.

### Erecting a perpendicular

`erect-perpendicular` chooses a point on l different from P, constructs two
points equidistant from P, and intersects equal circles about them. The returned
Line is defined from P to an intersection on the **left of directed l**. Thus:

```racket
[n (c:erect-perpendicular (line A B) A)]
[r (ray A (end-point n))]
```

produces a ray into the left half-plane of A→B, useful when constructing a square.
This is a geometric branch convention, not an “up on screen” choice. Reversing
the defining points of l changes that preferred side, not the perpendicular locus.
A soft preference chooses a compass opening relative to l's defining-point
spacing; the exact opening has no bearing on perpendicularity.

### Dropping a perpendicular

Two circles centered at distinct defining points of l, both through external P,
meet once more at Q. Joining P to Q gives the perpendicular. The returned Line is
defined from **P toward Q**, across l. Intersect with l to obtain the foot H:

```racket
[n (c:drop-perpendicular l P)]
[H (intersection n l)]
[away (ray H (end-point n))]
```

The last ray points away from P and is useful for reflection. The algorithm does
not call a numerical projection primitive. Very large or poorly placed defining
points of l can make its auxiliary circles large; choose appropriate givens or
layout for a clear expanded exposition.

### Internal angle bisector

`(c:angle-bisector A B C)` returns the **internal** bisector ray at B. A circle
centered at B finds equal-distance points on the two rays. Equal circles about
those points meet in two places; the intersection farther from B selects the
internal ray for both acute and obtuse angles. Zero and straight angles are
rejected rather than silently choosing an arbitrary bisector.

### Parallel through an external point

`parallel-through-point` composes `drop-perpendicular` and
`erect-perpendicular`. Its nested exposition can itself be expanded. For a point
already on l, use l directly; the external-point construction intentionally
rejects that case instead of hiding a different algorithm inside a conditional.

### Copy a segment onto a ray

The target ray supplies the origin and direction. The result is an endpoint,
**not a segment and not a `(Point Segment)` pair**:

```racket
[Q (c:copy-segment AB (ray O T))]
[OQ (segment O Q)]
```

The radius of a circle centered at O is set to the length of AB. Its unique
intersection with the target ray is Q. This uses the new elementary compass form:

```racket
(circle O #:radius (length AB))
```

The radius must be positive and finite. In this form the circle's through-point
for reveal animation is chosen on the positive world-x axis at that radius.
`(circle O P)` still starts revealing at the explicitly supplied P.

This library uses a **transferable compass**, the usual fixed-opening model in
these videos. It does not expand a strict collapsible-compass length-transfer
construction into Euclid I.2. That distinction is explicit rather than hidden in
a helper claiming to use only two-point circles.

### Copy an angle onto a ray

```racket
[a (angle B A C)]               ; A is the vertex
[r (c:copy-angle a (ray O T) 'left)]
```

`a` is a nondrawable Angle value. The copied Ray starts at O. `Side` is required:
`'left` or `'right` of directed O→T, independent of the original angle's orientation.
The non-reflex angle measure is copied; a zero or straight source is rejected.
The source circle, equal target radius, and copied chord determine the new ray
without computing an angle and rotating a vector as the construction algorithm.

`angle-first`, `angle-vertex`, and `angle-last` access an Angle's three defining
points. `start-point` and `end-point` access a Line/Segment/Ray's defining points;
for an infinite line, “end-point” means the second **defining** point, not a finite
end of the locus. `side-of?` checks which strict half-plane a point occupies.

## Application videos

| Example module | Main library uses | Final mathematical check |
|---|---|---|
| `square-on-segment.rkt` | Erect, copy length, two parallels | Four equal sides, right angles, parallel opposite sides. |
| `circumcenter.rkt` | Two perpendicular bisectors | Equal radii; circle through all three vertices. |
| `incircle.rkt` | Two angle bisectors, three dropped perpendiculars | Equal perpendicular distances; contacts on all three sides. |
| `triangle-midline.rkt` | Two constructed midpoints | Half-side marks, parallel midline, half base length. |
| `reflect-point.rkt` | Drop and copy length beyond the foot | Mirror line perpendicular to PQ and through its midpoint. |
| `copy-triangle-sas.rkt` | Two length copies and one angle copy | All corresponding sides match; included angles match. |
| `divide-segment-five.rkt` | Five unit copies, four parallels | Division points at fifths; five equal lengths. |
| `tangent-at-point.rkt` | Erect at a radius endpoint | Perpendicular to the radius at the given circumference point. |
| `orthocenter.rkt` | Three dropped perpendiculars | All three altitude lines concurrent. |
| `regular-hexagon.rkt` | Repeated sixty-degree angle and radius copies | Six distinct successive vertices on the circle; equal sides. |
| `equilateral-triangle-chain.rkt` | Repeated side and angle copies | Three adjacent equal equilateral triangles. |
| `parallel-at-distance.rkt` | Erect, copy prescribed distance, parallel | Perpendicular distance equals the supplied segment length. |
| `copy-angle.rkt` | A right-side angle copy | Equal non-reflex angles, with labels α. |

The first eight are the primary composition suite. The remaining five implement
the additional examples discussed. Examples use fixed nondegenerate illustrative
inputs, not a promise that every modified triangle can use the same caption or
finite altitude segment. The helper contracts above define the general API.

Every example exports its construction value, `example-theme`,
`make-demo-timeline`, and `make-demo-scene`. Loading the new example modules is
headless; scene conversion and the command-line renderer load the native adapter
only when requested. Most demonstrate one expanded helper followed by collapsed
reuse. The resulting frame counts differ from the earlier three-demo package.

## Rendering

From the repository root, render one video:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/examples/square-on-segment.rkt \
  --dark --workers 10 \
  --mp4 geometry-output/videos/dark/square-on-segment.mp4 \
  geometry-output/dark/square-on-segment
```

Render all thirteen in both themes (26 videos):

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket" \
WORKERS=10 sh geometry/examples/render-library.sh both
```

Use `light` or `dark` instead of `both` to render one theme. Set
`GEOMETRY_OUTPUT=/some/path` for a different output root. The batch reads an
explicit module manifest, excludes helper files, and stops on a failed render.
Videos run one after another; each video's frame renderer uses the requested
number of separate Racket processes. There is no nested ten-by-thirteen pool.

For stills, omit `--frames`/`--mp4`. `--describe` reports numerical realization and
native annotation diagnostics. The original examples and `gallery.rkt` remain
available separately; `render-library.sh` does not repeat those four older videos.

## Validation and visual review

Run `racket geometry/run-tests.rkt --library` for the base-only mathematical,
composition, sample-order and estimated-annotation checks. Run
`racket geometry/run-tests.rkt` on a full Animate installation for these plus the
existing RackUnit suite and new native bitmap/PNG tests. See TESTING.md for exactly
which checks were executed for this delivery.

The label/marker layout is still a bounded heuristic. Some expanded-helper
intermediate states report label/curve overlap warnings with estimated font
boxes. They are not silently described as solved. Inspect the native `--describe`
report and the generated stills at the intended output size; a `label-side` or
`label-at` hint remains available. Right-angle size and the shorter tick length
are unchanged. Narration describes mathematics, not color or emphasis commands.


## v0.8.1 audit corrections

The eight exported names, argument types, return values, and transferable-compass
assumption are unchanged. The helpers now use `(caption ...)` templates for
object names, so expanding a source angle at a new vertex does not refer to the
caller's wrong A/B/C. Distinct private points receive deterministic display names
without changing their hygienic internal identities.

The `copy-angle` helper chooses an interior point U on the first source segment
and weakly prefers an opening of one third of that segment. It draws the source
circle, obtains D on the second arm, explicitly draws the chord UD, then copies
that opening and chord at the target. This avoids the former full-side opening
that made D coincide with the original endpoint in common examples. The result
is still the same angle for every valid compass opening.

Expanded helpers explicitly show supporting lines/rays that are part of their
instructions. Cleanup still removes only private auxiliaries, never caller
objects or declared results. `bisect-segment` no longer draws a duplicate initial
segment before expanding its perpendicular-bisector helper. The latter hides
its private base at the conclusion instead of leaving a duplicate colored edge
on top of a caller's segment.

Applications teach a new construction once and reuse it collapsed when further
expansion would obscure the purpose: the circumcenter uses known perpendicular
bisectors; reflection uses a known perpendicular foot before showing distance
copying; the hexagon uses known angle copying after showing a 60° triangle.
The foundation demonstrations and gallery still support expanded use.

See EXAMPLE-AUDIT.md for all thirteen applications, the original three videos,
and the gallery, including the remaining native-render review checklist.
