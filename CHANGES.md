# Changes

## 1.23.0 — SCENE-3D-V

- Completed the SCENE-3D-T/U/V corrective pass. Terminal trajectory monitoring,
  event isolation, Hermite bounds, prepared arc-length queries, per-component
  topology diagnostics, canonical analysis-space dual/net/Schlegel operations,
  deterministic hull clustering, and shared part provenance are now covered by
  focused regressions and canonical visual probes.

- Completed the SCENE-3D-V conformance pass. Software/OpenGL comparisons now
  report interior, edge, and alpha coverage separately; GLSL light and clip
  limits share one authoritative record with preflight; actual V tests run in
  both real-context lanes. Shadow descriptors now also accept semantic
  world/texel `shadow-bias3d` values, while the former normalized-depth fields
  remain documented compatibility controls.

- Added SCENE-3D-V10's immutable material/light/fragment-lighting inspection
  model and preview inspector sections. A mesh click now exposes authored
  material policies, named light data, and a pure per-light equation report
  including pre-tone-map linear and final sRGB colours. The preview never
  reads or guesses a renderer-private map: an unsupplied declared-shadow
  factor is explicitly reported as `not-sampled`. The new lighting-inspector
  example makes this workflow available in GRacket.

- Added SCENE-3D-V9 OpenGL directional and spot shadows. The retained GPU
  renderer creates context-owned depth-texture framebuffers, renders eligible
  opaque mesh casters in a depth pass, and applies explicit square PCF only to
  receiver diffuse/specular terms. A byte-bounded LRU owns the map resources;
  its identity excludes the viewing camera, so camera-only motion reuses a
  map, while caster/light/settings/bounds changes regenerate one. Hardware
  comparison uses projection-space depth: the named bias formula is retained,
  but perspective bias magnitudes are not numerically interchangeable with the
  software renderer's forward-depth values. Point-light cube maps, transparent
  casters/receivers, strokes, markers, billboards, and GPU picking remain
  outside V9.

- Added SCENE-3D-V8 software directional and spot shadow maps. The reference
  renderer now fits deterministic orthographic/perspective light cameras,
  rasterizes opaque eligible meshes into immutable positive-depth maps, and
  applies the documented depth/normal bias plus square PCF factor only to
  diffuse and Blinn--Phong specular light. Emission and ambient remain
  unchanged. Explicit world-space bounds are supported; otherwise maps report
  their direct current-frame caster fit. Transparent meshes, strokes, markers,
  billboards, and point-light cube maps remain outside V8.

- Added SCENE-3D-V7's immutable directional/spot shadow descriptors and
  settings (map size, depth/normal bias, PCF radius, explicit bounds, and a
  prepared-bound key). `prepare-shadow-bounds3d` unions opaque caster bounds
  across an explicit sampled frame range and rejects a changing shadow-light
  pose. Future map identities exclude the view camera but include caster
  geometry/transforms/policy, light pose/settings, and prepared bounds.
  Point-light cube shadows remain deferred.

- Added SCENE-3D-V6 OpenGL finite-light evaluation. The retained GPU renderer
  now supports named point and spot lights with the same attenuation, range,
  smoothstep-cone, Lambert, and Blinn--Phong rules as the software reference.
  Its ordered packed uniforms enforce fixed limits of four directional, eight
  point, and four spot lights before drawing. Light-only frames reuse geometry
  cache entries. Persistent finite-light buffer caching remains future work.

- Added SCENE-3D-V5's deterministic software point and spot lighting. The
  reference rasterizer now uses perspective-correct camera-space fragment
  positions, named attenuation/range policies, smoothstep spot cones, and the
  authored light order for diffuse and Blinn--Phong accumulation. Double-sided
  materials flip a back-face normal toward the viewing side. Shadows and
  attenuation/range animation remain later work.

