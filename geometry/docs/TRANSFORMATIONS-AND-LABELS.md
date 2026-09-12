# Transformations and semantic labels — v0.9.1

## Mathematical images, not animation transforms

These operations construct **new geometry**. The original object is unchanged.
The new object can be intersected, used in assertions, labelled, passed to a
construction helper, and shown using its ordinary reveal policy. A rotation
operation does not animate an object travelling around its centre.

Within a `construction` or `define-construction`:

```racket
[Ap (reflect A l)]
[Bp (rotate B O (degrees 60))]
[Cp (translate C (vector 4 0))]
[Dp (dilate D O 2)]
```

Coordinates, vector components and label distances use local world units.
Angles supplied to `rotate` and `rotation` use radians. `(degrees 60)` explicitly
converts degrees to radians; `60deg` is not DSL syntax. Positive rotation is
counterclockwise in the mathematical Cartesian plane.

## Reusable transformations

A `Transform` is an immutable, nondrawable similarity. A `Vector` is an immutable,
nondrawable displacement, distinct from a Point.

```racket
[v (vector-between A B)]
[T (translation v)]
[R (rotation O (degrees 90))]
[M (reflection l)]
[D (dilation O 3/2)]

[A2 (transform T A)]
[AB2 (transform T AB)]
[k2 (transform T k)]
```

| Expression | Type and meaning |
|---|---|
| `(vector dx dy)` | Vector with finite components. |
| `(vector-between A B)` | Vector B − A. |
| `(vector-x v)`, `(vector-y v)` | Number components. |
| `(identity-transform)` | Identity Transform. |
| `(translation v)` | Translation by Vector v. |
| `(rotation O theta)` | Rotation about Point O, in radians. |
| `(reflection l)` | Reflection in an infinite Line. |
| `(dilation O k)` | Dilation about O by finite, nonzero k. |
| `(compose-transform T S ...)` | Composition, **rightmost first**. No arguments gives identity. |
| `(inverse-transform T)` | Inverse Transform. |
| `(transformation-scale T)` | Positive length factor. |
| `(transformation-orientation T)` | +1 for orientation-preserving, −1 for reversing. |
| `(transform T object)` | The image, retaining the object's type. |

The direct forms `translate`, `rotate`, `reflect`, and `dilate` put the object
first; `transform` puts the reusable Transform first.

For example:

```racket
[T (compose-transform
     (translation (vector 4 0))
     (rotation O (degrees 90)))]
[A2 (transform T A)]   ; first rotate about O, then translate
[undo (inverse-transform T)]
```

Negative dilation is allowed: it places an image point on the opposite ray from
the centre and scales its distance by `abs(k)`. In two dimensions this still
preserves orientation. Zero is rejected because it would collapse lines, rays,
circles and angles to points. Overflow, underflow to a singular transformation,
and degenerate defining geometry are errors, not silent type changes.

`reflection` requires a Line. To reflect in the supporting line of a segment,
write `(line (start-point AB) (end-point AB))` explicitly.

## Supported image types

Point, Segment, Line, Ray, Circle, Angle, Relation and Marker are supported.
A ray's origin and defining direction are transformed together. A circle's
centre and defining circumference point are transformed together; its radius
is multiplied by the Transform's positive length factor. An Angle keeps its
middle-point vertex. Reflection reverses its signed sweep but preserves its
unsigned measure.

Relation and Marker values are transformed semantically by mapping their
underlying geometry. A transformed Marker is redrawn at the current theme's
annotation sizes; its glyph strokes are not stretched. A false Relation is not
made true by transforming it. Use `assert` to check a claim as before.

Only similarities are supported: there is no shear or nonuniform scale and no
ellipse-valued image of a circle. Transformation, Number, Text, Vector and Label
values cannot themselves be transformed by `transform`.

Source styling, labels, display names, and reveal hints do not silently transfer
to an image. The new object has its own identity and ordinary type defaults.
Use `style`, `reveal`, and labels on that new object. The eight standard
straightedge/compass constructions still use their original construction
algorithms; these operations do not replace them with coordinate shortcuts.

## Procedural entry points

The tables above describe the checked DSL. `core.rkt` and `main.rkt` re-export
both new modules; they can also be required separately:

```racket
(require "geometry/transformations.rkt" "geometry/labels.rkt")
```

