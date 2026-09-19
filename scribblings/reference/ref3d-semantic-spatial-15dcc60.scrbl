#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag '("ref3d-semantic-spatial-15dcc60" "spatial-relations")]{3D: Relations and geometric annotations}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Spatial relations provide derived geometry without a mutable per-frame updater.
A @racket[spatial-relation] is a spatial Visual declaration with a concrete
template, an explicit list of inputs, and a resolver. During a regular
@racket[scene] sample, Animate first samples ordinary spatial and camera
animation, then resolves spatial relations inside each @racket[view3d], then
renders the spatial viewport, and finally resolves projected labels as ordinary
two-dimensional Visuals. This order means a label may use the resolved
position of a relation result, while ordinary 2D layout can still use the
label.

The three dependency declarations make a resolver's inputs inspectable:

@defproc[(spatial-dependency? [value any/c]) boolean?]{Recognizes a declared
spatial relation dependency.}
@defproc[(spatial-visual-dependency [target spatial-path?]) spatial-dependency?]{
Declares a relative or view-rooted path to a spatial Visual.}
@defproc[(spatial-value-dependency [target symbol?]) spatial-dependency?]{
Declares one immutable named Scene value.}
@defproc[(spatial-camera-dependency [view-id symbol?]) spatial-dependency?]{
Declares the camera of one owning @racket[view3d].}

