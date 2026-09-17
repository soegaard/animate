#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-retained-renderer-0e201a5"]{3D: Compiled geometry and instances}

@declare-exporting[animate/3d/render #:use-sources (animate/3d/render)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defstruct*[compiled-geometry3d
            ([key any/c] [mesh mesh3d?] [local-bounds aabb3?]
             [face-normals vector?] [edge-adjacency vector?]
             [analysis mesh3d-analysis?]) #:transparent]{A camera-independent
geometry resource. Its canonical key includes local vertices, triangle and
explicit-edge topology, normals, and per-vertex colours; it excludes material,
opacity, transforms, camera, lights, and viewport settings.}
@defstruct*[compiled-instance3d
            ([path (listof symbol?)] [geometry-key any/c]
             [world-transform affine3?] [normal-transform linear3?]
             [material material3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]
             [surface-mode (or/c 'visible 'depth-only 'none)]) #:transparent]{The
ordered placement and style of one compiled geometry use.}
@defstruct*[compiled-stroke3d
            ([path (listof symbol?)] [points vector?] [closed? boolean?]
             [world-transform affine3?] [style stroke3d?] [opacity real?]
             [clip-planes list?] [drawing-index exact-nonnegative-integer?]
             [source-kind symbol?] [source-metadata immutable-hash?])
            #:transparent]{A camera-independent sampled centreline. Screen
width, dashes, clipping, depth classification, and cap/join coverage are
prepared only for a concrete frame.}
@defstruct*[compiled-point-marker3d
            ([path (listof symbol?)] [position vec3?] [world-transform affine3?]
             [style point-style3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]) #:transparent]{A
camera-independent point marker.}
@defstruct*[compiled-arrow-marker3d
            ([path (listof symbol?)] [from vec3?] [to vec3?]
             [world-transform affine3?] [style arrow-style3d?] [opacity real?]
             [clip-planes list?] [drawing-index exact-nonnegative-integer?])
            #:transparent]{A camera-independent arrowhead marker.}
@defstruct*[compiled-edge-overlay3d
            ([path (listof symbol?)] [geometry-key any/c]
             [world-transform affine3?] [normal-transform linear3?]
             [style edge-style3d?] [opacity real?] [clip-planes list?]
             [drawing-index exact-nonnegative-integer?]) #:transparent]{An
outlined mesh reference whose feature selection is deliberately deferred until
camera-frame preparation.}
@defstruct*[compiled-view3d
            ([geometries vector?] [instances vector?] [strokes vector?]
             [point-markers vector?] [arrow-markers vector?] [edge-overlays vector?]
             [background any/c]
             [render-mode symbol?] [transparency-mode symbol?]) #:transparent]{
The immutable camera-independent renderer input. Use
@racket[compiled-view3d-primitives] for stable drawing-index order across these
primitive vectors.}
@defstruct*[frame3d-spec
            ([camera camera3d?] [lights list?] [width exact-positive-integer?]
             [height exact-positive-integer?]) #:transparent]{The state which
may change from one rendered frame to the next.}
@defproc[(compile-view3d [view view3d?]) compiled-view3d?]{Lowers a spatial
tree deterministically, sharing equal geometry resources in first encounter
order. It does not inspect the view's camera.}
@defproc[(compiled-view3d-primitives [view compiled-view3d?]) vector?]{Returns
the mesh instances, strokes, point markers, arrow markers, and edge overlays in
stable drawing-index order.}
@defproc[(view3d->frame3d-spec [view view3d?]
                                [width exact-positive-integer?]
                                [height exact-positive-integer?]) frame3d-spec?]{
Extracts frame-varying camera, light, and viewport state.}
@defproc[(view3d->render3d-request [view view3d?]
                                   [width exact-positive-integer?]
                                   [height exact-positive-integer?]
                                   [#:cancellation-token cancellation-token any/c #f]
                                   [#:attachments attachments (listof symbol?) '(color)]
                                   [#:theme theme color-theme? #f])
         render3d-request?]{Conveniently compiles @racket[view] and packages
the resulting compiled view, frame specification, and requested attachments.
The canonical attachment names are @racket['color], @racket['linear-depth],
@racket['object-id], and @racket['normal]. A renderer may return a superset,
but cannot omit a requested attachment. The resulting request owns an immutable
color-context snapshot. Without @racket[#:theme], it captures an enclosing
render context when present, otherwise the built-in light theme.}
