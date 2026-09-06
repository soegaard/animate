# Changes

## Unreleased — 3D Q/R/S foundations

- Added a common immutable surface-lowering record and deterministic producers
  for adaptive parametric, signed-trimmed parametric, and fixed-resolution
  implicit surfaces. Their mesh/provenance and diagnostics remain pure; the
  renderer receives ordinary indexed meshes.
- Added scale-aware section settings, deterministic plane-local coordinates,
  rich section components, two-sided mesh cuts, separate simple-concave cap meshes,
  ordered multi-plane clipping helpers, and pure section measurements. The
  existing one-plane clip and section APIs continue to expose convenient loops
  and chains.
- Added immutable spatial anchors for points, paths, bounds, mesh vertices,
  edges/faces, curves, and retained parametric surface coordinates. Added pure
  direct-mode label placement records/layout values, immutable prepared
  minimum-cost label trajectories, and the anchor-aware `label3d` spelling for
  projected labels. Equal-priority labels retain declaration order and
  equal-cost candidates retain declared preference order.
- Added independently addressable section fills, deterministic even/odd hatch
  strokes, indexed mesh slicing with shared cut vertices and interpolated
  normals, immutable slice-stack/cross-section/volume-estimate helpers, and
  stable midpoint Riemann-volume columns, washer slabs, and cylindrical shells.
- Added CPU surface-pick refinement with retained parametric or implicit source
  provenance. Regular parametric surface anchors now retain their resolved
  world normal and u-tangent.
- Hardened the P backend locally: absolute-source CI package installation,
  unique GL context identities, owned context custodians, premultiplied GL
  compositing/readback conversion, byte-bounded FBOs, and shared software
  frame artifacts for projected-label depth queries.

Known boundaries: adaptive implicit extraction, analytic implicit picking,
trim Boolean regions, holed cap triangulation, general polygon section fills,
final-compositor integration for
prepared label trajectories, annotation primitives, and billboard texture
rendering are not complete in this change. The OpenGL paths are compiled but
not executed here because they require a GUI-capable OpenGL context; no GUI or
permission-requiring command was used.

## 1.22.0 — SCENE-3D-P

- Added the explicit `animate/3d/opengl` backend. `animate`, `animate/3d`,
  and `animate/3d/render` remain headless and do not load the OpenGL binding or
  create a GUI context. `opengl-renderer3d` owns a hidden Racket GUI canvas,
  serializes every GL call on its owner, and returns copied top-down
  straight-alpha ARGB bytes to the existing ordinary 2D/Pict compositor.
- Added a Racket `opengl`-package implementation with capability diagnostics,
  GL-resource lifetime wrappers, GLSL 1.50 shaders, matrix/float packing,
  VBO/EBO/VAO geometry retention, a byte-bounded LRU cache, owned RGBA8/depth
  framebuffer targets, optional multisample resolve, and tested RGBA readback
  row conversion. No native handle is stored in a Scene, `view3d`, mesh, or
  other authored value.
- Added OpenGL opaque, flat/smooth, clip-plane, transparent, depth-only, and
  SCENE-3D-O stroke/point/arrow rendering passes. The software renderer remains
  the default and conformance reference. OpenGL is opt-in through
  `current-view3d-renderer3d` or a project's
  `(render-spec #:renderer3d (opengl-renderer3d-spec ...))` declaration.
- Project final rendering and project preview now accept that declaration.
  Explicit OpenGL needs the Racket 9.3 `gracket` executable; a plain `racket`
  process reports this configuration requirement rather than silently switching
  to software. `#:fallback 'software` is the only deliberate fallback policy.
- Added the OpenGL context, direct rendering, project-selection, cache,
  readback, and context-restart tests; `tools/run-3d-probes.rkt` now has ten P
  probes and `--compare-renderers software,opengl`, which writes separate trees
  plus quantitative absolute-difference PNGs. `tools/benchmark-3d.rkt` runs
  the same canonical workloads through software or explicit OpenGL and records
  warm-frame/cache/FBO/readback evidence without a timing CI threshold. Added
  the retained cube, project, and two-viewport examples.

Known boundary: this first optional backend requires a compatible OpenGL 3.2 /
GLSL 1.50 context and is tested on macOS plus an optional Xvfb lane. It uses
one serialized context with `#:workers 1`; it does not offer threaded GPU
parallelism, direct OpenGL preview-canvas composition, GPU picking, textures,
shadows, specular/roughness shading, or order-independent transparency. The
software renderer remains the portable default. GPU and software images are
compared by documented tolerance—especially at antialiased and transparent
edges—not by bit identity.

## 1.21.0 — SCENE-3D-O