- Added SCENE-3D-V4's immutable finite-light timeline requests: named light
  intensity and linear-light colour, point/spot position, spot aim, and spot
  cone animation. Each compilation captures exact local clip-start values and
  samples directly, including within timed, succession, parallel, staggered,
  and reparameterized compositions. Near-antipodal spot directions use a
  deterministic quaternion fallback. V4 is model/timeline work only:
  finite-light rendering is still V5, and attenuation, range, and shadow
  descriptors remain fixed during a clip.

- Added SCENE-3D-V3's immutable, stable light model. Ambient, directional,
  point, and spot lights each have a required-unique symbolic identity,
  generic inspection accessors, declared future shadow policy, and immutable
  `view3d` lookup/replacement/update operations. Point/spot values carry
  named attenuation and the specified smoothstep cone calculation. Current
  renderers deliberately reject finite lights during capability preflight;
  their physical evaluation arrives in V5 rather than being approximated as
  directional lighting.

- Added SCENE-3D-V2's explicit cross-backend colour contract. Semantic input
  colours remain sRGB, while mesh lighting, transparent composition, strokes,
  markers, and billboards use linear RGB; alpha remains linear. A view owns an
  immutable `tone-map3d` policy (`'clamp` by default or `'reinhard`) and final
  stored ARGB pixels are tone-mapped then sRGB encoded. The OpenGL path now
  composites into a linear floating-point target before shared final encoding;
  focused transfer-vector and opt-in interior-pixel conformance tests cover
  the two paths. Full ICC/display-HDR management and colour-managed outer 2D
  composition remain intentionally out of scope.

- Added SCENE-3D-V1 material semantics across the deterministic software and
  optional OpenGL renderers: explicit Lambert or Blinn--Phong lighting,
  validated roughness-to-exponent mapping, specular colour, additive emission,
  and durable shadow-caster/receiver policy. The spatial inspector reports the
  exact derived exponent. Immutable material update helpers and mesh/surface
  reconstruction paths preserve all fields rather than dropping future shadow
  policy during a utility operation. Unlit materials retain base colour and add
  emission; shadow policy remains declarative until the shadow stage.
- Added SCENE-3D-V0's extensible immutable `renderer3d-capabilities` value:
  symbol features, exact/transparent limits, and immutable diagnostics replace
  the nine positional booleans. Renderer instances now report through
  `renderer3d-capabilities-of`; `renderer3d-supports?`,
  `renderer3d-capability-limit`, and `renderer3d-require-capabilities` make
  the result safe to query without starting rendering.
- Added one pure per-frame feature/limit demand calculation shared by project
  preflight and the built-in renderer prepare paths. `check-project!` samples
  the selected project frame grid and reports unsupported 3D features or
  insufficient resource limits before rendering. It opens a short-lived owned
  OpenGL renderer only for an explicitly selected GRacket/OpenGL project.
- The initial OpenGL declaration now records four directional-light and eight
  clip-plane shader limits. It rejects over-limit directional lights before
  uniform upload instead of silently truncating them. Point/spot lights and
  shadows remain unadvertised future work; a capability
  name in the common vocabulary is never an implementation claim.

- Began SCENE-3D-U with immutable optional semantic vertex, edge, and triangle
  face IDs on `mesh3d`. IDs are validated within their part kind and use
  numeric source indices when omitted. `mesh3d-semantic-key` deliberately
  layers these annotations over the unchanged render `geometry-key3d`, so
  semantic matching never splits GPU geometry sharing. One-to-one mesh
  operations retain IDs; flat-normal expansion explicitly keeps only face IDs,
  and merge rejects mixed or colliding semantic namespaces.
- Added SCENE-3D-U1's immutable navigable triangle topology: deterministic
  half-edges, edge/face/vertex and boundary-component records, edge-connected
  components (including isolated vertices), topology queries, and explicit
  Euler/boundary/genus reports. The cached structural skeleton is geometry-keyed
  while each query overlays its own semantic part IDs; nonmanifold or
  nonorientable inputs produce diagnostics rather than guessed genus values.
