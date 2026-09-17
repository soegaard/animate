#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-meshes-topology-s-dbebcef"]{3D: Topology-safe mesh matching}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defproc[(spatial-line-route3d) spatial-line-route3d?]{Creates the default
straight reference-translation route.}
@defproc[(spatial-line-route3d? [value any/c]) boolean?]{Recognizes a straight
spatial route.}
@defproc[(spatial-arc-route3d [#:axis axis vec3?] [#:angle angle finite-real?])
         spatial-arc-route3d?]{Creates a circular reference route. The
nonzero @racket[axis] must be perpendicular to the source/destination
translation chord when the request is compiled, and @racket[angle] must be
strictly between @racket[-pi] and @racket[pi], excluding zero.}
@defproc[(spatial-arc-route3d? [value any/c]) boolean?]{Recognizes a circular
spatial route.}
@defproc[(spatial-bezier-route3d [control-1 vec3?] [control-2 vec3?])
         spatial-bezier-route3d?]{Creates an endpoint-exact cubic route whose
controls are translations in the target parent's local coordinates.}
@defproc[(spatial-bezier-route3d? [value any/c]) boolean?]{Recognizes a cubic
spatial route.}
@defproc[(spatial-route3d? [value any/c]) boolean?]{Recognizes any supported
spatial matching route.}
@defproc[(spatial-route3d-sample [route spatial-route3d?] [from vec3?]
                                  [to vec3?] [progress (real-in 0 1)])
         vec3?]{Samples a route directly. It returns the original @racket[from]
and @racket[to] values at zero and one.}

@defproc[(mesh3d-correspondence-compatible?
          [source mesh3d?] [destination mesh3d?]
          [correspondence mesh-correspondence3d?]) boolean?]{Reports whether
the plan supplies a complete bijection of vertices and render triangles and
every mapped source triangle uses the mapped vertices of its destination
partner. This is the safety test required before interpolating indexed mesh
geometry.}

@defproc[(mesh3d-matching-sample [source mesh3d?] [destination mesh3d?]
                                  [correspondence mesh-correspondence3d?]
                                  [route spatial-route3d?]
                                  [progress (real-in 0 1)]) mesh3d?]{Samples a
same-topology matching transition. Interior samples retain the source triangle
and edge arrays, interpolate each mapped vertex, optional per-vertex normal and
colour, material envelope, opacity, wireframe colour/width, and decomposed
transform. Reference translation follows @racket[route]. Progress zero and one
return the exact source and destination mesh values.}

@defproc[(mesh3d-cross-fade-sample [source mesh3d?] [destination mesh3d?]
                                    [route spatial-route3d?]
                                    [progress (real-in 0 1)]) spatial-visual?]{
Samples a topology-changing transition as two independently valid temporary
mesh layers under the stable source identity. It returns the exact endpoints;
the temporary group appears only at interior progress.}

@defproc[(group3d-face-parts-matching-sample
          [source group3d?] [destination group3d?]
          [matches (or/c #f (listof spatial-correspondence3d?))]
          [route spatial-route3d?] [progress (real-in 0 1)]) group3d?]{Samples
stable direct @racket[mesh3d] children as mathematical face parts. A supplied
@racket[spatial-correspondence3d] names source/destination child IDs and may
override @racket[route]; omitted matches pair equal child IDs. Each matched
pair independently uses a complete compatible mesh plan or a local safe
cross-fade. Unmatched source children fade out and unmatched destination
children fade in beneath generated IDs that exist only at interior samples.
The outer group endpoint values are exact.}

@defproc[(transform-matching-mesh3d
          [target spatial-path?] [destination mesh3d?]
          [#:correspondence correspondence (or/c #f mesh-correspondence3d?) #f]
          [#:topology topology (or/c 'require-equal 'cross-fade) 'require-equal]
          [#:route route spatial-route3d? (spatial-line-route3d)]) any/c]{
Creates a @racket[scene-play] request for the @racket[mesh3d] at
@racket[target]. @racket[destination] must preserve the target mesh's spatial
identity. With @racket['require-equal], an omitted plan is prepared at clip
admission, then must prove a complete compatible topology; otherwise admission
raises an explanation with the unmatched-plan diagnostics. With
@racket['cross-fade], source and destination index arrays remain separate and
fade under a temporary group. The final sample installs the exact destination
mesh and leaves no temporary identity.

The runnable example is
@filepath{examples/3d/transform-matching-polyhedra.rkt}.}
@defproc[(transform-matching-mesh3d-request? [value any/c]) boolean?]{Recognizes
a request created by @racket[transform-matching-mesh3d].}

@defproc[(transform-matching-spatial
          [target spatial-path?] [destination group3d?]
          [#:matches matches (or/c #f (listof spatial-correspondence3d?)) #f]
          [#:route route spatial-route3d? (spatial-line-route3d)]) any/c]{
Creates a @racket[scene-play] direct face-part request. The group currently at
@racket[target] and @racket[destination] must share their outer spatial
identity; direct mesh child pairs are given by @racket[matches] or equal child
IDs. Matching children interpolate only after their own compatible plan is
proved; unmatched or topology-changing children cross-fade. The final sample
installs the exact destination group, with no generated child identities.}
@defproc[(transform-matching-spatial-request? [value any/c]) boolean?]{Recognizes
a request created by @racket[transform-matching-spatial].}

@bold{Limitations.} Face-part matching currently requires an explicitly
authored @racket[group3d] with direct @racket[mesh3d] face children, such as
@racket[polyhedron-net3d-group]. It does not split arbitrary triangle meshes
into polygonal groups on demand, retarget arbitrary nested spatial trees, infer
a graph isomorphism, or attach labels/strokes to faces. A route changes a
part's reference translation; it does not bend internal mesh topology. Use
@racket['cross-fade] for any whole-mesh topology change, unmatched part, or
ambiguity.
@defproc[(mesh3d-normals [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable normals.}
@defproc[(mesh3d-colors [mesh mesh3d?]) (or/c #f vector?)]{Returns optional immutable colours.}
@defproc[(mesh3d-material [mesh mesh3d?]) material3d?]{Returns the surface material.}
@defproc[(mesh3d-wireframe-color [mesh mesh3d?]) any/c]{Returns the current edge colour.}
@defproc[(mesh3d-wireframe-width [mesh mesh3d?]) positive-real?]{Returns the cosmetic edge width.}
@defproc[(mesh3d-local-bounds [mesh mesh3d?]) aabb3?]{Returns bounds enclosing local vertices.}

