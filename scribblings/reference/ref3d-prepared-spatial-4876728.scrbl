#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-4876728"]{3D: Drawing and inspecting trajectories}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(trajectory-samples3d [trajectory prepared-trajectory3d?]
                                [#:count count exact-integer? 64]) vector?]{Returns
an immutable uniform-time sequence of positions from retained dense trajectory
data. It never invokes the author ODE field.}
@defproc[(trajectory-tube3d [trajectory prepared-trajectory3d?]
                             [#:id id symbol? 'trajectory-tube]
                             [#:radius radius positive? 1/20]
                             [#:sides sides exact-integer? 12]
                             [#:samples samples exact-integer? 64]
                             [#:caps? caps? boolean? #t]) mesh3d?]{Lowers retained
trajectory samples into a deterministic finite tube mesh. It is a display
choice, not a re-integration, and its world radius and sample count are
explicit.}
@defproc[(trajectory-ribbon3d [trajectory prepared-trajectory3d?]
                               [#:id id symbol? 'trajectory-ribbon]
                               [#:width width positive? 1/10]
                               [#:samples samples exact-integer? 64]
                               [#:initial-normal initial-normal (or/c false/c vec3?) #f]) mesh3d?]{Lowers
prepared samples to a two-sided ribbon mesh. Its normal frame uses discrete
parallel transport, projected at every retained tangent. A closed-loop twist
correction is intentionally not automatic: a finite display ribbon must not
silently choose a loop-closing convention for its author.}
@defproc[(trajectory-bundle3d [map prepared-flow-map3d?]
                               [#:id id symbol? 'trajectory-bundle]
                               [#:style style (or/c 'tube 'ribbon) 'tube]
                               [#:radius radius positive? 1/20]
                               [#:width width positive? 1/10]
                               [#:sides sides exact-integer? 12]
                               [#:samples samples exact-integer? 64]
                               [#:initial-normal initial-normal (or/c false/c vec3?) #f]) group3d?]{Lowers
every retained trajectory of a prepared flow map in stable seed order. The
selected tube or parallel-transport ribbon style is display-only: it never
calls the author field or reintegrates a seed. A trajectory that terminated
early remains a shorter retained bundle child.}
@defproc[(trajectory-inspection3d [trajectory prepared-trajectory3d?]) immutable-hash?]{Returns
a read-only report of retained solver diagnostics, termination, event hits, and
arc length.}
@defproc[(view3d-dynamical-inspections3d [view view3d?]) list?]{Returns ordered
immutable report hashes for every @racket[flow-particle3d] relation in
@racket[view]. Each hash contains its rooted spatial @racket['path] and a
@racket[trajectory-inspection3d] @racket['report]. The query walks retained
relation metadata only: it never evaluates an ODE field, resolves a relation,
or changes the authored view. The preview's @italic{3D dynamics} inspector
section presents the same reports.}
@defproc[(trajectory-pick-inspection3d [trajectory prepared-trajectory3d?]
                                        [point vec3?]
                                        [#:samples samples exact-integer? 128]
                                        [#:near-event-time near-event-time (or/c false/c nonnegative-real?) #f])
         immutable-hash?]{Returns a read-only nearest-trajectory report for a
world-space pick. It records the nearest declared uniform curve sample, its
nearest sampled-polyline interpolation time and position, retained arc-length
position and derivative, and a nearby retained event hit when one lies within
the declared or sample-interval time radius. It does not reintegrate or invoke
the author field.}
@defproc[(equilibrium-inspection3d [search equilibrium-search3d?]) immutable-hash?]{Returns
the complete retained convergence report without hiding failed seed slots.}
@defproc[(linearization-inspection3d [value linearization3d?]) immutable-hash?]{Returns
the local Jacobian, eigendata, classification, and tolerance diagnostics.}
@defproc[(flow-map-inspection3d [map prepared-flow-map3d?] [index exact-nonnegative-integer?])
         immutable-hash?]{Returns one flow-map source/endpoint trajectory slot,
including its absent-endpoint status when applicable. These inspection values
do not mutate a Scene, selection, camera, or preview overlay.}
