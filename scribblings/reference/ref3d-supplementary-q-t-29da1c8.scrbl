#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-supplementary-q-t-29da1c8"]{3D: Cuts, sections, and numerical volume}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defthing[cut-mesh3d procedure?]{Cuts a mesh by one declared plane and returns
the clipped halves, section, and optional caps.}
@defthing[clip-planes3d procedure?]{Applies ordered render-only plane clips to
a spatial visual.}
@defthing[clip-box3d procedure?]{Applies a render-only axis-aligned box clip to
a spatial visual.}
@defthing[section-fill3d procedure?]{Builds a visible cap-style mesh for a
section.}
@defthing[section-hatch3d procedure?]{Builds deterministic hatch strokes in a
section's local plane basis.}
@defthing[section3d-area procedure?]{Measures the signed-area-normalized
section region under the documented validity policy.}
@defthing[section3d-centroid procedure?]{Returns the centroid of a measurable
section region.}
@defthing[section3d-perimeter procedure?]{Returns the perimeter of a measurable
section region.}
@defproc[(section3d-settings? [value any/c]) boolean?]{Recognizes the immutable
numerical policy used by section and cut operations.}
@defthing[slice-stack3d procedure?]{Builds stable section groups for an ordered
stack of planes.}
@defthing[prepare-cross-section-function3d procedure?]{Prepares an immutable
table of sampled cross sections and measurements.}
@defthing[volume-by-slices3d procedure?]{Estimates volume from a prepared
cross-section table with an explicit quadrature rule.}

