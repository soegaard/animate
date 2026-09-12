# Compass-transfer circle reveal — v0.9.8

## v0.9.7 choreography

The temporary radius carrier now follows a six-part teaching sequence: draw it
over the source measure, lift it to a nearby parallel, pulse an attention halo,
transport it rigidly to the new centre, pulse again on arrival, then sweep the
circle. The automatic compass action lasts 10.0 seconds unless action duration is
explicitly overridden. The carrier is solid; a separate wide translucent
`compass-attention` under-stroke creates the two glow-like pulses.

The implementation remains pure and random-access. The pulse strength, carrier
position, and partial circle are all direct functions of reveal progress.


## Goal

When a circle radius comes from a length already represented by geometry, show
where that radius comes from instead of immediately sweeping a synthetic circle.
The mathematical object remains an ordinary `Circle`; only its first reveal is
special.

## Author API

No new syntax is required for the normal case:

```racket
[c (circle O #:radius (length AB))]
[d (circle P #:radius (distance A B))]
[r (length AB)]
[e (circle Q #:radius r)]
```

These use compass transfer automatically. A two-point `(circle O P)` retains the
ordinary two-front reveal. Explicit control is available with:

```racket
(reveal [c compass] [d bidirectional])
```

Forcing `compass` on a two-point circle uses `OP` as its source measure. Forcing
it on a literal or otherwise source-free radius is an error.

## Radius provenance

The renderer follows immutable compiler nodes through Number aliases and helper
argument/result aliases. Automatic provenance recognizes only:

- `(length segment-expression)`
- `(distance point-expression point-expression)`

Arbitrary arithmetic such as `(* 2 (length AB))`, `(+ r 1)`, and literal radii
fall back to the ordinary reveal. This prevents the presentation layer from
inventing a geometric source for an arbitrary numerical value.

## Animation

The automatic transfer uses a deliberately slow six-part choreography. With the
default **10.0 second** compass action:

1. **pickup** — draw a solid movable carrier directly over the source measure;
2. **parallel lift** — move it a small distance to a line parallel to the source;
3. **source attention** — pulse a wide translucent highlight under the carrier;
4. **transport** — move the carrier rigidly to the new circle centre;
5. **target attention** — pulse the highlight again after arrival; and
6. **sweep** — rotate the carrier counterclockwise while its tip traces the circle.

The carrier length and direction remain fixed during the parallel lift and
transport. The offset side is chosen from the two perpendicular directions using
the realized view and caption band, preferring the side that stays visible and
out of the caption area. At the target, the carrier orientation is chosen so the
early sweep is also likely to stay in view.

The attention pulse is a geometry-local equivalent of Animate's temporary
attention vocabulary: the frame sampler adds a wide translucent
`compass-attention` under-stroke whose opacity follows a single pulse. This keeps
the entire geometry timeline pure and random-access; no scene mutation or
frame-to-frame effect state is introduced.

The guide fades during the last part of the sweep. At progress 1 it has zero
opacity and the mathematical circle is complete. The source geometry never
moves.

## Architecture

`private/reveal.rkt` owns the pure/random-access semantics:

- `compass-source`
- `compass-reveal-state`
- `resolve-compass-source`
- `resolve-circle-reveal`
- `compass-circle-reveal`

`animate.rkt` resolves provenance once when preparing the scene and renders the
transient guide separately from the circle. The guide is not inserted into the
geometry graph and therefore cannot affect layout, intersections, assertions,
labels, helper results, or final state.

The semantic selectors `compass-guide` and `compass-attention` control the solid movable carrier and its wide translucent attention halo.

## Interaction with presentation state

Only a fresh `reveal` plays the compass transfer. Later `show`/`hide` operations
work on the complete circle and never replay the guide. Static-frame reuse is
unchanged: only the reveal interval is dynamic.

## Standard-library impact

The feature applies automatically to existing transferable-compass operations.
In particular:

- `copy-segment` transfers `(length source)`;
- `copy-angle` transfers `(distance B U)` and `(length chord)`.

Their mathematical construction code does not change. Standard copying helpers
also mark their construction circles with `fit-circle` so large auxiliary
circumferences participate in camera fitting.

Review bundles emit dedicated `pickup`, `source-attention`, `transport`,
`target-attention`, and `sweep` stills for each compass-circle step. These
positions are defined in reveal-progress space; the planner inverts the
timeline's smoothstep easing before choosing timestamps.

## Validation

Base-only checks verify:

- exact carrier length during pickup, parallel lift, transport, and sweep;
- deterministic parallel offset and transport;
- peak source/target attention pulses;
- equality of the moving guide tip and partial-circle endpoint;
- a full `2π` final sweep and zero guide opacity at completion;
- length/distance/Number-alias provenance;
- helper alias propagation;
- ordinary two-point fallback;
- explicit compass mode and source-free diagnostics; and
- independent light/dark guide styling.

Native integration additionally checks that `c/compass-guide` exists during the
transfer, that `c/compass-attention` exists at an attention peak, and that both
are absent from the settled frame.
