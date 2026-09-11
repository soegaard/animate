# Mathematical Authoring DSL for `animate`

## Status

This document describes a proposed first version of a mathematical-authoring DSL for the Racket `animate` project.

The DSL is aimed initially at **geometrical construction videos**. Its central design goal is that the source should read like the mathematical construction itself, while `animate` derives the visual presentation and animation from the mathematical structure.

The design is intentionally small. Features should be added when real constructions demonstrate a need for them.

---

# 1. Design principles

The DSL separates four concerns:

1. **Mathematics** — what geometric objects exist and how they depend on each other.
2. **Exposition** — when objects are introduced to the viewer.
3. **Presentation state** — whether objects or labels are shown, hidden, deemphasized, or highlighted.
4. **Layout** — how free givens and construction choices are concretely realized so that the resulting diagram works well in the view.

A typical construction therefore has this shape:

```racket
(construction example
  (given ...)
  (require ...)
  (layout ...)
  (initially ...)
  (step ...)
  (step ...)
  ...)
```

Not every construction needs every clause.

---

# 2. A first example: equilateral triangle

```racket
(construction equilateral-triangle
  (given
    [A (point -2 0)]
    [B (point  2 0)])

  (step
    "Start with the segment AB."
    [AB (segment A B)])

  (step
    "Draw a circle centred at A through B."
    [cA (circle A B)])

  (step
    "Draw the corresponding circle centred at B."
    [cB (circle B A)])

  (step
    "Let C be their intersection."
    [C (intersection cA cB #:side-of AB 'left)])

  (step
    "Join C to A and B."
    [AC (segment A C)]
    [BC (segment B C)])

  (step
    "This is the required equilateral triangle."
    (deemphasize cA cB)
    (highlight AB AC BC)))
```

This should read almost exactly like a ruler-and-compass construction.

The bindings describe mathematical objects:

```racket
[AB (segment A B)]
[cA (circle A B)]
```

The surrounding `step` determines when the viewer learns about them.

---

# 3. `construction`

```racket
(construction name
  clause ...)
```

Defines one complete construction or construction-based exposition.

Example:

```racket
(construction perpendicular-bisector-demo
  ...)
```

A construction is not merely a sequence of drawing commands. It is compiled into a mathematical dependency graph plus an exposition plan.

This distinction allows `animate` to:

- inspect dependencies;
- determine which geometric incidences matter;
- solve layout globally;
- realize free choices deterministically;
- derive sensible reveal animations;
- reuse constructions inside later constructions.

---

# 4. `given`

## 4.1 Concrete givens

For a standalone construction, `given` introduces the objects supplied before the construction proper begins.

```racket
(given
  [A (point -2 0)]
  [B (point  2 0)])
```

By default, givens are visible at the beginning.

A given may be any suitable geometric object, not only a point.

For example:

```racket
(given
  [l (line (point -3 0)
           (point  3 0))]
  [P (point 0 0)])
```

---

## 4.2 Free givens

Coordinates are presentation details. A construction may instead specify an arbitrary given:

```racket
(given
  [A (point)]
  [B (point)])
```

Here `A` and `B` are mathematically arbitrary points. Their concrete coordinates are chosen later by the realization/layout system.

This is different from `choose`.

- A free given is supplied by the problem.
- `choose` represents freedom exercised by the construction.

---

# 5. `require`

`require` states mathematical preconditions on the givens.

```racket
(require
  (distinct? A B))
```

or:

```racket
(require
  (on P l))
```

Types and preconditions are intentionally separate.

For example:

```racket
P : Point
l : Line
```

says what kinds of objects `P` and `l` are, while:

```racket
(on P l)
```

states a mathematical relation between them.

`require` is not a layout mechanism. It expresses conditions that must be true for the construction itself to be valid.

---

# 6. `step`

```racket
(step
  "Narration associated with this step."
  form ...)
```

A `step` is a pedagogical unit.

It may:

- introduce new mathematical objects;
- change presentation state;
- highlight existing objects;
- perform several related actions.

Example:

```racket
(step
  "Draw a circle centred at A through B."
  [cA (circle A B)])
```

The string is narration or explanatory text associated with the step. It does not necessarily have to appear visually on screen.

The same construction may later be rendered:

- with narration;
- with subtitles;
- silently;
- with alternative textual presentation.

---

# 7. Bindings inside steps

A binding introduces a mathematical object.

```racket
[AB (segment A B)]
```

means:

> `AB` is the segment from `A` to `B`.

