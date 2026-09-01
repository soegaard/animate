# Visual Animation House Style

This project follows the existing Geo application’s Racket style. The Geo
modules `construction-model.rkt`, `construction-geometry.rkt`,
`tool-controller.rkt`, `jsxgraph-adapter.rkt`, and `geometry-page.rkt` are the
authoritative examples when this guide leaves room for interpretation.

The central rule is:

> Keep semantic model and timeline code pure, explicit, immutable, and
> deterministic. Isolate rendering and external effects behind adapters.

## 1. Module shape

Use a short module title and responsibility paragraph before imports.

```racket
#lang racket/base

;;;
;;; Scene State Model
;;;

;; Defines immutable snapshots of the visuals present in a scene.
;;
;; This module contains no pict, bitmap, filesystem, process, or browser
;; dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require ...)

;; Exports
(provide ...)
```

Use named sections for groups of related definitions:

```racket
;;;
;;; Data Representation
;;;

;;;
;;; Timeline Sampling
;;;

;;;
;;; Validation
;;;
```

Module boundaries should describe real responsibilities, not merely keep files
small.

## 2. Naming

Use kebab-case Racket names.

- Predicates end in `?`: `scene?`, `finite-real?`, `clip-contains?`.
- Observable mutation or external effects end in `!`: `render-frames!`,
  `delete-old-frames!`, `encode-mp4!`.
- Pure immutable updates do **not** end in `!`: `scene-add`,
  `scene-state-update`, `visual-with-position`.
- Clear conversions use `x->y`: `visual->pict`, `scene-state->pict`,
  `frame-index->time`, `scene-frame->bitmap`.
- Prefer domain names such as `visual`, `state`, `clip`, `camera`, and `scn`
  over generic names such as `value`, `data`, `table`, and `item`.
- Use a short conventional name such as `st` or `scn` when the full name would
  shadow a structure binding needed by `struct-copy`.

## 3. Function documentation

Give every top-level constant and function a contract comment followed by one
brief purpose sentence.

```racket
; frame-index->time : exact-nonnegative-integer?
;                     [#:fps exact-positive-integer?]
;                     -> nonnegative-real?
;;   Converts a zero-based frame index to its exact sample time.
(define (frame-index->time frame-index #:fps [fps 30])
  ...)
```

For a constant:

```racket
; origin : vec2?
;;   Gives the origin of world coordinates.
(define origin
  (vec2 0 0))
```

Document tiny local helpers only when their role or accepted values are not
obvious. Do not narrate straightforward implementation steps.

Comments should explain semantic meaning, invariants, ordering, or a
non-obvious constraint. Avoid comments such as “increment the counter” or
“loop over the list.” Source comments do not replace the public Scribble
reference entries required by Section 15.

## 4. Structure documentation

Place field documentation immediately after each structure definition.

```racket
(struct scene-state (visuals-by-id drawing-order)
  #:transparent)

;; scene-state represents one immutable scene snapshot.
;;  - visuals-by-id  immutable hash?   maps ids to Visual values.
;;  - drawing-order  (listof symbol?)  ids in back-to-front painting order.
;;                                    Ordering is significant.
```

For every field, document:

- its expected kind of value;
- its semantic role;
- whether ordering is significant;
- any identity or immutability invariant.

Do not rely on a vague field name such as `order` when
`drawing-order` communicates the invariant directly.

When a structure has validated invariants, do not expose a raw constructor that
can bypass them. Export its predicate and accessors explicitly, and provide a
validated construction function instead. A structure guard is also acceptable
when direct construction is intentionally part of the public API.

## 5. Imports and exports

Use explicit `provide` forms. Public modules should expose only the intended
API.

Use focused `require`s:

- require focused local modules normally;
- use `only-in` when importing a few bindings from a broad external module;
- use `prefix-in` when two modules have overlapping or potentially confusing
  vocabularies;
- inside a `#:methods` body, use `define/generic` when a method forwards to a
  contained value; calling the method name directly would call the current
  implementation recursively instead of redispatching;
- do not import a rendering or effect module into a pure model module.

A public re-export module may group names by responsibility:

```racket
(provide
 ;; Geometry
 ...

 ;; Visual model
 ...

 ;; External output
 render-frames!
 encode-mp4!)
```

## 6. Pure model and adapter boundaries

The intended dependency direction is:

```text
geometry
   ↓
affine transforms
   ↓
Visual model, arrows, axes, semantic text, formulas, formula correspondence,
and groups
   ↓
formula-part transition planning, scene state, animation, and timeline
   ↓
Pict renderer protocol and adapters
   ↓
frame renderer
   ↓
PNG renderer / video encoder
```

The following modules must remain pure and deterministic:

- geometry;
- affine-transform data and interpolation;
- camera data and coordinate conversion;
- Visual data, identity, semantic opacity, arrows, Cartesian axes, plain text,
  formulas, formula assemblies, and group hierarchy;
- formula-part transition plans and samples;
- scene-state data;
- animation requests and interpolation;
- timeline construction and sampling.

Pure modules must not depend on:

- `pict`;
- bitmap classes;
- filesystem APIs;
- process execution;
- FFmpeg;
- browser or JavaScript APIs.

`Visual` values are the semantic model. A pict is one rendered representation
of a Visual, not the Visual itself.

## 7. Pict renderer protocols

Renderer extension belongs in the adapter layer, not in the semantic `Visual`
protocol.

- Define backend-specific renderer interfaces in dedicated adapter modules.
- Keep built-in renderer implementations separate from the pure Visual model.
- Pass renderer sets explicitly as immutable ordered values; do not mutate a
  process-global renderer registry.
- Renderer order is significant. The first renderer that reports support for a
  Visual is selected.
- A support method must return a boolean, and a Pict renderer must return a
  pict. Validate both invariants at the protocol boundary.
- Propagate an explicit `#:renderers` argument through scene, frame, and output
  adapters so third-party Visuals work at every rendering level.
- Custom renderers may precede the defaults to override a built-in
  representation deliberately.
- Apply optional semantic opacity after renderer dispatch or group composition
  so custom renderers do not need to duplicate global-opacity handling.
- When no explicit renderer supports a built-in group, compose its children in
  the Pict adapter and pass the same explicit renderer list to every descendant.
- Let an explicit renderer that supports a group override built-in recursive
  composition according to the ordinary first-supporting-renderer rule.
- Keep plain-text content, font requests, and anchor choices in a pure model
  module. Construct platform fonts and Pict text only in the adapter layer.
- Interpret semantic text size in local world units and convert it through the
  camera before applying the Visual's affine scale and rotation.
- Keep the selected text anchor at the center of the local Pict used by scene
  and group placement. Resolve alignment before affine scale and rotation.
- Render built-in arrows and axes by deriving ordinary semantic path geometry
  and passing it through the shared path backend. Keep arrow tips and axis ticks
  out of Pict-specific model data.
- Treat arrow-tip and axis-tip dimensions as local world-unit geometry. Keep
  shaft, tick, and tip outline widths cosmetic and independent of semantic
  scale.
- Keep LaTeX formula source, mode, preamble, options, size, and anchor data in a
  pure model module. Invoke `latex-pict`, `pdflatex`, and Poppler only from a
  rendering adapter.
- Load external formula typesetting only when a nonempty formula is rendered.
  Empty formula source must produce stable transparent local geometry without
  launching TeX.
- Treat formula option order as significant and copy mutable source, preamble,
  and option strings into immutable model storage.
- Calibrate formula font size against the selected 10pt, 11pt, or 12pt
  document-class base, then resolve the anchor before affine scale and rotation.
- Keep deterministic formula tests independent of external TeX by injecting a
  fixed typesetter or custom renderer. Put real TeX integration tests in a
  separate optional environment-dependent suite.
- Opacity must preserve the rendered Pict's width, height, and anchor. A zero-
  opacity Visual remains a semantic scene participant until it is removed.

## 8. Renderer-aware relative layout

Relative layout belongs at the rendering-adapter boundary when dimensions
come from Pict, platform fonts, LaTeX, groups, or custom renderers.

- Keep layout-box values in mathematical containing coordinates with positive y
  upward. Store edges as left, bottom, right, and top.
- Measure the complete centered local Pict produced by the selected coordinate
  camera and explicit renderer list. Convert its pixel dimensions back to the
  containing coordinate units through that same camera scale.
- Call the result a render box, not an ink bound. Symmetric anchor padding,
  transparent reserved space, and group-compositor extents are significant.
- Apply layout to immutable Visual values by replacing only reference position.
  Validate that custom `visual-with-position` methods preserve identity and
  install the requested position.
- Measure gaps between render-box edges in nonnegative containing-coordinate
  units. Keep horizontal and vertical alignment symbols explicit and separately
  validated.
- Preserve list order in horizontal and vertical arrangements. Leave the first
  Visual fixed unless the caller explicitly requests union centering.
- Permit empty layout lists. Their union box is false, and centering or
  arrangement returns an empty list without inventing geometry.
- Pass `#:camera` and `#:renderers` through every public measurement and layout
  operation. Use the same values for layout and final rendering.
- Document that measuring nonempty formulas can invoke `latex-pict`, LaTeX, and
  Poppler. Font, TeX, camera, or custom-renderer changes may change layout.
- Test formula layout with deterministic injected renderers. Do not make the
  mandatory suite depend on one external TeX or font installation.
- Do not place Pict values, cached metrics, renderer objects, or process state in
  the semantic Visual model merely to support layout.
- Measure arrows and axes through the selected renderer like every other Visual.
  Their tips, ticks, stroke padding, and deliberate custom-renderer padding are
  part of the complete render box.

## 9. Identity and ordering

Visual identity must be explicit or allocated inside a deterministic scene
builder. Do not use a process-global mutable id counter.

```racket
(circle #:id 'moving-circle
        #:center (vec2 -3 0)
        #:radius 3/4)
```

Scene state must preserve top-level drawing order explicitly. The project
convention is back-to-front order: later entries paint over earlier entries.
A group must preserve a separate back-to-front order for its descendants.

Every identity exposed through one built-in group tree must be a symbol, must
be unique in that tree, and must differ from the group identity. Treat a custom
affine Visual as one leaf unless a future public child protocol says otherwise.
Nested child identities are semantic, but they are not top-level scene-state
lookup or animation targets until an
explicit nested-targeting stage defines that behavior.

Immutable replacement must preserve a Visual’s id and drawing position unless
the operation explicitly changes order. Group updates must also preserve child
order unless the operation explicitly replaces it.

## 10. Affine transform semantics

Store translation, rotation, and scale as semantic model data, never as a
backend-specific Pict transformation.

- Apply components in the fixed order scale, rotate, then translate.
- Use mathematical world coordinates and counter-clockwise radians.
- Store scale as positive finite x and y factors. A uniform scale may be
  accepted at an API boundary but should be normalized to two components.
- Keep `visual-position` as the translation component so position-only Visuals
  and the existing `move-to` API remain compatible.
- Put full transform support in a separate semantic protocol. A third-party
  Visual may implement position only and remain movable.
- Immutable component updates must preserve identity, geometry, style,
  opacity, and the other transform components.
- Apply scale to semantic geometry before rendering when stroke width is
  cosmetic. Do not scale cosmetic stroke width accidentally by scaling a
  finished Pict.
- A renderer for a third-party affine Visual is responsible for interpreting
  that Visual's transform data.

### Arrows and Cartesian axes

- Store arrow shafts in significant start-to-end order. Use the midpoint of the
  untransformed endpoints as the semantic anchor.
- Require distinct finite arrow endpoints. Define point-at queries on the
  transformed shaft with progress in the closed unit interval.
- Treat start and end tips as independent semantic flags. Store tip length and
  width in local world units so affine scale affects them with the shaft.
- Keep arrow stroke width cosmetic. Do not enlarge it by scaling a finished
  Pict.
- Represent one axis interval with explicit minimum, maximum, and positive tick
  step. Require the interval to contain zero while axes cross at numeric origin.
  Reject endpoint pairs whose computed span is not positive and finite.
- Generate tick values as ordered nonzero integer multiples of the stored step
  within the closed interval. Do not derive them from pixel spacing. Use one
  documented fixed tolerance for inexact endpoint quotients so decimal input
  does not lose an endpoint through binary rounding.
- Map the complete numeric x and y intervals to explicit positive local lengths.
  Keep x and y unit lengths independent and reject a non-finite or zero
  length-per-coordinate-unit result.
- Make coordinate-to-point and point-to-coordinate conversion pure inverses of
  the complete semantic axes transform. Permit extrapolation outside displayed
  ranges and document inexact trigonometric round trips.
- Render shafts and ticks as open semantic path subpaths and tips as closed
  triangular subpaths through the shared path adapter.
- Do not add hidden numeric labels, grids, sampled plots, or automatic label
  placement to the axes model. Introduce each as an explicit later layer.

### Sampled function graphs

- Sample one-variable procedures at construction time and store only immutable
  path geometry. Do not retain the procedure, exceptions, renderer state, or
  sample cache in the resulting Visual.