Outside the DSL, use `(geometry-vector dx dy)` and the accessors
`geometry-vector-x` / `geometry-vector-y`. Racket's own `vector` remains its
ordinary vector constructor. The other transformation and label procedures use
the same names and argument order as the DSL forms. An ordinary angle value is
constructed with `angle-spec`, not the DSL-only `angle` expression. Typed helper
values are still invoked within a construction, not as ordinary procedures.

## Typed helper composition

Transforms and labels can be helper inputs or results. Text is also a type, so
label text can be supplied by a caller rather than embedded in helper code.

```racket
(define-construction labelled-image
  (given [source : Segment]
         [mapping : Transform]
         [name : Text])
  (results Segment Label)
  (step "Construct and label the image."
    [image (transform mapping source)]
    [caption (length-label image name)])
  (layout (label-position caption 0.4))
  (result image caption))

;; Within a caller:
(step "Construct the reflected segment."
  (expand [(AB2 length-name)
           (labelled-image AB (reflection l) "a′")]
          #:auxiliaries 'hide))
```

The output aliases retain the helper's annotation hints. Transform, Vector and
Text bindings do not produce visual actions or consume an action duration.
A narrated step can still have a reading delay and ending pause.

## Four kinds of semantic label

A `Label` is a first-class, drawable annotation attached to geometric data.
It is not a point or curve and cannot be used as an intersection operand.

```racket
[name-A (point-label A "A′")]
[base-note (segment-label AB "5 cm")]
[a (length-label BC "a")]
[alpha (angle-label (angle B A C) "α")]
```

A label can be returned from a helper, shown or hidden, highlighted, or given
its own theme/style. Its position is found by the shared annotation planner,
not entered as a text coordinate. Text stays upright and horizontal beside a
sloping segment or reflected figure.

An `angle-label` draws a single indicating arc by default. This arc does **not**
assert equality with other angles. For matching equality notation use an
`equal-angle` marker as before, and suppress the label's additional arc:

```racket
[alpha (angle-label (angle B A C) "α" #:arc? #f)]
```

An angle label requires a nondegenerate minor angle strictly between 0 and 180
degrees, with the geometry tolerance applied near the endpoints. Right angles
are allowed and measured as 90°; use a perpendicular marker when a square is the
appropriate notation.

## Computed measurements

Omit the text to display a measurement taken from the target:

```racket
[a-value (length-label BC #:precision 2 #:unit "cm")]
[alpha-value (angle-label (angle B A C) #:precision 1)]
```

Lengths default to two decimal places; angles default to zero decimal places
and a degree symbol. `#:precision` must be an exact integer from 0 to 12.
Decimal formatting uses Racket's `real->decimal-string`, including its rounding;
precision zero is normalized to omit any trailing decimal point.
rule and fixed number of decimal places.

A unit is a **display suffix**, not a conversion. Saying `#:unit "cm"` assumes
that a world-unit length is to be interpreted as a centimetre. There is no unit
algebra in this release. Text must be a nonempty single line without tabs.

Authored text is authoritative: `(segment-label AB "5 cm")` and
`(length-label AB "a")` do not assert a numerical length. With explicit text,
formatting precision has no effect and `#:unit` is rejected; include any units
in the text itself. The numeric form is the one to use when the displayed
measurement must follow the geometry.

Formatting is resolved when the geometry is realized. Changing a given and
realizing the construction again recomputes dependent label values. It is not a
per-frame numeric updater.

To label an image, label its transformed target:

```racket
[AB2 (dilate AB O 2)]
[length-AB2 (length-label AB2 #:precision 1)]
```

The lettering is not scaled or mirrored. The length is measured from AB2.

## Independent labels versus automatic names

Points still have automatic name labels. An independent `point-label` does not
silently suppress that name or rename the point in structured captions:

```racket
(initially (hide-label A))
(step "This point is A′."
  [name-A (point-label A "A′")])
```

For a simple rename with no independent annotation lifetime, keep using:

```racket
(layout (label-text A "A′"))
```

That existing form also supplies the point's name in structured captions. Label
identifiers in captions are identifiers, not live substitutions of computed
measurement text; refer to geometry or use authored text for those explanations.

