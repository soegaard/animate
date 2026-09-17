#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lig-33bbf37"]{3D: Lighting inspection}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defstruct*[material-inspection3d
            ([material material3d?] [fields immutable-hash?]) #:transparent]{
An immutable, presentation-neutral report of every material parameter relevant
to the current lighting contract. @racket[fields] names the base colour,
normal mode, lighting model, ambient/diffuse/specular coefficients, specular
colour, roughness, derived exponent, emission, double-sided policy, and
cast/receive-shadow policies.}
@defproc[(material3d-inspection [material material3d?]) material-inspection3d?]{
Returns the immutable material report without rendering or changing
@racket[material].}

@defstruct*[light-inspection3d
            ([light light3d?] [fields immutable-hash?]) #:transparent]{
An immutable description of one light. Its fields include the stable ID, kind,
colour, intensity, position or direction where applicable, attenuation/range,
spot angles, and its shadow descriptor.}
@defproc[(light3d-inspection [light light3d?]) light-inspection3d?]{Returns the
immutable light report without allocating renderer resources.}

@defstruct*[fragment-light-sample3d
            ([id symbol?] [kind symbol?] [direction any/c] [distance any/c]
             [attenuation any/c] [cone any/c] [facing any/c]
             [shadow-factor real?] [shadow-state symbol?]
             [diffuse-energy real?] [specular-energy real?]
             [diffuse-linear any/c] [specular-linear any/c]) #:transparent]{
One per-light term in a lighting probe. Ambient samples deliberately use
@racket[#f] for geometric values that have no ambient meaning.}
@defstruct*[fragment-lighting-report3d
            ([world-point vec3?] [normal vec3?] [view-direction vec3?]
             [material material3d?] [light-samples list?]
             [pre-tone-map any/c] [final-srgb rgba-color?]
             [diagnostics list?] [authored-lights list?]
             [theme-id symbol?] [appearance-fingerprint bytes?]
             [resolved-material material3d?] [resolved-lights list?]) #:transparent]{
The complete pure fragment-lighting explanation: normalized geometry, each
light's diffuse/specular/shadow term, the accumulated linear colour before
tone mapping, final sRGB output, and any honest unavailable-data diagnostic.
The material and lights fields retain authored specifications; the separate
resolved fields record the concrete colours used for arithmetic.}
@defproc[(fragment-lighting-inspection3d
          [material material3d?] [lights (listof light3d?)]
          [world-point vec3?] [normal vec3?] [camera-position vec3?]
          [#:tone-map tone-map tone-map3d? default-tone-map3d]
          [#:shadow-factors shadow-factors immutable-hash? #hasheq()]
          [#:theme theme color-theme? animate-light-theme])
         fragment-lighting-report3d?]{
Recomputes the documented lighting equation from immutable authoring values
under the selected immutable theme. Tokenized material and light colours are
resolved once before numerical color-space calculations begin.
@racket[shadow-factors] may supply a sampled fraction in @math{[0,1]} for each
named shadowed light. The preview's @tt{Material}, @tt{Lights}, and
@tt{Fragment probe} inspector sections use the same query after a mesh click.}

@bold{Current limitation.} A pure probe does not read a private software or
OpenGL depth map: when a light declares a shadow but its factor has not been
explicitly supplied, the report uses a numerically unshadowed factor of one,
marks it @racket['not-sampled], and returns a diagnostic. This prevents the
inspector from guessing hidden renderer state or changing the rendered Scene.
It is not a per-pixel GPU debugger; the preview probe reports the exact CPU
pick and authored equations, while actual shadow-map sampling remains backend
owned.

@defproc[(ambient-light3d [#:id id symbol? 'ambient]
                           [#:intensity intensity nonnegative-real? 1]
                           [#:color color color-spec? "white"]
                           [#:shadow shadow #f #f])
         ambient-light3d?]{Creates uniform ambient illumination with a stable
authored identifier. The colour specification must resolve to opaque under the
frame's theme. Shadow descriptors are reserved for a later stage; the only
accepted current value is @racket[#f].}
@defproc[(directional-light3d [direction vec3?]
                               [#:id id symbol? 'key]
                               [#:intensity intensity nonnegative-real? 1]
                               [#:color color color-spec? "white"]
                               [#:shadow shadow (or/c #f directional-shadow3d?) #f])
         directional-light3d?]{Creates a directional light whose colour must
resolve to opaque under the frame's theme. Its direction is the direction in
which illumination travels, so a normal facing
its negation receives diffuse light. The direction is normalized. A
@racket[directional-shadow3d] makes both built-in opaque renderers produce and
sample one depth map.}
@defproc[(point-light3d [position vec3?]
                         [#:id id symbol? 'point]
                         [#:intensity intensity nonnegative-real? 1]
                         [#:color color color-spec? "white"]
                         [#:attenuation attenuation light-attenuation3d?
                          (inverse-square-attenuation3d)]
                         [#:range range (or/c #f positive-real?) #f]
                         [#:shadow shadow #f #f])
         point-light3d?]{Creates a finite-position light value.}
@defproc[(spot-light3d [position vec3?] [direction vec3?]
                        [#:id id symbol? 'spot]
                        [#:intensity intensity nonnegative-real? 1]
                        [#:color color color-spec? "white"]
                        [#:inner-angle inner-angle nonnegative-real? 0]
                        [#:outer-angle outer-angle positive-real? @math{pi/4}]
                        [#:attenuation attenuation light-attenuation3d?
                         (inverse-square-attenuation3d)]
                        [#:range range (or/c #f positive-real?) #f]
                        [#:shadow shadow (or/c #f spot-shadow3d?) #f])
         spot-light3d?]{Creates a finite-position cone light. Its normalized
direction points outward; inside @racket[inner-angle] illumination is full,
outside @racket[outer-angle] it is zero, and the interval between uses the
fixed smoothstep falloff. Angles are radians. A @racket[spot-shadow3d] is
sampled by both built-in opaque renderers. Point-light cube shadows remain
deferred, so a point light accepts only @racket[#f].}
@defproc[(ambient-light3d? [value any/c]) boolean?]{Recognizes ambient light.}
@defproc[(ambient-light3d-id [light ambient-light3d?]) symbol?]{Returns its stable ID.}
@defproc[(ambient-light3d-intensity [light ambient-light3d?]) nonnegative-real?]{Returns ambient intensity.}
@defproc[(ambient-light3d-color [light ambient-light3d?]) color-spec?]{Returns the retained ambient colour specification.}
@defproc[(ambient-light3d-shadow [light ambient-light3d?]) #f]{Returns reserved shadow policy.}
@defproc[(directional-light3d? [value any/c]) boolean?]{Recognizes directional light.}
@defproc[(directional-light3d-id [light directional-light3d?]) symbol?]{Returns its stable ID.}
@defproc[(directional-light3d-direction [light directional-light3d?]) vec3?]{Returns normalized travel direction.}
@defproc[(directional-light3d-intensity [light directional-light3d?]) nonnegative-real?]{Returns directional intensity.}
@defproc[(directional-light3d-color [light directional-light3d?]) color-spec?]{Returns the retained directional colour specification.}
@defproc[(directional-light3d-shadow [light directional-light3d?])
         (or/c #f directional-shadow3d?)]{Returns attached shadow intent.}
@defproc[(point-light3d? [value any/c]) boolean?]{Recognizes a point light.}
@defproc[(point-light3d-id [light point-light3d?]) symbol?]{Returns its stable ID.}
@defproc[(point-light3d-position [light point-light3d?]) vec3?]{Returns position.}
@defproc[(point-light3d-intensity [light point-light3d?]) nonnegative-real?]{Returns intensity.}
@defproc[(point-light3d-color [light point-light3d?]) color-spec?]{Returns the retained colour specification.}
@defproc[(point-light3d-attenuation [light point-light3d?]) light-attenuation3d?]{Returns attenuation policy.}
@defproc[(point-light3d-range [light point-light3d?]) (or/c #f positive-real?)]{Returns optional cutoff range.}
@defproc[(point-light3d-shadow [light point-light3d?]) #f]{Returns reserved shadow policy.}
@defproc[(spot-light3d? [value any/c]) boolean?]{Recognizes a spot light.}
@defproc[(spot-light3d-id [light spot-light3d?]) symbol?]{Returns its stable ID.}
@defproc[(spot-light3d-position [light spot-light3d?]) vec3?]{Returns position.}
@defproc[(spot-light3d-direction [light spot-light3d?]) vec3?]{Returns normalized outward direction.}
@defproc[(spot-light3d-intensity [light spot-light3d?]) nonnegative-real?]{Returns intensity.}
@defproc[(spot-light3d-color [light spot-light3d?]) color-spec?]{Returns the retained colour specification.}
@defproc[(spot-light3d-inner-angle [light spot-light3d?]) nonnegative-real?]{Returns full-cone angle in radians.}
@defproc[(spot-light3d-outer-angle [light spot-light3d?]) positive-real?]{Returns cutoff-cone angle in radians.}
@defproc[(spot-light3d-attenuation [light spot-light3d?]) light-attenuation3d?]{Returns attenuation policy.}
@defproc[(spot-light3d-range [light spot-light3d?]) (or/c #f positive-real?)]{Returns optional cutoff range.}
@defproc[(spot-light3d-shadow [light spot-light3d?])
         (or/c #f spot-shadow3d?)]{Returns attached shadow intent.}
@defproc[(light3d? [value any/c]) boolean?]{Recognizes any authored light.}
@defproc[(light3d-id [light light3d?]) symbol?]{Returns its stable ID.}
@defproc[(light3d-kind [light light3d?]) (or/c 'ambient 'directional 'point 'spot)]{Returns its kind.}
@defproc[(light3d-color [light light3d?]) color-spec?]{Returns the retained light colour specification, which must resolve to opaque for rendering.}
@defproc[(light3d-intensity [light light3d?]) nonnegative-real?]{Returns intensity.}
@defproc[(light3d-shadow [light light3d?]) (or/c #f shadow3d?)]{Returns attached shadow intent, if any.}