- Replaced the ambiguous curve-radius interface with immutable `stroke3d` and
  `tube-style3d` values. Mathematical curves, axes, grids, and vector shafts
  now default to camera-resolved screen strokes; explicit `tube-style3d`
  retains physical tubular geometry.
- Added deterministic screen/world widths, butt/square/round caps,
  miter/bevel/round joins, validated dashes with stable source phase, and
  depth modes for visible, hidden, and always-visible mathematical marks.
  Stroke preparation preserves author clipping and source progress for picking.
- Added screen/world point and arrow-marker styles, along with screen-sized
  default points and arrowheads. They participate in the same clip, depth, and
  picking semantics as strokes.
- Added path-transparent `with-edges3d` overlays with explicit, all, boundary,
  crease, silhouette, and feature-edge selection plus visible, depth-only, and
  omitted surface policies. Feature classification uses the current transformed
  geometry and camera; the renderer has ordered opaque, depth-only, hidden,
  visible, transparent, and always-overlay passes.
- Added eight SCENE-3D-O probe scenes, including hidden lines, edge modes,
  screen/world widths, a cap/join/dash gallery, a dolly arrow, near-plane
  clipping, and picking, plus focused tiny-raster and random-access tests.

Known boundary: hidden-line classification intentionally considers opaque and
depth-only surfaces only; transparent surfaces are not reliable hidden-line
occluders. Strokes use deterministic software coverage rather than analytic
antialiasing, and sampled curves remain limited by their authored samples.

## 1.20.0 — SCENE-3D-N

- Added pure, deterministic `mesh3d` topology diagnostics: scale-aware
  degenerate-face detection, duplicate-face reports, boundary chains/loops,
  non-manifold and inconsistent-winding edges, stable face components,
  isolated vertices, signed component volumes, and broad-phase
  self-intersection candidates.
- Added explicit `mesh3d-orient-consistently` and `mesh3d-orient-outward`
  repair operations. They return replacement immutable meshes plus reports and
  reject ambiguous topology rather than silently guessing an outside.
- `animate/3d/render` now compiles a `view3d` into camera-independent shared
  geometry and ordered instances. Render requests pair that compiled view with
  a `frame3d-spec`; the retained software backend separately caches geometry
  resources and camera-space preparation, exposes immutable metric snapshots,
  and preserves the existing software pixels.
- Added `examples/3d/mesh-diagnostics.rkt`, SCENE-3D-N visual probes, cache and
  topology tests, and geometry-key/count fields in probe manifests.

Known boundary: self-intersection reporting is broad phase only. Topology
repair neither heals holes nor rebuilds authored vertex normals. The retained
software geometry cache is an implementation resource, not GPU storage;
OpenGL remains a later roadmap stage.

## 1.19.0 — SCENE-3D-M

- Added `animate/3d/render`, a backend-neutral renderer protocol with stable
  backend IDs, explicit capability sets, immutable render requests/results,
  preparation fingerprints, and release hooks. `view3d` remains an immutable
  semantic value; it never stores a renderer cache, bitmap, native handle, or
  GPU resource.
- The existing deterministic software rasterizer is now the stateless
  conformance reference and can separately prepare camera-space triangles and
  rasterize them into a fresh depth target. The default opaque `view3d` path
  uses a bounded, thread-safe retained backend that reuses identical immutable
  preparations without changing pixels, depth ordering, or random-access frame
  semantics.
- Added reference/retained output conformance tests and
  `examples/3d/retained-renderer.rkt`, including a small REPL cache probe.
- Replaced the one-off wireframe snapshot script with
  `tools/run-3d-probes.rkt`, a stage-aware visual-probe runner for SCENE-3D-B
  through SCENE-3D-M. Each run records rendered frames, sampled cameras,
  renderer-fingerprint digests, frame hashes, and a release manifest.

Known boundary: no Pict3D package or GPU adapter is bundled. The retained
backend caches the reference renderer's fully camera-prepared triangles, so a
camera or viewport change is intentionally a miss. Any future GPU adapter will
remain optional, use the same protocol, and compare pixels with tolerance rather
than require bit-identical software output.

## 1.18.0 — SCENE-3D-L

- `animate/3d` now provides immutable `spatial-inspection` records for a
  sampled `view3d`, exact double-sided ray/triangle hits with barycentric
  coordinates, and deterministic `view3d-pick` / `view3d-pixel-pick` queries.
  A query first culls world AABBs, then transforms to a cached local BVH before
  its exact triangle test; tie-breaking is stable by drawing and triangle index.
