#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-curves-an-44fde38"]{3D: Spatial curves and vector diagrams}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Spatial diagram geometry is finite. A sampled curve's centreline is separate
from its rendering style. A mathematical
@racket[stroke3d] is resolved after projection and can retain a constant pixel
width. A @racket[tube-style3d] creates explicit physical tube geometry whose
apparent width changes with the camera. Partial curves, reveals, and
curve-following are sampled directly from the complete immutable centreline at
the requested scene time; they never use a mutable updater or the preceding
frame.

@defproc[(stroke3d [#:color color color-spec? "steelblue"]
                   [#:width width positive? 2]
                   [#:width-mode width-mode (or/c 'screen 'world) 'screen]
                   [#:cap cap (or/c 'butt 'square 'round) 'round]
                   [#:join join (or/c 'miter 'bevel 'round) 'round]
                   [#:miter-limit miter-limit positive? 4]
                   [#:dash dash (or/c #f list? vector?) #f]
                   [#:dash-offset dash-offset finite-real? 0]
                   [#:dash-space dash-space (or/c 'screen 'world) width-mode]
                   [#:opacity opacity (real-in 0 1) 1]
                   [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                   [#:depth-bias depth-bias nonnegative-real? 1e-5])
         stroke3d?]{Creates an immutable mathematical-stroke style. In
@racket['screen] mode, width and default dashes are pixels after projection;
in @racket['world] mode width is a full physical diameter. A dash pattern is
an even-length list or vector of positive finite lengths. @racket['test]
draws visible portions, @racket['hidden] draws occluded portions, and
@racket['always] ignores depth.}
@defproc[(stroke3d? [value any/c]) boolean?]{Recognizes a stroke style.}
@defproc[(stroke3d-color [style stroke3d?]) color-spec?]{Returns stroke colour.}
@defproc[(stroke3d-width [style stroke3d?]) positive?]{Returns width.}
@defproc[(stroke3d-width-mode [style stroke3d?]) (or/c 'screen 'world)]{Returns width units.}
@defproc[(stroke3d-cap [style stroke3d?]) (or/c 'butt 'square 'round)]{Returns endpoint-cap style.}
@defproc[(stroke3d-join [style stroke3d?]) (or/c 'miter 'bevel 'round)]{Returns polyline-join style.}
@defproc[(stroke3d-miter-limit [style stroke3d?]) positive?]{Returns miter limit.}
@defproc[(stroke3d-dash [style stroke3d?]) (or/c #f vector?)]{Returns the validated dash pattern.}
@defproc[(stroke3d-dash-offset [style stroke3d?]) finite-real?]{Returns dash phase.}
@defproc[(stroke3d-dash-space [style stroke3d?]) (or/c 'screen 'world)]{Returns dash units.}
@defproc[(stroke3d-opacity [style stroke3d?]) (real-in 0 1)]{Returns local opacity.}
@defproc[(stroke3d-depth-mode [style stroke3d?]) (or/c 'test 'always 'hidden)]{Returns depth policy.}
@defproc[(stroke3d-depth-bias [style stroke3d?]) nonnegative-real?]{Returns normalized depth bias.}
@defproc[(stroke3d-with-color [style stroke3d?] [color color-spec?]) stroke3d?]{Recolours a stroke.}
@defproc[(stroke3d-with-opacity [style stroke3d?] [opacity (real-in 0 1)]) stroke3d?]{Changes local opacity.}

@defproc[(tube-style3d [#:radius radius positive? 1/20]
                        [#:sides sides exact-positive-integer? 8]
                        [#:color color color-spec? "steelblue"])
         tube-style3d?]{Creates the explicit physical style used when a curve
should lower to a tube mesh.}
@defproc[(tube-style3d? [value any/c]) boolean?]{Recognizes a tube style.}
@defproc[(tube-style3d-radius [style tube-style3d?]) positive?]{Returns physical radius.}
@defproc[(tube-style3d-sides [style tube-style3d?]) exact-positive-integer?]{Returns radial tessellation count.}
@defproc[(tube-style3d-color [style tube-style3d?]) color-spec?]{Returns tube colour.}

@defproc[(point-style3d [#:size size positive? 8]
                         [#:size-mode size-mode (or/c 'screen 'world) 'screen]
                         [#:color color color-spec? "cornflowerblue"]
                         [#:opacity opacity (real-in 0 1) 1]
                         [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                         [#:depth-bias depth-bias nonnegative-real? 1e-5])
         point-style3d?]{Creates a circular point-marker style. Screen size is
its diameter in pixels; world size is a physical diameter projected at the
point anchor.}
@defproc[(point-style3d? [value any/c]) boolean?]{Recognizes a point-marker style.}
@defproc[(arrow-style3d [#:length length positive? 12]
                         [#:length-mode length-mode (or/c 'screen 'world) 'screen]
                         [#:width width (or/c #f positive?) #f]
                         [#:color color color-spec? "tomato"]
                         [#:opacity opacity (real-in 0 1) 1]
                         [#:depth-mode depth-mode (or/c 'test 'always 'hidden) 'test]
                         [#:depth-bias depth-bias nonnegative-real? 1e-5])
         arrow-style3d?]{Creates a screen or world arrowhead style. Its
direction is taken from the final projected nondegenerate shaft segment.}
@defproc[(arrow-style3d? [value any/c]) boolean?]{Recognizes an arrowhead style.}

@defproc[(point3d [position vec3?] [#:id id symbol?]
                  [#:style style point-style3d? (point-style3d)])
         spatial-visual?]{Creates one finite screen/world point marker.}
@defproc[(curve3d? [value any/c]) boolean?]{Recognizes a sampled spatial curve.}
@defproc[(line3d [from vec3?] [to vec3?] [#:id id symbol?]
                 [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)])
         curve3d?]{Creates a finite straight spatial line. The alias
@racket[segment3d] has the same arguments.}
@defproc[(segment3d [from vec3?] [to vec3?] [#:id id symbol?]
                    [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)])
         curve3d?]{Creates the same finite geometry as @racket[line3d].}
@defproc[(polyline3d [points (or/c list? vector?)] [#:id id symbol?]
                     [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)]
                     [#:closed? closed? boolean? #f]
                     [#:transform transform transform3? identity-transform3]
                     [#:opacity opacity (real-in 0 1) 1])
         curve3d?]{Creates a sampled polyline. Adjacent repeated points are
removed before stroke preparation or tube frames are formed.}
@defproc[(parametric-curve3d [procedure procedure?]
                             [#:range range (list/c finite-real? finite-real?) (list 0 1)]
                             [#:samples samples exact-positive-integer? 64]
                             [#:id id symbol?]
                             [#:style style (or/c stroke3d? tube-style3d?) (stroke3d)]
                             [#:closed? closed? boolean? #f])
         curve3d?]{Samples @racket[procedure] at equally spaced, inclusive
range endpoints. The declared @racket[samples] locations are deterministic.}
@defproc[(tube3d [points (or/c list? vector?)] [#:id id symbol?]
                [#:radius radius positive? 1/20]
                [#:sides sides exact-positive-integer? 8]
                [#:closed? closed? boolean? #f]
                [#:width-mode width-mode 'world])
         mesh3d?]{Creates a tube mesh using transported local frames.}
@defproc[(arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                  [#:shaft-style shaft-style stroke3d? (stroke3d #:color "tomato")]
                  [#:tip-style tip-style arrow-style3d? (arrow-style3d #:color "tomato")])
         group3d?]{Creates a shaft and screen/world marker tip at stable
descendants @racket['shaft] and @racket['tip].}
@defproc[(double-arrow3d [from vec3?] [to vec3?] [#:id id symbol?]
                         [#:shaft-style shaft-style stroke3d? (stroke3d #:color "tomato")]
                         [#:tip-style tip-style arrow-style3d? (arrow-style3d #:color "tomato")])
         group3d?]{Creates a shaft with one marker tip at each endpoint.}

@defproc[(with-edges3d [mesh mesh3d?]
                        [#:edges edges (or/c 'explicit 'all 'boundary 'crease 'silhouette 'feature) 'feature]
                        [#:visible visible (or/c #f stroke3d?) (stroke3d #:color "black" #:width 2)]
                        [#:hidden hidden (or/c #f stroke3d?) #f]
                        [#:crease-angle crease-angle finite-real? (/ pi 6)]
                        [#:surface surface (or/c 'visible 'depth-only 'none) 'visible])
         edge-overlay3d?]{Wraps a mesh with camera-prepared outlines without
adding a path component. @racket['feature] means boundary, crease, and
silhouette edges. A @racket['depth-only] surface occludes lines without
painting a surface colour.}
@defproc[(edge-style3d? [value any/c]) boolean?]{Recognizes a mesh-outline style.}
@defproc[(edge-overlay3d? [value any/c]) boolean?]{Recognizes an outlined mesh wrapper.}

@defproc[(axes3d [#:id id symbol?]
                  [#:x-range x-range list? (list -3 3)]
                  [#:y-range y-range list? (list -3 3)]
                  [#:z-range z-range list? (list -3 3)])
         group3d?]{Creates finite axes. Paths such as
@racket['(world axes x-axis)], @racket['(world axes x-ticks)], and
@racket['(world axes labels x)] remain stable. The final path is an invisible
3D anchor intended for @racket[follow-projected-spatial].}
@defproc[(coordinate-plane3d [plane (or/c 'xy 'xz 'yz)] [#:id id symbol?])
         mesh3d?]{Creates one finite double-sided coordinate plane.}
@defproc[(grid-plane3d [plane (or/c 'xy 'xz 'yz)] [#:id id symbol?])
         group3d?]{Creates a finite grid of physical-width spatial lines.}
@defproc[(basis-vectors3d [#:id id symbol?]) group3d?]{Creates coloured i, j,
and k arrows.}
@defproc[(vector-arrow3d [vector vec3?] [#:id id symbol?]) group3d?]{Creates
one arrow from the origin to @racket[vector].}
@defproc[(vector-components3d [vector vec3?] [#:id id symbol?]) group3d?]{Creates
orthogonal component arrows plus a resultant at stable descendants.}

@defproc[(move-along-curve3d [target spatial-path?] [curve spatial-path?]
                              [#:start start finite-real? 0]
                              [#:end end finite-real? 1]) any/c]{Moves a
spatial target by arc-length fraction along a curve path in the same
@racket[view3d].}
@defproc[(orient-along-curve3d [target spatial-path?] [curve spatial-path?]
                                [#:start start finite-real? 0]
                                [#:end end finite-real? 1]) any/c]{Rotates the
target's local positive x direction to the sampled tangent.}

For an already-present curve path, @racket[(create '(world curve))],
@racket[(uncreate '(world curve))], and @racket[(show-passing-flash
'(world curve))] use the same direct curve sampling. A passing flash adds a
temporary coloured tube sliver over its unchanged source curve; it disappears
at each clip endpoint. The canonical vector-camera-orbit example is
@filepath{examples/3d/vector-components.rkt}.

