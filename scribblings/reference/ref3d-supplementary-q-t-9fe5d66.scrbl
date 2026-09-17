#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-supplementary-q-t-9fe5d66"]{3D: Anchors and projected labels}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defthing[anchor3d? procedure?]{Recognizes an immutable spatial anchor.}
@defthing[vertex-anchor3d procedure?]{Anchors a label to a stable mesh vertex.}
@defthing[edge-anchor3d procedure?]{Anchors a label to a stable mesh edge.}
@defthing[face-anchor3d procedure?]{Anchors a label to a stable mesh face.}
@defthing[curve-anchor3d procedure?]{Anchors a label to a retained curve
position.}
@defthing[surface-anchor3d procedure?]{Anchors a label to a retained surface
parameter point.}
@defthing[resolved-anchor3d procedure?]{Constructs or recognizes the immutable
world-space result of resolving an anchor.}
@defthing[label3d procedure?]{Attaches a crisp two-dimensional visual to a
spatial anchor.}
@defthing[layout-labels3d procedure?]{Computes direct-mode candidate placements
for projected labels.}
@defthing[prepare-label-layout3d procedure?]{Precomputes a deterministic
multi-frame label-placement table.}
@defthing[prepared-label-layout3d? procedure?]{Recognizes an immutable prepared
label-placement table.}
@defthing[billboard-style3d? procedure?]{Recognizes an immutable billboard
display policy.}

