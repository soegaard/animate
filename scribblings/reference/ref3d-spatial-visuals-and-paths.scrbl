#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-spatial-visuals-and-paths"]{3D: Objects, groups, and paths}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


Spatial content uses a protocol distinct from ordinary
two-dimensional @racket[visual?] values. This prevents an ordinary scene path
or two-dimensional animation request from silently treating a mesh as a Pict.
Only its enclosing @racket[view3d] is an ordinary two-dimensional Visual.

@defproc[(spatial-visual? [value any/c]) boolean?]{Recognizes an immutable
spatial Visual.}
@defproc[(spatial-container? [value any/c]) boolean?]{Recognizes an immutable
spatial container. It is deliberately separate from the ordinary 2D container
protocol.}
@defproc[(spatial-id [object spatial-visual?]) symbol?]{Returns its stable
identity within one spatial container.}
@defproc[(spatial-transform [object spatial-visual?]) transform3?]{Returns its
local transform.}
@defproc[(spatial-with-transform [object spatial-visual?] [transform transform3?])
         spatial-visual?]{Returns a transformed immutable copy.}
@defproc[(spatial-opacity [object spatial-visual?]) (and/c real? (between/c 0 1))]{
Returns the opacity inherited by descendants.}
@defproc[(spatial-with-opacity [object spatial-visual?]
                               [opacity (and/c real? (between/c 0 1))])
         spatial-visual?]{Returns an immutable opacity update.}
@defproc[(spatial-local-bounds [object spatial-visual?]) aabb3?]{Returns local
untransformed spatial bounds.}

@defproc[(spatial-position [object spatial-visual?]) vec3?]{Returns the
translation component of the local transform.}
@defproc[(spatial-with-position [object spatial-visual?] [position vec3?])
         spatial-visual?]{Replaces that local translation.}
@defproc[(spatial-rotation [object spatial-visual?]) rotation3?]{Returns the
local rotation.}
@defproc[(spatial-with-rotation [object spatial-visual?] [rotation rotation3?])
         spatial-visual?]{Replaces that local rotation.}
@defproc[(spatial-scale [object spatial-visual?]) vec3?]{Returns the local
scale.}
@defproc[(spatial-with-scale [object spatial-visual?] [scale vec3?])
         spatial-visual?]{Replaces the nonzero local scale components.}

@defstruct*[spatial-child ([id symbol?] [visual spatial-visual?])
  #:transparent]{
An immutable direct-child entry. Its id must be the child Visual's
@racket[spatial-id]. Direct-child order is significant and stable.
}
@defproc[(group3d [children (listof spatial-visual?)]
                  [#:id id symbol?]
                  [#:transform transform transform3? identity-transform3]
                  [#:opacity opacity (and/c real? (between/c 0 1)) 1])
         group3d?]{
Creates an immutable spatial container. Direct child identities must be unique
and cannot equal the group's identity.
}
@defproc[(group3d? [value any/c]) boolean?]{Recognizes a spatial group.}
@defproc[(group3d-children [group group3d?]) (listof spatial-visual?)]{
Returns direct children in their declared order.}
@defproc[(group3d-with-children [group group3d?]
                                 [children (listof spatial-visual?)])
         group3d?]{Returns an immutable direct-child replacement.}

@defproc[(spatial-path? [value any/c]) boolean?]{Recognizes a nonempty list of
symbols.}
@defproc[(spatial-relative-ref [container spatial-container?]
                               [path spatial-path?]) spatial-visual?]{
Resolves a nonempty path relative to a spatial container.
}
@defproc[(spatial-relative-replace [container spatial-container?]
                                   [path spatial-path?]
                                   [replacement spatial-visual?])
         spatial-container?]{Rebuilds an immutable spatial ancestry, requiring
the replacement to retain the final path identity.}

