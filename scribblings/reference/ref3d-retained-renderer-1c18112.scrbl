#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-retained-renderer-1c18112"]{3D: Frame requests and results}

@declare-exporting[animate/3d/render #:use-sources (animate/3d/render)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}
@defstruct*[render3d-request
            ([compiled-view compiled-view3d?]
             [frame-spec frame3d-spec?]
             [attachments (listof symbol?)]
             [cancellation-token any/c] [color-context any/c]) #:transparent]{
One backend-local request. The cancellation field is either @racket[#f] or the
preview's cooperative cancellation token; it is not serialised into scene
state.
}
@defstruct*[renderer3d-render-result
            ([artifact renderer3d-frame-artifact?]) #:transparent]{
A completed backend-independent frame. The artifact is its only frame payload
and may outlive the backend that produced it.
}
@defstruct*[renderer3d-frame-artifact
            ([width exact-positive-integer?]
             [height exact-positive-integer?]
             [straight-argb (or/c #f bytes?)]
             [linear-depth-snapshot (or/c #f vector?)]
             [object-id-snapshot (or/c #f vector?)]
             [normal-snapshot (or/c #f vector?)]
             [camera camera3d?]
             [diagnostics any/c]) #:transparent]{
The immutable attachment owner for a completed frame. Pixel snapshots are
top-left-origin. Linear depth is positive camera-space depth; an uncovered
pixel is @racket[+inf.0].}
@defproc[(renderer3d-frame-artifact-attachments
          [artifact renderer3d-frame-artifact?])
         (listof symbol?)]{Returns the canonical set of attachments actually
present in @racket[artifact].}
@defproc[(renderer3d-frame-linear-depth-at
          [artifact renderer3d-frame-artifact?]
          [x exact-nonnegative-integer?]
          [y exact-nonnegative-integer?])
         (or/c #f real?)]{Returns the positive linear depth at a top-left
pixel, or @racket[#f] when the artifact has no depth attachment or the pixel is
outside the viewport.}
@defproc[(renderer3d-render-result->bitmap [result renderer3d-render-result?])
         bitmap?]{Converts the copied ARGB frame to a Racket bitmap for the
ordinary @racket[view3d] Pict boundary.}

