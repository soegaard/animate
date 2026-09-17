#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-parametric-surfac-075e668"]{3D: Parametric surfaces and calculus}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-G adds fixed-topology rectangular parametric surfaces. A surface is
sampled once at inclusive parameter-grid sites and therefore has stable vertex
and triangle identities. Its normals use declared analytic derivatives when
both are supplied; otherwise they use deterministic centred/one-sided finite
differences, adjacent-face fallback, and explicit unresolved-index reporting.

@defproc[(parametric-surface3d [procedure procedure?]
                               [#:u-range u-range list? (list -1 1)]
                               [#:v-range v-range list? (list -1 1)]
                               [#:resolution resolution list? (list 33 33)]
                               [#:id id symbol?]) surface3d?]{Creates a fixed
rectangular sampled parameterization.}
@defproc[(function-surface3d [function procedure?]
                             [#:x-range x-range list? (list -1 1)]
                             [#:y-range y-range list? (list -1 1)]
                             [#:resolution resolution list? (list 33 33)]
                             [#:id id symbol?]) surface3d?]{Creates the graph
@racket[(vec3 x y (function x y))] and retains scalar-field data for calculus
helpers.}
@defproc[(surface3d? [value any/c]) boolean?]{Recognizes an immutable sampled
surface.}
@defproc[(surface3d-resolution [surface surface3d?]) list?]{Returns its fixed
@racket[(list u-count v-count)] topology.}
@defproc[(surface3d-position-at [surface surface3d?] [u finite-real?]
                                 [v finite-real?]) vec3?]{Evaluates a point in
the authored parameter domain.}
@defproc[(surface3d-normal-at [surface surface3d?] [u finite-real?]
                               [v finite-real?]) vec3?]{Returns a safe unit
normal, using the recorded deterministic fallback when necessary.}
@defproc[(surface-color [surface surface3d?] [color color-spec?]) surface3d?]{
Changes the uniform material colour without changing samples or topology.}
@defproc[(surface-color-by-height [surface surface3d?]) surface3d?]{Adds an
opaque per-vertex z-height colour field.}
@defproc[(surface-color-by-scalar [surface surface3d?] [scalar procedure?])
         surface3d?]{Adds a deterministic opaque per-vertex colour ramp from
the scalar evaluated at each existing sample.}
@defproc[(surface-checkerboard [surface surface3d?]) surface3d?]{Adds a
deterministic parameter-space checkerboard colour field.}
@defproc[(surface-point [surface surface3d?] [u finite-real?] [v finite-real?]
                        [#:id id symbol?]) mesh3d?]{Creates a point at a
surface parameter.}
@defproc[(surface-tangent-u [surface surface3d?] [u finite-real?]
                            [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the @racket[u] tangent direction.}
@defproc[(surface-tangent-v [surface surface3d?] [u finite-real?]
                            [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the @racket[v] tangent direction.}
@defproc[(surface-normal [surface surface3d?] [u finite-real?]
                          [v finite-real?] [#:id id symbol?]) group3d?]{
Draws an arrow in the direct tangent-plane normal direction.}
@defproc[(surface-tangent-plane [surface surface3d?] [u finite-real?]
                                 [v finite-real?] [#:id id symbol?]) mesh3d?]{
Creates a finite tangent parallelogram at the parameter point.}
@defproc[(surface-coordinate-curve [surface surface3d?] [#:id id symbol?])
         curve3d?]{Samples one fixed-@racket[u] or fixed-@racket[v] coordinate
curve.}
@defproc[(surface-gradient-arrow [surface surface3d?] [x finite-real?]
                                  [y finite-real?] [#:id id symbol?]) group3d?]{
Creates the xy gradient arrow for a declared @racket[function-surface3d].}

