#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-animation-847149f"]{3D: Animating the 3D camera}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(camera3d-move-to [view-id symbol?] [position vec3?]) any/c]{Moves a
camera to an absolute position, retaining its lens and orientation.}
@defproc[(camera3d-look-at-to [view-id symbol?] [target vec3?]
                              [#:up up vec3? y-axis3]) any/c]{Reorients a
camera to look at a world point.}
@defproc[(camera3d-orbit-by [view-id symbol?]
                             [#:center center vec3? origin3]
                             [#:azimuth azimuth finite-real? 0]
                             [#:elevation elevation finite-real? 0]) any/c]{
Creates a finite orbit about @racket[center]. Position follows the exact orbit;
at every sampled position, orientation is a normalized quaternion that looks
directly at @racket[center]. This prevents a camera from looking away from its
subject midway through a large orbit.}
@defproc[(camera3d-roll-to [view-id symbol?] [angle finite-real?]) any/c]{Sets
the absolute roll around the current forward direction.}
@defproc[(camera3d-field-of-view-to [view-id symbol?]
                                    [field-of-view finite-real?]) any/c]{
Interpolates a perspective camera's vertical field of view. It rejects an
orthographic camera.}
@defproc[(camera3d-orthographic-height-to [view-id symbol?]
                                           [height positive-real?]) any/c]{
Interpolates an orthographic camera's visible height. It rejects a perspective
camera.}
@defproc[(camera3d-dolly-by [view-id symbol?] [distance finite-real?]) any/c]{
Moves along the clip-start forward axis; positive distance moves forward.}
@defproc[(camera3d-fit [view-id symbol?]
                        [#:padding padding positive-real? 11/10]) any/c]{
Frames the current spatial bounds conservatively.}
@defproc[(camera3d-follow [view-id symbol?] [path spatial-path?]) any/c]{
Retains the clip-start camera offset from a spatial target path rooted at the
same view. It is resolved after local spatial transforms at each sampled time.}

All these forms work as leaves of @racket[timed], @racket[succession],
@racket[animation-group], and @racket[lagged-start]. A 3D camera remains
separate from the ordinary two-dimensional render camera, so a formula or
caption stays fixed while the view's spatial camera moves.

In interactive preview, an inspection camera is an overlay on the authored
camera: drag in a spatial viewport to orbit, shift-drag to pan its target, use
the mouse wheel to dolly (or orthographic zoom), and press @tt{R} to return to
the authored view. The override is part of the immutable preview render
request—including a subprocess worker request—and is never written into source
or the Scene. The Animate menu can reset it or copy an expression/animation
scratch form for authoring.

For runnable examples, see @filepath{examples/3d/wireframe-cube.rkt},
@filepath{examples/3d/opaque-cube.rkt}, and
@filepath{examples/3d/depth-test.rkt};
@filepath{examples/3d/camera-orbit.rkt} is the canonical motion probe.

@bold{Current limitation:} opaque mode is a software rasterizer for filled
triangles. It has flat, unlit, and smooth shading, depth-aware transparency,
spatial relations, projected labels, specular response, and directional/spot
shadows. It does not provide general mesh texture mapping or order-independent
transparency. Picking is covered by the inspection chapters. An ordinary two-dimensional traversal of a spatial child is
rejected: use rooted 3D animation paths or @racket[view3d-spatial-*].

