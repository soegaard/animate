#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-anchors-a-adb8ffb"]{3D: Spatial anchors and label layout}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-S begins the annotation layer with immutable @racket[anchor3d?]
descriptors. @racket[vertex-anchor3d], @racket[edge-anchor3d],
@racket[face-anchor3d], @racket[curve-anchor3d], @racket[surface-anchor3d],
and bounds/origin anchors resolve after every spatial transformation into a
@racket[resolved-anchor3d] world point, normal/tangent when available, source
path, and stable provenance identity. Parametric surface anchors—including
generated adaptive and trimmed surfaces—expose evaluated normals and
@racket[u]-tangents after their complete world transform. A
@racket[surface-pick-anchor3d] carries an immutable exact pick provenance;
this makes an implicit surface's interpolated normal available without
pretending it owns a UV tangent frame.

@defproc[(surface-pick-anchor3d [pick surface-pick3d?]) anchor3d?]{Creates an
immutable anchor from one exact surface-picking result. Parametric picks retain
their UV coordinate. Implicit picks retain the lowered triangle index and
barycentric point, so later spatial transforms affect the resolved world point
and normal without mutating the original pick.}

@racket[label3d] uses such an anchor while retaining its content as a crisp
ordinary 2D Visual. @racket[label-placement3d] and
@racket[layout-labels3d] provide a deterministic, pure direct-mode candidate
layout in output pixels. The outer scene compositor resolves and measures all
projected labels for a sampled frame before it positions any one label, then
consumes that one batched direct layout without re-rendering the viewport.
@racket[prepare-label-layout3d] optionally computes
an immutable dynamic-programming candidate table for a declared finite frame
grid, applying explicit movement and switching penalties without relying on
the previously displayed frame. Equal-priority labels retain declaration order,
and equal-cost candidates retain the declared preferred-direction order.

@defproc[(prepare-scene-label-layout3d
          [scene scene?]
          [#:frames frames (listof exact-nonnegative-integer?)]
          [#:view view-id (or/c #f symbol?) #f]
          [#:fps fps exact-positive-integer? 30]
          [#:camera camera (or/c #f camera?) #f]
          [#:supersample supersample exact-positive-integer? 1]
          [#:switch-penalty switch-penalty nonnegative-real? 0]
          [#:movement-penalty movement-penalty nonnegative-real? 0])
         prepared-label-layout3d?]{Samples the declared source-frame grid,
resolves and measures the same stable projected-label slots used by final
composition, and returns an immutable table.  A @racket[#:view] selection
prepares one @racket[view3d] while labels in other viewports keep their direct
layout.  The function has no previous-frame dependency and does not create a
3D renderer artifact while it measures labels.  Supply its result through the
@racket[#:prepared-label-layout] option of @racket[scene-frame->bitmap],
@racket[render-frame-indices!], or the project render operations.}

Current limitations: prepared tables are explicit render inputs rather than a
default project-render policy, and a table applies only to the source-frame
grid and viewport raster for which it was measured. Core
world-space dimensions, angle markers, normal markers, and coordinate tripods
are fixed-structure spatial relations, but they do not yet supply automatic
formula labels or camera-facing screen sizing. Leaders are fixed one-pixel grey
2D paths and are attached for top-level projected labels; they intentionally do
not claim 3D occlusion or textured styling. The executable anchor probe is
@filepath{examples/3d/anchor-aware-labels.rkt}.

The canonical acceptance scene is
@filepath{examples/3d/sphere-plane-section.rkt}.