Because the binding appears in a `step`, the object is also introduced visually at that step.

This differs from:

```racket
(show AB)
```

which changes only the presentation state of an object that already exists.

---

# 8. Basic geometry forms

The first version should remain small.

Likely core forms include:

```racket
(point ...)
(segment A B)
(line A B)
(circle A B)
(intersection ...)
(intersections ...)
```

Additional forms should be introduced only as needed by actual constructions.

---

## 8.1 `point`

Explicit point:

```racket
(point 2 3)
```

Free point:

```racket
(point)
```

A free point is intended primarily for use as a given whose concrete realization will be selected by the layout system.

---

## 8.2 `segment`

```racket
(segment A B)
```

Creates the finite segment from `A` to `B`.

The distinction between `segment`, `line`, and later `ray` should be mathematically real. Intersection operations should respect it.

---

## 8.3 `line`

```racket
(line A B)
```

Creates the infinite line through points `A` and `B`.

For rendering, a line is clipped to the view. Its entire infinite extent is never required to fit.

---

## 8.4 `circle`

```racket
(circle A B)
```

means:

> the circle centred at `A` and passing through `B`.

This syntax deliberately resembles a compass construction rather than requiring:

```racket
(circle #:center A
        #:radius (distance A B))
```

The first version need not simulate a physical compass. It merely gives circles a pleasant canonical appearance animation.

The exact reveal animation is a renderer decision and is not part of the DSL semantics.

---

# 9. Intersections

## 9.1 One selected intersection

```racket
(intersection c1 c2 ...)
```

returns one geometrically selected intersection.

Because many pairs of objects may have more than one intersection, the DSL should support selectors that express geometric intent.

Examples:

```racket
(intersection c1 c2
              #:side-of AB 'left)
```

```racket
(intersection c l
              #:other-than A)
```

Possible future selectors include:

```racket
#:near P
#:far-from P
```

Coordinate-dependent selectors should be avoided when a geometric description is available.

---

## 9.2 All intersections

When both intersections are relevant:

```racket
[(C D) (intersections c1 c2)]
```

This destructuring form is natural for constructions such as the perpendicular bisector.

The implementation should define a deterministic ordering, even when authors do not normally rely on it.

---

# 10. Presentation state

Mathematical existence and visual visibility are separate.

An object may continue to exist mathematically after it has been hidden or deemphasized.

For example:

```racket
(hide cA)
```

does not destroy `cA`. It may still be used later:

```racket
[D (intersection cA l)]
```

The first version should distinguish persistent presentation state from temporary emphasis.

---

# 11. `initially`

```racket
(initially
  form ...)
```

Changes the presentation state before the first step.

By default, givens are shown at the beginning. `initially` provides an escape hatch when a different opening is desired.

Example:

```racket
(construction example
  (given
    [A (point -2 0)]
    [B (point  2 0)])

  (initially
    (hide A B))

  (step
    "Start with two points A and B."
    (show A B))

  ... )
```

`given` still describes the mathematics. `initially` changes only the presentation.

---

# 12. `show` and `hide`

```racket
(show A B)
(hide cA cB)
```

These operations make existing objects visible or invisible.

They are persistent state changes.

Suggested semantics:

- showing a hidden object animates its appearance;
- showing an already visible object is a no-op;
- hiding a visible object animates its disappearance;
- hiding an already hidden object is a no-op.

An authoring/debug mode may warn about redundant state changes.

---

# 13. `show-label` and `hide-label`

Point labels are usually inferred from binding names.

For example:

```racket
[A (point -2 0)]
```

normally produces a visible point labelled `A`.

Labels can be controlled independently:

```racket
(hide-label A B)
(show-label A B)
```

This is useful when auxiliary point names would clutter the final diagram.

Example:

```racket
(step
  "This is the perpendicular bisector of AB."
  (deemphasize cA cB)
  (hide-label C D)
  (highlight l))
```

---

# 14. `deemphasize` and `normalize`

Some objects should remain visible but recede into the background.

```racket
(deemphasize cA cB)
```

is a persistent state change.

The renderer may represent deemphasis using, for example:

- gray;
- lower opacity;
- thinner strokes;
- stippling or dashed strokes.

The construction source does not specify the exact graphic treatment.

To return an object to ordinary presentation:

```racket
(normalize cA cB)
```

`deemphasize` should not be confused with `highlight`.

---

# 15. `highlight`

```racket
(highlight AB AC BC)
```