@defproc[(spatial-relation [template spatial-visual?]
                           [#:depends-on dependencies (listof spatial-dependency?) null]
                           [#:structure structure (or/c 'root-only 'fixed) 'root-only]
                           [#:cache-key cache-key any/c #f]
                           [resolver procedure?])
         spatial-relation?]{
Creates a semantic spatial Visual. @racket[resolver] accepts a
@racket[spatial-relation-context?] and the transform-free local template, and
must return concrete spatial geometry with the template's ID. Its outer
transform and opacity remain independently animatable.

A @racket['root-only] relation may change all of its internal structure and can
only be addressed at its own root path. A @racket['fixed] relation must return
the template's exact child-ID tree, so a descendant is addressable. Generic
resolver procedures are intentionally not cross-process-cacheable; supply a
stable @racket[#:cache-key] to declare an explicit cache identity.}

@defproc[(spatial-relation? [value any/c]) boolean?]{Recognizes a semantic
spatial relation.}
@defproc[(spatial-relation-dependencies [relation spatial-relation?])
         (listof spatial-dependency?)]{Returns the declared inputs.}
@defproc[(spatial-relation-structure [relation spatial-relation?])
         (or/c 'root-only 'fixed)]{Returns the declared structural policy.}
@defproc[(spatial-relation-cacheability [relation spatial-relation?])
         (or/c 'explicit-key 'disabled)]{Reports whether the relation has an
explicit stable cache key.}

The resolver context is read-only and accepts only declared inputs.
@defproc[(spatial-relation-context? [value any/c]) boolean?]{Recognizes a
spatial relation resolver context.}
@defproc[(spatial-relation-context-spatial-ref
          [context spatial-relation-context?] [target spatial-path?])
         spatial-visual?]{Resolves a declared relative or rooted target.}
@defproc[(spatial-relation-context-spatial-world-transform
          [context spatial-relation-context?] [target spatial-path?])
         affine3?]{Returns a declared target's sampled world transform.}
@defproc[(spatial-relation-context-spatial-position
          [context spatial-relation-context?] [target spatial-path?])
         vec3?]{Returns a declared target's sampled world origin.}
@defproc[(spatial-relation-context-value-ref
          [context spatial-relation-context?] [target symbol?])
         any/c]{Reads a declared immutable named Scene value.}
@defproc[(spatial-relation-context-camera [context spatial-relation-context?])
         camera3d?]{Reads the declared camera of the owning view.}

An undeclared access is an authoring error. Relations resolve lazily with one
cache for the sampled viewport; a cycle reports complete paths rooted at the
owning view, such as @racket['(world links ab)].

The following constructors describe common spatial relationships:

@defproc[(segment-between3d [from spatial-path?] [to spatial-path?]
                             [#:id id symbol?]
                             [#:color color any/c "slategray"]
                             [#:width width positive-real? 2]
                             [#:opacity opacity real? 1])
         spatial-relation?]{Produces a finite semantic segment between the
current world origins of two declared targets.}
@defproc[(line-between3d [from spatial-path?] [to spatial-path?]
                          [#:id id symbol?]
                          [#:padding padding nonnegative-real? 10]
                          [#:color color any/c "slategray"]
                          [#:width width positive-real? 2]
                          [#:opacity opacity real? 1])
         spatial-relation?]{Produces the displayed portion of the infinite
line through two current origins.}
@defproc[(arrow-between3d [from spatial-path?] [to spatial-path?]
                           [#:id id symbol?]
                           [#:color color any/c "slategray"]
                           [#:width width positive-real? 2]
                           [#:tip-size tip-size positive-real? 1/4]
                           [#:opacity opacity real? 1])
         spatial-relation?]{Produces a segment with a small semantic arrow
head at @racket[to].}
@defproc[(plane-through3d [first spatial-path?] [second spatial-path?]
                           [third spatial-path?] [#:id id symbol?]
                           [#:color color any/c "lightskyblue"]
                           [#:opacity opacity real? 1])
         spatial-relation?]{Produces a double-sided triangular plane through
three current origins.}
@defproc[(normal-at3d [target spatial-path?] [normal vec3?]
                       [#:id id symbol?]
                       [#:length length positive-real? 1]
                       [#:color color any/c "darkmagenta"]
                       [#:width width positive-real? 2]
                       [#:tip-size tip-size positive-real? 1/4]
                       [#:opacity opacity real? 1])
         spatial-relation?]{Produces a directed normal marker from a target's
current origin.}
@defproc[(distance-segment3d [from spatial-path?] [to spatial-path?]
                              [#:id id symbol?]
                              [#:color color any/c "darkgoldenrod"]
                              [#:width width positive-real? 2]
                              [#:opacity opacity real? 1])
         spatial-relation?]{Produces a semantically named finite distance
segment.}

@defproc[(distance-dimension3d [from spatial-path?] [to spatial-path?]
                                [#:id id symbol?]
                                [#:offset offset vec3? (vec3 0 1/3 0)]
                                [#:color color any/c "darkgoldenrod"]
                                [#:width width positive-real? 2]
                                [#:tip-size tip-size positive-real? 1/6]
                                [#:opacity opacity real? 1])
         spatial-relation?]{Produces extension segments and a two-ended
dimension line. The offset is an explicit world-space vector, so the mark
retains mathematical meaning under camera motion.}
@defproc[(angle-marker3d [first spatial-path?] [vertex spatial-path?]
                          [second spatial-path?] [#:id id symbol?]
                          [#:radius radius positive-real? 1/3]
                          [#:samples samples exact-integer? 12]
                          [#:color color any/c "darkorange"]
                          [#:width width positive-real? 2]
                          [#:opacity opacity real? 1])
         spatial-relation?]{Produces the smaller arc from @racket[first]
through @racket[vertex] to @racket[second]. The three current points must
remain non-collinear.}
@defproc[(right-angle-marker3d [first spatial-path?] [vertex spatial-path?]
                                [second spatial-path?] [#:id id symbol?]
                                [#:size size positive-real? 1/3]
                                [#:color color any/c "darkorange"]
                                [#:width width positive-real? 2]
                                [#:opacity opacity real? 1])
         spatial-relation?]{Produces a three-segment corner following the
two current rays. It is square when the rays are perpendicular; it deliberately
does not silently assert that an animated non-right configuration is right.}
@defproc[(dihedral-angle3d [axis-from spatial-path?] [axis-to spatial-path?]
                            [first-face-point spatial-path?]
                            [second-face-point spatial-path?]
                            [#:id id symbol?]
                            [#:radius radius positive-real? 1/3]
                            [#:samples samples exact-integer? 12]
                            [#:color color any/c "darkorange"]
                            [#:width width positive-real? 2]
                            [#:opacity opacity real? 1])
         spatial-relation?]{Produces a signed smaller arc around the ordered
hinge, using one off-axis point from each incident face. Face points on the
hinge and coincident face directions are rejected when the relation resolves.}
@defproc[(normal-marker3d [target spatial-path?] [normal vec3?]
                           [#:id id symbol?]
                           [#:length length positive-real? 1]
                           [#:color color any/c "darkmagenta"]
                           [#:width width positive-real? 2]
                           [#:tip-size tip-size positive-real? 1/4]
                           [#:opacity opacity real? 1])
         spatial-relation?]{The fixed-child-tree annotation spelling of
@racket[normal-at3d]. The supplied normal is a world direction.}
@defproc[(coordinate-tripod3d [target spatial-path?] [#:id id symbol?]
                               [#:length length positive-real? 1]
                               [#:width width positive-real? 2]
                               [#:tip-size tip-size positive-real? 1/4]
                               [#:x-color x-color any/c "firebrick"]
                               [#:y-color y-color any/c "forestgreen"]
                               [#:z-color z-color any/c "royalblue"]
                               [#:opacity opacity real? 1])
         spatial-relation?]{Produces three current-origin arrows for the
fixed world x, y, and z directions.}