- Added SCENE-3D-U2's immutable polygonal-face complex. It can preserve render
  triangles, use an explicit triangle partition, or deterministically merge
  edge-connected transformed coplanar triangles. Generated face IDs expose
  their least source triangle; explicit IDs win. Regions with holes, branches,
  or repeated boundary vertices remain diagnosed rather than being fabricated
  into simple polygons.
- Added SCENE-3D-U3's deterministic convex-hull preparation. It preserves
  source-point provenance, returns true 0D/1D/2D results for degenerate input,
  emits an outward indexed mesh for solid input, and optionally groups its
  supporting triangles into U2 polygonal faces. Exact coordinates use exact
  orientation signs; inexact near-zero decisions and the selected tolerance
  policy are explicit diagnostics.
- Added SCENE-3D-U4's separate combinatorial and polar dual operations.
  Results retain face/edge/vertex primal-to-dual mappings, including explicit
  absence for renderer diagonals within polygonal faces. The geometric polar
  operation verifies a closed orientable manifold, convex supporting planes,
  and a strictly interior centre before constructing a result.
- Added SCENE-3D-U5's deterministic Schlegel projection preparation and flat
  3D edge visual. It preserves primal vertex/edge/face identities, validates
  that inner projected vertices stay inside the chosen simple outer face, and
  reports the target plane, canonical basis, margin, and viewpoint distance.
- Added SCENE-3D-U6's prepared polyhedral nets. Nets use a face-adjacency
  spanning tree, rigid root-plane face frames based on the actual hinge edge,
  positive-area polygon overlap reports, and deterministic cut edges. The
  bounded `'minimum-overlap` search reports whether its candidate enumeration
  was complete; it never claims an optimum after a limit is reached.
- Added SCENE-3D-U6's canonical face groups and fold/unfold clips. A prepared
  net now names one stable direct mesh child per mathematical face; interior
  animation samples recursively rotate children about their source hinges and
  inherit current parent maps, preserving shared edge endpoints at every
  random-access frame. The current clip intentionally requires those
  identity-local-transform canonical meshes rather than retargeting arbitrary
  authored spatial trees.
- Added SCENE-3D-U7's conservative mesh-correspondence plan. Explicit maps,
  semantic IDs, unchanged indexed topology, and unique local topological
  signatures have distinct diagnostic reasons. Ambiguous signatures remain
  unmatched, and every authored map is checked to be injective.
- Extended SCENE-3D-U7 with an explicit bounded geometric fallback. It only
  assigns still-unmatched parts to unused destinations in a declared
  local-normalized comparison frame, uses a deterministic Hungarian assignment,
  preserves semantic/topological decisions already made, and reports accepted
  costs plus threshold/capacity rejections. It is off by default and rejects
  candidate sets beyond its stated bound instead of pretending to solve a
  large-mesh correspondence problem.
- Added SCENE-3D-U7's first topology-safe matching request:
  `transform-matching-mesh3d`. Complete compatible correspondence plans
  interpolate only mapped vertex/normal/colour data while preserving source
  index arrays at interior frames; source and destination values are exact at
  the clip boundaries. Explicit line, circular-arc, and cubic-Bézier routes
  affect only the reference translation. Any topology change requires the
  separate `'cross-fade` mode, which retains two independent mesh layers
  instead of inventing unrelated indexed interpolation. General polygonal
  face-part and nested spatial-tree matching are still pending.
- Extended U7 with `transform-matching-spatial` for explicitly authored direct
  `group3d` mesh children. It accepts injective named face-part matches (or
  equal child IDs), morphs only independently compatible mesh pairs, and fades
  unmatched/incompatible children under interior-only identities. General
  group splitting and nested-tree retargeting remain intentionally unsupported.