- The interactive preview keeps spatial selection out of the authored scene.
  Clicking a 3D facet retains a preview-only selection and draws its world AABB,
  exact triangle, normal, local frame, and ray-pixel marker above the cached
  viewport. The new `Animate → 3D selection` menu copies path/point/normal,
  focuses only the inspection camera, and supplies scratch REPL values,
  including a clipping plane.
- Added `examples/3d/spatial-inspector-picking.rkt`, an asymmetric mesh probe
  for the new click inspection workflow.

Known boundary: picking currently operates on indexed mesh triangles (including
generated curves and surfaces). It has no analytic implicit-shape, UV,
interpolated-vertex-normal, or GPU-picking path; overlays stay preview-only and
never affect a normal frame/video render.

## 1.17.0 — SCENE-3D-K

- Added a generic immutable `ode-state-space` numerical kernel with real,
  `vec2`, `vec3`, and fixed-length numeric-vector state spaces. The existing
  two-dimensional RK4/RK45 API now uses that kernel without changing its
  public call shape.
- `animate/3d` now provides prepared fixed-RK4 and adaptive-RK45 trajectories,
  deterministic static vector fields and streamlines, and parameter-driven
  spatial particles/clouds. PNG and preview renderers prepare particle
  positions before resolving spatial relations, so their workers do not call
  an author ODE field.
- Added `examples/3d/prepared-lorenz-flow.rkt`, a camera-orbiting Lorenz
  attractor probe with a prepared particle and tangent.

Known boundary: 3D vector fields use an author-chosen finite rectangular grid;
there is no adaptive streamline integration, event handling, streamline
topology analysis, or 3D picking/inspection yet.

## 1.16.0 — SCENE-3D-J

- `animate/3d` now provides world-coordinate `apply-linear3` and
  `apply-affine3` requests. They preserve an indexed mesh's topology exactly
  and also map whole named spatial subtrees, including coordinate diagrams.
- `apply-pointwise3` samples the currently authored vertices through a spatial
  point map. `apply-homotopy3` evaluates `H(point, phase)` directly at every
  sample time. Both default to explicit failure; their opt-in `'drop-triangle`
  policy deterministically removes incident triangles without repairing holes.
- Added `linear-transformation-diagram3d` and the canonical
  `examples/3d/spatial-maps-and-homotopies.rkt` scene. It contrasts an exact
  affine shear, an authored-vertex ellipsoid deformation, and a direct twist
  homotopy.

## 1.15.0 — SCENE-3D-I

- `animate/3d` now separates render-only half-space `clip3d` wrappers from
  `slice-mesh3d`, which creates actual clipped mesh geometry. `section-by-plane3d`
  preserves deterministic loops/open chains, and `section-curve3d` makes them
  visible as ordinary tube curves.
- Materials now preserve semantic alpha. The software renderer performs an
  opaque depth-writing pass followed by explicit `'object-sorted` or
  `'triangle-sorted` transparent passes; transparent triangles depth-test
  against opaque geometry but do not write depth.
- Projected labels support `#:occlusion 'always-visible`, `'hide`, or `'fade`
  against the opaque depth target. Added the
  `examples/3d/sphere-plane-section.rkt` moving-section probe.

## 1.14.0 — SCENE-3D-H

- `animate/3d` now provides standard indexed solids, deterministic simple-contour
  `extrude3d`, axis-safe `revolve3d`, parallel-transport `sweep3d`, and mesh
  normal, winding, boundary, transform, wireframe, and merge utilities.
- Added the `examples/3d/solid-of-revolution.rkt` mathematical video probe.

## 1.13.0 — SCENE-3D-G

- `animate/3d` now provides deterministic fixed-grid `parametric-surface3d`
  and `function-surface3d` values. Analytic derivatives are used when supplied;
  otherwise normals use explicit finite differences, adjacent-face fallback,
  and recorded unresolved sites rather than producing NaNs.
- Surface colour fields, coordinate curves, tangent vectors/planes, normals,
  gradients, and level-curve segments are ordinary spatial geometry. The
  opaque reference renderer now interpolates vertex colours and `'smooth`
  normals perspective-correctly.
- `reveal-surface-u`, `reveal-surface-v`, and `transform-surface3d` derive each
  frame directly from captured immutable grids. Surface morphs require equal
  domains/resolution and compatible material structure.
- `examples/3d/tangent-plane.rkt` is the canonical saddle-surface demo.

Known boundary: surface topology is fixed to a rectangular grid. There is no
adaptive/trimmed/implicit surface, topology-changing morph, texture mapping,
solid/extrusion API, clipping plane, transparency, picking, or occlusion-aware
3D label.

## 1.12.0 — SCENE-3D-F