- Use a closed, increasing x interval with a documented exact sample count of at
  least two. Include both endpoints and preserve exact rational grid values when
  exact inputs permit it.
- Require exactly one result from each sampling call. Accept a finite real as a
  sample and `#f` as an explicit gap. Treat positive infinity, negative infinity,
  and NaN as gaps. Reject unrelated values and zero or multiple results.
- Do not silently turn a procedure exception into a discontinuity. Report the x
  coordinate and exception message at the sampling boundary.
- Keep discontinuity heuristics explicit. An optional maximum jump is measured
  in numeric y-coordinate units before axes scaling; no heuristic jump threshold
  is applied when the option is false.
- Clip accepted line segments to the displayed axes rectangle when clipping is
  enabled. Clip segments, not only sample points, so boundary intersections are
  represented exactly by path endpoints.
- Preserve every gap and rejected segment as a subpath break. Never reconnect
  separated runs merely because clipped endpoints happen to coincide.
- Convert numeric coordinates to axes-local geometry with the independent x and
  y unit lengths. Copy the axes transform into the graph Visual only as a
  construction-time snapshot.
- Return an ordinary path Visual so the shared path renderer, Create, Uncreate,
  affine updates, opacity, groups, and timeline semantics apply without a
  graph-specific rendering or animation protocol.
- Test exact sampling order, gaps, clipping, explicit jump rejection, procedure
  errors, axes alignment, transformed graphs, Create, and deterministic PNG
  output separately.

### Parametric curves and ordered data plots

- Represent one parameter domain with explicit ordered start and end values.
  Permit increasing or decreasing traversal, require distinct finite endpoints,
  and reject a non-finite computed span.
- Sample coordinate-valued procedures immediately at construction time. Include
  both parameter endpoints and preserve exact rational parameter values when
  exact inputs permit it.
- Require exactly one result from each parametric sampling call. Accept a `vec2`
  as one numeric coordinate and `#f` as an explicit gap. Report invalid result
  counts, values, parameter coordinates, and procedure exceptions explicitly.
- Accept data series only as explicit ordered lists of `vec2` values and `#f`
  gaps. Never sort by x, infer chronology, remove repeated points, or retain the
  caller's input collection in the resulting Visual.
- Keep optional parametric/data discontinuity rejection explicit. Measure
  `#:max-distance` as Euclidean distance in numeric-coordinate units before axes
  scaling. Apply no threshold when the option is false.
- Share segment clipping, run assembly, coordinate conversion, and interpolation
  rules across function, parametric, and data plots in one pure module.
- Provide explicit `linear` and `smooth` interpolation modes. Keep linear as the
  default. Represent smooth interpolation with semantic cubic Bézier segments
  derived from uniform Catmull-Rom tangents.
- For a two-point smooth run, use one line-equivalent cubic with controls at one
  third and two thirds. For longer runs, preserve every sample as a cubic
  endpoint in significant traversal order.
- Clip accepted sample segments before smooth interpolation. When clipping is
  enabled, clamp generated controls to the closed axes rectangle so the Bézier
  convex hull remains visible. Document that boundary clamping can reduce
  tangent continuity.
- Preserve every explicit gap, rejected pair, and clipped-out segment as a run
  boundary. Empty input, one isolated point, and isolated finite samples produce
  no drawn segment.
- Return ordinary path geometry and path Visuals. Copy the axes transform only
  as a construction-time snapshot and reuse existing path rendering, Create,
  Uncreate, morphing, opacity, layout, groups, and timeline behavior.
- Test increasing and decreasing domains, exact endpoint sampling, point-series
  order, explicit gaps, Euclidean distance rejection, clipping, line/cubic
  segment kinds, exact controls, boundary clamping, transform snapshots, and
  deterministic PNG output separately.

### Group transforms and hierarchy

- Store group children as semantic affine Visual values, never as Picts.
- Interpret child positions in coordinates local to the group anchor.
- Store child order explicitly from back to front and treat it as significant.
- Permit empty groups and nested groups.
- Require the complete built-in child tree to use unique symbol identities.
  Treat a custom affine Visual as one leaf.
- Restrict a group's own scale to positive equal components while the transform
  model has no shear component. A non-uniform parent scale followed by a rotated
  child can require shear and must be rejected rather than approximated.
- Inherit parent uniform scale and rotation through child semantic transforms
  before rendering. Apply parent translation when the complete group is placed
  in its containing coordinate system.
- Apply each child opacity before composition and the group opacity after the
  complete child composition.
- Keep the built-in group Pict box symmetric around the semantic group anchor;
  use a stable transparent one-pixel Pict for an empty group.
- Validate custom affine child results at adapter boundaries: identity must be
  preserved, the requested transform must be installed, and position must agree
  with transform translation.
- Keep nested child lookup and animation out of the top-level scene-state API
  until a dedicated stage defines path-like addressing and replacement rules.

### Plain-text Visuals

- Store text content as immutable semantic strings. Copy mutable input strings
  at construction and immutable-update boundaries.
- Keep plain-text model modules free of Pict values, `font%` objects, drawing
  contexts, platform font handles, and device-specific metrics.
- Measure semantic font size in local world units. Convert through the camera
  only in the rendering adapter.
- Represent supported font family, style, weight, and alignment choices with
  explicit validated symbols. Do not pass arbitrary backend objects into the
  model.
- Treat an optional face name as a semantic preference. Document that actual
  face selection and glyph metrics depend on the rendering environment.
- Define horizontal and vertical alignment as an anchor on the untransformed
  text box. Resolve that anchor first, then apply scale and rotation around it.
- Permit an empty string and render it as stable transparent local geometry.
- Reject carriage returns and newlines while the public abstraction promises
  one-line plain text. Add multiline layout only as a deliberate later stage.
- Preserve identity, transform, opacity, font data, color, and alignment when
  replacing content immutably.
- Apply global opacity after text renderer dispatch, just as for every other
  opacity-aware Visual.
- Test semantic determinism separately from platform-font rasterization.
  Byte-level text-rendering tests must run in one fixed Racket, operating-system,
  font-installation, and rendering environment.

### LaTeX formula Visuals

- Store formula source, preamble, document-class options, Preview-package
  options, display mode, font size, alignment, transform, and opacity as pure
  immutable semantic data.
- Copy mutable source, preamble, and option strings at construction and
  immutable-update boundaries. Preserve significant option order.
- Support explicit inline, tight display-style, and real display-environment
  modes. Do not infer delimiters from source text.
- Accept source without surrounding math delimiters. Allow multiline source and
  stable empty source.
- Keep Pict values, PDF pages, TeX process results, Poppler objects, caches, and
  external executable state outside the formula model.
- Use the same horizontal and vertical anchor semantics as plain text. Resolve
  the typeset Pict's selected anchor before affine scale and rotation.
- Measure semantic formula font size in local world units. Map the selected
  standard 10pt, 11pt, or 12pt document-class base to that size through the
  camera. Reject conflicting standard size options.
- Let explicit preamble commands control mathematical coloring in this stage;
  do not pretend a generic Pict color operation can reliably recolor arbitrary
  PDF-derived formula content.
- Preserve identity, transform, opacity, mode, size, preamble, options, and
  alignment when replacing formula source immutably.
- Apply global opacity after formula renderer dispatch so a custom formula
  renderer follows the same rule as every other opacity-aware Visual.
- Document that exact formula output depends on the TeX distribution, installed
  packages, `latex-pict`, Poppler, and their versions.
- Treat formula source and preamble as trusted input. Document that the adapter
  invokes an external TeX process and does not provide a security sandbox.

### Named formula parts and correspondence

- Represent one formula part with a local symbol name and one semantic formula
  Visual. Require the formula Visual identity to equal the part name.
- Treat part names as local to one formula assembly. They are not top-level
  scene-state identities or direct animation targets. Animate them collectively
  through the containing assembly and an explicit correspondence.
- Store formula parts in explicit back-to-front order and preserve that order
  through lookup, replacement, rendering, and correspondence queries.
- Typeset each part independently at its local formula position. Do not imply
  that TeX automatically spaces or lays out separate parts as one document.
- Permit empty formula assemblies. Render them as stable transparent one-pixel
  local geometry without invoking TeX.
- Give a complete formula assembly the same affine and opacity behavior as a
  group. Restrict its parent scale to a positive uniform value while the model
  has no shear component.
- Propagate the explicit renderer list to every part. Let an explicit renderer
  that supports the complete assembly override recursive composition according
  to the ordinary first-supporting-renderer rule.
- Model manual correspondence as explicit immutable source and destination
  assemblies plus an ordered list of source-name and destination-name pairs.
- Require correspondence to be one-to-one. Every named part must exist, and a
  source or destination name may appear at most once.
- Do not infer matches from equal names. An empty match list is a valid explicit
  choice. Preserve match order as significant transition-layer order.
- Report unmatched source and destination names in their original assembly part
  order.
- Keep correspondence pure. It must not contain Picts, typesetting results,
  hidden tokenization, or renderer state.
- Compile a formula-part transformation against the current assembly. Require
  its ordered local names to equal the correspondence source names exactly, but
  use the current formula values, transforms, and opacities.
- Treat the correspondence destination as a part-layout template. Install its
  exact ordered parts at the structural endpoint, but preserve the current
  top-level assembly identity, transform, and opacity unless separate requests
  change those independent components.
- Keep one moving layer for matched formulas with equal typesetting data. When
  source, mode, size, preamble, options, or anchors differ, move two layers and
  cross-fade source into destination.
- Fade unmatched source parts out at their current local transforms. Fade
  unmatched destination parts in at their destination local transforms.
- Define deterministic interior drawing order: unmatched source parts in source
  order, matched layers in explicit match order, then unmatched destination
  parts in destination order. For a changed match, put its source layer before
  its destination layer.
- Allocate deterministic temporary local identities without colliding with the
  top-level identity or either endpoint namespace. Exact endpoints must restore
  the endpoint part names rather than temporary identities.

## 11. Path geometry semantics

Store path geometry as semantic model data, never as a Pict, `dc-path%`, SVG
string, or mutable drawing-context command list.

- Represent a path as ordered subpaths. Represent each subpath with a start
  point, ordered segments, and an explicit open-or-closed flag.
- Treat point, segment, and subpath order as significant. Length, reveal, and
  morphing operations must use that order deterministically.
- Keep path points in local mathematical coordinates with positive y upward.
  Apply affine placement only when sampling or rendering a Visual.
- Measure path length in local world units. Include the implicit closing edge
  of a closed subpath. Document how each segment kind is measured and any
  approximation it uses.
- Define partial geometry by fractions of total ordered arc length. Complete
  one subpath before traversing the next one.
- Define point lookup by the same total ordered arc-length model as partial
  extraction. Require positive finite total length, include implicit closing
  edges, and make exact zero/one return the first/last traversal endpoint.
- A partial piece of a closed subpath is open. Preserve closure only when the
  complete subpath is selected.
- The exact interval from zero through one must preserve the original geometry,
  including point-only and zero-length subpaths. Other positive partial
  intervals may omit zero-length traversal elements.
- Permit explicit empty path geometry. Do not encode invisibility with a
  backend-specific blank Pict.
- Keep segment kinds extensible. A new segment kind must define semantic
  bounds, length, point mapping, partial extraction, and adapter conversion
  before it participates in `Create` and `Uncreate`.
- For cubic Bézier segments, store the two control points and endpoint. The
  segment start remains the preceding subpath point.
- Find cubic bounds from endpoint and derivative extrema. Do not use the larger
  control-point box as the semantic curve bounds.
- Use deterministic adaptive subdivision for cubic arc length. Keep the
  tolerance and maximum depth fixed in the model implementation, and document
  that curved length is approximate.
- Extract cubic intervals with de Casteljau subdivision. Do not replace a
  partial cubic with backend-specific commands or a polyline approximation.
- Define direct path morphing only for structurally compatible paths. Require
  equal subpath counts, corresponding closure values, equal segment counts,
  and corresponding segment kinds.
- Pair morphing subpaths and segments by stored order. Interpolate subpath
  starts, line endpoints, cubic control points, and cubic endpoints.
- Keep strict morph compatibility and interpolation available as explicit
  operations. Do not make strict APIs normalize behind the caller's back.
- Limited morph normalization may convert stored lines to equivalent cubics and
  split stored cubics until corresponding segment counts match. Expose this as
  a named pure operation and as a distinct timeline request.
- Convert a line from start to end with control points at one third and two
  thirds of the segment. Keep existing cubics unchanged.
- For each corresponding nonempty subpath, normalize to the larger stored
  segment count. Repeatedly split the longest current cubic at parameter one
  half. Resolve equal approximate lengths by choosing the earliest segment in
  traversal order.
- Keep implicit closed-path edges implicit during normalization. Do not split
  them or add them to the stored segment list.
- Limited normalization must not add or remove subpaths, change closure, pair a
  point-only subpath with drawn geometry, reverse traversal, rotate a closed
  starting point, reorder subpaths, or choose a hidden geometric best match.
- Preserve the exact source path at morph progress zero and the exact
  destination path at progress one. Normalized interior representations may
  contain more cubic segments than either endpoint representation.
