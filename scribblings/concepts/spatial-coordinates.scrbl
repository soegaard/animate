#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     racket/math
                     animate/3d
                     animate/3d/opengl))

@title[#:tag "spatial-coordinates"]{Spatial Coordinates}

SCENE-3D-A introduces the mathematical coordinate system used by spatial
Visuals, SCENE-3D-B makes its wireframe part visible, SCENE-3D-C adds
opaque triangle meshes, SCENE-3D-D adds deterministic spatial and camera
motion, SCENE-3D-E adds semantic spatial relations plus crisp ordinary 2D
labels anchored to projected spatial points, SCENE-3D-F adds finite points,
tubes, sampled curves, arrows, axes, grids, and vector diagrams, SCENE-3D-G
adds fixed-grid parametric/function surfaces with direct-time calculus helpers,
SCENE-3D-I adds clipping, sections, and depth-aware transparency, and
SCENE-3D-J adds direct-time linear, affine, pointwise, and homotopy maps.
SCENE-3D-K adds immutable prepared 3D ODE trajectories plus deterministic
static vector-field, streamline, and particle geometry. SCENE-3D-L adds
immutable spatial inspection records, deterministic local BVH traversal, and
exact camera-ray triangle picking for a sampled @racket[view3d].
SCENE-3D-M adds an effectful retained-renderer protocol behind that immutable
model. SCENE-3D-N adds explicit indexed-mesh topology diagnostics, orientation
repair, and camera-independent compiled geometry resources; renderer caches and
metrics remain outside the spatial tree and the deterministic software path
remains the conformance reference. SCENE-3D-O adds renderer-independent
mathematical strokes, screen-sized points and arrowheads, and camera-dependent
feature/silhouette outlines. These marks prepare from immutable centrelines at
the requested frame; they do not become camera-dependent author values.
SCENE-3D-P adds an optional Racket/OpenGL implementation behind the same
renderer protocol. It owns retained GPU resources and an offscreen framebuffer,
then reads copied ARGB pixels back into the ordinary 2D composition; the
software renderer remains the default reference.
It still does not add a
second scene timeline: @racket[view3d] is an ordinary two-dimensional Visual
inside the existing immutable scene, with a separate immutable spatial tree.

Spatial coordinates are right-handed:

@verbatim{
                    +y
                    ↑
                    │
          +x  →     o     ⊙ +z
                         toward the viewer
}

The coordinate constants are @racket[origin3], @racket[x-axis3],
@racket[y-axis3], and @racket[z-axis3]. In particular,
@racket[(vec3-cross x-axis3 y-axis3)] is @racket[z-axis3]. A two-dimensional
world point embeds in the future spatial coordinate system as
@racket[(vec3 x y 0)].

The algebra, spatial-tree, mesh, and camera values in
@racketmodname[animate/3d] are immutable, finite semantic data. They can be
calculated and tested in a headless process just like the existing immutable
scene model. Rendering a @racket[view3d] through @racketmodname[animate] uses
the ordinary Pict renderer; that adapter is the deliberate effectful boundary,
not a second rendering system exposed to authors.

The author-oriented @racket[transform3] applies its components in this order:

@racketblock[
(define transformed
  (make-transform3
   #:translation (vec3 4 0 0)
   #:rotation (axis-angle z-axis3 (/ pi 2))
   #:scale (vec3 2 2 2)))

(transform3-apply-point transformed (vec3 1 0 0))
]

That example first scales the local point, then rotates it counter-clockwise
around positive @racket[z-axis3], then translates it. A general composition of
nonuniform decomposed transforms can create shear, so @racket[transform3-compose]
returns an exact @racket[affine3] map rather than silently discarding it.

@bold{Current limitation:} a @racket[view3d] can draw depth-tested filled
triangles plus mathematical screen/world strokes. Opaque triangles are clipped
against all six camera-frustum planes, back-face culled by default,
unlit/flat/smooth shaded, and resolved by a deterministic z-buffer. A
render-only @racket[clip3d] adds local half-space clipping, while
@racket[slice-mesh3d] and plane sections produce actual geometry. Transparent
triangles are sorted far-to-near against the opaque depth target, which is
deterministic but not order-independent transparency. There is no texture
mapping, specular response, shadows, or arbitrary slice cap generation. Stage
L picking operates on indexed mesh triangles (including generated curve and
surface meshes), not analytic implicit shapes, UVs, or a GPU selection pass;
its preview overlays are diagnostic-only and never enter a rendered frame.
The default retained backend caches reference camera-space preparation but is
not GPU accelerated. The optional OpenGL backend requires an explicit
@racketmodname[animate/3d/opengl] choice in a GUI-capable Racket process and
uses one serialized context, FBO readback, and tolerance-based rather than
bit-exact software conformance. It has no direct GL presentation, GPU picking,
textures, shadows, specular/roughness shading, or order-independent
transparency.
Stage F diagrams have deterministic physical-radius tubes and direct-time curve
animation; Stage O adds screen-space widths, caps, joins, dashes, visible and
hidden depth modes, and screen-sized marker primitives. The software coverage
is deterministic rather than analytically antialiased, and hidden-line
classification deliberately ignores transparent surfaces. Stage G surfaces use
fixed rectangular topology, deterministic normal fallbacks, and direct-time
reveal/morph. Adaptive/implicit surfaces and general solids remain later work.
Projected labels are 2D overlays with fixed pixel offsets—not
occlusion-aware 3D billboards—but may opt into opaque-depth @racket['hide] or
@racket['fade] behaviour and can overlap. `move3d-*`,
`rotate3d-*`, `scale3d-*`,
and `camera3d-*` requests are finite immutable clips: a frame is calculated
from its requested time rather than the previous frame. Camera aspect comes
from the viewport being rendered, so a camera is reusable in viewports of
different sizes. Linear and affine map requests retain exact indexed topology
and can apply to a whole named spatial subtree. Pointwise and homotopy maps
currently operate on unwrapped @racket[mesh3d] values only; they sample the
  authored vertices and do not adaptively remesh. A non-injective map can make
  degenerate or self-intersecting triangles. The default invalid-point policy is
  an error; @racket['drop-triangle] deliberately leaves holes and does not cap
  or repair them. Prepared 3D ODE fields must return finite @racket[vec3]
  values. Their vector-field grids and streamline seeds are explicit finite
samples, not adaptive field-line topology; there is no event detection or
3D ODE source inspector.