- Began SCENE-3D-U8's topology-aware picking data. Mesh inspections now retain
  immutable Euler/boundary/manifold/orientability/component/genus diagnostics,
  while an exact triangle pick carries semantic vertex and edge IDs, render
  triangle and polygonal-face policy, connected component, and incident
  boundary components. A raw `mesh3d` honestly reports each render triangle as
  its polygonal face until a separate polygonal-complex mapping is attached.
- U8 picking now also has an on-demand `spatial-pick-topology-overlay3d`
  value for preview clients: nearest vertex/edge, selected face, component
  faces, component boundary segments, and directed halfedges are all
  world-space immutable diagnostic data. `topology-inspection3d` provides the
  same semantic-part and invariant report to both the preview pane and
  headless callers. The preview paints these after the rendered bitmap, while
  its topology section reports semantic IDs and invariants. Neither path
  changes an authored `view3d`.

- Added `jacobian3d`, a deterministic local ODE-field derivative query. It
  validates author-supplied analytic `linear3` derivatives or uses
  scale-aware symmetric finite differences; one-sided sampling happens only
  at an explicitly declared domain boundary. Every result records its method,
  coordinate steps, work count, and local error indicator.
- Added explicit seed-bounded damped Newton equilibrium search. It preserves
  every seed's convergence or failure diagnostic, and clusters successful
  roots deterministically using the earliest contributing seed.
- Added deterministic local eigensystems, tolerance-aware linearization
  classifications, and finite real-eigendirection diagram geometry. Complex
  invariant planes remain explicit data instead of acquiring an arbitrary
  default rendered extent.
- Added prepared seed-preserving 3D flow maps with explicit endpoints or
  absences after early termination, plus pair and displacement queries.
- Added `trajectory-tube3d`, which lowers retained dense trajectory positions
  to a deterministic tube mesh without calling an author field during display.
- Added `trajectory-ribbon3d`, using discrete parallel transport from an
  optional explicit initial normal. Closed-loop twist correction remains an
  author-visible future policy rather than an implicit geometric alteration.
- Added immutable dynamical inspection reports for prepared trajectories,
  equilibrium searches, linearizations, and individual flow-map slots.
- Flow-map diagnostics now distinguish persistently keyed numerical inputs
  from opaque memory-only fields, and retain a versioned preparation identity.
- Added `flow-map-grid3d`, an endpoint-only visual for explicit structured
  grids; unstructured seed sets are rejected rather than inventing adjacency.
- Added grid-only local flow-map Jacobian and volume-factor queries using
  retained endpoint neighbours and explicit central/one-sided differences.
- Added `flow-volume-cell3d`, which lowers one explicit retained grid cell to
  a hexahedral endpoint mesh. It preserves the map's actual eight corners and
  rejects missing endpoint or unstructured-neighbourhood claims.
- Added `trajectory-bundle3d`, a stable seed-ordered tube or ribbon group
  built solely from retained flow-map trajectories.
- Added canonical saddle-linearization and prepared flow-volume examples.
- Added retained-data trajectory pick reports with a declared sampling policy,
  nearest position/time, arc length, stored derivative, and nearby event hit.
- Flow-map cache identities now include the normalized solver, seed set,
  termination/event cache keys, time parameterization, retained-dense
  resampling, and endpoint policy; an opaque event makes preparation
  memory-only.
- Added bounded indexed worker preparation for independent
  streamline/flow/Poincaré seeds and cooperative cancellation checks at solver,
  event-root, seed, and display-resampling boundaries. Worker completion never
  affects seed/visual order or the reported first failure.
- Added `view3d-dynamical-inspections3d` and a preview-only 3D dynamics
  inspector section for retained `flow-particle3d` trajectories.
  Solver, accepted/rejected steps, termination, event count, field work, and
  arc length are inspected from immutable prepared data without modifying a
  scene or triggering numerical preparation.

- Added a common immutable surface-lowering record and deterministic producers
  for adaptive parametric, signed-trimmed parametric, and fixed-resolution
  implicit surfaces. Their mesh/provenance and diagnostics remain pure; the
  renderer receives ordinary indexed meshes.
