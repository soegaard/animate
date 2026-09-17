#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-semantic-spatial-d97c90c"]{3D: Projected labels}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(projected-label [template visual?] [#:view view-id symbol?]
                          [#:target target (or/c vec3? spatial-path?)]
                          [#:offset offset vec2? origin]
                          [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                           'always-visible]
                          [#:placement placement label-placement3d?
                           default-label-placement3d]
                          [#:leader leader (or/c #f leader-style3d?) #f]
                          [#:visibility visibility (or/c 'always 'inside-frustum
                                                        'anchor-visible)
                           'always])
         projected-label?]{
Creates an ordinary 2D text, formula, or other concrete Visual whose centre
follows a point projected through a sampled @racket[view3d]. @racket[offset]
is in screen pixels (with Animate's y-up convention), so it is not enlarged
or rotated by the spatial camera. The final compositor jointly measures and
places sibling labels. @racket['inside-frustum] suppresses an anchor outside
the camera rectangle; @racket['anchor-visible] additionally suppresses an
anchor behind opaque geometry. A @racket[leader-style3d] requests a crisp
two-dimensional grey connector from the selected label-box attachment to its
projected anchor; @racket['nearest] and @racket['center] are the supported
attachments, and @racket[elbow?] selects a horizontal-first elbow.}
@defproc[(projected-label? [value any/c]) boolean?]{Recognizes a projected
label definition.}
@defstruct*[label-placement3d ([preferred list?]
                               [distance nonnegative-real?]
                               [candidates exact-positive-integer?]
                               [keep-inside? boolean?]
                               [avoid-overlap? boolean?]
                               [avoid list?]
                               [stability-weight nonnegative-real?]
                               [leader-threshold nonnegative-real?])
  #:transparent]{The immutable direct-mode placement policy. Directions are
chosen in declared @racket[preferred] order when candidate costs tie.}
@defthing[default-label-placement3d label-placement3d?]{The standard
north-east-first direct placement policy.}
@defstruct*[leader-style3d ([attachment (or/c 'nearest 'center)]
                            [elbow? boolean?]
                            [minimum-length nonnegative-real?])
  #:transparent]{Requests a compositor leader. Its length is measured in
output pixels after label placement.}
@defproc[(follow-projected-point [template visual?] [#:view view-id symbol?]
                                 [#:point point vec3?]
                                 [#:offset offset vec2? origin]
                                 [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                  'always-visible]
                                 [#:placement placement label-placement3d?
                                  default-label-placement3d]
                                 [#:leader leader (or/c #f leader-style3d?) #f]
                                 [#:visibility visibility (or/c 'always 'inside-frustum
                                                               'anchor-visible)
                                  'always])
         projected-label?]{The literal-point spelling of @racket[projected-label].}
@defproc[(follow-projected-spatial [template visual?] [#:view view-id symbol?]
                                   [#:target target spatial-path?]
                                   [#:offset offset vec2? origin]
                                   [#:occlusion occlusion (or/c 'always-visible 'hide 'fade)
                                    'always-visible]
                                   [#:placement placement label-placement3d?
                                    default-label-placement3d]
                                   [#:leader leader (or/c #f leader-style3d?) #f]
                                   [#:visibility visibility (or/c 'always 'inside-frustum
                                                                 'anchor-visible)
                                    'always])
         projected-label?]{The spatial-path spelling of @racket[projected-label].}

The canonical example uses all of this without a second timeline:

@racketblock[
(define label-a
  (follow-projected-spatial
   (math-tex #:id 'label-a "A")
   #:view 'world
   #:target '(tetrahedron A)
   #:offset (vec2 -20 -18)))

(scene-play
 (scene-add (make-scene) world label-a)
 (rotate3d-by '(world tetrahedron) (axis-angle y-axis3 pi))
 (camera3d-orbit-by 'world #:azimuth pi)
 #:duration 2)
]

For the complete moving tetrahedron with labels A–D, see
@filepath{examples/3d/projected-labels.rkt}.