`hide name-A` hides the Label. `hide-label name-A` hides only its text; for an
angle Label the indicating arc remains until the whole Label is hidden.
Showing/hiding the target does not cascade to independent Labels, just as it
does not cascade to independent Markers. This permits a dimensional annotation
to remain while a helper curve is removed. Authors control both explicitly.

## Placement

The native adapter measures text using Animate's existing text/Pict path. The
pure core can use estimated metrics. Both use the same placement rules and
co-visibility information. Labels reserve ink space against points, curves,
markers, other labels and the caption band.

Length and segment labels try several fractions along the target and both sides
of its normal. The text is not rotated. Angle labels remain on the angular
bisector, with alternative radial distances. Their optional arcs participate
in the same planner. Point labels use candidates around their target point.

Positions are chosen once and remain fixed through hide/show, highlighting,
review sampling, and out-of-order frame access.

```racket
(layout
  (label-outside-of a A) ; a is attached to BC, outside triangle ABC
  (label-position a 0.4)
  (marker-radius alpha 0.34)
  (label-offset name-A (point -0.4 0.1)))
```

`label-position` applies to length/segment Labels only. Its fraction must be
strictly between 0 and 1, measured from the segment's first endpoint.

For a triangle, side labels conventionally sit outside. `label-outside-of`
expresses this geometrically: the named Point lies on the inside half-plane and
the Label is constrained to the opposite half-plane. For triangle `ABC`, use
`(label-outside-of a A)` for a label on `BC`, `(label-outside-of b B)` for `CA`,
and `(label-outside-of c C)` for `AB`. The reference point must not be collinear
with the labelled segment. An explicit non-`auto` `label-side` cannot be combined
with the outside constraint.

`label-offset` now accepts Label as well as Point. For a Label it is relative
to the target point, segment midpoint, or angle vertex. An exact relative pin
wins over automatic `label-position` and side preferences. As before, an
absolute `label-at` overrides a relative pin, and an adapter `#:labels` override
has the highest priority.

`marker-radius` accepts an angle Label, including one with its arc suppressed,
and controls the radial starting point for its placement. Other marker-specific
hints continue to require the corresponding Marker type.

`label-text` can override a Label's displayed text as a presentation escape
hatch. Such an override intentionally replaces even a computed measurement;
it is not a numerical assertion.

The planner is heuristic. Impossible pins and very crowded/narrow-angle diagrams
can still produce explicit overlap/outside-safe-area warnings. It does not move
the underlying mathematical geometry or invent a claim to make labels fit.

## Themes and drawing order

```racket
(geometry-theme
  (label [font-size 0.28])
  (semantic-label [offset 0.14])
  (length-label (label [font-style italic]))
  (angle-label [radius 0.28] (stroke [width 2])))
```

Available selectors are `semantic-label`, `point-label`, `segment-label`,
`length-label`, and `angle-label`. Generic text defaults form the base, followed
by semantic-label, then the specific kind, then state rules and explicit object
styles. Font sizes, offsets and arc radii remain world lengths; stroke widths
remain Animate's cosmetic widths. No new font or color palette is bundled.

First-class Labels are drawn after geometric objects so later support lines
cannot paint over their text. The existing line/ray-behind-segment order,
right-angle sizes and shortened equality ticks are unchanged.

## Examples, review and tests

New standalone examples: `transformations.rkt` and `semantic-labels.rkt`. The
gallery also contains all four transformation kinds and symbolic/numeric labels.
All support light/dark themes, review triplets, ordinary videos and process
workers. The review registry now has **19 examples**; `--library` still means
the thirteen compass-and-straightedge applications.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --transform-labels
"$RACKET" geometry/run-tests.rkt
"$RACKET" geometry/review-examples.rkt --example transformations --both --output geometry-review-v091
"$RACKET" geometry/review-examples.rkt --example semantic-labels --both --output geometry-review-v091
"$RACKET" geometry/review-examples.rkt --example gallery --both --output geometry-review-v091
```

For a video:

```sh
"$RACKET" geometry/examples/transformations.rkt --dark --workers 10 \
  --mp4 geometry-output/videos/dark/transformations.mp4 geometry-output/dark/transformations
```

See `TRANSFORMATIONS-AND-LABELS-PLAN.md` for the implementation plan and
`TRANSFORM-LABEL-VALIDATION.md` for what was actually executed.
