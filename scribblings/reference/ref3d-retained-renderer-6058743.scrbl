#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-retained-renderer-6058743"]{3D: Software rendering and statistics}

@declare-exporting[animate/3d/render #:use-sources (animate/3d/render)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defproc[(software-renderer3d) renderer3d?]{Creates a stateless deterministic
reference backend.}
@defproc[(retained-software-renderer3d [#:capacity capacity exact-positive-integer? 32])
         renderer3d?]{Creates a bounded, thread-safe backend that retains
prepared camera-space triangles, while allocating a new colour/depth target for
every render.}
@defthing[default-software-renderer3d renderer3d?]{The bounded retained backend
used by @racket[view3d]'s opaque Pict adapter.}
@defparam[current-view3d-renderer3d renderer renderer3d?]{Dynamically selects
the backend used by opaque @racket[view3d] rendering. The parameter affects the
effectful rendering boundary only; it is not captured in semantic scene values.
When a section-output cache is enabled, its declared backend identity is part of
the mandatory render envelope.}
@defproc[(retained-software-renderer3d-cache-hits [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports retained preparation hits.}
@defproc[(retained-software-renderer3d-cache-misses [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports retained preparation misses.}
@defproc[(retained-software-renderer3d-cache-size [renderer renderer3d?])
         exact-nonnegative-integer?]{Reports the current bounded cache size.}
@defstruct*[renderer3d-statistics
            ([spatial-compilations exact-nonnegative-integer?]
             [geometry-fingerprints exact-nonnegative-integer?]
             [geometry-cache-hits exact-nonnegative-integer?]
             [geometry-cache-misses exact-nonnegative-integer?]
             [geometry-cache-bytes integer?]
             [instance-count exact-nonnegative-integer?]
             [source-triangle-count exact-nonnegative-integer?]
             [clipped-triangle-count exact-nonnegative-integer?]
             [raster-triangle-count exact-nonnegative-integer?]
             [pixel-count exact-nonnegative-integer?]
             [bitmap-conversion-count exact-nonnegative-integer?]
             [preparation-milliseconds real?]
             [raster-milliseconds real?]
             [readback-milliseconds real?]) #:transparent]{An immutable
snapshot of renderer-owned counters and elapsed-time observations. They are
benchmark evidence, not timing assertions for CI.}
@defproc[(renderer3d-statistics-reset! [renderer renderer3d?]) void?]{Resets
the built-in software renderer's counters without changing semantic values.}
@defproc[(renderer3d-statistics-snapshot [renderer renderer3d?])
         renderer3d-statistics?]{Returns a coherent immutable metric snapshot.}

