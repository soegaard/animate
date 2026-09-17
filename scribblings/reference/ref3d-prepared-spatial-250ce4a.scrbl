#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-250ce4a"]{3D: Drawing vector fields and particles}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(vector-field3d
          [field (or/c (procedure-arity-includes/c 3)
                       (procedure-arity-includes/c 4))]
          [#:id id symbol?]
          [#:x-range x-range list? (list -2 2)]
          [#:y-range y-range list? (list -2 2)]
          [#:z-range z-range list? (list -2 2)]
          [#:x-count x-count exact-positive-integer? 5]
          [#:y-count y-count exact-positive-integer? 5]
          [#:z-count z-count exact-positive-integer? 5]
          [#:normalize? normalize? boolean? #f]
          [#:length-range length-range (or/c false/c list? pair?) #f]
          [#:color-by-magnitude? color-by-magnitude? boolean? #f]
          [#:seed-order seed-order symbol? 'xyz]) group3d?]{Samples an
explicit finite rectangular grid once. Zero derivatives are omitted.
@racket[#:seed-order] is one of @racket['xyz], @racket['xzy], @racket['yxz],
@racket['yzx], @racket['zxy], or @racket['zyx], giving stable child order.
When requested, magnitude controls the displayed arrow length and colour.}
@defproc[(streamline3d [field procedure?] [seed vec3?] [#:id id symbol?])
         curve3d?]{Creates one finite static RK4 streamline.}
@defproc[(streamlines3d [field procedure?] [seeds (listof vec3?)]
                         [#:id id symbol?]) group3d?]{Creates deterministic
static streamline children.}
@defproc[(flow-particle3d [trajectory ode-trajectory3d?]
                           [phase scene-parameter?]
                           [#:id id symbol?]
                           [#:tangent-length tangent-length
                            (or/c false/c positive?) #f]) spatial-relation?]{
Creates a prepared position marker, optionally with a visible nonzero tangent.
At an equilibrium, the tangent child remains structurally present but invisible
rather than claiming an arbitrary direction.}
@defproc[(flow-cloud3d [trajectories (listof ode-trajectory3d?)]
                        [phase scene-parameter?] [#:id id symbol?]) group3d?]{
Creates one prepared particle per trajectory using the shared time parameter.}

The canonical acceptance scenes are
@filepath{examples/3d/prepared-lorenz-flow.rkt} and
@filepath{examples/3d/lorenz-events.rkt}; the latter distinguishes retained
nonterminal rise/fall roots through the same Lorenz surface. Explicit policies are shown
in @filepath{examples/3d/event-aware-trajectory.rkt} and
@filepath{examples/3d/trajectory-termination.rkt}, while
@filepath{examples/3d/adaptive-streamlines.rkt} shows T3's world-space
resampling and @filepath{examples/3d/deterministic-seed-sets.rkt} shows T4
Poisson seed provenance. @filepath{examples/3d/poincare-section.rkt} shows T5
dense plane crossings.

