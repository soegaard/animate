#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-e990084"]{3D: Equilibria and local linearization}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(jacobian3d [field any/c] [point vec3?]
                     [#:time time finite-real? 0]
                     [#:derivative derivative (or/c false/c procedure?) #f]
                     [#:step step (or/c false/c positive?) #f]
                     [#:domain domain (or/c false/c procedure?) #f])
         jacobian3d-result?]{Returns an immutable local derivative matrix for
an ODE field at @racket[point]. An analytic @racket[#:derivative] follows the
field's usual @racket[(x y z)] or @racket[(time x y z)] calling convention and
must return a finite @racket[linear3]. Otherwise the result uses deterministic
scale-aware symmetric finite differences. The optional @racket[#:domain]
predicate receives a @racket[vec3]; it is the only reason a one-sided stencil
is used. The result records its method, coordinate steps, total evaluations,
and a local first-versus-second-order error indicator where it is available.}
@defproc[(jacobian3d-result? [value any/c]) boolean?]{Recognizes the transparent
immutable result record returned by @racket[jacobian3d]. Its constructor and
accessors begin with @tt{jacobian3d-result-}.}
@defproc[(equilibrium-points3d [field any/c] [seeds seed-set3d?]
                                [#:solver solver equilibrium-solver3d?
                                           default-equilibrium-solver3d]
                                [#:jacobian derivative (or/c false/c procedure?) #f]
                                [#:merge-distance merge-distance positive? 1e-6]
                                [#:domain domain (or/c false/c procedure?) #f]
                                [#:time time finite-real? 0]
                                [#:cancellation-token cancellation-token any/c #f]) equilibrium-search3d?]{Runs
bounded damped Newton searches from precisely the declared seed order. A
successful root is clustered against earlier successful roots only, so the
earliest seed is its canonical representative. Failed seeds remain as
@racket[equilibrium-seed-result3d?] entries with an explicit status such as
@racket['singular-jacobian], @racket['out-of-domain], @racket['stalled], or
@racket['iteration-limit]. A cancellation token is checked between seed
searches and Newton/backtracking iterations; it raises instead of returning a
partial root collection.}
@defproc[(equilibrium-search3d? [value any/c]) boolean?]{Recognizes the
immutable search result. Its @tt{seeds}, @tt{roots}, @tt{seed-results}, and
@tt{diagnostics} accessors retain all seed outcomes rather than only the
converged representatives.}
@defproc[(equilibrium-seed-result3d? [value any/c]) boolean?]{Recognizes one
immutable seed outcome. Its accessors begin with @tt{equilibrium-seed-result3d-}.}
@defproc[(equilibrium-solver3d [residual-tolerance positive?]
                               [step-tolerance positive?]
                               [maximum-iterations exact-positive-integer?]
                               [damping positive?]
                               [minimum-damping positive?]) equilibrium-solver3d?]{Constructs
the explicit tolerances and deterministic backtracking schedule used by an
equilibrium search.}
@defproc[(equilibrium-solver3d? [value any/c]) boolean?]{Recognizes an
equilibrium solver settings value.}
@defthing[default-equilibrium-solver3d equilibrium-solver3d?]{The default
bounded damped Newton settings.}
@defproc[(eigensystem3d-of [matrix linear3?] [#:tolerance tolerance positive? 1e-10])
         eigensystem3d?]{Computes a bounded deterministic real 3×3 eigensystem.
Eigenvalues are ordered by real component, then imaginary component, with the
positive member of a conjugate pair first. Real eigenvectors use the sign whose
largest-magnitude component is positive. Diagnostics report the characteristic
discriminant and near-defect tolerance rather than concealing numerically
ambiguous cases.}
@defproc[(eigensystem3d? [value any/c]) boolean?]{Recognizes immutable
eigensystem data. Its accessors begin with @tt{eigensystem3d-}.}
@defproc[(linearize3d [field any/c] [point vec3?]
                       [#:time time finite-real? 0]
                       [#:jacobian derivative (or/c false/c procedure?) #f]
                       [#:tolerance tolerance positive? 1e-8]) linearization3d?]{Combines
a Jacobian and deterministic eigensystem at a point. It classifies sink,
source, saddle, spiral sink/source, center-like, nonhyperbolic, or indeterminate
using the declared tolerance; complex pairs expose complementary invariant-plane
data where a stable real normal is available.}
@defproc[(linearization3d? [value any/c]) boolean?]{Recognizes an immutable
local linearization. Its accessors begin with @tt{linearization3d-}.}
@defproc[(linearization-diagram3d [value linearization3d?]
                                  [#:id id symbol? 'linearization]
                                  [#:scale scale positive? 1]) group3d?]{Lowers
the retained real eigendirections to named finite 3D diagram lines. Stable,
unstable, and center directions receive separately configurable stroke styles.
The finite extent is explicitly author-chosen by @racket[scale]; invariant planes
remain data because no universal plane-patch size is mathematically correct.}
