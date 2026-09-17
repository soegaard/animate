#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-supplementary-q-t-api"]{3D: Supplementary Q--T API}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


The following bindings complete the public surface/section/annotation APIs
introduced by the Q--T stages.  Their detailed data conventions are described
in the preceding sections; the bindings are listed here so that a client can
link to the exact exported names.