- Preserve subpath structure, closure, identity, style, and affine placement
  during immutable point transformations unless an operation explicitly
  changes one of them.
- Constructors from points in a containing coordinate system should document
  how they choose the Visual reference position and normalize stored local points.
- Keep cosmetic stroke width outside semantic point scaling.
- Put `dc-path%`, pens, brushes, fill rules, and drawing-context mutation in the
  Pict adapter only. Restore all drawing-context state before a `dc` callback
  returns.
- Render closed path outlines with miter joins so polygon corners remain sharp.
  Render open paths with round endpoint caps and miter joins between segments.
- Test open, closed, compound, mixed-segment, point-only, zero-length, and
  empty paths separately. For curves, also test extrema bounds, length
  approximation, subdivision, rendering, and reveal.

## 12. Animation semantics

Construction and sampling must be independent of render order.

- A play clip captures its complete starting scene state.
- Requests are compiled to explicit endpoints when `scene-play` is called.
- Sampling frame 40 must not depend on rendering frames 0 through 39.
- Clip intervals are half-open, except that sampling the scene’s total duration
  returns its final state.
- Simultaneous requests may target the same Visual when they update disjoint
  animation components.
- Two simultaneous requests may not update the same target and animation
  component unless a later composition rule defines the result explicitly.
- `Create` introduces an identity that was absent before the clip. Prepare one
  empty-path placeholder with the final Visual's identity, style, affine
  transform, and opacity before compiling the clip's other requests.
- `fade-in` also introduces an absent identity. Prepare the complete Visual at
  opacity zero before compiling the clip's other requests.
- Several introduction requests add Visuals in request order, in front of
  existing Visuals. Request order must not otherwise change their shared start
  state.
- `Create` and `Uncreate` require a finite computed local path length so every
  intermediate sample is defined. Curve reveal uses the same deterministic
  approximate arc-length model as `path-geometry-partial`.
- `Uncreate` requires a present path Visual, retracts its visible prefix, and
  removes it from the structural endpoint.
- `morph-to` requires a present built-in path Visual and a structurally
  compatible destination path. It changes local path geometry only.
- `morph-to-normalized` requires a present built-in path Visual and a
  destination supported by the explicit limited normalizer. Compilation must
  capture both exact endpoints and their compatible normalized cubic forms.
- `move-along-path` is a translation request parameterized by total arc length.
  Compile a path Visual route from its current clip-start identity and affine
  transform before measuring it. Treat raw path geometry as already expressed
  in the target's containing coordinate system.
- A signed path-motion normal offset is relative to the actual traversal
  direction. Positive means left of motion; reverse traversal therefore flips
  the path normal. Keep polyline corner behavior segment-local unless a future
  explicit join rule says otherwise.
- `orient-along-path` is a separate rotation request. Derive rotation from the
  sampled traversal tangent rather than interpolating only endpoint angles.
  It may compose with path translation but must conflict with same-target
  `rotate-to`, `rotate-by`, or another path-orientation request.
- Require one positive-length continuous subpath for motion. Drawing may use
  compound discontinuous paths, but motion must reject gaps instead of silently
  teleporting between subpaths. Permit forward, reverse, and partial traversal
  by independent start/end fractions in the closed unit interval.
- A compiled motion route is a clip-start snapshot. Simultaneously moving or
  morphing the path Visual does not dynamically deform the route. Document that
  the target should already be at the selected start point when continuity at
  the clip boundary matters.
- Morphing may run with translation, rotation, scale, and opacity fading for
  the same identity. Strict morphing, normalized morphing, `Create`, and
  `Uncreate` share the path-geometry component and therefore conflict for the
  same identity in one play clip.
- Morphing follows ordinary eased progress at the clip endpoint. It has no
  structural endpoint override. An easing function that does not map one to
  one may therefore leave the final path short of the requested destination.
- A formula-part transformation preserves exact source parts at eased progress
  zero and samples deterministic temporary layers at interior progress. At the
  structural endpoint, install the exact destination parts even when easing
  does not map one to one.
- A formula-part transformation changes the formula-parts component and reserves
  the presence component. It may run with translation, rotation, scale, and
  `fade-to`, but not with same-target `fade-in`, `fade-out`, `Create`, or
  `Uncreate`; structural add/remove order would otherwise be ambiguous.
- Structural endpoints take precedence over unusual easing for presence-
  changing requests and formula-part transformations. Completed `Create` stores
  the full path, completed `fade-in` stores the supplied opacity, completed
  formula-part transformation stores exact destination parts, and completed
  `Uncreate` or `fade-out` stores no target. Document that an easing function
  that does not map one to one can create a boundary discontinuity.
- Reveal and morph animation must operate on semantic path geometry, not
  rendered Picts.
- Model global opacity as a finite real in the closed interval `[0, 1]` through
  an optional semantic opacity-Visual protocol. Built-in Visual constructors
  default to opacity one.
- `fade-to` requires a present opacity Visual, changes only the opacity
  component, and follows ordinary eased endpoint semantics.
- `fade-in` introduces an absent opacity Visual through an opacity-zero
  placeholder. Its structural endpoint installs the complete supplied opacity
  even when easing does not map one to one.
- `fade-out` requires a present opacity Visual, samples toward opacity zero,
  and removes the Visual from the structural endpoint even when unusual easing
  leaves a nonzero sampled opacity.
- Treat translation, rotation, scale, opacity, path geometry, formula parts,
  and presence as explicit animation components. A request may change more than
  one component. `fade-in` and `fade-out` change opacity and presence;
  `Create` and `Uncreate` change path geometry and presence; formula-part
  transformation changes formula parts and reserves presence.
- Permit same-target requests only when all of their component sets are
  disjoint. In particular, reject `fade-in` with same-target `Create` and
  reject `fade-out` with same-target `Uncreate` because both pairs update
  presence.
- Apply opacity to the complete rendered Visual after renderer selection. Do
  not bake opacity into fill, stroke, path, or renderer-specific model fields.
- Exact rational times are preferred for deterministic tests and frame
  conversion.

Decorative editor state—selection handles, pen strokes, previews, debug
labels, and similar overlays—must stay outside the semantic exported scene
unless it is deliberately part of the animation.

## 13. Racket and Rhombus interoperability

Keep the core representation in ordinary Racket values that Rhombus can import
directly. Provide a small Rhombus example for public API changes.

Do not add a silent compatibility workaround for a Racket/Rhombus compiler or
runtime problem. Stop and record a minimal reproduction so the underlying
problem remains visible.

## 14. Browser and WebRacket adapters

These rules apply when a future editor or browser preview is added:

- prefer WebRacket, `browser`, and `web-easy` bindings over raw `js-ref`,
  `js-set!`, or ad hoc JavaScript;
- use raw JavaScript FFI only for genuinely dynamic browser APIs or missing
  bindings;
- centralize wrappers for DOM text, attributes, storage, clipboard,
  fullscreen, and related operations;
- keep pure geometry, Visual, scene, and controller code separate from the DOM
  adapter;
- keep toolbar and grouping behavior data-driven;
- goal and highlight styling takes precedence over cosmetic user colors;
- previews, snapping, overlap disambiguation, keyboard affordances, and status
  text belong in controller/adapter layers;
- settings may preview live, but persistence occurs only through an explicit
  save operation.

The Geo application’s `./build.sh`, local page URL, and Playwright smoke script
are specific to that application and are not commands for this repository.

## 15. Public Scribble documentation

The authoritative public reference is
`scribblings/animate.scrbl`. Write it as a reference manual in simple,
direct language. It must describe the actual API exported by `main.rkt`.

Documentation is part of every public API change:

- Add a defining Scribble entry for every new public structure, constructor,
  generic interface, predicate, accessor, function, and constant in the same
  change that exports it.
- Update the existing entry in the same change whenever a public signature,
  default, result, unit, side effect, error, ordering rule, identity rule, or
  other semantic behavior changes.
- Remove or revise documentation when a public binding is removed or renamed.
- Do not leave a public binding documented only by a README example or a source
  comment.

Use the Scribble form that defines the binding for cross-reference purposes:

- `defstruct*` for a public structure and all bindings from `struct-out`;
- `defproc` for procedures, predicates, constructors, accessors, and mutating
  or effectful operations;
- `defthing` for constants and generic-interface values;
- `defmodule` for the public module.

Each reference entry should state, where applicable:

- what each argument means and which arguments are optional;
- defaults and accepted value ranges;
- the result and its units;
- whether the operation is pure, mutating, or externally effectful;
- significant identity, drawing-order, transform-order, or timeline rules;
- important validation failures and boundary cases;
- numeric approximation rules, tolerances, and depth limits;
- a small example when the operation is not obvious.

For public structures, document every field and whether field or child ordering
is significant. For protocols, document the obligations placed on custom
implementations, not only the dispatcher functions.

The package does not register the manual through `scribblings`. Build it
manually after public API or documentation changes:

```sh
scribble --htmls --dest doc scribblings/animate.scrbl
```

## 16. Testing and build

After source changes, run:

```sh
raco make main.rkt
raco test tests/scene-a-test.rkt \
          tests/scene-a-render-test.rkt \
          tests/scene-b-test.rkt \
          tests/scene-b-render-test.rkt \
          tests/scene-c-test.rkt \
          tests/scene-c-render-test.rkt \
          tests/scene-e-test.rkt \
          tests/scene-e-render-test.rkt \
          tests/scene-f-test.rkt \
          tests/scene-f-render-test.rkt \
          tests/scene-g-test.rkt \
          tests/scene-g-render-test.rkt \
          tests/scene-h-test.rkt \
          tests/scene-h-render-test.rkt \
          tests/scene-i-test.rkt \
          tests/scene-i-render-test.rkt \
          tests/scene-j-test.rkt \
          tests/scene-j-render-test.rkt \
          tests/scene-k-test.rkt \
          tests/scene-k-render-test.rkt \
          tests/scene-l-test.rkt \
          tests/scene-l-render-test.rkt \
          tests/scene-m-test.rkt \
          tests/scene-m-render-test.rkt \
          tests/scene-n-test.rkt \
          tests/scene-n-render-test.rkt \
          tests/scene-o-test.rkt \
          tests/scene-o-render-test.rkt \
          tests/scene-p-test.rkt \
          tests/scene-p-render-test.rkt \
          tests/scene-q-test.rkt \
          tests/scene-q-render-test.rkt \
          tests/scene-r-test.rkt \
          tests/scene-r-render-test.rkt \
          tests/scene-s-test.rkt \
          tests/scene-s-render-test.rkt \
          tests/scene-t-test.rkt \
          tests/scene-t-render-test.rkt \
          tests/scene-u-test.rkt \
          tests/scene-u-render-test.rkt \
          tests/scene-v-test.rkt \
          tests/scene-v-render-test.rkt \
          tests/scene-w-test.rkt \
          tests/scene-w-render-test.rkt \
          tests/scene-x-test.rkt \
          tests/scene-x-render-test.rkt \
          tests/scene-x-example-test.rkt \
          tests/scene-y-test.rkt \
          tests/scene-y-render-test.rkt
scribble --htmls --dest doc scribblings/animate.scrbl
```

Keep pure model tests separate from filesystem and rendering tests.

Model tests should cover:

- exact scene samples at start, intermediate times, clip boundaries, and end;
- stable Visual identity;
- explicit back-to-front drawing order;
- immutable add, remove, and replacement behavior;
- simultaneous disjoint-component animation and duplicate-component rejection;
- exact translation, rotation, and scale samples;
- rejection of non-finite semantic coordinates and invalid scale factors;
- every built-in Visual type through shared animation operations;
- path segment, subpath, closure, empty-path, bounds, and point-order
  invariants;
- exact path lengths, partial intervals, subpath boundaries, and zero-length
  behavior;
- `Create` introduction, `Uncreate` removal, drawing order, and same-target
  disjoint-component behavior;
- path-morph compatibility, endpoint preservation, line and cubic point
  interpolation, mismatch diagnostics, and same-target component conflicts;
- morphing with simultaneous affine changes and later clips compiled from the
  preceding path endpoint;
- line-to-cubic conversion, normalizable-path predicates, normalized segment
  counts, longest-first midpoint splitting, deterministic tie handling,
  unsupported normalization diagnostics, and exact normalized-morph endpoints;
- opacity interval validation, immutable opacity replacement, third-party
  opacity Visuals, fade-to interpolation, fade-in placeholders, fade-out
  removal, unusual easing, drawing order, and opacity/presence conflicts;
- group construction, empty and nested groups, local child coordinates,
  significant child order, tree identity validation, inherited uniform
  transforms, opacity preservation, and group animation;
- rejection of non-affine children, malformed custom affine protocol results,
  and non-uniform group scale endpoints during scene-play compilation;
- plain-text content copying, font and alignment predicates, one-line
  validation, immutable content replacement, group participation, and ordinary
  affine and opacity animation;
- formula mode and option predicates, immutable source, preamble, and ordered
  option copying, standard document-font-size validation, source replacement,
  group participation, and ordinary affine and opacity animation;
