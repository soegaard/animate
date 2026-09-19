#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-maps-and-891ec29"]{3D: Spatial maps and homotopies}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Spatial map requests use the ordinary immutable @racket[scene] timeline. Every target is a rooted spatial path, and every map procedure is
authored in world coordinates. This makes a map applied to a nested child mean
the same thing as applying it to an equivalent top-level child. A surrounding
parent map must therefore be invertible when the result is rebased into that
parent's local coordinate system.

@racket[apply-linear3] and @racket[apply-affine3] retain the original spatial
subtree and attach a full affine map to it. They consequently preserve the
indexed topology exactly, even for a shear, reflection, or singular map. A
named child of a transformed @racket[group3d] remains addressable. The
canonical @racket[linear-transformation-diagram3d] groups coordinate planes,
a unit cube, basis arrows, and an arbitrary vector so one map applies to all
of them coherently.

@racketblock[
(scene-play
 (scene-add (make-scene) world)
 (apply-linear3 '(world diagram)
                (linear3 1 0 1
                         0 1 0
                         0 0 1))
 (apply-homotopy3
  '(world sheet)
  (lambda (point phase)
    (vec3 (vec3-x point)
          (* (cos phase) (vec3-y point))
          (* (sin phase) (vec3-y point)))))
 #:duration 2)
]

@defproc[(linear-transformation-diagram3d
          [#:id id symbol?]
          [#:vector vector vec3? (vec3 3/2 1 1/2)]
          [#:cube-side cube-side positive-real? 1]
          [#:plane-size plane-size positive-real? 3])
         group3d?]{Creates the named coordinate-plane, unit-cube, basis-arrow,
and vector diagram intended for a coherent linear transformation.}
@defproc[(apply-linear3 [path spatial-path?] [map linear3?]) any/c]{Animates a
world-coordinate linear map from identity to @racket[map].}
@defproc[(apply-affine3 [path spatial-path?] [map affine3?]) any/c]{Animates a
world-coordinate affine map from identity to @racket[map].}
@defproc[(apply-pointwise3 [path spatial-path?] [map-point procedure?]
                            [#:on-failure on-failure
                             (or/c 'error 'drop-triangle) 'error]
                            [#:recompute-normals? recompute-normals? boolean? #t])
         any/c]{Maps the source mesh's authored world-space vertices. During
the clip, each vertex moves linearly from its source position to
@racket[(map-point source-point)]. The default reports a bad map result; the
explicit @racket['drop-triangle] policy removes every incident triangle.}
@defproc[(apply-homotopy3 [path spatial-path?] [homotopy procedure?]
                           [#:on-failure on-failure
                            (or/c 'error 'drop-triangle) 'error]
                           [#:recompute-normals? recompute-normals? boolean? #t])
         any/c]{Evaluates @racket[(homotopy source-point phase)] directly at
each nonzero requested phase. Unlike endpoint interpolation, the supplied
homotopy controls the complete intermediate geometry.}

An example is
@filepath{examples/3d/spatial-maps-and-homotopies.rkt}.

