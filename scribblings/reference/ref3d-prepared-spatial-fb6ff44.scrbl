#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-prepared-spatial-fb6ff44"]{3D: Poincare sections and return maps}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(poincare-section3d [trajectory prepared-trajectory3d?] [plane plane3?]
                             [#:trajectory-id trajectory-id symbol? 'trajectory]
                             [#:direction direction (or/c 'any 'positive 'negative) 'any]
                             [#:tolerance tolerance positive? 1e-8]
                             [#:deduplicate-time deduplicate-time positive? tolerance]
                             [#:tangent-policy tangent-policy (or/c 'ignore 'include) 'ignore]
                             [#:initial-hit initial-hit (or/c 'include 'exclude 'require) 'exclude])
         vector?]{Extracts immutable @racket[poincare-hit3d?] crossings by
running the event root finder over retained dense trajectory segments. A
positive/negative direction means increasing/decreasing signed distance along
increasing physical time. Shared endpoint roots are time-deduplicated; a
tangent contact is omitted unless explicitly included. The default
@racket['exclude] omits a qualifying hit at the trajectory's range start so a
return map begins with its first return. @racket['include] retains it, and
@racket['require] retains it but reports an error when the trajectory does not
start on the section.}
@defproc[(poincare-hit3d? [value any/c]) boolean?]{Recognizes an immutable
crossing record. Its accessors begin with @tt{poincare-hit3d-}; @tt{source-event}
is the serializable dense root record, not an event procedure.}
@defproc[(poincare-hit3d-plane-coordinates [hit poincare-hit3d?] [plane plane3?])
         vector?]{Returns the point's deterministic two-coordinate plane basis
projection, suitable for an ordinary two-dimensional plot.}
@defproc[(poincare-hits3d [hits (or/c list? vector?)] [#:id id symbol?]
                          [#:style style any/c]) group3d?]{Lowers hit values to
ordinary spatial point markers.}
@defproc[(prepare-poincare-map3d [field any/c] [plane plane3?] [seeds seed-set3d?]
                                 [#:direction direction (or/c 'any 'positive 'negative) 'any]
                                 [#:tangent-policy tangent-policy (or/c 'ignore 'include) 'ignore]
                                 [#:initial-hit initial-hit (or/c 'include 'exclude 'require) 'exclude]
                                 [#:parallel? parallel? (or/c boolean? 'auto) 'auto]
                                 [#:cancellation-token cancellation-token any/c #f])
         prepared-poincare-map3d?]{Prepares per-seed first and second crossings.
Missing returns remain @racket[#f] in the same seed slot; the result is not a
claim that an arbitrary flow has a global return map. Independent trajectory
preparation may use bounded worker threads but retains seed order.}
@defproc[(prepared-poincare-map3d? [value any/c]) boolean?]{Recognizes an
immutable per-seed return-map record. Its accessors begin with
@tt{prepared-poincare-map3d-}.}