- formula-part identity, local-name uniqueness, significant part order, lookup,
  immutable replacement, empty assemblies, group inheritance, and ordinary
  whole-assembly affine and opacity animation;
- manual correspondence order, one-to-one validation, missing-name diagnostics,
  explicit empty mappings, and unmatched-name order;
- formula-part transformation target and namespace validation, current-source
  compilation, exact endpoints, deterministic temporary names and layer order,
  matched movement, changed-formula cross-fades, unmatched fades, unusual
  easing, later clips, component conflicts, and simultaneous outer transforms;
- layout-box guards, renderer-aware measurement, exact edge gaps, alignment,
  arrangement order, union centering, and defective custom position updates;
- arrow endpoint order, midpoint anchoring, tip flags and dimensions, affine
  endpoint queries, point-at progress, and invalid zero-length arrows;
- axis-range guards, ordered nonzero ticks, x/y unit lengths, affine coordinate
  conversion and inverse round trips, extrapolation, and axes animation;
- function, parametric, and data sampling order, endpoint inclusion, explicit
  gaps, jump/distance rejection, clipping, interpolation modes, exact cubic
  controls, ordered point input, and copied axes transforms.

Rendering tests should cover:

- fixed camera dimensions;
- deterministic frame count;
- exact `frame-index->time` conversion;
- expected frame filenames;
- preservation of unrelated files during cleanup;
- byte-identical output when rendering the same scene twice;
- renderer precedence and unsupported Visual diagnostics;
- third-party Visual and renderer propagation through PNG output;
- transformed built-in geometry and deterministic transformed PNG output;
- open, closed, compound, partial, and empty path rendering;
- invisible creation starts, intermediate reveal frames, structural endpoints,
  and deterministic reveal PNG output;
- source, intermediate, and destination path-morph bounds and deterministic
  morph PNG output for line and cubic paths;
- normalized morph rendering when segment kinds or counts differ, including
  exact endpoint frames and deterministic repeated PNG output;
- unchanged Pict bounds across opacity values, custom-renderer opacity,
  transparent-background equivalence, fade frame progression, structural
  removal frames, and deterministic repeated opacity PNG output;
- empty-group rendering, nested composition, child-order overlap, inherited
  transform equivalence, renderer propagation through descendants, explicit
  custom group overrides, group opacity, and deterministic group PNG output;
- plain-text font sizing, anchors, non-uniform scale, rotation, renderer
  overrides, nested group equivalence, opacity, empty text, stable local-raster
  reuse across position/camera-pan changes, invalidation across appearance/zoom
  changes, and deterministic PNG output in one fixed font environment;
- formula renderer selection, mode-to-typesetter dispatch, 10pt/11pt/12pt size
  calibration, anchors, non-uniform scale, rotation, custom overrides, nested
  group equivalence, opacity, empty source, and deterministic injected-typesetter
  PNG output without launching TeX;
- empty formula assemblies, recursive part-renderer propagation, significant
  overlapping part order, whole-assembly overrides, nested transform
  equivalence, opacity, animation frames, and deterministic PNG output without
  launching TeX;
- source, interior, and destination formula-part transformation frames, moving
  matched parts, cross-fading changed formulas, unmatched fades, stable outer
  transforms, exact endpoint rendering, frame counts, and deterministic repeated
  PNG output through an injected renderer without launching TeX;
- renderer-aware layout dimensions, exact gaps, custom renderer metrics, fitted
  backgrounds, and deterministic arranged-scene PNG output;
- arrow shaft and tip bounds, single/double/tipless rendering, axes shafts,
  ordered ticks and maximum-end tips, custom renderer precedence, label layout,
  group composition, opacity, transforms, and deterministic PNG output.
- sampled-function grid order, explicit and non-finite gaps, segment clipping,
  maximum-jump rejection, transformed axes alignment, path-renderer reuse,
  Create frames, and deterministic PNG output;
- parametric and data linear/smooth rendering, clipped smooth bounds, ordinary
  path Create frames, frame counts, and deterministic repeated PNG output;
- number-line conversion, ticks, grid geometry, generated label order, and
  deterministic coordinate-decoration rendering;
- absolute and relative camera pan and zoom, shared easing with Visual requests,
  wait holds, static overrides, fixed frame dimensions, changed dynamic frames,
  and deterministic repeated PNG output.

FFmpeg integration tests should be separate and optional because they depend on
an external executable.

## 17. Change discipline

Change only intended project files. Leave unrelated user edits untouched.

When a change affects the public API, update together:

- `main.rkt`;
- `scribblings/animate.scrbl`;
- examples when they illustrate the affected API;
- tests;
- `README.md`;
- this house-style guide when the rule itself changes.


## 18. Compact implementation prompt

Use this block when handing a focused implementation task to a coding agent:

```text
Follow HOUSE_STYLE.md and the existing Geo code style.

Racket/Rhombus style:
- Prefer small, explicit functions with local helpers over large inline blocks.
- Use predicate suffix ?, external-effect suffix !, and conversion names x->y.
- Add a contract comment and one short purpose sentence before every top-level
  definition.
- Document every struct field and state explicitly when ordering matters.
- Use explicit provide forms and focused requires; use only-in for a few names
  from a broad external module.
- Preserve module boundaries: semantic geometry, path, Visual, scene-state,
  animation, and timeline code stay separate from pict, filesystem, process,
  browser, and JavaScript adapters.
- Keep renderer protocols backend-specific and outside the semantic Visual
  model.
- Keep renderer-aware layout in a separate adapter module. Measure symmetric
  local Pict boxes with an explicit camera and renderer list, convert dimensions
  back to world units, and update only immutable Visual positions.
- Add or update the defining Scribble entry in the same change as every public
  API addition or change. Document arguments, defaults, results, units, effects,
  semantic rules, and important errors in simple language.

Animation model:
- Keep Visual values, camera values, and timeline sampling immutable and
  deterministic.
- Store the camera with the scene timeline. Compile camera and Visual requests
  from one shared clip start and sample both at the same eased progress.
- Treat camera center and visible world width as separate animation components.
  Keep pixel dimensions and background fixed during a camera play clip.
- Interpret camera zoom factors as magnification: values above one reduce the
  visible world width and zoom in. Reject nonpositive or non-finite endpoints.
- Let rendering sample the scene camera by default. An explicit static camera
  is an override and must ignore the scene-camera track for that render.
- Store affine components in scale-rotate-translate order.
- Store groups as ordered semantic affine children in local coordinates. Require
  unique identities throughout each built-in group tree, permit nesting, and
  keep nested children outside top-level scene lookup and targeting.
- Restrict group scale to a positive uniform factor while shear is unsupported.
  Inherit parent scale and rotation through child model transforms, place group
  translation at the containing level, and apply group opacity after child
  composition.
- Recursively propagate the same renderer list through groups. An explicit
  renderer that supports a group overrides built-in composition.
- Keep plain text as immutable one-line semantic content with explicit font,
  color, and anchor data. Keep Pict text, `font%`, platform metrics, and face
  substitution in the adapter layer.
- Measure text size in local world units, resolve the selected anchor before
  scale and rotation, permit stable empty text, and reject line breaks until a
  deliberate multiline stage defines layout.
- Rasterize nonempty built-in plain text at a stable local origin after anchor,
  semantic scale, and rotation but before scene placement. Do not rerasterize a
  position-only move or camera pan at a new device-space glyph origin.
- Keep the plain-text raster cache private to the renderer and bounded. Exclude
  Visual identity, position, opacity, and camera center from its appearance key;
  include content/font/color/alignment, semantic scale/rotation, and camera pixel
  scale so camera zoom or appearance changes rerasterize at the new resolution.
- If an adapter-native text color cannot be snapshotted safely for a cache key,
  bypass the cache rather than retaining stale mutable style state. Still freeze
  that render at local origin before placement. Do not extend this policy to
  formula rendering without a separate visual regression.
- Keep LaTeX formulas as immutable semantic source, mode, size, preamble,
  ordered options, alignment, transform, and opacity. Keep `latex-pict`, PDF,
  Poppler, and TeX execution in a separate adapter.
- Typeset nonempty formulas at natural TeX scale, calibrate the selected
  10pt/11pt/12pt base to local world units, then resolve the shared text anchor
  before affine scale and rotation. Empty source must not launch TeX.
- Test formula layout with an injected deterministic typesetter or renderer.
  Keep real TeX integration tests optional and environment-specific.
- Treat relative-layout bounds as renderer boxes rather than tight ink bounds.
  Preserve transparent anchor padding, use nonnegative world-unit gaps, preserve
  identity and order, and use the same camera/renderers for final rendering.
- Keep arrows as midpoint-anchored start-to-end semantic shafts with independent
  tips. Keep axes ranges, ordered ticks, explicit x/y lengths, and coordinate
  conversion pure. Render both through shared semantic path geometry; keep tip
  dimensions geometric and stroke widths cosmetic.
- Sample one-variable functions immediately into axes-local path geometry.
  Include both domain endpoints, preserve explicit/non-finite gaps, keep optional
  y-jump rejection explicit, clip segments to the displayed axes rectangle, and
  copy the axes transform only as an immutable construction-time snapshot.
- Treat parameter domains as ordered closed values that may increase or
  decrease. Sample parametric procedures into `vec2` coordinates and consume
  data series in their explicit list order, with `#f` as a gap.
- Share clipping and run assembly across coordinate plots. Keep maximum-distance
  rejection explicit, default interpolation linear, and smooth interpolation a
  documented Catmull-Rom-to-cubic conversion with clipped controls clamped to
  the axes rectangle.
- Store named formula parts in explicit back-to-front order. Treat part names
  as local to one formula assembly, not as top-level scene targets.
- Keep manual formula correspondence explicit, ordered, one-to-one, and pure.
  Do not infer matches from equal names or hide renderer and typesetting state
  inside correspondence values.
- Compile formula-part transformations from the current source values after
  checking the exact ordered source namespace. Preserve the outer assembly and
  install exact destination parts at structural completion.
- Use one moving layer for equal matched formulas, moving source/destination
  cross-fade layers for changed formulas, and ordered fades for unmatched parts.
  Allocate deterministic collision-free temporary local names for interiors.
- Keep paths as ordered local subpaths and semantic segments; never store
  Pict, dc-path%, or SVG commands in the model.
- Measure and extract paths by local ordered arc length. Include closed-path
  closing edges and preserve closure only for complete selected subpaths.
- Keep strict morphing for structurally compatible paths. Provide limited
  normalization as an explicit pure operation and a distinct timeline request.
- Limited normalization converts lines to equivalent cubics, then splits the
  longest current cubic at parameter 1/2 until corresponding counts match;
  equal lengths choose the earliest segment. Never reverse paths, rotate closed
  starts, reorder subpaths, change closure, or invent point-only geometry.
- Implement Create/Uncreate with semantic partial paths. Create introduces an
  absent identity; Uncreate removes a present path Visual at the endpoint.
- Model global opacity as a semantic `[0, 1]` component through an optional
  opacity-Visual protocol. Apply it after Pict renderer dispatch.
- `fade-to` keeps a present Visual; `fade-in` introduces an absent Visual from
  opacity zero; `fade-out` removes a present Visual at the endpoint.
- Permit same-target requests only for disjoint animation components. Treat
  morph, `Create`, and `Uncreate` as path-geometry updates; treat `fade-in`
  and `fade-out` as opacity and presence updates, and `Create`/`Uncreate` as
  path and presence updates.
- Keep cosmetic stroke width independent of semantic scale.
- Do not use a process-global mutable Visual-id counter.
- Store drawing order explicitly from back to front.
- Keep previews, handles, pen strokes, and debug overlays outside the semantic
  exported scene unless deliberately animated.
- Goal/highlight styling overrides cosmetic user colors.
- Pass immutable ordered renderer sets explicitly; first supporting renderer
  wins, and no process-global renderer registry is mutated.

Browser/WebRacket adapters:
- Prefer WebRacket/browser/web-easy bindings and existing helper wrappers over
  raw js-ref, js-set!, or ad hoc JavaScript.
- Use raw JS FFI only for a genuinely dynamic API or a missing binding.
- Keep toolbar/group behavior data-driven; provide previews, snapping,
  overlap disambiguation, keyboard affordances, and clear status text.
- Preview settings live, but persist them only when the user saves.
- Report a minimal reproduction for a compiler/runtime problem instead of
  silently adding a workaround.

