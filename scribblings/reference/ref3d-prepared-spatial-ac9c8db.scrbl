#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-ac9c8db"]{3D: Flow maps and volume change}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(prepare-flow-map3d [field any/c] [seeds seed-set3d?]
                             [#:start-time start-time finite-real? 0]
                             [#:end-time end-time finite-real? 1]
                             [#:solver solver any/c #f]
                             [#:termination termination any/c #f]
                             [#:on-termination policy (or/c 'absent 'use-termination-point) 'absent]
                             [#:parallel? parallel? boolean? #t]
                             [#:cancellation-token cancellation-token any/c #f]) prepared-flow-map3d?]{Prepares
one retained trajectory in every declared seed slot. A normally completed slot
has its endpoint; an early-terminated slot is @racket[#f] by default, or its
actual stopping point under @racket['use-termination-point]. Thus source,
endpoint, and termination provenance stay aligned in seed order. Its diagnostics
contain a versioned preparation identity when @racket[field]
is an @racket[ode-field3d] with an explicit cache key and every termination
event has an explicit cache key. The identity records solver, seed-set,
termination, time-parameterization, dense-resampling, and endpoint policy.
An opaque field or event is reported as @racket['memory-only], so it is never
mistaken for persistently serializable numerical input. Independent seed slots
use bounded worker threads when @racket[#:parallel?] is true; trajectories,
endpoints, diagnostics, and any raised failure retain seed order rather than
worker completion order.}
@defproc[(prepared-flow-map3d? [value any/c]) boolean?]{Recognizes an immutable
prepared flow map. Its accessors begin with @tt{prepared-flow-map3d-}.}
@defproc[(flow-map3d-ref [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         (or/c false/c vec3?)]{Returns the endpoint in seed order, or @racket[#f]
for an absent endpoint.}
@defproc[(flow-map3d-pairs [map prepared-flow-map3d?]) vector?]{Returns immutable
@racket[(cons seed endpoint)] entries for slots with endpoints.}
@defproc[(flow-map3d-displacement [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         (or/c false/c vec3?)]{Returns endpoint minus source for one slot.}
@defproc[(flow-map-grid3d [map prepared-flow-map3d?]
                           [#:id id symbol? 'flow-map-grid]
                           [#:connectivity connectivity 'axis-neighbours]) group3d?]{Lowers
a flow map from an explicit @racket['grid] seed set to retained endpoint edges.
An absent endpoint breaks its incident edges. Arbitrary unstructured seed sets
are rejected because no neighbourhood relation is implied by their order.}
@defproc[(flow-volume-cell3d [map prepared-flow-map3d?]
                              [cell-index exact-nonnegative-integer?]
                              [#:id id (or/c false/c symbol?) #f]
                              [#:material material material3d? default-material3d]) mesh3d?]{Lowers
one retained hexahedral seed cell to its eight endpoint corners and twelve
outward-wound triangular faces. @racket[cell-index] enumerates lower corners in
the source grid's retained declaration order; it is not a loose seed index. The
operation requires an explicit complete grid and eight retained endpoints. It
does not interpolate, repair an absent endpoint, or infer volume from an
unstructured cloud.}
@defproc[(flow-map3d-local-jacobian [map prepared-flow-map3d?]
                                    [index exact-nonnegative-integer?]) linear3?]{Estimates
the local endpoint derivative from a retained explicit grid neighbourhood.
Interior slots use central differences and grid boundaries use a retained
one-sided difference. An absent endpoint, incomplete axis neighbourhood, or
unstructured seed set is an error rather than a guessed result.}
@defproc[(flow-map3d-volume-factor [map prepared-flow-map3d?]
                                   [index exact-nonnegative-integer?]) finite-real?]{Returns
the determinant of @racket[flow-map3d-local-jacobian] at one grid slot.}
