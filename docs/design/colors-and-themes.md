# Colors and themes: COLOR-0 inventory and implementation notes

This document records the color behavior present before palette tokens and
themes are introduced. It is an implementation inventory, not a public color
reference or a proposed numerical palette.

**Starting revision:** `89e8c231272b2f2b767647db6bc448dc297a1f99`

## Current implementation status (through COLOR-D)

COLOR-A adds immutable literal, palette-token, role-token, mix, and alpha
specifications. COLOR-B adds explicit immutable palettes, themes, and
resolution. COLOR-C keeps those specifications alive through pure style and
geometry processing:

- compatible solid, gradient, and checker interpolation retains token-bearing
  expressions; all-literal expressions may fold safely;
- fill/stroke transitions and write-in opacity transforms no longer require a
  theme while sampling a scene;
- 3D material/light authoring, surface coloring, clipping, surface matching,
  mesh matching, and light animation retain specifications until preparation;
- color scales accept already-normalized scalar coordinates and define clamp,
  error, repeated-stop, and endpoint behavior; and
- shared normalized sRGB transfer functions now serve the color resolver and
  3D color-space facade.

COLOR-D now establishes an immutable explicit 2D render context at
`visual->pict`, `scene-state->pict`, `scene->pict`, and
`scene-frame->bitmap`. It captures the selected theme, resolved-role table,
appearance fingerprint, and resolver version. The context is also captured by
delayed Pict callbacks, so drawing a Pict after another themed render cannot
change its appearance. Primitive and structured paints, composites, text,
temporary text effects, formula tint layers, camera backgrounds, and custom
Pict renderers resolve through that snapshot. Text and formula appearance
caches include its appearance fingerprint.

Project, preview, software-3D, and OpenGL preparation still need COLOR-E and
COLOR-F to transport this explicit snapshot through plans, workers, cache
keys, and 3D numerical preparation.

## Current literal contract

`private/color-style.rkt` is pure and renderer independent. An `rgba-color`
stores sRGB red, green, and blue components in `[0,255]` and alpha in `[0,1]`.
It accepts finite fractional components. `rgb-color` is an opaque shorthand.

`color-spec?` accepts an `rgba-color`, a supported literal string, a palette
or role token, or an immutable color expression. Strings are never symbolic
theme names:

- X11/Racket-style names use Animate's own lowercase lookup table. Whitespace,
  hyphens, and underscores are ignored while finding a named literal.
- `transparent` is literal transparent black.
- `#RGB`, `#RGBA`, `#RRGGBB`, and `#RRGGBBAA` are accepted. Alpha is an exact
  fraction of 255.
- Unknown strings, nonfinite components, out-of-range components, and `#f` are
  rejected as colors. `#f` remains the separate no-fill/no-stroke sentinel.

`rgba-color-lerp` is componentwise encoded-sRGB interpolation. Its exact zero
and one endpoints retain their input objects. `interpolate-value` accepts only
already-resolved `rgba-color` values; arbitrary strings are intentionally not
scene values eligible for interpolation.

## Color-consuming call sites

The categories below describe existing behavior. They are the migration map for
later COLOR slices; no item is changed by COLOR-0.

