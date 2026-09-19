#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-inspectio-46dec95"]{3D: Spatial inspection and exact picking}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Spatial inspection exposes the hierarchy that an already sampled
@racket[view3d] submits to its renderer. Inspection is immutable query data;
it never adds a wireframe, selection flag, acceleration structure, or other
hidden state to an authored Scene. The preview uses the same query data after a
viewport click and paints its AABB, exact triangle, normal, local frame, and
ray-pixel marker only after the cached bitmap has been drawn.

@defstruct*[spatial-inspection
            ([path (listof symbol?)]
             [kind symbol?]
             [local-transform transform3?]
             [world-transform affine3?]
             [local-bounds aabb3?]
             [world-bounds aabb3?]
             [material any/c]
             [triangle-count exact-nonnegative-integer?]
             [vertex-count exact-nonnegative-integer?]
             [camera-position vec3?]
             [view-position (or/c #f vec3?)]
             [projected-position (or/c #f vec2?)]
             [view-depth (or/c #f nonnegative-real?)]
             [metadata immutable-hash?]) #:transparent]{
One deterministic pre-order description of a spatial group, mesh, curve, or
surface. @racket[path] begins with the enclosing @racket[view3d] identity;
@racket[local-transform] is the authored decomposition while
@racket[world-transform] includes all spatial ancestors. Empty geometry has
false projection/depth fields rather than an invented point.
}

@defstruct*[spatial-pick
            ([inspection spatial-inspection?]
             [path (listof symbol?)]
             [triangle-index (or/c #f exact-nonnegative-integer?)]
             [point vec3?]
             [distance nonnegative-real?]
             [barycentric vec3?]
             [normal vec3?]
             [ray ray3?]
             [metadata immutable-hash?]) #:transparent]{
The nearest spatial pick. @racket[spatial-pick-kind] returns
@racket['mesh-triangle], @racket['stroke-segment], @racket['point-marker], or
@racket['arrow-marker]. Mesh hits are exact ray/triangle intersections; screen
marks use the same prepared projected footprint and depth predicate as the
renderer. Stroke metadata includes source segment index/progress, world point,
view depth, pixel distance, and style. Ties are resolved by depth, drawing
index, then authored triangle or source segment index.

For a mesh triangle, metadata also carries immutable semantic and topological
inspection data: @racket['semantic-vertex-ids], @racket['semantic-edge-ids],
@racket['render-triangle-id], @racket['connected-component],
@racket['boundary-components], and @racket['topology].  The latter records the
Euler characteristic, boundary count, manifold/closed/orientable predicates,
component invariants, genus report, and diagnostics.  The explicitly named
@racket['semantic-polygonal-face-id] currently equals the render-triangle ID,
with @racket['polygonal-face-policy] set to @racket['render-triangle]: a plain
@racket[mesh3d] does not yet retain a separate polygonal-face-complex mapping.
@racket['nearest-semantic-vertex-id] and @racket['nearest-semantic-edge-id]
classify the nearest lower-dimensional primitive from barycentric coordinates;
they do not claim an exact lower-dimensional ray intersection. The latter's
@racket['nearest-edge-incident-face-ids] reports every incident triangle face.
Inspection only reads immutable topology; it does not alter the Scene.
}
@defstruct*[topology-inspection3d
            ([path (listof symbol?)]
             [semantic-vertex-ids vector?]
             [semantic-edge-ids vector?]
             [nearest-vertex-id any/c]
             [nearest-edge-id any/c]
             [nearest-edge-incident-face-ids vector?]
             [render-triangle-id any/c]
             [polygonal-face-id any/c]
             [polygonal-face-policy any/c]
             [connected-component any/c]
             [boundary-components vector?]
             [topology hash?]) #:transparent]{
One immutable, presentation-neutral explanation of a mesh pick's semantic
parts and topological report. The preview's @tt{3D topology} section uses this
record; a headless authoring tool can use precisely the same data.}
@defproc[(spatial-pick-topology-inspection3d [pick spatial-pick?])
         (or/c #f topology-inspection3d?)]{
Returns a @racket[topology-inspection3d] for an exact mesh-triangle pick, and
@racket[#f] for a stroke or marker pick. It only repackages already retained
immutable pick data; it does not traverse or mutate the scene.}
@defstruct*[spatial-topology-overlay3d
            ([vertex vec3?]
             [edge vector?]
             [face vector?]
             [component-faces vector?]
             [boundary-segments vector?]
             [halfedges vector?]) #:transparent]{
Preview-only world-space geometry derived from one exact mesh pick. The
@racket[vertex] and @racket[edge] designate the nearest semantic primitive
under the triangle hit; @racket[face] is the selected render triangle;
@racket[component-faces] contains its edge-connected component;
@racket[boundary-segments] contains that component's boundary edges; and
@racket[halfedges] preserves the selected triangle's directed source edges.
Each segment is an immutable two-@racket[vec3] vector and each face is an
immutable three-@racket[vec3] vector. This is diagnostic geometry only: it is
not a @racket[mesh3d] and cannot affect rendering, matching, or scene state.
}
@defproc[(spatial-pick-topology-overlay3d [view view3d?] [pick spatial-pick?])
         (or/c #f spatial-topology-overlay3d?)]{
Returns the immutable topology overlay for an exact mesh-triangle pick in
@racket[view], or @racket[#f] for screen-space marks or a pick that does not
have a matching mesh command in that view. The function performs its component
traversal only on demand after a selection; it does not mutate or augment the
view. The preview paints at most the first 256 component-face outlines and
512 boundary segments to preserve UI responsiveness; the returned value and
the topology inspection report always retain the complete component.}
@defstruct*[surface-pick3d
            ([spatial-pick spatial-pick?]
             [surface-kind symbol?]
             [parameter (or/c #f vector?)]
             [trim-boundary any/c]
             [source-cell any/c]
             [interpolated-normal (or/c #f vec3?)]) #:transparent]{
A refinement of an exact mesh @racket[spatial-pick] for a @racket[surface3d].
The source cell is immutable triangle provenance, not an implementation cache.
}
@defproc[(spatial-pick-kind [pick spatial-pick?])
         (or/c 'mesh-triangle 'stroke-segment 'point-marker 'arrow-marker)]{
Returns the selected primitive kind.}

@defproc[(view3d-spatial-inspections [view view3d?]) (listof spatial-inspection?)]{
Returns deterministic pre-order records, including containers.
}
@defproc[(view3d-spatial-inspection-tree [view view3d?])
         (listof spatial-inspection?)]{An explicit spelling for the same
pre-order hierarchy, convenient for a tree UI.}
@defproc[(view3d-spatial-inspection-at [view view3d?]
                                        [path (listof symbol?)])
         (or/c #f spatial-inspection?)]{Returns the matching record, or
@racket[#f] when @racket[path] does not occur in this view.}
@defproc[(view3d-pick [view view3d?] [ray ray3?])
         (or/c #f spatial-pick?)]{
Picks a spatial object with world ray @racket[ray]. It first culls world AABBs,
transforms the candidate ray to mesh-local coordinates, traverses a local BVH,
and finishes with exact triangle and barycentric testing.
}
@defproc[(view3d-surface-pick [view view3d?] [ray ray3?])
         (or/c #f surface-pick3d?)]{
Uses the same CPU path as @racket[view3d-pick], returning @racket[#f] unless
the nearest hit is a surface. Parametric parameters are interpolated from
retained vertex provenance; an implicit result retains its source grid/tetrahedron
record instead.}
@defproc[(view3d-pixel-pick [view view3d?] [pixel-x finite-real?]
                             [pixel-y finite-real?]
                             [#:width width exact-positive-integer?]
                             [#:height height exact-positive-integer?])
         (or/c #f spatial-pick?)]{
Builds the camera ray through a top-left-origin viewport pixel. It performs
exact mesh picking and supplements it with prepared screen-stroke and marker
footprints; it does not sample a rendered bitmap or require a GUI.
}

@defproc[(mesh3d-bvh [mesh mesh3d?]) mesh3d-bvh?]{Returns the immutable local
acceleration tree used for picking. It splits on the longest centroid axis,
uses a stable median, and breaks ties by triangle index. The cache is an
implementation resource, not semantic scene state.}
@defproc[(mesh3d-bvh? [value any/c]) boolean?]{Recognizes an inspection BVH.}
@defproc[(bvh3d-node? [value any/c]) boolean?]{Recognizes an internal BVH node.}
@defproc[(bvh3d-leaf? [value any/c]) boolean?]{Recognizes a BVH leaf.}
@defproc[(bvh3d-bounds [tree mesh3d-bvh?]) aabb3?]{Returns local bounds for a
node or leaf.}
@defproc[(bvh3d-triangle-indices [tree mesh3d-bvh?])
         (listof exact-nonnegative-integer?)]{Returns the complete stable set
of contained triangle indices.}
@defproc[(bvh3d-ray-candidates [tree mesh3d-bvh?] [ray ray3?])
         (listof exact-nonnegative-integer?)]{Returns deterministic local
triangle candidates. Exact triangle testing remains separate.}

The canonical preview probe is
@filepath{examples/3d/spatial-inspector-picking.rkt}. Open it with
@racketmodname[animate/preview], click a visible facet, then use the
@tt{3D topology} inspector section to see semantic part IDs and invariants;
the post-render overlay marks its face, component, boundaries, half-edges, and
normal. @tt{Animate → 3D selection} can copy the spatial path, hit point, or
normal; its scratch action also supplies a clipping plane. Focusing the
inspection camera changes only the preview override, never the authored camera
or timeline. The raw mesh uses render triangles as polygonal faces, so the
probe does not claim an unretained higher-level polygonal-face mapping.