- `animate/3d` now provides finite `point3d`, `line3d`, `segment3d`,
  `polyline3d`, `arrow3d`, `double-arrow3d`, `parametric-curve3d`, and
  `tube3d` geometry. Curve samples are deterministic, adjacent repeated points
  are removed before framing, and tubes use a transported frame rather than
  independent unstable cross-sections.
- `axes3d`, `coordinate-plane3d`, `grid-plane3d`, `basis-vectors3d`,
  `vector-arrow3d`, and `vector-components3d` provide stable spatial paths for
  vector diagrams. Axis label anchors work with Stage E projected 2D labels.
- Existing curve paths support `create`, `uncreate`, and `show-passing-flash`;
  `move-along-curve3d` and `orient-along-curve3d` sample exact curve data at
  the requested timeline time, with no updater or frame-order dependency.
- `examples/3d/vector-components.rkt` is the canonical vector demo.

Known boundary: widths are physical `world` radii. A requested `'screen` width
is rejected rather than pretending to be equivalent; depth-aware screen-space
strokes, smooth curve joins, arbitrary surfaces/solids, picking, transparency,
and occlusion-aware 3D labels remain later work.

## 1.11.0 — SCENE-3D-E

- `animate/3d` now has immutable `spatial-relation` Visuals. A relation
  explicitly declares spatial-path, scene-value, and camera dependencies; it
  resolves lazily against one sampled `view3d`, reports dependency cycles with
  full rooted paths, and never writes into a Scene.
- Built-in `line-between3d`, `segment-between3d`, `arrow-between3d`,
  `plane-through3d`, `normal-at3d`, and `distance-segment3d` establish a
  semantic relation vocabulary while retaining the existing deterministic mesh
  renderer.
- `projected-label`, `follow-projected-point`, and
  `follow-projected-spatial` keep ordinary 2D text or formula Visuals crisp at
  fixed pixel size while their anchors follow the sampled spatial camera.
- `examples/3d/projected-labels.rkt` is the canonical moving-tetrahedron
  example: its A–D TeX labels follow projected vertex anchors while both the
  tetrahedron and camera move.

Known boundary: relation strokes and arrowheads are temporary mesh geometry;
there are no points/tubes/curves, curve labels, surfaces/solids, spatial
occlusion or picking, clipping planes, or transparency. Projected labels are
always-visible 2D overlays rather than occlusion-aware 3D billboards.

## 1.10.0 — SCENE-3D-D

- `animate/3d` now adds finite immutable requests for local spatial position,
  rotation, scale, full transforms, camera pose/lens motions, orbiting,
  dollying, framing, and following a spatial target.
- Every 3D request is compiled against an exact clip-start state and sampled
  directly at the requested time. It works in timed, sequential, parallel, and
  lagged compositions without a mutable updater or frame-order dependency.
- Preview supports an inspection-only immutable `camera3d` override. It is
  part of the preview render specification and subprocess worker protocol, and
  clearing it restores the authored camera without changing the Scene.
- `examples/3d/camera-orbit.rkt` demonstrates a rotating cube, camera orbit,
  and a fixed source-addressable 2D matrix formula.

Known boundary: 3D camera navigation and authored camera animation are present,
but spatial relations, projected labels, 3D picking, curves, surfaces, solids,
clipping planes, and transparency remain later stages.

## 1.9.0 — SCENE-3D-C

- `animate/3d` now supports immutable opaque materials and ambient/directional
  lights, plus `view3d`'s `'opaque` render mode.
- The first software triangle backend performs deterministic six-plane
  clipping, CCW back-face culling, pixel-centre rasterization, perspective
  depth testing, stable equal-depth ties, and flat or unlit shading.
- `examples/3d/opaque-cube.rkt` and `examples/3d/depth-test.rkt` demonstrate
  the renderer. Transparency, smooth shading, texture mapping, shadows,
  picking, and spatial animation remain later work.

## 1.8.0 — SCENE-EM

This is an intentional API cleanup release, not a compatibility release.

- Rendering, encoding, and media assembly now belong to `animate/render`.
  `animate` remains headless and provides semantic scene construction and pure
  sampling.
- Live layout relations are named `follow-above`, `follow-below`,
  `follow-left-of`, and `follow-right-of`, making their continuing dependency
  explicit; the former `keep-*` spellings were removed.
- Complete render/preview declarations now live in `animate/project`, with a
  pure normalization and planning phase before source preparation or output.
- The registered Scribble manual is split into guide, concept, reference, and
  cookbook chapters.
- Formula string transitions retain immutable source-match plans for preview
  inspection.

Examples, tests, and documentation in this repository use the current module
layout. No deprecated aliases are provided.