| Category | Current locations | Current behavior and later requirement |
| --- | --- | --- |
| Literal parsing and numerical helpers | `private/color-style.rkt`; `private/interpolation.rkt` | The literal table and hex parser are authoritative. Keep them separate from future token validation. Keep `rgba-color-lerp` as an explicitly numerical helper. |
| Constructor validation | `private/visual-model.rkt`, `private/arrow-visual.rkt`, `private/axes-visual.rkt`, `private/point-marker-visual.rkt`, `private/text-visual.rkt`, `private/formula-style.rkt`, `private/paint.rkt`, `private/animation.rkt` | These retain literal strings or `rgba-color` values in authored 2D values. Future tokens may be accepted here, but must not be resolved here. |
| Authoring-time paint and style interpolation | `private/paint.rkt`, `private/animation.rkt`, `private/interpolation.rkt` | `paint-lerp`, gradient-stop interpolation, checker interpolation, fill animation, stroke animation, write-in, and several effects eagerly turn literal strings into `rgba-color` at intermediate samples. COLOR-C must retain typed color expressions instead. |
| Pict and drawing conversion | `private/paint-pict.rkt`, `private/shape-pict-renderers.rkt`, `private/path-pict-renderer.rkt`, `private/latex-formula-pict-renderer.rkt`, `private/tagged-formula-pict-renderer.rkt` | COLOR-D resolves each color through a captured `render-color-context` immediately before it enters `racket/draw` or formula SVG CSS. A delayed Pict re-installs its captured context while drawing. |
| Scene/frame entry points | `private/frame-renderer.rkt`, `private/pict-adapter.rkt`, `private/camera.rkt` | `visual->pict`, `scene-state->pict`, `scene->pict`, and `scene-frame->bitmap` accept `#:theme`; an internal context carries it through recursion and callbacks. Camera background still defaults to literal `"white"`; COLOR-G reviews semantic defaults. |
| Formula appearance | `private/formula-style.rkt`, `private/latex-formula-pict-renderer.rkt`, `private/tagged-formula-pict-renderer.rkt` | Formula styling retains a color spec until it forms a colored Pict or styled SVG. Appearance-cache keys contain the context fingerprint; TeX source/geometry stays independent. |
| 3D model validation | `private/3d/material3d.rkt`, `private/3d/light3d.rkt`, `private/3d/mesh3d.rkt`, `private/3d/stroke3d.rkt`, `private/3d/marker3d.rkt`, `private/3d/view3d-visual.rkt` | Materials and lights currently resolve colors in constructors; mesh attributes retain color specs. COLOR-F must separate authored from resolved material/light values. Physically literal light defaults stay literal. |
| 3D semantic color processing | `private/3d/surface-color.rkt`, `private/3d/clipping3d.rkt`, `private/3d/parametric-surface3d.rkt`, `private/3d/matching-animation3d.rkt`, `private/3d/light-animation3d.rkt` | Surface ramps, mesh cuts, generated surfaces, matching, and light animation eagerly resolve/interpolate colors. COLOR-C/F must preserve color expressions through semantic geometry. |
| Software and OpenGL preparation | `private/3d/software-renderer3d.rkt`, `private/3d/renderer3d.rkt`, `private/3d/raster-target3d.rkt`, `private/3d/opengl/geometry-pack.rkt`, `private/3d/opengl/renderer.rkt`, `private/3d/opengl/stroke-pass.rkt`, `private/3d/opengl/readback.rkt` | These are numerical consumers. They resolve channels for alpha classification, raster targets, uniforms, and packed vertex buffers. Tokens must be resolved on the CPU before this boundary. |
| Project, preview, and worker identity | `project.rkt`, `private/project-execution.rkt`, `private/preview-controller.rkt`, `private/preview-cache.rkt`, `private/preview-render-request.rkt`, `private/preview-worker-protocol.rkt`, `private/preview-worker-main.rkt` | Current frame identities include source, camera, renderer, and raster choices but no theme. Preview keys use document/render generations and frame settings; worker messages use the project-plan fingerprint and generations. Later theme identity must be carried through each one. |
| Renderer appearance caches | `private/shape-pict-renderers.rkt`, `private/latex-formula-pict-renderer.rkt`, `private/tagged-formula-pict-renderer.rkt`, `private/3d/frame-artifact-cache3d.rkt` | Text and formula appearance caches already include literal color data. 3D frame artifacts key on concrete view content, dimensions, camera, renderer, and attachments. Future resolved appearance fingerprints must prevent stale reuse while preserving layout and geometry reuse. |

## Existing literal-name distinction

The semantic literal-name table in `private/color-style.rkt` is deliberately
not a call to `racket/draw`'s color database. The rendering adapters convert
the resolved Animate literal to a drawing color. Future work must preserve this
ordering so a drawing-backend name-table change cannot alter semantic scene
data.

## Defaults to review in COLOR-G

These defaults are categorized by purpose, not changed here.

| Purpose | Current examples | Future direction |
| --- | --- | --- |
| Scene/background appearance | `private/camera.rkt`, `private/3d/view3d-visual.rkt`, raster targets | The normal scene background is a candidate for `theme-background`. An explicit author string remains literal. |
| General author-facing fill/stroke/text | `private/visual-model.rkt`, `private/shape-catalogue.rkt`, `private/text-visual.rkt`, axes, number lines, plots, and decorations | Generic default fills, outlines, labels, grids, and demonstration highlights need a purpose-by-purpose semantic-role review. Do not mechanically replace every black or blue string. |
| Effects and helper palettes | `private/animation.rkt`, `private/statistics-visual.rkt`, calculus and linear-algebra helpers | These require separate decisions between intentionally illustrative colors and portable defaults. |
| Physical 3D defaults | `private/3d/light3d.rkt`, `private/3d/material3d.rkt`, renderer clear/shadow paths | Light white, specular white, zero emission black, and internal transparent pens are physical or adapter literals unless a future API explicitly accepts a token. |
| Preview chrome | `private/preview-window.rkt` | Inspector/timeline/widget colors are editor UI, not exported-scene theme roles. |

## Remaining cache identity changes

When themes are added, the complete normalized theme snapshot and its resolver
version/fingerprint must be part of every appearance-producing identity:

1. COLOR-D direct 2D scene/frame rendering carries one immutable color context
   through Pict creation, including delayed Pict drawing closures. Text and
   formula appearance caches include its fingerprint; source/layout geometry
   does not change solely because a theme changes.
2. Preview memory-cache keys, render requests, worker protocol messages, and
   stale-result checks must include the selected theme fingerprint.
3. Project plans, prepared projects, persistent frame keys, and section-video
   keys must store a normalized snapshot, not a mutable lookup or display name.
4. 3D material/light uniforms and themeable vertex-color buffers need an
   appearance key. Position/index/normal geometry, topology, BVHs, and ODE
   samples remain reusable when only colors change.
5. Alpha after theme resolution participates in opaque/translucent pass and
   shadow decisions. It cannot be treated as an RGB-only uniform update.

## COLOR-0 test coverage

The characterization tests are intentionally literal-only and run under
headless `racket`/`raco test`:

- `tests/color-literal-characterization-test.rkt`
- `tests/color-paint-characterization-test.rkt`
- `tests/color-render-boundary-test.rkt`

They establish the existing parser, channel units, alpha behavior, exact
interpolation endpoints, `#f` no-paint distinction, headless import boundary,
and a tiny renderer boundary probe. Future token/theme changes must retain
these literal guarantees.