is a temporary attention event rather than a persistent presentation state.

For example:

```racket
(step
  "This is the required equilateral triangle."
  (deemphasize cA cB)
  (highlight AB AC BC))
```

means:

1. leave the helper circles visible but secondary;
2. briefly draw attention to the triangle.

The exact highlight animation belongs to the renderer.

---

# 16. Multiple forms in a step

Forms in a step are normally performed in source order.

For example:

```racket
(step
  "Join C to A and B."
  [AC (segment A C)]
  [BC (segment B C)])
```

naturally draws `AC` and then `BC`.

If simultaneous animation is desired, a future or optional form may be:

```racket
(together
  [AC (segment A C)]
  [BC (segment B C)])
```

This should be introduced only if actual examples demonstrate the need.

---

# 17. `choose`

Some constructions contain arbitrary choices.

Example:

```racket
[A (choose (point-on l #:except P))]
```

This means:

> introduce a point `A` on `l`, different from `P`, chosen by the construction.

`choose` does not immediately select a random coordinate.

It introduces a constrained free object whose concrete realization is selected later.

This is essential because the system should consider the complete construction before deciding which choice produces a good diagram.

---

## 17.1 `choose` is deterministic

Given the same:

- construction;
- view;
- layout hints;
- rendering settings;

the same concrete realization should be selected.

`choose` is therefore not random by default.

---

## 17.2 Free givens versus `choose`

These are mathematically different.

```racket
(given
  [A (point)])
```

means:

> `A` is arbitrary input supplied by the problem.

Whereas:

```racket
[X (choose (point-on c))]
```

means:

> the construction is allowed to choose a suitable `X`.

Both may become unknowns in the realization problem, but their mathematical provenance differs.

---

# 18. `layout`

```racket
(layout
  hint ...)
```

provides presentation/layout guidance without changing the mathematics.

For example:

```racket
(layout
  (focus A B C D P)
  (prefer (distance A P) 1.5))
```

Layout hints should normally be **soft preferences**.

The layout system is free to violate them when necessary to produce a valid and readable diagram.

---

## 18.1 `focus`

```racket
(layout
  (focus A B C D P))
```

means approximately:

> these objects form the visual core of the construction; prefer a realization and framing in which they are comfortably visible and well balanced.

It does not necessarily mean that their exact bounding box should fill the frame.

---

## 18.2 `prefer`

```racket
(layout
  (prefer (distance A P) 1.5))
```

means:

> a distance around `1.5` is aesthetically desirable, but not mathematically required.

A preference is not a theorem and is not part of the construction's correctness.

---

## 18.3 Future hard layout constraints

A stronger escape hatch may eventually be useful.

For example:

```racket
(layout
  (constrain (< (distance A P) 2)))
```

This should remain separate from mathematical `require`.

- `require` states a precondition of the construction.
- `constrain` would state a hard condition on one rendered realization.

Such a feature should be added only when needed.

---

# 19. Layout is based on semantic relevance

The layout system should not simply try to fit the entire geometric extent of every object.

For example, in a perpendicular construction, helper circles may extend far outside the frame. Only the relevant portions near important points and intersections need to remain legible.

The guiding principle is:

> Fit the semantically relevant parts of the construction, not necessarily the complete extents of its geometric objects.

Examples:

| Object | Typical visibility obligation |
|---|---|
| Point | Point and relevant label |
| Segment | Endpoints and segment |
| Line | Relevant incidences; remaining line clipped |
| Ray | Origin and relevant incidences; remaining ray clipped |
| Circle | Center, defining points, intersection points, and relevant arcs |
| Intersection | Point plus enough of the intersecting objects to make the incidence legible |

The construction dependency graph should help infer these obligations automatically.

---

# 20. Anonymous geometry

Not every object needs a name.

For example:

```racket
[given-line
 (line (point -3 0)
       (point  3 0))]
```

The nested points may exist only to realize the line. They need not be independently shown or labelled.

A useful rule is:

> Named bindings are author-visible construction objects. Nested expressions may create anonymous supporting geometry.

---

# 21. Example: perpendicular bisector

```racket
(construction perpendicular-bisector
  (given
    [A (point -2 0)]
    [B (point  2 0)])

  (step
    "Start with the segment AB."
    [AB (segment A B)])

  (step
    "Draw a circle centred at A through B."
    [cA (circle A B)])

  (step
    "Draw a circle centred at B through A."
    [cB (circle B A)])

  (step
    "The two circles meet at C and D."
    [(C D) (intersections cA cB)])

  (step
    "Draw the line through C and D."
    [l (line C D)])

  (step
    "This is the perpendicular bisector of AB."
    (deemphasize cA cB)
    (hide-label C D)
    (highlight l)))
```