- Trim fields now drive the same adaptive dyadic refinement tree through
  corner, side-midpoint, and centre classification rather than forcing a
  global minimum lattice. `trim-field3d`, `trim-and3d`, `trim-or3d`, and
  `trim-not3d` define signed Boolean trim expressions with deterministic root
  refinement. Finite sampling still cannot guarantee discovery of an
  arbitrarily small off-sample feature, and named boundary-loop reconstruction
  remains unfinished.
- Adaptive and trimmed parametric surface anchors now obtain deterministic
  local frames from their retained evaluator and parameter range; an implicit
  surface still does not pretend to have UV tangents.
- Added scale-aware section settings, deterministic plane-local coordinates,
  rich section components, two-sided mesh cuts, separate concave and holed cap meshes,
  ordered multi-plane clipping helpers, and pure section measurements. The
  existing one-plane clip and section APIs continue to expose convenient loops
  and chains.
- Added immutable spatial anchors for points, paths, bounds, mesh vertices,
  edges/faces, curves, and retained parametric surface coordinates. Added pure
  direct-mode label placement records/layout values, immutable prepared
  minimum-cost label trajectories, and the anchor-aware `label3d` spelling for
  projected labels. `prepare-scene-label-layout3d` and
  `prepare-project-label-layout3d` now sample and measure stable slots before
  workers start; an explicitly supplied table is consumed by final composition
  and participates in the project frame-cache identity. Equal-priority labels
  retain declaration order and equal-cost candidates retain declared preference
  order.
- Added `surface-pick-anchor3d`, which converts immutable exact surface-pick
  provenance into a current anchor. Parametric picks retain their UV frame;
  implicit picks retain a current barycentric point and interpolated normal
  without fabricating a UV tangent.
- Added fixed-structure world-space annotation relations:
  `distance-dimension3d`, `angle-marker3d`, `right-angle-marker3d`,
  `dihedral-angle3d`, `normal-marker3d`, and `coordinate-tripod3d`. Their
  named children are derived anew from declared spatial targets at every scene
  sample, and lower through the existing software/OpenGL geometry paths.
- The outer Pict compositor now gathers, measures, and consumes one direct
  projected-label layout for each sampled frame, so direct-mode labels share
  deterministic, overlap-aware candidate selection and the same negotiated
  viewport artifact. It minimizes overlap where a collision-free placement is
  not possible; it does not promise that every label set is disjoint.
- Projected-label visibility now has executable `inside-frustum` and
  `anchor-visible` policies. Top-level labels can request a deterministic
  one-pixel grey straight or horizontal-first-elbow leader through
  `leader-style3d`; the leader is a crisp 2D compositor overlay, not a 3D
  mesh.
- Added independently addressable section fills, deterministic even/odd hatch
  strokes, indexed mesh slicing with shared cut vertices and interpolated
  normals/RGBA colours, exact-coordinate welded capped halves, immutable
  slice-stack/cross-section/volume-estimate helpers, and
  stable midpoint Riemann-volume columns, washer slabs, and cylindrical shells.
- Section measurements now reject open/branch components, repeated vertices,
  zero-area loops, and touching or crossing loop arrangements instead of
  silently assigning them an even/odd area.
- Added `cut-mesh-by-box3d`, an explicit uncapped geometry operation matching
  the ordered six local-axis half-spaces of render-only `clip-box3d`.
- Added CPU surface-pick refinement with retained parametric or implicit source
  provenance. Regular parametric surface anchors now retain their resolved
  world normal and u-tangent.
- Added immutable straight-ARGB `billboard3d` image primitives with screen or
  world dimensions, camera- or upright-axis-facing policy, alpha-aware depth
  testing, software rasterization, and a matching Racket/OpenGL texture pass.
  The spatial inspector and the repository probe now report billboard items.