Testing/build:
- Run raco make main.rkt after source changes.
- Run raco test tests/scene-a-test.rkt tests/scene-a-render-test.rkt
  tests/scene-b-test.rkt tests/scene-b-render-test.rkt
  tests/scene-c-test.rkt tests/scene-c-render-test.rkt
  tests/scene-e-test.rkt tests/scene-e-render-test.rkt
  tests/scene-f-test.rkt tests/scene-f-render-test.rkt
  tests/scene-g-test.rkt tests/scene-g-render-test.rkt
  tests/scene-h-test.rkt tests/scene-h-render-test.rkt
  tests/scene-i-test.rkt tests/scene-i-render-test.rkt
  tests/scene-j-test.rkt tests/scene-j-render-test.rkt
  tests/scene-k-test.rkt tests/scene-k-render-test.rkt
  tests/scene-l-test.rkt tests/scene-l-render-test.rkt
  tests/scene-m-test.rkt tests/scene-m-render-test.rkt
  tests/scene-n-test.rkt tests/scene-n-render-test.rkt
  tests/scene-o-test.rkt tests/scene-o-render-test.rkt
  tests/scene-p-test.rkt tests/scene-p-render-test.rkt
  tests/scene-q-test.rkt tests/scene-q-render-test.rkt
  tests/scene-r-test.rkt tests/scene-r-render-test.rkt
  tests/scene-s-test.rkt tests/scene-s-render-test.rkt
  tests/scene-t-test.rkt tests/scene-t-render-test.rkt
  tests/scene-u-test.rkt tests/scene-u-render-test.rkt
  tests/scene-v-test.rkt tests/scene-v-render-test.rkt
  tests/scene-w-test.rkt tests/scene-w-render-test.rkt
  tests/scene-x-test.rkt tests/scene-x-render-test.rkt
  tests/scene-x-example-test.rkt
  tests/scene-y-test.rkt tests/scene-y-render-test.rkt.
- Keep pure model tests separate from rendering/filesystem/FFmpeg tests.
- Change only intended project files and leave unrelated user edits untouched.
```


## Number lines and coordinate decorations

- Keep a number line's numeric range, regular tick step, shaft length, tips,
  style, affine transform, and opacity as immutable semantic data.
- The number-line reference position represents numeric zero. Document this
  explicitly whenever a constructor or conversion operation changes.
- Build grid lines as semantic path geometry. Do not store Picts or drawing
  commands in the axes or number-line model.
- Preserve increasing numeric order for ticks and labels. Preserve x-labels
  before y-labels when an API returns one combined list.
- Numeric label constructors must require an explicit symbol prefix and derive
  stable collision-resistant child identities from that prefix and list order.
- Formatter procedures run only during construction, must accept one value, and
  must return exactly one string. Do not retain the procedure in model data.
- Automatic labels remain upright and are snapshot values. Their positions
  inherit the source coordinate object's current transform, but later changes to
  the source do not mutate or recompute existing labels.
- Grid and label gaps are semantic world-unit distances. Cosmetic stroke widths
  remain renderer-level pixel widths.
- Test conversion round trips, transformed positions, tick ordering, label
  identity order, empty decoration geometry, custom formatters, and deterministic
  rendering.

## Animated camera timelines

- Store one immutable current camera in every scene. A play or wait clip records
  both its complete Visual state and complete camera state.
- Keep camera animation in a pure module with no Pict, bitmap, filesystem,
  process, browser, or JavaScript dependency.
- Permit camera requests and Visual requests in the same `scene-play`. Compile
  relative requests from the camera at the beginning of that clip, not from a
  value captured when the request was constructed.
- Treat camera center and camera world width as independent components. Reject
  two center requests or two width requests in one play clip; allow one of each.
- Preserve camera pixel width, pixel height, aspect ratio, and background while
  interpolating center or visible world width.
- `camera-zoom-to` receives an absolute positive visible world width.
  `camera-zoom-by` receives a positive magnification factor: values above one
  zoom in by dividing the clip-start world width by the factor. Interpolate the
  resulting visible width linearly after easing, not logarithmically.
- Camera endpoints follow the easing result like Visual movement, rotation, and
  scale. Do not add a structural endpoint override for pan or zoom.
- `scene-camera-at` and `scene-sample` use the same closed time interval and the
  same half-open clip selection rules.
- `scene-set-camera` is instantaneous and appends no clip. As with an
  instantaneous Visual addition, follow it with a wait or play clip when the
  replacement must appear in rendered frames.
- Rendering without a camera keyword samples the scene camera at each frame.
  A supplied camera is a deliberate static override for every sampled frame.
- Keep renderer-aware layout functions on static camera values. Dynamic layout
  reflow during camera animation is not implicit.
- Test absolute and relative pan and zoom, mixed Visual/camera request order,
  duplicate-component rejection, wait holds, unusual easing, static overrides,
  fixed frame dimensions, and deterministic repeated PNG output.

## Renderer-aware camera framing and following

- Keep camera fitting at the Pict-adapter boundary. Text, formulas, groups, and
  custom Visuals must be measured through the same explicit renderer list used
  by final rendering.
- A fit request is an immutable snapshot. It stores only a concrete target
  center and visible world width; it must not retain Visuals, Picts, renderers,
  procedures, or a live scene connection.
- Apply equal padding in semantic world units before aspect-ratio correction.
  The fitted visible width is the maximum of the padded horizontal extent and
  the width needed to contain the padded vertical extent.
- Preserve camera pixel width, pixel height, aspect ratio, and background when
  fitting. A fit request changes both center and visible world width and
  therefore reserves both camera components in one play clip.
- Resolve `camera-fit-scene` targets against the scene's current top-level state
  by stable identity. Do not search nested group children implicitly.
- Treat fitting as a snapshot of current or explicitly supplied values. Do not
  silently recompute layout while geometry changes inside the same clip, and do
  not hide a fixed-point remeasurement policy. Document that fixed-pixel custom
  renderers can have different world extents at the fitted endpoint.
- Keep camera following clip-local. A follow request tracks one top-level
  Visual's reference position only during the play clip that contains the
  request; it is not persistent observer state.
- Preserve the followed target's normalized frame position. When zoom changes
  simultaneously, scale the target's world-space offset by the sampled visible
  width and height so its pixel position remains fixed.
- Compile follow metadata from the prepared clip-start state and preserve the
  target's pre-removal motion state for structural endpoints. During sampling,
  read the target's actual sampled Visual position rather than interpolating
  only between motion endpoints. This permits curved/path motion as well as
  same-clip `fade-in`, `create`, `fade-out`, and `uncreate`.
- A follow request changes the camera-center component. It may run with one
  zoom request, but conflicts with pan, fit, or another follow request.
- Test renderer-dependent fit dimensions, aspect-ratio correction, stable
  target lookup, fit conflicts, follow-plus-zoom, structural targets, fixed
  pixel positions, unusual easing, and deterministic repeated PNG output.


## Automatic open-path morph correspondence

- Keep open-path correspondence in pure semantic path geometry. Do not use
  renderer boxes, Picts, camera coordinates, frame rate, pixels, or output files
  to decide endpoint direction.
- Require exactly one positive finite open source subpath and one positive finite
  open destination subpath. Closed paths remain the responsibility of SCENE-AC,
  and compound pairing remains a separate stage.
- Sample source and destination at deterministic total-arc-length fractions that
  include both endpoints. Score mean Euclidean point distance for stored
  destination traversal and, when enabled, its exact semantic reversal.
- Select reverse traversal only for a strictly lower score. Exact score ties must
  preserve the caller's forward destination object. Do not introduce a cyclic
  phase search for open paths because their endpoints remain distinct.
- Return ordinary immutable `path-geometry`; when forward traversal wins, return
  the exact destination object. Use `path-geometry-reverse` only for the selected
  reversed correspondence.
- `morph-to-open-aligned` must preserve the exact clip-start source at eased
  progress zero and the exact caller-requested destination at eased progress one.
  Direction-aligned geometry is interior normalization correspondence only.
- Reserve the same path-geometry animation component as strict, normalized,
  closed-loop aligned, compound-aligned, create, and uncreate requests. Movement,
  rotation, scale, and opacity remain independently composable.
- Test reversed and forward-only correspondence, exact no-op and direction ties,
  cubic paths, invalid closed/compound/degenerate inputs, exact endpoints,
  renderer integration, and deterministic repeated PNG output.


## Topology-changing compound morph correspondence

- Keep SCENE-AH birth/death preparation in pure semantic path geometry. Never
  use renderer boxes, pixels, camera state, frame rate, or output files to decide
  which subpaths match or where unmatched seeds live.
- Validate every real source/destination subpath as positive finite geometry
  before introducing controlled degenerate seeds. Empty whole geometries are
  legal so pure birth from empty and pure death to empty remain expressible.
- Partition open and closed topology classes exactly as SCENE-AG does. Never pair
  an open path directly with a closed loop. When class counts differ, solve a
  rectangular minimum-cost assignment by padding only the forced count
  difference with deterministic zero-cost dummy slots; do not invent a semantic
  birth/death penalty in this stage.
- Reuse SCENE-AE forward/reverse scores for real open pairs and SCENE-AC
  phase/direction scores for real closed pairs. The smaller class side is thereby
  matched globally to the lowest-total-cost subset of the larger side.
- Represent an unmatched real subpath by a one-line-segment degenerate seed at
  that real subpath's exact axis-aligned path-bounds center. Preserve its
  `path-subpath-closed?` value. Births use the destination center; deaths use the
  source center. Do not guess semantic anchors or hole centers.
- Rebuild interior pairs with every existing source slot first in exact source
  order, then append birth-only slots in exact caller destination order. When
  both topology-class counts already match, reduce exactly to SCENE-AG and reuse
  its identity/alignment behavior.
- `morph-to-topology-changing` must use the prepared equal-count geometry only
  for normalized interior interpolation. Eased progress zero must preserve the
  exact clip-start source and eased progress one the exact caller destination,
  including endpoint subpath counts and storage order.
- Reserve the ordinary path-geometry animation component. Test pure birth/death,
  simultaneous class count changes, seed centers, rectangular subset selection,
  SCENE-AG reduction, exact endpoints, invalid pre-existing degenerate subpaths,
  rendering, and deterministic repeated PNG output.


## Explicit topology-changing morph anchors

- Keep SCENE-AI anchor selection semantic and declarative. `#:birth-anchor` and
  `#:death-anchor` accept only the exact symbol `'bounds-center` or one finite
  local `vec2`; do not use callbacks, renderer boxes, pixels, camera state, frame
  rate, or mutable anchor maps in this stage.
- Preserve SCENE-AH as the default exactly. Omitting both keywords, or passing
  `'bounds-center`, must place each unmatched seed at the real subpath's exact
  axis-aligned path-bounds center.
- An explicit `vec2` is local path geometry, not world/frame coordinates. All
  births on the destination side share `#:birth-anchor`; all deaths on the source
  side share `#:death-anchor`. Visual transforms apply later through the existing
  path Visual model.
- Anchor options may affect only unmatched slots. In the SCENE-AI forced-only
  policy those slots come only from topology-count differences; SCENE-AJ may
  create additional voluntary unmatched slots through numeric penalties. Anchor
  choice itself must not change real-pair scores, topology partitioning,
  destination direction/phase, or slot ordering.
- Preserve exact structural endpoints: source at eased progress zero and exact
  caller destination at eased progress one. Synthetic anchored seeds remain
  interior normalization correspondence only.
- Test explicit and default anchors, pure birth/death, simultaneous birth/death,
  transformed Visual locality, invalid anchor values, exact endpoints, component
  conflicts, rendering, and deterministic repeated PNG output.
- SCENE-AI itself uses only one shared fallback point per side. SCENE-AK adds
  sparse original-subpath-index overrides without changing the shared fallback
  semantics. Penalty-driven optional birth/death remains SCENE-AJ policy.


## Per-subpath topology-changing morph anchors

- Keep SCENE-AK additive to SCENE-AI: `#:birth-anchor` and `#:death-anchor`
  remain the shared fallbacks. `#:birth-anchor-map` and `#:death-anchor-map`
  are sparse overrides only; empty maps must reproduce SCENE-AI exactly.
- Use original caller path indexes as stable map keys. Birth-map keys address the
  exact destination subpath list supplied by the caller; death-map keys address
  the exact clip-start source subpath list. Topology partitioning, assignment,
  reordering, reversal, and closed-loop phase selection must never renumber map
  lookup keys.
- Accept only hash maps with exact nonnegative integer keys and anchor values
  accepted by SCENE-AI (`'bounds-center` or finite local `vec2`). Direct geometry
  preparation must reject out-of-range keys for the corresponding endpoint path.
- A missing map key falls back to the shared anchor. An explicit
  `'bounds-center` map value overrides an explicit shared `vec2`, allowing one
  subpath to opt back into its own bounds center.
- Apply map overrides only to unmatched slots. Matched real pairs must ignore
  anchor maps completely, and anchor choice must not affect pair scores,
  assignment, direction/phase, penalties, slot order, or endpoint storage.
- SCENE-AJ voluntary unmatched slots use the same original-index map lookup as
  forced count-difference slots. Do not introduce separate map semantics for
  numeric penalty mode.
- Timeline requests must snapshot caller hash contents into immutable maps at
  request construction so later mutation cannot change animation semantics.
- Test sparse fallback, per-index birth/death placement, explicit bounds-center
  overrides, penalized voluntary slots, mutable-map snapshotting, range/value
  validation, exact endpoints, rendering, and deterministic PNG output.
- Do not add per-subpath penalty maps, appearance-aware matching, semantic hole
  inference, or open-to-closed correspondence in SCENE-AK. SCENE-AL later adds
  sparse numeric penalty overrides without changing these anchor-map rules.


## Penalized topology-changing correspondence

