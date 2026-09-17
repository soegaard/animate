#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-retained-renderer-65f0695"]{3D: Retained renderer backends}

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


SCENE-3D-N keeps @racket[animate/3d] pure and places effectful implementation
choice in @racketmodname[animate/3d/render]. SCENE-3D-O extends that compiled
view with ordered, renderer-neutral centreline strokes and screen markers. A
backend receives an immutable @racket[render3d-request] containing a
camera-independent compiled view, a frame specification, and a canonical
attachment demand.  It returns one immutable @racket[renderer3d-frame-artifact]
which owns every delivered attachment. Thus changing a backend, releasing its
cache, or recovering from a failed optional native renderer cannot mutate a
@racket[view3d], any of its spatial children, or a completed frame.

@defmodule[animate/3d/render]

@defthing[geometry-key3d procedure?]{The immutable renderer geometry identity
for an indexed mesh.  It excludes semantic part IDs and material state.}
@defthing[geometry-key3d? procedure?]{Recognizes a @racket[geometry-key3d]
value.}

@defproc[(renderer3d? [value any/c]) boolean?]{Recognizes a renderer-backend
instance.}
@defproc[(renderer3d-id [renderer renderer3d?]) symbol?]{Returns a stable
backend identity, such as @racket['software-reference].}
@defthing[prop:renderer3d-cache-identity any/c]{A structure-type property whose
immutable primitive datum declares a backend's pixel-affecting configuration
for an enclosing persistent cache. A backend without a stable declaration
omits the property.}
@defproc[(renderer3d-cache-identity [renderer renderer3d?]) any/c]{Returns the
declared backend appearance identity or @racket[#f]. An opaque
@racket[view3d] Pict adapter treats @racket[#f] conservatively: section-output
caching is disabled rather than reusing pixels rendered with an ambient custom
backend. The built-in OpenGL backend identifies a live driver/profile and its
compiled shader-source digests; when configured to fall back, it delegates this
identity to the software renderer that actually produced the pixels.}
@defproc[(renderer3d-capabilities-of [renderer renderer3d?])
         renderer3d-capabilities?]{Returns the backend's immutable declared
feature set, limits, and diagnostics.}
@defproc[(renderer3d-fingerprint [renderer renderer3d?]
                                 [request render3d-request?]) any/c]{Returns
an implementation-owned cache key for this immutable request. It is diagnostic
and cache data, never a scene identity.}
@defproc[(renderer3d-prepare [renderer renderer3d?]
                             [request render3d-request?]) any/c]{Builds or
retrieves backend-owned preparation data.}
@defproc[(renderer3d-render [renderer renderer3d?]
                            [preparation any/c]
                            [request render3d-request?])
         renderer3d-render-result?]{Rasterizes a fresh frame from a
preparation and request.}
@defproc[(renderer3d-release [renderer renderer3d?]) void?]{Releases every
resource retained by @racket[renderer]. It does not change an existing Scene or
an already returned render result.}

@defstruct*[renderer3d-capabilities
            ([features set?] [limits immutable-hash?] [diagnostics immutable-hash?])
            #:transparent]{
The immutable declaration returned by @racket[renderer3d-capabilities-of].
@racket[features] is an immutable set of symbols; @racket[limits] maps a
symbol to an exact number (or a transparent future resource value), and
@racket[diagnostics] records immutable backend details. It replaces the former
nine positional booleans, which could not safely grow with renderer features.
}

@defthing[renderer3d-known-features set?]{The vocabulary currently includes
@racket['wireframe], @racket['opaque-triangles], @racket['perspective],
@racket['orthographic], @racket['depth-buffer], @racket['flat-shading],
@racket['smooth-shading], @racket['transparency], @racket['clipping-planes],
@racket['screen-strokes], @racket['linear-depth], @racket['object-id],
@racket['ambient-light], @racket['directional-light], @racket['point-light],
@racket['spot-light], @racket['specular], @racket['emission],
@racket['directional-shadow], and @racket['spot-shadow]. A vocabulary symbol
is not an implied implementation claim: use @racket[renderer3d-supports?].}

@defthing[renderer3d-known-limits set?]{The current limit vocabulary includes
@racket['maximum-directional-lights], @racket['maximum-point-lights],
@racket['maximum-spot-lights], @racket['maximum-shadow-lights],
@racket['maximum-clip-planes], @racket['maximum-shadow-map-size], and
@racket['maximum-samples].}

@defproc[(renderer3d-supports? [capabilities renderer3d-capabilities?]
                                [features (or/c symbol? (listof symbol?) set?)])
         boolean?]{Returns true exactly when every requested feature is in the
immutable report.}
@defproc[(renderer3d-capability-limit [capabilities renderer3d-capabilities?]
                                      [limit symbol?]
                                      [default any/c #f])
         any/c]{Returns the declared limit, or @racket[default] when the
backend did not declare it. A zero limit is distinct from an absent limit.}
@defproc[(renderer3d-missing-capabilities [capabilities renderer3d-capabilities?]
                                          [features (or/c symbol? (listof symbol?) set?)])
         (listof symbol?)]{Returns missing requested features in request order.}
@defproc[(renderer3d-require-capabilities [capabilities renderer3d-capabilities?]
                                          [features (or/c symbol? (listof symbol?) set?)])
         void?]{Raises a diagnostic exception when one or more requested
features are missing.}
@defproc[(renderer3d-request-required-features [request render3d-request?])
         set?]{Infers the immutable set of features needed by one compiled
request, including projection, material shading, present light kinds, clipping,
screen marks, transparency, and requested frame attachments.}
@defproc[(renderer3d-request-required-limits [request render3d-request?])
         immutable-hash?]{Returns exact per-frame resource demands, including
directional-light and clip-plane counts.}
@defproc[(renderer3d-require-request-capabilities [renderer renderer3d?]
                                                  [request render3d-request?])
         void?]{Checks the same inferred feature and limit demand before a
built-in backend prepares resources. @racket[check-project!] performs this
comparison across every selected project frame before rendering begins.}

@bold{Current capability limitation:} The software backend has no practical
fixed directional, point, spot, or clipping bound. The optional OpenGL shaders
explicitly support at most four directional lights, eight point lights, four
spot lights, and eight clip planes; an over-limit request raises an error
rather than silently dropping lights. Its maximum sample count is the live GL
limit, although a one-sample framebuffer remains available. The software
backend supports directional and spot maps in V8; the OpenGL backend supports
the same descriptor kinds in V9 through a maximum of eight cached depth maps.