- Began SCENE-3D-T with explicit `ode-field3d` and solver values plus dense,
  immutable prepared trajectories. Fixed RK4 and adaptive RK45 now retain all
  required numerical nodes and endpoint derivatives: position, tangent, and
  arc-length queries use binary search and stored interpolation only, so
  later rendering and preview workers never reintegrate an author field.
- Added SCENE-3D-T1 event descriptors and immutable event-hit records. Event
  functions are evaluated only during preparation against dense Hermite
  segments; hits are sorted in physical time, shared-node roots are deduplicated,
  and a terminal root becomes the corresponding canonical trajectory endpoint.
- Added SCENE-3D-T2 immutable trajectory-termination policies for symmetric
  time budgets, AABB exits, dense arc-length budgets, sampled low-speed stops,
  maximum step counts, policy-owned terminal events, and explicit field-error
  handling. Preparation records immutable termination-hit data and clips the
  returned trajectory to the resolved dense endpoint. AABB checking splits
  each Hermite segment at all coordinate extrema before bisection, reports an
  exact outward face normal, and preserves an accepted node already on a face.
- Added SCENE-3D-T3 immutable prepared streamlines with explicit time or
  autonomous arc-length parameterization, branch diagnostics, deterministic
  world-space chord/turn/length resampling, and one canonical seed point for
  bidirectional lines. `streamline3d` now routes through the same preparation
  and resampling path; no later visual construction calls its author field.
- Added SCENE-3D-T4 immutable deterministic seed sets. Explicit, grid, plane,
  curve, surface, Fibonacci-sphere, and Poisson constructors retain canonical
  point order and serializable provenance/diagnostics. Poisson sampling owns a
  SplitMix64 source seeded by an explicit integer, so it never reads or changes
  Racket's process-global random generator.
- Added immutable prepared streamline collections over those seed sets. They
  preserve seed declaration order, retain set-wide diagnostics, and can use a
  deterministic spatial-hash separation boundary against earlier accepted
  lines. Separation intentionally makes preparation ordered; independent sets
  use bounded concurrent Racket threads and remain canonical by seed index.
- Added SCENE-3D-T5 Poincare extraction over retained dense trajectory
  segments, including physical-time ordering, crossing-direction filters,
  duplicate-time suppression, explicit tangent-touch policy, marker visuals,
  and seed-slot-preserving first/second-return map records.
- Hardened the P backend locally: absolute-source CI package installation,
  unique GL context identities, owned context custodians, premultiplied GL
  compositing/readback conversion, byte-bounded FBOs, and shared software
  frame artifacts for projected-label depth queries.

Known boundaries: SCENE-3D-T currently has sign-changing and endpoint event
roots, but not isolated tangency detection. Arc-length limits use the same
deterministic eight-chord estimate as general trajectory queries rather than a
certified integral; low-speed termination checks accepted nodes and one
midpoint per segment, without a configurable consecutive-check policy. It also
lacks a process-serializable multicore preparation executor,
equilibrium/flow-map analysis, and certified arc-length integration. Adaptive implicit
extraction, analytic implicit picking,
trim Boolean regions, general mesh attribute descriptors (UV/scalar/semantic
IDs), touching/self-intersecting section validation, repeated capped
multi-plane geometry cuts, general polygon section fills, automatic default
use of prepared label trajectories are not complete in this change. Core mathematical annotations are world-space
relations; they do not yet provide automatic formula labels or camera-facing
screen sizing. Leaders are currently top-level 2D compositor overlays, with
intentionally fixed styling.
The OpenGL paths are compiled and
the explicit integration test remains separate from ordinary headless runs.

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

Known boundary: this optional backend requires a compatible OpenGL 3.2 /
GLSL 1.50 context and is tested on macOS plus an optional Xvfb lane. It uses
one serialized context with `#:workers 1`; it does not offer threaded GPU
parallelism, direct OpenGL preview-canvas composition, GPU picking, textures,
shadows, or order-independent transparency. The
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