- Preserve the exact SCENE-AH/AI default. Omitting `#:birth-penalty` and
  `#:death-penalty`, or passing `'forced` for both, must retain forced-only dummy
  slots and exact equal-count reduction to SCENE-AG.
- Numeric penalty mode requires both keywords together as finite nonnegative
  local path-unit costs. Do not silently mix one numeric side with one forced
  side, and reject infinities, NaNs, negatives, callbacks, or renderer-derived
  values.
- Optimize one topology class at a time. Real source/destination edges keep the
  existing SCENE-AC/AE correspondence score; source-to-dummy edges cost the death
  penalty; dummy-to-destination edges cost the birth penalty; unused dummy pairs
  cost zero. Never pair open paths directly with closed loops.
- Use a global assignment, not greedy pair rejection. A source and destination
  may be voluntarily unmatched even when class counts are equal if death plus
  birth lowers total primary cost.
- Treat topology-change count as a secondary lexicographic objective. Exact
  primary-cost ties must prefer fewer births/deaths so a real correspondence is
  retained when its cost merely equals replacement cost. Preserve deterministic
  index ordering after both objectives tie.
- Reuse SCENE-AI seed placement for every unmatched slot, whether forced by count
  difference or selected voluntarily. Penalties may affect assignment only; they
  must not affect anchor location, direction/phase scoring, interpolation,
  rendering, or exact endpoint storage.
- Preserve exact source storage at eased progress zero and exact caller
  destination storage at eased progress one. Synthetic voluntary slots remain
  interior normalization correspondence only.
- Test forced/default compatibility, low/high penalties, exact cost ties,
  selective global rejection, unequal counts, explicit anchors, validation,
  exact endpoints, conflicts, rendering, and deterministic repeated PNG output.
- Do not add per-subpath penalty maps, appearance-aware scoring, semantic hole
  inference, or open-to-closed correspondence in SCENE-AJ. SCENE-AK may vary
  seed anchors per original subpath index without changing this cost policy;
  SCENE-AL may vary numeric dummy-edge costs per original subpath index.


## Per-subpath topology-changing penalties

- Keep SCENE-AL additive to SCENE-AJ: `#:birth-penalty` and `#:death-penalty`
  remain the shared numeric fallbacks. `#:birth-penalty-map` and
  `#:death-penalty-map` are sparse overrides only; empty maps must reproduce
  SCENE-AJ numeric behavior exactly.
- Use original caller path indexes as stable map keys. Birth-map keys address
  the exact destination subpath list supplied by the caller; death-map keys
  address the exact source subpath list at preparation/clip start. Topology
  partitioning, global assignment, destination reorder, open reversal, and
  closed-loop phase must never renumber these keys.
- Accept only finite nonnegative real map values. Missing entries fall back to
  the corresponding shared numeric penalty. Do not add symbolic per-entry modes,
  callbacks, renderer values, camera state, or mutable cost procedures.
- Nonempty penalty maps require AJ numeric mode: both shared penalties must be
  finite nonnegative reals. Reject nonempty maps when the shared policy is
  `'forced` rather than inventing mixed forced/numeric dummy-edge semantics.
- Apply penalty-map overrides only to dummy edges: a death edge reads the
  original source index and a birth edge reads the original destination index.
  Real source/destination candidate scores remain the existing SCENE-AC/AE
  geometric scores.
- Preserve AJ's global augmented assignment and lexicographic tie rule. The
  primary objective uses the resolved per-edge costs; exact primary ties still
  prefer fewer topology changes, then deterministic index order.
- Preserve SCENE-AI/AK anchor semantics independently. Cost maps decide whether
  a slot is unmatched; anchor maps decide where the resulting unmatched slot
  collapses/grows. Neither family may mutate the other's lookup or scoring.
- Timeline requests must snapshot caller penalty hashes into immutable maps at
  request construction. Direct geometry preparation rejects out-of-range keys;
  request compilation validates ranges against the clip-start source and stored
  destination.
- Preserve exact source storage at eased progress zero and exact caller
  destination storage at eased progress one. Sparse costs affect only interior
  correspondence preparation.
- Test shared-cost fallback, source/destination original-index overrides,
  reordered assignment, mixed topology, one-sided maps, immutable snapshots,
  forced-mode rejection, range/value validation, exact endpoints, rendering,
  and deterministic repeated PNG output.
- Do not add appearance-aware matching, semantic hole inference, direct
  open-to-closed correspondence, or arbitrary per-pair scoring callbacks in
  SCENE-AL. SCENE-AM may add sparse numeric real-edge penalties without changing
  the geometric scorer or introducing callbacks.


## Per-pair real-match penalties

- Keep SCENE-AM additive to SCENE-AJ/AL. `#:match-penalty-map` is a sparse
  additive cost on real source/destination assignment edges; it must not replace
  SCENE-AC/AE geometric scores or alter birth/death dummy costs.
- Key every entry by the original caller pair
  `(cons source-index destination-index)`. Topology partitioning, class-local
  ordering, global assignment, open reversal, closed-loop phase, and augmented
  dummy rows/columns must never renumber these indexes.
- Accept only finite nonnegative numeric pair penalties. Missing entries add
  zero. Keep the API data-oriented: no procedures, renderer state, camera state,
  mutable callbacks, or appearance queries participate in match scoring.
- Apply the pair penalty after selecting the best allowed direction/phase for
  that real candidate edge. Thus one sparse cost biases semantic identity while
  leaving SCENE-AC/AE alignment semantics unchanged.
- Support pair penalties in both policy modes. In `'forced` mode, nonempty maps
  must bypass the equal-count SCENE-AG fast path and participate in the ordinary
  topology-class assignment. In numeric AJ mode, add the pair penalty to the
  real edge before comparing it with birth/death alternatives.
- Preserve AJ's lexicographic tie rule. A real edge whose total primary cost
  exactly equals death plus birth still wins on fewer topology changes.
- Reject out-of-range keys and keys that name open-to-closed or closed-to-open
  pairs during geometry preparation. Timeline requests validate key shape and
  values when constructed, snapshot the hash immutably, then validate range and
  topology at clip compilation when the source geometry is available.
- Preserve AK anchor maps and AL dummy-edge cost maps independently. Pair costs
  affect only real assignment edges; endpoint penalty maps affect only dummy
  edges; anchor maps affect only selected unmatched seed positions.
- Preserve exact source storage at eased progress zero and exact caller
  destination storage at eased progress one. Pair penalties affect only
  interior correspondence preparation.
- Test forced/equal-count reassignment, forced unequal-count subset selection,
  numeric voluntary replacement, exact ties, mixed-topology original indexes,
  malformed/out-of-range/impossible keys, immutable request snapshots,
  rendering differences, and deterministic repeated PNG output.
- Do not add arbitrary scoring callbacks, appearance-aware scoring, semantic
  hole inference, or direct open-to-closed correspondence in SCENE-AM.


## Automatic mixed-topology compound morph correspondence

- Keep mixed-topology correspondence in pure semantic path geometry. Partition
  candidates by the existing `path-subpath-closed?` topology bit; never use
  renderer appearance, fill behavior, camera state, or spatial overlap to infer
  whether an open path may pair with a closed loop.
- Require a nonempty source, positive finite length for every participating
  subpath, equal open counts, and equal closed counts. SCENE-AG itself must reject
  unequal counts; use SCENE-AH for controlled birth/death semantics.
- Solve open and closed assignment classes independently. Reuse SCENE-AE/AF
  forward-versus-reverse scoring for open candidate pairs and SCENE-AC/AD
  phase/direction scoring for closed candidate pairs. Do not invent a cross-class
  penalty merely to feed one larger assignment matrix.
- After both class assignments, rebuild destination correspondence in exact source
  subpath order. Reuse exact destination subpath objects whenever their selected
  direction/phase is unchanged, and return the exact destination geometry when
  the complete correspondence is already a no-op.
- The mixed-capable geometry operation may reduce to the homogeneous AF or AD
  behavior when one topology class is empty; keep those public APIs unchanged.
- `morph-to-mixed-compound-aligned` must preserve the exact clip-start source at
  eased progress zero and exact caller-requested destination at eased progress
  one. All class pairing/reordering/alignment remains interior correspondence.
- Reserve the ordinary path-geometry animation component. Test interleaved mixed
  topology, class-local global assignment, homogeneous reductions, direction/
  phase alignment, topology-count mismatch, degenerate paths, exact endpoints,
  rendering, and deterministic repeated PNG output.


## Automatic open-compound morph correspondence

- Keep multi-open pairing in pure semantic path geometry. Reuse SCENE-AE
  endpoint-direction scores for every candidate pair and the deterministic global
  assignment policy from SCENE-AD; do not inspect renderer or camera state.
- Require equal nonzero subpath counts and require every source/destination
  subpath to be open with positive finite length. Use SCENE-AG for matching-count
  mixed open/closed topology and SCENE-AH when topology-class counts differ.
- Cache one source open path's total-arc-length samples while evaluating every
  destination candidate. For each pair, reverse destination traversal only when
  SCENE-AE's reversed score is strictly lower; exact direction ties stay forward.
- Solve pairing globally rather than greedily. Reuse the same deterministic
  minimum-total-cost assignment and destination-index tie rules as SCENE-AD.
- Return ordinary immutable `path-geometry` reordered to source correspondence.
  Reuse exact destination subpath objects when a pair keeps stored direction, and
  return the exact destination geometry when the whole correspondence is a no-op.
- `morph-to-open-compound-aligned` must preserve the exact clip-start source at
  eased progress zero and the exact caller-requested destination at eased progress
  one. Reordering/reversal is interior normalization correspondence only.
- Reserve the ordinary path-geometry animation component. Movement, rotation,
  scale, and opacity remain independently composable.
- Test reordered/reversed compounds, global-versus-greedy assignment, exact ties,
  one-subpath reduction to SCENE-AE, forward-only mode, invalid mixed/closed/empty/
  unequal/degenerate inputs, exact endpoints, rendering, and deterministic PNGs.


## Automatic compound-path morph correspondence

- Keep compound pairing in pure semantic path geometry. Build pair costs from
  SCENE-AC total-arc-length loop correspondence; never inspect Picts, pixels,
  camera state, renderer bounds, frame rate, or output files.
- Require equal nonzero subpath counts in this stage, and require every paired
  candidate subpath to be closed with positive finite length. Do not silently
  create/remove loops or mix open/closed topology.
- Evaluate every source/destination pair before assignment. Use a deterministic
  minimum-total-cost assignment rather than greedy storage-order matching.
- Reuse SCENE-AC phase/direction alignment within each candidate pair, including
  its forward-on-direction-tie and smaller-phase tie rules. Cache one source
  loop's score samples across all destination candidates in that assignment row.
- Resolve exact assignment ties deterministically. Prefer preserving earlier
  source-row matches when an equally good free destination is available, then
  prefer the lower destination index. Do not use randomness or hash iteration.
- Return ordinary immutable `path-geometry` with destination subpaths reordered
  to source correspondence. Reuse untouched destination subpath objects when no
  phase/direction change is required, and return the original destination object
  when pairing/alignment changes nothing.
- `morph-to-compound-aligned` must preserve the exact clip-start source at eased
  progress zero and the exact caller-requested destination at eased progress one.
  Reordered/aligned geometry is interior normalization correspondence only.
- Reserve the same path-geometry animation component as strict, normalized,
  one-loop aligned, create, and uncreate requests. Movement, rotation, scale,
  and opacity remain independently composable.
- Test reordered compounds, global-versus-greedy assignment, exact assignment
  ties, one-loop reduction, forward-only mode, unequal/empty/open/degenerate
  validation, normalized interior state, exact endpoints, renderer integration,
  and deterministic repeated PNG output.


## Automatic closed-loop morph correspondence

- Keep automatic correspondence in semantic path geometry. Do not sample Picts,
  camera coordinates, rendered pixels, or frame output to choose a morph match.
- Treat phase/direction alignment as preparation for morph normalization, not as
  a replacement path representation. Return ordinary immutable `path-geometry`
  and reuse the existing cubic normalization/interpolation pipeline.
- Restrict the first automatic correspondence stage to exactly one positive
  finite closed subpath on each side. Do not silently invent pairings for
  compound figures, holes, or disconnected subpaths.
- Score correspondence in total-arc-length coordinates using a fixed deterministic
  sample count. Include stored positive-edge boundary phases in the coarse
  candidates so exact vertex correspondences are not lost to a uniform grid.
- Search both traversal directions only when explicitly allowed. On exact score
  ties, prefer forward traversal; on exact phase ties, prefer the smaller phase.
  Symmetric figures must not reverse or split gratuitously.
- Use a fixed number of refinement rounds. Alignment must not depend on frame
  rate, renderer tolerance, wall-clock time, randomness, or adaptive time budget.
- `morph-to-aligned` must preserve the exact clip-start source at eased progress
  zero and the exact caller-requested destination at eased progress one. Use the
  aligned/reversed/cycled geometry only as the interior normalized correspondence.
