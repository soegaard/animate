#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-optional-racket-o-35de9ff"]{3D: Optional Racket/OpenGL backend}

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defmodule[animate/3d/opengl]

SCENE-3D-P adds an explicit GPU implementation of the same
@racket[renderer3d] protocol. Requiring this module is the opt-in boundary for
@racketmodname[opengl] and @racketmodname[racket/gui/base]; neither
@racketmodname[animate], @racketmodname[animate/3d], nor
@racketmodname[animate/3d/render] loads it. The renderer owns a hidden canvas
only to obtain a context, renders each @racket[view3d] to an owned RGBA8/depth
framebuffer, reads it back, flips the rows, and returns the ordinary top-down
straight-alpha ARGB result used by the Pict compositor.

@defproc[(opengl-renderer3d-spec
          [#:samples samples exact-positive-integer? 4]
          [#:cache-megabytes cache-megabytes exact-positive-integer? 512]
          [#:fallback fallback (or/c 'error 'software) 'error])
         opengl-renderer3d-spec?]{Declares an explicit backend configuration.
@racket['error] rejects an unavailable context. @racket['software] is the only
deliberate fallback policy and is reported in backend statistics; no request
silently changes backend. The requested sample count is clamped to the live
driver's maximum before rendering. Diagnostics report both the requested and
effective counts, and persistent cache identity uses the effective count.}
@defproc[(opengl-renderer3d-spec? [value any/c]) boolean?]{Recognizes an
OpenGL backend declaration.}
@defproc[(opengl-renderer3d [spec opengl-renderer3d-spec?
                                  (opengl-renderer3d-spec)]) renderer3d?]{
Creates a retained backend with one serialized owned OpenGL context. It checks
for OpenGL 3.2 and GLSL 1.50 plus VBO/EBO/VAO/FBO/depth/readback support before
returning.}
@defproc[(opengl-renderer3d? [value any/c]) boolean?]{Recognizes an OpenGL
renderer instance, including one whose explicit fallback is active.}
@defproc[(opengl-renderer3d-available?) boolean?]{Creates and closes a short
lived hidden context to test availability. It is a real capability probe, not
a package-presence test.}
@defproc[(opengl-renderer3d-info [renderer opengl-renderer3d?]) immutable-hash?]{
Returns serializable GL version, GLSL version, vendor, renderer, profile,
limits, required-capability, and optional-feature diagnostics. Its optional
backend diagnostic data includes both requested and effective multisample
counts.}
@defproc[(opengl-renderer3d-statistics [renderer opengl-renderer3d?]) immutable-hash?]{
Returns backend counters plus geometry-cache and framebuffer-cache information.}
@defproc[(opengl-renderer3d-reset-statistics! [renderer opengl-renderer3d?]) void?]{
Resets measured counters without changing cached immutable geometry.}
@defproc[(opengl-renderer3d-release! [renderer opengl-renderer3d?]) void?]{
Deletes shader, VAO/VBO/EBO, framebuffer, and context-owner resources. It is
idempotent and never changes an authored spatial value.}

For final project output, use an explicit declaration:

@racketblock[
(render-spec
 #:renderer3d
 (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 512 #:fallback 'error)
 #:workers 1)
]

An OpenGL project must run in Racket 9.3 @exec{gracket}; a plain @exec{racket}
process produces an actionable project diagnostic instead of selecting software
implicitly. Project preview inherits this declaration and owns the retained
renderer for the lifetime of its window. Camera motion changes uniforms and a
viewport-size change only reallocates the FBO; neither reuploads immutable
geometry.

@bold{OpenGL limitations:} The first backend has one serialized context and
therefore requires @racket[#:workers 1]; it does not create threaded GPU
workers. It uses FBO readback rather than direct OpenGL preview-canvas
composition. It supports Lambert/Blinn--Phong materials and a packed finite
light stream with fixed limits of four directional, eight point, and four spot
lights. The OpenGL backend supports V9 directional/spot maps through a
context-owned bounded depth-texture cache. There is no GPU picking, general
mesh textures, point-light cube shadows, persistent
mapped buffers, PBO pipelining, compute/geometry shaders, or order-independent
transparency. The software backend remains the portable default and conformance
reference. Compare GPU/software pixels by tolerance: opaque interiors,
antialiased edges, and transparent regions need different thresholds and must
not be expected to be bit-identical.

The reference/retained conformance tests compare projected output at exact
endpoints and in nonmonotonic camera-frame order. The canonical probe is
@filepath{examples/3d/retained-renderer.rkt}; evaluating
@tt{(retained-renderer-summary)} there demonstrates a cache hit without
changing the visible scene.

The repository tool @filepath{tools/run-3d-probes.rkt} renders the canonical
visual probes for any visible stage from @tt{3D-B} through @tt{3D-P}. For
example, @tt{gracket tools/run-3d-probes.rkt --stage 3D-P --renderer opengl
--output rendered-examples/3d-p-opengl} writes frame PNGs plus @tt{manifest.rktd} and a
@tt{diagnostics.rktd} file per probe. The manifest records Animate and Racket
versions, renderer ID, output dimensions, sample times, sampled 3D cameras,
renderer-fingerprint digests, compiled geometry keys/counts, frame hashes, and
for O, compiled stroke/marker/outline counts and requested screen/world width
modes. @tt{--compare-renderers software,opengl} writes side-by-side software
and OpenGL trees, per-frame absolute-difference PNGs, and channel-difference
metrics in @tt{comparison.rktd}.
Probe images are human review evidence; semantic and small-raster tests remain
the correctness oracle. @filepath{tools/benchmark-3d.rkt} measures the same
ten named workloads through either backend. Its OpenGL run reports first
context/shader/allocation work separately from warm frames, plus retained
geometry, framebuffer, readback, and renderer counters. It has no CI timing
threshold; the acceptance checks are zero geometry uploads for warm
camera/object-transform work and zero framebuffer reallocations at an unchanged
viewport.

@bold{Current limitation:} Screen strokes use deterministic software coverage,
not analytic antialiasing. Curve centreline detail is limited by authored
samples. Hidden-line classification uses opaque and @racket['depth-only]
surfaces only: transparent surfaces are not reliable hidden-line occluders.
Screen points and arrowheads are camera-facing marks, not lit mesh spheres or
cones. Surface topology is a fixed rectangular grid. Solid construction currently
supports only simple single contours (no holes or self-intersections), and
revolution accepts only nonnegative-radius profiles around a cardinal axis.
There is no adaptive tessellation, trimmed domain, texture mapping, arbitrary
implicit surface, or cap generation for arbitrary sliced meshes.
Transparent intersections are not order-independent: triangle sorting is a
useful deterministic approximation, not OIT. Section joining does not repair
pathological nonmanifold meshes. Projected labels are crisp 2D overlays; the
final compositor now uses overlap-aware candidate selection among direct-mode
projected labels (it minimizes overlap but cannot guarantee a disjoint result), but
prepared trajectories remain explicit inputs for their sampled frame grid.
Leaders and visibility policies are consumed by final composition. Only opaque
depth is considered for their hide/fade policy. Billboard image annotations
are depth-tested, but do not yet provide source-mapped text or exact picking.
Linear and affine map requests do not resample geometry; singular maps use a
deterministic authored-normal shading fallback. Pointwise and homotopy maps
currently accept only an unwrapped @racket[mesh3d], not curves, surfaces, or
arbitrary containers. They use the source's fixed authored vertices without
adaptive remeshing, so non-injective maps can create degenerate or
self-intersecting triangles. @racket['drop-triangle] leaves open holes and
does not cap or repair them; it is deliberately not the default. Turning off
normal recomputation preserves source normals and can make nonlinear shading
misleading. Spatial ODE fields require finite @racket[vec3] results. Vector
fields and streamlines have finite explicit author samples; they do not offer
adaptive field-line topology, event detection, or adaptive stopping. There is
no 3D ODE source inspector. Spatial picking accelerates indexed mesh triangles
(including generated tube/surface meshes) with object bounds and a local BVH,
and uses the same prepared screen footprints for strokes and markers. It does
not yet expose texture UVs, interpolate supplied vertex normals for a pick,
support analytic implicit geometry, or perform a GPU-backed selection pass.
Preview overlays and selection scratch values are
diagnostic-only and are intentionally absent from normal frame/video renders.
The retained software backend caches immutable geometry separately from the
reference renderer's camera-space preparations; a camera or viewport change may
therefore miss that software preparation cache. The optional OpenGL backend
retains immutable geometry separately and uses tolerant, not bit-exact, image
comparison.