This example motivates:

- `intersections`;
- destructuring bindings;
- `deemphasize`;
- independent label control.

---

# 22. Example: perpendicular through a point on a line

```racket
(construction perpendicular-through-point
  (given
    [l (line (point -3 0)
             (point  3 0))]
    [P (point 0 0)])

  (require
    (on P l))

  (layout
    (focus P))

  (step
    "Choose a point A on the line."
    [A (choose (point-on l #:except P))])

  (step
    "Draw a circle centred at P through A."
    [cP (circle P A)])

  (step
    "Let B be the other intersection with the line."
    [B (intersection cP l #:other-than A)])

  (step
    "Draw equal circles centred at A and B."
    [cA (circle A B)]
    [cB (circle B A)])

  (step
    "The circles meet at C and D."
    [(C D) (intersections cA cB)])

  (step
    "Draw the line through C and D."
    [m (line C D)])

  (step
    "This is the perpendicular to l through P."
    (deemphasize cP cA cB)
    (hide-label A B C D)
    (highlight m P)))
```

This example motivates:

- `choose`;
- `#:other-than`;
- `require`;
- global realization and layout.

---

# 23. Reusable constructions

A construction may be abstracted and reused as a helper in later videos.

Reusable constructions are defined with `define-construction`.

The inputs are typed explicitly.

Example:

```racket
(define-construction perpendicular-bisector
  (given [A : Point]
         [B : Point])

  (results Line)

  (require
    (distinct? A B))

  (step
    "Draw a circle centred at A through B."
    [cA (circle A B)])

  (step
    "Draw a circle centred at B through A."
    [cB (circle B A)])

  (step
    "The circles meet at C and D."
    [(C D) (intersections cA cB)])

  (step
    "Draw the line through C and D."
    [m (line C D)])

  (result m))
```

The public contract is:

```racket
(given [A : Point]
       [B : Point])

(results Line)
```

The final:

```racket
(result m)
```

identifies the object that supplies the declared result.

The implementation should check that `m` really has type `Line`.

---

# 24. Types in `define-construction`

Input types are mandatory for reusable constructions.

A likely initial type vocabulary includes:

```text
Point
Segment
Line
Ray
Circle
```

Possible future types include:

```text
Arc
Angle
Polygon
Length
Number
```

Types make reusable constructions checkable before rendering.

For example:

```racket
(perpendicular-bisector some-circle A)
```

should be rejected because the helper expects two `Point`s.

Local bindings may have inferred types.

For example:

```racket
[cA (circle A B)]
```

naturally gives:

```text
cA : Circle
```

---

# 25. Multiple results

A reusable construction may later support several results.

For example:

```racket
(results Point Point Line)
```

paired with:

```racket
(result C D l)
```

A caller could then use destructuring:

```racket
[(C D l) (some-construction ...)]
```

Named public results may eventually be useful, but positional results are sufficient for the first version.

---

# 26. Using one construction inside another

Suppose `perpendicular-bisector` has already been defined:

```racket
(define-construction perpendicular-bisector
  (given [A : Point]
         [B : Point])
  (results Line)
  ...)
```

A later construction can use it:

```racket
(construction circumcenter
  (given
    [A (point)]
    [B (point)]
    [C (point)])

  (require
    (noncollinear? A B C))

  (step
    "Construct the perpendicular bisector of AB."
    [m1 (perpendicular-bisector A B)])

  (step
    "Construct the perpendicular bisector of BC."
    [m2 (perpendicular-bisector B C)])

  (step
    "Their intersection is the circumcenter."
    [O (intersection m1 m2)]))
```

This allows later videos to use previously taught constructions as higher-level operations.

---

# 27. Collapsed versus expanded helper constructions

A reusable construction should retain its internal construction graph.

That makes two presentation modes possible.

Collapsed use:

```racket
[m1 (perpendicular-bisector A B)]
```

may present the helper as one known operation.

Expanded use could eventually be requested explicitly:

```racket
(expand
  [m1 (perpendicular-bisector A B)])
```

and replay its internal construction steps.

This allows a series of videos to build a library of known techniques without losing the ability to show their internals when needed.

The exact surface syntax for expansion is provisional.

---

# 28. Layout across helper constructions