- Reserve the ordinary path-geometry animation component. Aligned, normalized,
  strict, create, and uncreate requests therefore conflict on one target, while
  movement, rotation, scale, and opacity remain independently composable.
- Test phase-only matching, reverse matching, forward-only mode, symmetric/no-op
  ties, cubic interior phases, exact endpoint representation, request conflicts,
  invalid open/compound/degenerate inputs, rendering integration, and deterministic
  repeated PNG output.


## Joined offset path geometry

- Keep joined offsets as ordinary semantic `path-geometry`. Do not add renderer
  stroke state, sampled Picts, or a second motion-route representation merely to
  make a parallel path continuous.
- Define signed offset geometrically relative to stored traversal: positive is
  left, negative is right. Reverse animation does not implicitly change a path
  construction that was already completed.
- Apply miter, bevel, and round policies only on the outside of a turn. Resolve
  the inside with the natural intersection of the adjacent shifted lines so the
  path does not reverse tangent through a short inside arc.
- Represent round outside joins with semantic cubic Bézier pieces, splitting
  sweeps so no piece exceeds a quarter turn. Keep the construction deterministic
  and independent of camera scale or renderer tolerance.
- Bound outside miters with an explicit geometric ratio. Fall back to bevel when
  the intersection exceeds the selected miter limit rather than allowing
  unbounded spikes.
- Reject nonzero joined offsets when a source edge has no direction, at exact
  180-degree reversals, or for source segment families whose offset semantics
  have not yet been specified. A zero offset remains an identity operation.
- Let existing path consumers operate on the generated geometry unchanged. Test
  direct rendering, arc-length motion, tangent orientation, camera following,
  closed paths, join fallback, invalid geometry, and deterministic PNG output.


## Path-following motion

- Keep motion routes semantic. Reuse path geometry and the deterministic
  arc-length model; do not pre-render a route or store sampled Picts.
- Let linear timeline progress mean linear total arc-length progress. Curves use
  the same deterministic adaptive arc-length approximation as reveal/extraction.
- Resolve a path Visual by stable identity at clip compilation and apply its
  current affine transform before measuring world-space arc length. A stale
  constructor value therefore names the current scene route rather than storing
  stale coordinates.
- Treat raw path geometry as coordinates in the motion target's containing
  coordinate system. Reject a world path Visual route for a frame-space target.
- Reserve the translation component for path motion. Same-target `move-to` and
  `move-along-path` conflict; disjoint animation components may compose.
- Compute unit path tangents and left normals from the same ordered arc-length
  model as point lookup. For cubics, use the geometric derivative with a
  deterministic one-sided fallback at stationary points. Exact edge boundaries
  retain the preceding traversal edge, matching point lookup.
- Keep tangent orientation explicit through `orient-along-path`, reserving the
  rotation component independently from translation. A constant rotation offset
  may adjust a Visual whose natural forward axis is not local positive x.
- Snapshot the route for the clip. Dynamic route deformation remains separate
  future semantics; neither translation offsets nor orientation observe a path
  Visual changing during the same clip.
- Camera follow must consume the sampled target state when present. Preserve a
  camera-only fast path for clips without follow requests.
- Test unequal edge lengths, cubic arc lookup, implicit closure, reverse and
  partial fractions, transformed path Visuals, stale-id resolution, route gaps,
  coordinate-domain rejection, camera-follow elbows/curves, and deterministic
  repeated rendering.

## Frame-space overlays and callouts

- Keep frame-space overlays as pure semantic Visual wrappers. Store semantic
  content and a captured visible frame width; never cache Picts, bitmaps, drawing
  contexts, renderer objects, or live camera observers in the wrapper.
- Give frame space an origin-centered y-up coordinate system. Derive its render
  camera from the current output pixel dimensions and the wrapper's captured
  visible width, while deliberately ignoring later world-camera center and zoom.
- Preserve the wrapped content's stable identity. Render that content at a local
  origin, preserve its own style/geometry/affine state, and apply the wrapper's
  affine transform and opacity as an additional outer layer.
- Keep frame-space wrappers top-level. Do not mix them into ordinary world-space
  groups; for compound overlays, build an ordinary group first and wrap the
  complete group. Do not nest one frame-space wrapper inside another.
- Let fixed overlays participate in the ordinary immutable timeline protocols for
  move, rotation, scale, opacity, fade, and scene ordering. These changes
  modify frame-space semantic state, not camera state.
- Treat a callout as a hybrid only at the adapter boundary: its annotation lives
  in frame space, while its target is either a fixed world point or a stable
  top-level world Visual identity resolved from each sampled scene state.
- Draw callout leaders in the Pict adapter, beneath the annotation. Connector
  width is cosmetic output-pixel width, and wrapper opacity applies to the leader
  exactly once. Do not retain target Visual values as live observer state.
- Relative layout may combine world Visuals with world Visuals, or frame Visuals
  that share one captured frame width. Reject mixed coordinate domains and
  incompatible frame widths. Measure a callout by its annotation only, not by its
  cross-space connector.
- Exclude frame-space objects from world-camera semantics. Implicit scene fitting
  ignores them, explicit fitting rejects them, and camera following rejects them.
- Test camera-independent pixel output, ordinary frame-space animation, renderer-
  aware measurement, group-domain rejection, moving callout targets, missing
  targets, camera-fit/follow separation, and deterministic repeated PNG output.

## Point markers, scatter plots, and filled coordinate areas

- Keep point-marker shape, size, fill, stroke, transform, and opacity as pure
  semantic model data. Do not store Picts or renderer callbacks in a marker.
- Keep the supported marker-shape set explicit. Size is a local world-unit
  extent; cosmetic stroke width is not multiplied by semantic scale.
- Perform explicit renderer selection before built-in marker fallback. Convert
  unsupported built-in markers to existing circle, rectangle, or path Visuals,
  and apply semantic opacity exactly once after conversion.
- Build scatter plots as immutable ordered groups. Preserve input order and
  derive child identities from the plot identity and original list index.
  Omitting a gap or clipped point must not renumber later markers.
- Treat scatter clipping as a center-point test. Do not silently clip marker
  geometry at an axes boundary.
- Copy the axes placement as a construction-time snapshot. Include the current
  nonuniform axes scale in marker positions, but keep marker glyphs upright and
  at their requested world-unit size.
- Build filled coordinate areas as ordinary closed semantic path subpaths.
  Close each accepted graph or data run separately to one horizontal baseline.
- Reuse the existing function and data sampling rules. Preserve explicit gaps,
  clipping, jump or distance breaks, and linear or smooth interpolation.
- When clipping is enabled, clamp the baseline to the visible y range. Document
  that the operation fills beneath the visible accepted path rather than
  reconstructing regions whose complete graph lies outside the display.
- Keep cubic graph segments cubic inside filled areas. Add straight baseline
  edges without flattening the sampled boundary.
- Test marker fallback and custom overrides, input-index identities, transformed
  scatter placement, baseline clamping, discontinuous areas, smooth area
  segments, ordinary timeline behavior, and deterministic PNG output.

## Local visual animation timing

- Keep SCENE-AN/AR timing semantic and renderer-independent. A timed request
  stores one ordinary Visual request or one sequential/parallel/lagged
  composition plus local start, duration, and optional easing; never store
  frames, Picts, bitmaps, timers, or mutable scheduler state.
- At top level, measure timed start and duration in seconds from the enclosing
  `scene-play` boundary and require the endpoint to fit the clip. Inside a
  composition, interpret the same values as intrinsic timing units that are
  proportionally scaled by the parent. Starts remain nonnegative finite and
  durations positive finite.
- Preserve the historical `scene-play` code path exactly when no `timed` wrapper
  or animation composition is present. In a locally scheduled clip, an ordinary
  unwrapped Visual request spans the full enclosing duration and inherits the
  enclosing easing.
- Let a timed request with no local easing inherit its enclosing timing context.
  A supplied local easing replaces the inherited easing. For a timed composition
  it becomes the inherited easing of descendant leaves; a nested timed child may
  override it. Do not compose easing functions implicitly.
- Compile equal-start Visual requests together so `fade-in` and `create`
  placeholders retain historical shared-start behavior. Compile later start
  batches against the exact semantic state at their local boundary.
- Treat positive-measure overlap on one target/component as a conflict. Exact
  endpoint touching is legal, so a later relative request may compile from the
  earlier request's exact endpoint.
- Process a local event boundary in this semantic order: sample all previously
  active component values at the boundary; apply structural endpoint rules;
  remove ended leaves; install same-time introductions; then sample newly
  starting leaves at local progress zero. This ordering must be independent of
  request order and support same-ID reintroduction at a removal boundary.
- Do not allow `fade-out` or `uncreate` to remove a target while another
  same-target animation remains active past that removal time.
- Keep arbitrary-time sampling direct. Reconstruct a requested state from
  compiled semantic event data; never obtain frame N by evaluating frames
  0 through N-1.
- Keep camera requests full-clip through SCENE-AW. `camera-follow` must consume
  the actual locally scheduled Visual state. Timed camera requests remain a
  later stage.
- Test delayed starts, endpoint holding, inherited/overridden easing, touching
  relative requests, overlap rejection, structural introduction/removal,
  same-boundary endpoint ordering, camera follow, exact final state, legacy
  no-composition behavior, rendered timing, and deterministic repeated PNG output.

## Successive visual animation composition

- Keep SCENE-AO succession as pure schedule data. Through SCENE-AQ a succession
  stores ordered ordinary Visual animation children or nested sequential/parallel/
  lagged compositions; never store compiled leaves, sampled scene states, frames, Picts,
  or mutable scheduler state in the public composition value.
- Assign a top-level succession the complete enclosing `scene-play` duration in
  this stage. Divide that interval equally among direct children in argument
  order. Treat any nested composition as one direct child; a nested succession
  divides its share, a nested parallel group reuses that complete share, and a
  nested lagged start staggers children inside that share.
- Apply the enclosing `scene-play` easing independently to each ordinary
  succession leaf's normalized local progress. Do not ease the outer sequence
  once and then derive child time from that eased value.
- Expand succession into the same local leaf representation used by SCENE-AN.
  Compile every later leaf against the exact semantic state at its own start
  boundary; do not implement a second sequence-specific sampling engine.
- Run overlap and structural-removal validation on expanded leaves so top-level
  ordinary or timed siblings compose according to their concrete intervals.
  Touching same-component sequence leaves remain legal.
- Preserve AN event ordering at every child boundary: old component endpoints,
  structural finalization, same-time introductions, then new progress-zero
  samples. This must support `fade-in` followed by motion and exact-boundary
  removal/reintroduction.
- Keep `timed` leaf-only through SCENE-AQ and reject timed wrappers inside
  composition values. Keep camera requests outside compositions and full-clip.
  Defer explicit child durations, timed composites, and general duration
  rescaling until their composition semantics are defined.
- Accept a nonempty direct child list only. Snapshot the ordered child list in
  the succession value so caller-side list construction cannot change the
  composition later.
- Test equal slices, nested subdivision, relative endpoint chaining, easing
  reset per leaf, siblings and conflicts, structural boundaries, camera follow,
  list-form construction, rendered chronology, exact final state, and
  deterministic repeated PNG output.

## Parallel visual animation composition

- Keep SCENE-AP `animation-group` as pure schedule data. Through SCENE-AQ it
  stores a nonempty,
  immutable ordered child spine made from ordinary Visual requests, successions,
  nested animation groups, or lagged starts; never store compiled animations or
  sampled states.
- Give every direct animation-group child the same complete interval assigned to
  the group. Do not divide group duration by child count. A nested group reuses
  that interval recursively; a nested succession divides it according to AO; a
  nested lagged start staggers children according to AQ.
- Expand groups into the same `visual-request-spec` leaves used by AN/AO. Do not
  add a parallel-clip representation or sample child groups independently.
- Preserve deterministic direct-child order when several expanded leaves start at
  the same instant. Compile that equal-start batch together so historical
  simultaneous introduction and component-composition semantics remain intact.
- Run the existing overlap validator after full composition-tree expansion. Two
  parallel leaves may share a target only when their reserved animation
  components are disjoint; same-component positive overlap remains an error.
- Allow `succession`, `animation-group`, and `lagged-start` to nest in any
  direction. Mixed trees must preserve exact local boundary compilation, structural
  event ordering,
  arbitrary-time sampling, and camera-follow behavior.
- Keep `timed` wrappers and camera requests outside nested compositions through AQ.
  Their local scaling/inheritance semantics belong to later composition stages.
- Test shared group intervals, same-component conflict rejection, group-in-sequence
  and sequence-in-group timing, recursive group nesting, per-leaf easing,
  structural simultaneous introduction/removal, camera follow, rendered parallel
  motion, exact final state, and deterministic repeated PNG output.


## Lagged visual animation composition

- Keep SCENE-AQ `lagged-start` as pure schedule data: one nonempty immutable
  ordered child spine plus one nonnegative finite lag ratio. Never store compiled
  requests, sampled states, frames, Picts, or renderer state in the public value.
- For assigned duration `D`, direct-child count `n`, and lag ratio `r`, assign
  every direct child duration `D / (1 + (n - 1) r)`. Offset consecutive starts by
  `r` times that child duration. The final child must end exactly at the assigned
  outer endpoint.
