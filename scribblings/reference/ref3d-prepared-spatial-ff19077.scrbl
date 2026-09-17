#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-ff19077"]{3D: Seeds and streamline sets}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(seed-set3d? [value any/c]) boolean?]{Recognizes an immutable,
canonical ordered collection of streamline seed points. Its accessors begin
with @tt{seed-set3d-}; @tt{points} is an immutable vector and @tt{count} is its
length. @tt{provenance}, @tt{diagnostics}, and @tt{cache-key} contain immutable
numeric/source descriptions rather than random-generator state or procedures.}
@defproc[(explicit-seeds3d [points (or/c list? vector?)]) seed-set3d?]{Retains
the declared finite @racket[vec3] point sequence exactly, including intentional
duplicate seeds.}
@defproc[(grid-seeds3d
          [#:x-range x-range list? (list -1 1)]
          [#:y-range y-range list? (list -1 1)]
          [#:z-range z-range list? (list -1 1)]
          [#:counts counts list? (list 3 3 3)]
          [#:order order symbol? 'xyz]) seed-set3d?]{Makes an endpoint-inclusive
rectangular seed lattice. A singleton axis is centred in its supplied range.
The last axis changes fastest; the six @racket['xyz]-style axis orders select
one visible canonical nesting order.}
@defproc[(plane-seeds3d [plane plane3?]
                        [#:u-range u-range list? (list -1 1)]
                        [#:v-range v-range list? (list -1 1)]
                        [#:counts counts list? (list 3 3)]) seed-set3d?]{Samples
the deterministic local plane coordinates of @racket[plane].}
@defproc[(curve-seeds3d [curve curve3d?]
                        [#:count count exact-positive-integer? 8]
                        [#:spacing spacing (or/c 'parameter 'arc-length) 'arc-length])
         seed-set3d?]{Samples a retained curve. @racket['parameter] means uniform
progress through the curve's stored sample sequence—not an unavailable source
procedure parameter—while @racket['arc-length] uses the retained polyline
arc-length query.}
@defproc[(surface-seeds3d [surface surface3d?]
                          [#:u-count u-count exact-positive-integer? 8]
                          [#:v-count v-count exact-positive-integer? 8]
                          [#:inside-domain? inside-domain? boolean? #t])
         seed-set3d?]{Samples a retained parametric surface in u-major order.
When @racket[inside-domain?] is true, points rejected by a retained domain
predicate are omitted and the diagnostic reports that omission.}
@defproc[(sphere-seeds3d [center vec3?] [radius nonnegative-real?]
                         [#:count count exact-positive-integer? 64]
                         [#:method method 'fibonacci]) seed-set3d?]{Makes
deterministic Fibonacci points on a sphere.}
@defproc[(poisson-seeds3d [bounds aabb3?]
                          [#:minimum-distance minimum-distance positive? 1]
                          [#:count-limit count-limit exact-nonnegative-integer? 128]
                          [#:seed seed exact-integer? 0]) seed-set3d?]{Makes an
acceptance-ordered deterministic Bridson-style Poisson set. It uses a local
SplitMix64 generator, FIFO active points, thirty candidates per active point,
and inclusive box/minimum-distance checks; it neither reads nor mutates the
process-global pseudo-random generator.}
@defproc[(prepared-streamline-set3d? [value any/c]) boolean?]{Recognizes an
immutable collection prepared from one @racket[seed-set3d?]. Its accessors
begin with @tt{prepared-streamline-set3d-}; @tt{streamlines} is an immutable
vector of accepted @racket[prepared-streamline3d?] values in seed declaration
order.}
@defproc[(prepare-streamlines3d
          [field any/c] [seeds seed-set3d?]
          [#:direction direction (or/c 'forward 'backward 'both) 'forward]
          [#:parameterization parameterization (or/c 'time 'arc-length) 'time]
          [#:solver solver any/c (adaptive-rk45-solver3d)]
          [#:termination termination (or/c false/c trajectory-termination3d?) #f]
          [#:sample-policy sample-policy streamline-sample-policy3d?
                           (streamline-sample-policy3d)]
          [#:separation separation (or/c false/c positive?) #f]
          [#:parallel? parallel? (or/c boolean? 'auto) 'auto]
          [#:cancellation-token cancellation-token any/c #f]) prepared-streamline-set3d?]{Prepares
one immutable streamline per accepted seed. When @racket[separation] is false,
the result is independent and canonical in seed order. A positive separation
processes seeds in that order, rejects a seed already too near an accepted
line, and makes a later candidate stop at a terminal separation event. The
set diagnostic reports accepted/rejected seeds, terminal reasons, field work,
curve samples, the policy separation, discarded short lines, and whether the
set was prepared by bounded worker threads, serially, or in ordered separation
mode. @racket['auto] uses workers only when its @racket[ode-field3d] and every
termination event explicitly declare @racket[parallel-safe?]. @racket[#t] is
an explicit author override and @racket[#f] is serial. Worker completion never
changes seed/child order. A cancellation token is checked at every seed
boundary and never leaves a partial set.}
@defproc[(adaptive-streamline-set3d [prepared prepared-streamline-set3d?]
                                    [#:id id symbol?]
                                    [#:style style any/c]
                                    [#:opacity opacity real? 1]) group3d?]{Lowers
all accepted prepared lines to ordinary named curve children.}