Choices made inside helper constructions should not be realized independently.

Instead, the outer construction should be able to solve all free givens and `choose` forms jointly.

Conceptually:

```text
outer free givens
        +
choices in helper 1
        +
choices in helper 2
        +
outer layout hints
        +
view
        ↓
one global realization
```

This avoids local choices that later produce a poor global composition.

Layout hints inside reusable helpers should be weak defaults. Outer layout guidance should be able to dominate them.

---

# 29. Canonical reveal animations

The DSL describes semantics, not exact animation mechanics.

Each geometry type can have a default reveal animation.

Possible defaults:

| Object | Default reveal |
|---|---|
| Point | Fade/scale in, then label |
| Segment | Stroke from first endpoint to second |
| Line | Grow through defining points |
| Circle | Animated stroke around circumference |
| Intersection point | Subtle emphasis/fade-in |
| `hide` | Fade out |
| `highlight` | Temporary emphasis |

For circles, one possible future animation is to begin at the non-center defining point and draw around the circumference in both directions.

This is deliberately postponed. The DSL should not depend on the exact reveal style.

---

# 30. Persistent state versus transient events

A useful semantic distinction is:

## Persistent presentation state

```racket
show
hide
show-label
hide-label
deemphasize
normalize
```

These change the scene state until changed again.

## Transient events

```racket
highlight
```

These temporarily draw attention and then return objects to their previous persistent state.

This distinction should be preserved in the implementation.

---

# 31. Construction graph and realization

A construction should first be compiled into an abstract dependency graph.

Example:

```text
A, B
 │
 ├── AB
 │
 ├── cA
 │
 └── cB
      │
      ├── C
      └── D
           │
           └── l
```

Only after the complete construction is known should `animate` choose concrete values for:

- free givens;
- `choose` objects;
- layout variables.

This avoids greedy local choices that later produce poor diagrams.

---

# 32. Realization and scoring

A first implementation does not require a sophisticated symbolic constraint solver.

For simple choices, the system may:

1. generate a deterministic set of candidate realizations;
2. construct the resulting geometry;
3. reject invalid candidates;
4. score the remaining candidates;
5. choose the best one.

Possible hard requirements:

- mathematical preconditions hold;
- required intersections exist;
- important points are visible;
- labels fit safely.

Possible soft preferences:

- important geometry occupies a healthy fraction of the view;
- labels do not collide;
- important features are not tiny;
- important incidences stay away from the frame edge;
- arbitrary givens avoid visually misleading special cases;
- diagrams are balanced.

---

# 33. Avoiding accidental special cases

When realizing arbitrary givens, layout may prefer generic-looking instances.

For example, an arbitrary segment need not always be perfectly horizontal.

A slight rotation may better communicate that the construction is general.

The layout system may therefore have weak default preferences against accidental:

- horizontalness;
- verticalness;
- symmetry;
- tangency;
- coincident labels;
- tiny angles;

unless such properties are mathematically intrinsic or pedagogically useful.

---

# 34. Suggested first-version core

The first useful version could consist of:

## Structure

```racket
construction
define-construction
given
results
result
require
layout
initially
step
```

## Geometry

```racket
point
segment
line
circle
intersection
intersections
```

## Choice and layout

```racket
choose
focus
prefer
```

## Presentation

```racket
show
hide
show-label
hide-label
deemphasize
normalize
highlight
```

Everything else should be added only after a real construction demonstrates a need.

---

# 35. Things deliberately postponed

The first version does **not** need:

- physical compass rendering;
- physical straightedge rendering;
- detailed per-object animation syntax;
- arbitrary style commands embedded in constructions;
- sophisticated camera scripting;
- a full constraint solver;
- refinement types for every geometric relation;
- named multi-results;
- proof automation;
- automatic theorem derivation;
- explicit auxiliary-object declarations;
- a large library of primitive constructions.

These may become valuable later, but they should not obscure the core model.

---

# 36. Summary

The central idea is:

> Geometry expressions say what objects are.  
> `step` says when the audience learns about them.  
> Presentation commands say how visible or prominent they are.  
> `layout` guides how abstract geometry is realized for the view.

This gives constructions a useful life beyond one animation.

They can become:

- reusable mathematical helpers;
- inspectable dependency graphs;
- sources for different animation styles;
- foundations for later higher-level constructions;
- potentially, eventually, foundations for mathematical explanation and proof-oriented authoring.

The DSL should therefore remain semantic first and graphical second.
