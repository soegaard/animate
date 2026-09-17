#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-supplementary-q-t-100c1a0"]{3D: Surface constructors and queries}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defthing[adaptive-parametric-surface3d procedure?]{Constructs a deterministic
adaptive parametric surface using the documented dyadic refinement policy.}
@defthing[trimmed-parametric-surface3d procedure?]{Constructs a parametric
surface restricted by declared trim fields.}
@defthing[implicit-surface3d procedure?]{Constructs a sampled implicit surface
from a scalar field and an iso value.}
@defthing[gen:surface3d any/c]{The generic interface implemented by every
surface value. Custom producers implement its kind, local mesh, diagnostics,
provenance, domain, evaluator, and local-frame methods.}
@defthing[surface3d-kind procedure?]{Returns a surface producer kind symbol.}
@defthing[surface3d-local-mesh procedure?]{Returns a @racket[surface-mesh3d]
with identity transform and opacity one.}
@defthing[surface3d-mesh procedure?]{Lowers a surface to its immutable indexed
local mesh representation; it is retained as the concise established spelling
for @racket[surface3d-local-mesh].}
@defthing[surface3d->mesh3d procedure?]{Returns a standalone @racket[mesh3d]
which preserves the surface's authored transform and opacity.}
@defthing[surface3d-domain procedure?]{Returns the retained
@racket[surface-domain3d], or @racket[#f] for a producer without UV domain.}
@defthing[surface3d-evaluate procedure?]{Evaluates a retained parametric
surface at one valid UV coordinate.}
@defthing[surface3d-frame-at procedure?]{Returns a @racket[surface-frame3d]
containing the point, two tangents, and normal at one valid UV coordinate.}
@defthing[surface3d-diagnostics procedure?]{Returns a serializable
@racket[surface-diagnostics3d] snapshot.}
@defthing[surface3d-provenance procedure?]{Returns immutable producer
provenance aligned with the local surface mesh.}
@defstruct*[surface-domain3d ([u-range list?]
                              [v-range list?]
                              [contains? (or/c #f procedure?)]
                              [cache-key any/c])
  #:transparent]{Stores a parametric bounding box, optional retained-domain
predicate, and stable domain identity. The predicate is deliberately not part
of diagnostics.}
@defstruct*[surface-diagnostics3d ([kind symbol?] [fields any/c])
  #:transparent]{Stores serializable producer diagnostics.}
@defstruct*[surface-frame3d ([point vec3?]
                             [tangent-u vec3?]
                             [tangent-v vec3?]
                             [normal vec3?])
  #:transparent]{A local parametric differential frame.}
@defstruct*[surface-mesh3d ([mesh mesh3d?]
                            [vertex-provenance vector?]
                            [triangle-provenance vector?]
                            [topology-key any/c]
                            [diagnostics any/c])
  #:transparent]{The immutable indexed lowering returned by
@racket[surface3d-local-mesh]. Its provenance vectors are aligned with the
mesh's vertices and render triangles; the topology key and diagnostics retain
producer-specific inspection information.}
@defthing[surface3d-domain-contains? procedure?]{Reports whether a parameter
point is inside a surface's retained domain.}
@defthing[surface3d-position-at? procedure?]{Returns a retained surface point
when the parameter lies inside that domain.}