- Preserve the semantic boundary cases: ratio zero is parallel-group timing;
  ratio one is equal-slice succession timing; ratios between zero and one overlap;
  ratios greater than one create hold gaps. The public default is `1/4`.
- When inexact arithmetic is involved, correct the final direct child's effective
  duration against the exact assigned interval endpoint. Do not let floating-point
  rounding place the final leaf slightly past the enclosing clip endpoint.
- Expand lagged starts into the same `visual-request-spec` leaves used by AN–AP.
  Do not introduce a lag-specific clip, sampler, renderer path, or mutable clock.
- Permit `lagged-start`, `succession`, and `animation-group` to nest in any
  direction. Each direct child receives one computed lagged interval and applies
  its own composition rule recursively inside that interval.
- Validate same-component overlap only after complete tree expansion. This makes
  overlapping same-component children an error for ratios below one while exact
  touching at ratio one remains legal and supports relative endpoint chaining.
- Preserve AN structural event ordering, local leaf easing, exact endpoint
  sampling, arbitrary-time reconstruction, and full-clip camera-follow behavior.
- Keep `timed` leaf-only and camera requests top-level through AQ. Explicit child
  durations, timed composites, and general composite duration scaling remain
  later-stage semantics.
- Test ratio validation and defaults, zero/unit boundary equivalence, overlap and
  gaps, same-component conflicts, nested mixed composition trees, easing reset,
  structural introduction/removal, camera follow, exact endpoints, rendered
  stagger chronology, and deterministic repeated PNG output.

## Duration-scaled visual animation composition

- SCENE-AR makes `timed` the explicit duration/delay primitive inside Visual
  composition trees. Permit it to wrap an ordinary Visual request or one
  `succession`, `animation-group`, or `lagged-start`; permit timed wrappers as
  direct children of those three composition forms. Keep camera requests outside
  compositions and reject `timed` around another `timed` wrapper.
- Preserve AO–AQ behavior when no nested timing is present. An unwrapped direct
  child always contributes one intrinsic timing unit, including a bare nested
  composition. A timed direct child contributes `start + duration` units. Wrap a
  nested composition explicitly when it should reserve a non-unit parent span.
- For succession, place direct child spans consecutively, scale their sum to the
  assigned outer duration, and correct the final child against the exact outer
  endpoint. A timed child's scaled delay is part of its allocated sequence span.
- For animation groups, start all direct children at the group start and scale
  against the longest direct child span. Shorter children finish early and hold
  their endpoints. With only unwrapped children every span is one, preserving AP
  full-interval timing exactly.
- For lagged starts, compute raw child starts from the previous direct child's
  span: `start[i+1] = start[i] + lag-ratio * span[i]`. Scale the complete raw
  envelope to the assigned duration. Ratio zero must equal duration-scaled group
  timing and ratio one must equal duration-scaled succession timing.
- A nested timed wrapper maps its intrinsic `start` and `duration` into the
  concrete interval assigned by its parent. Its active content ends at that
  assigned child endpoint; correct arithmetic against the exact endpoint rather
  than allowing inexact multiplication to drift past it.
- A top-level timed composition keeps literal second-based start/duration and
  scales the wrapped composition inside only that active interval. Before its
  start it has no effect; after its active endpoint its semantic endpoint holds.
- Expand all AR composition timing to the existing `visual-request-spec` leaf
  representation before conflict/removal validation and compilation. Do not add
  a duration-specific clip, mutable clock, frame dependency, or renderer path.
- Test weighted succession, delayed nested children, timed whole compositions,
  timed nested compositions, unequal-duration groups, zero/unit lag equivalence,
  inherited and overridden easing, structural events, post-expansion conflicts,
  camera-follow, exact endpoints, rendered chronology, and deterministic repeated
  PNG output. Keep the AO–AQ no-nested-timing suites as regression coverage.

## Stroke-width Visual animation

- SCENE-AS starts style animation with an optional semantic capability protocol,
  not concrete-type dispatch in the animation engine. A Visual that participates
  implements `gen:stroke-width-visual`, `visual-stroke-width`, and
  `visual-with-stroke-width`; `stroke-width?` is the shared nonnegative finite-real
  domain predicate.
- Built-in circles, rectangles, paths, arrows, axes, number lines, and point
  markers implement the protocol. Plot curves/areas that are themselves path
  Visuals inherit it. Do not claim that a `scatter-plot` group is a width target:
  its nested point-marker children are not top-level scene-state targets. Keep
  callout `connector-width` separate as frame-space connector style.
- `stroke-width-to` is an absolute request and owns the `stroke-width` animation
  component. It may overlap same-target translation, rotation, scale, opacity, or
  path-geometry changes, but overlapping same-target stroke-width leaves conflict
  after AN-AR schedule expansion. Exact touching remains legal.
- Keep stroke width semantic and renderer-independent. Do not add a style-specific
  clip, sampler, frame cache, or renderer animation branch; built-in renderers read
  the sampled Visual value they already support.
- Validate custom protocol behavior during request/scene compilation. The getter
  must return `stroke-width?`; the setter must return a Visual that still
  implements the protocol, preserve identity, and install the requested endpoint
  exactly, including exact/inexact numeric representation. Numeric `=` alone is
  insufficient for this endpoint check.
- Treat zero as a valid width, not as scene removal or stroke-style replacement.
  At raw/eased progress one, install the requested numeric endpoint directly so an
  exact destination is not contaminated by an inexact source value. The default
  Pict/racket/draw backend renders width zero as a device-dependent hairline and
  accepts pen widths only through 255 pixels. Keep `stroke-width?` renderer
  independent; report the narrower backend limit at rendering time.
- Test every built-in protocol implementation, direct and symbolic targets,
  invalid widths/unsupported Visuals, custom protocol validation including
  exact/inexact endpoint coercion, exact endpoints, scatter/callout exclusions,
  zero-width hairline behavior, the default backend width limit, compatible
  parallel components, overlap conflicts, sequential and locally timed chaining,
  structural introduction, independent renderer propagation for every built-in
  protocol type, fixed frame dimensions, and deterministic repeated PNG output.

## Fill/stroke color Visual animation

- SCENE-AT adds renderer-independent `rgba-color` values and supported textual
  `color-spec?` parsing without importing `racket/draw` into semantic model or
  animation modules. Convert semantic RGBA values only in renderer adapters.
- Preserve existing constructor style strings and `#f` paint sentinels. Exact
  animation boundaries must install the caller's original source/destination
  color specification; only interior samples normalize to `rgba-color`.
- `gen:fill-color-visual` and `gen:stroke-color-visual` are independent optional
  protocols. Circles, rectangles, paths, and point markers implement both;
  arrows, axes, and number lines implement stroke color. Keep text/formula color
  outside this stage. Do not claim that scatter-plot groups expose their nested
  marker colors as animation targets, and keep callout connector paint separate.
- `fill-color-to` owns the `fill-color` scheduler component and `stroke-color-to`
  owns `stroke-color`. They may overlap each other and stroke width, opacity,
  affine, and path geometry; same-target same-component overlap conflicts after
  AN--AR expansion. Exact touching is legal and chains from the exact prior style.
- A current fill/stroke value of `#f` means paint is absent and is not a color
  interpolation source. Do not silently reinterpret it as transparent; callers
  who want alpha interpolation can use the textual `transparent` color or an
  alpha-bearing `rgba-color`.
- Validate custom color protocol getters/setters at request/scene compilation.
  A source must satisfy `color-spec?`; setters must return a Visual that still
  implements the protocol, preserve identity, and install the requested endpoint
  exactly, including exact/inexact numeric representation inside `rgba-color`.
- Interpolate red, green, blue, and alpha componentwise in semantic sRGB value
  space. Keep color-space/perceptual interpolation as a future explicit policy,
  not an implicit renderer behavior.
- Test color parsing, exact endpoints and exactness coercion, alpha, every built-in
  protocol/rendering path independently, custom protocol failures, scatter/callout
  exclusions, independent components, overlap conflicts, timing-tree composition,
  structural introduction, stable frame dimensions, and deterministic repeated
  PNG output.

## Unified style transitions

- SCENE-AU adds `style-to` as composition syntax, not as a new compiled style
  animation. Expand each supplied property to the existing `fill-color-to`,
  `stroke-color-to`, `stroke-width-to`, or `fade-to` leaf so AS/AT validation,
  exact endpoints, easing, and renderer independence remain authoritative.
- Keep fill color, stroke color, stroke width, and opacity as independent scheduler
  components. A unified request owns only the properties actually supplied; do
  not introduce a coarse `style` conflict component.
- Use constructor-like keywords `#:fill`, `#:stroke`, `#:stroke-width`, and
  `#:opacity`. `#f` means omitted in `style-to`; require at least one non-`#f`
  property. This is not paint-presence animation and must not reinterpret a
  missing fill/stroke as transparent.
- Treat one `style-to` as one direct child for parent composition timing, then
  expand its selected primitive leaves in parallel inside that assigned interval.
  It must remain valid at top level, inside sequential/parallel/lagged composition,
  and under `timed`.
- Direct Visual targets should reuse primitive capability checks immediately;
  symbolic targets should defer those same checks until scene compilation. Avoid
  duplicating optional Visual protocol validation in the style composition layer.
- Test full and partial style sets, vacuous-request rejection, direct/symbolic
  capability failures, exact endpoints, property-specific conflicts with primitive
  requests, compatible motion/style concurrency, succession chaining, local timing,
  lagged composition, structural introduction, fixed render dimensions, and
  deterministic repeated PNG output.

## Animated scalar values

- SCENE-AV stores named finite-real scalar values in immutable `scene-state`
  snapshots alongside, but separately from, top-level Visuals. Named scalars are
  never painted directly; later derived Visual resolution may read them.
- Scalar IDs and Visual IDs share one global scene namespace. Reject collisions
  at instantaneous insertion so scheduler target identity remains unambiguous.
- Implement `value-to` as an ordinary compiled-animation leaf with component
  `scalar-value`; do not create a second value timeline or frame-by-frame updater.
- Preserve exact scalar source/destination representations at progress 0 and 1;
  use `real-lerp` only for interior progress.
- Scalar leaves must remain valid under `timed`, `succession`, `animation-group`,
  and `lagged-start`, including exact sequential boundary compilation and normal
  same-component overlap rejection.
- SCENE-AV values are not drawn directly. SCENE-AW derived Visuals sample these
  immutable values by scene time rather than mutating them per frame.

## Pure derived Visuals

- SCENE-AW derived Visual definitions are top-level semantic Visual identities carrying a concrete template whose
  resolved Visual is evaluated from one immutable sampled scene state. Do not
  introduce mutable updater state or previous-frame dependencies.
- SCENE-AW introduced scalar presence/lookup in the read-only `derived-context?`.
  SCENE-AX extends that same context with top-level Visual presence/lookup while
  preserving pure arbitrary-time resolution.
- SCENE-AX Visual dependency lookup is top-level and ID-based. Nested group
  children remain encapsulated and are not found by `derived-context-visual-ref`.
- `derived-context-visual-has?` checks presence without forcing resolution.
  `derived-context-visual-ref` returns a concrete resolved Visual and may recurse
  through other derived definitions regardless of drawing order.
- Resolve one dependency traversal with a local memo table and an explicit active
  DFS stack. Detect self-cycles and longer cycles deterministically; never depend on
  drawing order or host stack overflow for cycle behavior.
- Memoization is traversal-local only. Never persist a resolved Visual into
  `scene-state`, a clip snapshot, or a derived definition; a later state/sample must
  resolve again from that exact immutable state.
- Keep `scene-state-ref` as raw model lookup so the persistent resolver definition is
  retained in clip snapshots. Use `scene-state-resolved-ref` when concrete geometry is
  required, and preserve back-to-front order in
  `scene-state-resolved-visuals-in-drawing-order`.
- A resolver must return a concrete non-derived `visual?` whose `visual-id` is exactly
  the derived definition's template ID. Validate this on every resolution; do not
  silently rewrite identities or retain a concrete result beyond the current
  resolution traversal.
- Rendering, `camera-follow`, and `camera-fit-scene` must use resolved Visual state.
  Standalone operations that lack a scene state may inspect the persistent template
  reference position, but cannot infer the scene-aware resolved geometry.
- Through SCENE-AW, direct Visual animation requests targeting a derived definition are
  rejected. Animate its named scalar inputs with `value-to`; do not combine resolver
  output with imperative translation/style mutations that create two sources of truth.
- Resolver procedures are required by contract/documentation to be pure. Repeated
  rendering of the same sampled state must be byte-deterministic when the resolver and
  renderer are deterministic.
- Test raw-versus-resolved lookup, scalar-driven exact-time geometry, ordinary
  animated-Visual dependencies, drawing-order-independent chains/diamonds, missing
  scalar/Visual dependencies, self and multi-Visual cycles, malformed resolver
  results, identity preservation, direct-animation rejection, camera follow/fitting,
  render dimensions, changed pixels, and repeated PNG determinism.
