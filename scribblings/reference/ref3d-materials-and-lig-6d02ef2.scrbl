#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lig-6d02ef2"]{3D: Shadow descriptors and stable bounds}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defproc[(shadow-bias3d [#:world-normal-offset world-normal-offset nonnegative-real? 0]
                          [#:slope-scale slope-scale nonnegative-real? 0]
                          [#:constant-depth-offset constant-depth-offset nonnegative-real? 0]
                          [#:pcf-radius-texels pcf-radius-texels exact-nonnegative-integer? 1])
         shadow-bias3d?]{Creates renderer-neutral shadow bias. The three
distances are world-space distances: @racket[world-normal-offset] moves a
receiver along its normal, @racket[slope-scale] is multiplied by the derived
world length of one shadow texel and the grazing-angle factor, and
@racket[constant-depth-offset] moves it toward the light. The PCF radius is a
texel count. Both the software and OpenGL renderers project this same adjusted
receiver position before comparing the shadow map.}
@defproc[(shadow-bias3d? [value any/c]) boolean?]{Recognizes semantic shadow bias.}
@defproc[(shadow-bias3d-world-normal-offset [bias shadow-bias3d?]) nonnegative-real?]{Returns the world-normal offset.}
@defproc[(shadow-bias3d-slope-scale [bias shadow-bias3d?]) nonnegative-real?]{Returns the dimensionless grazing-angle scale.}
@defproc[(shadow-bias3d-constant-depth-offset [bias shadow-bias3d?]) nonnegative-real?]{Returns the world-space offset toward the light.}
@defproc[(shadow-bias3d-pcf-radius-texels [bias shadow-bias3d?]) exact-nonnegative-integer?]{Returns the PCF radius in texels.}

@defproc[(shadow-settings3d [#:map-size map-size exact-positive-integer? 1024]
                             [#:bias bias (or/c #f shadow-bias3d?) #f]
                             [#:depth-bias depth-bias (or/c #f nonnegative-real?) #f]
                             [#:normal-bias normal-bias (or/c #f nonnegative-real?) #f]
                             [#:pcf-radius pcf-radius (or/c #f exact-nonnegative-integer?) #f]
                             [#:bounds bounds (or/c #f aabb3?) #f]
                             [#:near near (or/c #f positive-real?) #f]
                             [#:far far (or/c #f positive-real?) #f]
                             [#:prepared-bounds-key prepared-bounds-key (or/c #f symbol?) #f])
         shadow-settings3d?]{Creates immutable shadow-map settings. An explicit
@racket[bounds] is a nonempty world-space shadow region. Without it, both
renderers fit the current opaque caster bounds; this direct-frame fit can
shimmer as casters move. @racket[prepared-bounds-key] is retained for stable
retained-renderer map identity and enables directional texel-centre snapping
when named. New code should pass @racket[#:bias] and a @racket[shadow-bias3d]
value. The depth/normal/PCF keywords are retained only for image-compatible
legacy scenes and cannot be combined with @racket[#:bias]; their normalized
depth units remain backend-specific.}
@defproc[(shadow-settings3d? [value any/c]) boolean?]{Recognizes shadow settings.}
@defproc[(shadow-settings3d-map-size [settings shadow-settings3d?]) exact-positive-integer?]{Returns map size.}
@defproc[(shadow-settings3d-bias [settings shadow-settings3d?]) (or/c #f shadow-bias3d?)]{Returns the semantic bias, or @racket[#f] for a legacy descriptor.}
@defproc[(shadow-settings3d-depth-bias [settings shadow-settings3d?]) nonnegative-real?]{Returns the legacy constant receiver-depth bias. New code should use @racket[shadow-settings3d-bias].}
@defproc[(shadow-settings3d-normal-bias [settings shadow-settings3d?]) nonnegative-real?]{Returns the legacy slope-dependent receiver bias. New code should use @racket[shadow-settings3d-bias].}
@defproc[(shadow-settings3d-pcf-radius [settings shadow-settings3d?]) exact-nonnegative-integer?]{Returns the legacy square PCF radius. New code should use @racket[shadow-settings3d-bias].}
@defproc[(shadow-settings3d-bounds [settings shadow-settings3d?]) (or/c #f aabb3?)]{Returns explicit world-space shadow-region bounds, if any.}
@defproc[(shadow-settings3d-near [settings shadow-settings3d?]) (or/c #f positive-real?)]{Returns optional light near plane.}
@defproc[(shadow-settings3d-far [settings shadow-settings3d?]) (or/c #f positive-real?)]{Returns optional light far plane.}
@defproc[(shadow-settings3d-prepared-bounds-key [settings shadow-settings3d?]) (or/c #f symbol?)]{Returns the optional prepared-bound name.}
@defproc[(directional-shadow3d [#:settings settings shadow-settings3d?
                                 (shadow-settings3d)])
         directional-shadow3d?]{Attaches the settings to a directional light.}
@defproc[(spot-shadow3d [#:settings settings shadow-settings3d?
                          (shadow-settings3d)])
         spot-shadow3d?]{Attaches the settings to a spot light.}
@defproc[(directional-shadow3d? [value any/c]) boolean?]{Recognizes a directional shadow descriptor.}
@defproc[(directional-shadow3d-settings [shadow directional-shadow3d?]) shadow-settings3d?]{Returns directional settings.}
@defproc[(spot-shadow3d? [value any/c]) boolean?]{Recognizes a spot shadow descriptor.}
@defproc[(spot-shadow3d-settings [shadow spot-shadow3d?]) shadow-settings3d?]{Returns spot settings.}
@defproc[(shadow3d? [value any/c]) boolean?]{Recognizes either supported shadow descriptor.}
@defproc[(shadow3d-kind [shadow shadow3d?]) (or/c 'directional 'spot)]{Returns descriptor kind.}
@defproc[(shadow3d-settings [shadow shadow3d?]) shadow-settings3d?]{Returns its immutable settings.}

@defstruct*[prepared-shadow-bounds3d
            ([light-id symbol?] [frame-range pair?] [bounds aabb3?]
             [light-space-bounds aabb3?] [diagnostics immutable-hash?]) #:transparent]{
A validated stable union of opaque caster bounds for one directional or spot
shadow light.}
@defproc[(prepare-shadow-bounds3d [views (or/c view3d? (nonempty-listof view3d?))]
                                      [#:light-id light-id symbol?]
                                      [#:frame-range frame-range pair? #f])
         prepared-shadow-bounds3d?]{Prepares one sampled view or an ordered
list of project-frame view samples. The inclusive frame range must match the
sample count. The light's pose and descriptor must stay fixed across samples;
prepare separate ranges for animated shadow-light poses.}
@defproc[(prepared-shadow-bounds3d-key [prepared prepared-shadow-bounds3d?]) vector?]{
Returns its immutable identity key.}
@defproc[(shadow-map3d-identity [view view3d?] [light-id symbol?]
                                 [prepared prepared-shadow-bounds3d?]) vector?]{
Returns the depth-map cache key. It includes caster geometry, transforms,
caster policy, light pose/settings, and prepared bounds, but deliberately
excludes the viewing camera.}

@defstruct*[shadow-map3d
            ([width exact-positive-integer?] [height exact-positive-integer?]
             [depth immutable-vector?] [camera camera3d?]
             [settings shadow-settings3d?] [bounds aabb3?]
             [diagnostics immutable-hash?]) #:transparent]{An immutable,
software-prepared depth map. Its depth vector stores positive light-camera
depth in top-left pixel order. The reference backend owns map construction;
the value is exposed for inspection and deterministic sampling.}
@defproc[(shadow-map3d-factor [map shadow-map3d?] [world-position vec3?]
                               [world-normal vec3?] [light-direction vec3?])
         real?]{Returns the fraction of a square PCF kernel which is lit. It
projects the semantic @racket[shadow-bias3d] receiver offset when present;
legacy descriptors use their historical
@racket[depth-bias + normal-bias*(1-max(0,n·l))] comparison. Samples outside
the fitted map are lit.}
@defproc[(shadow-light-camera3d [light (or/c directional-light3d? spot-light3d?)]
                                [settings shadow-settings3d?] [bounds aabb3?])
         camera3d?]{Fits the deterministic light camera used by the reference
map. Directional maps use a square orthographic fit and named prepared bounds
snap their centre to map texels; spots use the source, outward cone, and
near/far/range policy.}

@bold{Current limitation.} The V8 software and V9 OpenGL renderers create one
directional or spot depth map per descriptor and multiply only diffuse and
specular terms by its PCF result. Ambient and emission remain unchanged. Only
opaque mesh instances cast or receive; transparent surfaces, strokes, markers,
billboards, and point-light cube shadows are outside this stage. Direct-frame
fitting can shimmer, and a too-small explicit region yields unshadowed outside
samples. V9 caches context-owned GPU maps by eligible casters, light
pose/settings, and bounds, deliberately excluding viewing-camera motion.
Semantic @racket[shadow-bias3d] values avoid backend-specific depth tuning by
moving the receiver in world space before each renderer projects it. The
legacy depth/normal fields retain their original backend-specific behavior for
image compatibility.

@defstruct*[light-attenuation3d ([mode (or/c 'constant 'inverse-square 'polynomial)]
                                  [parameters immutable-hash?]) #:transparent]{
An immutable, inspectable finite-light attenuation policy. The parameter hash
uses the named schema selected by @racket[mode].}
@defproc[(constant-attenuation3d [#:factor factor nonnegative-real? 1])
         light-attenuation3d?]{Creates a distance-independent multiplier.}
@defproc[(inverse-square-attenuation3d
          [#:reference-distance reference-distance positive-real? 1]
          [#:cutoff cutoff (or/c #f positive-real?) #f])
         light-attenuation3d?]{Creates the finite rule
@math{(r / max(d,r))^2}, optionally zeroing beyond @racket[cutoff]. The
named reference distance explicitly clamps the otherwise singular origin.}
@defproc[(polynomial-attenuation3d [#:constant constant nonnegative-real? 1]
                                    [#:linear linear nonnegative-real? 0]
                                    [#:quadratic quadratic nonnegative-real? 0]
                                    [#:cutoff cutoff (or/c #f positive-real?) #f])
         light-attenuation3d?]{Creates @math{1/(c + ld + qd^2)}. At least one
coefficient must be positive.}
@defproc[(light-attenuation3d-factor [attenuation light-attenuation3d?]
                                      [distance nonnegative-real?])
         nonnegative-real?]{Evaluates the named attenuation policy.}
@defproc[(spot-smoothstep3d [progress finite-real?]) (and/c real? (between/c 0 1))]{
Returns the clamped cubic @math{t^2(3-2t)} used for spotlight falloff.}
@defproc[(spot-cone-factor3d [inner-angle nonnegative-real?]
                              [outer-angle positive-real?]
                              [angle nonnegative-real?])
         (and/c real? (between/c 0 1))]{Evaluates the fixed spot cone rule.}

Point and spot lights are evaluated by both the deterministic software
reference renderer and the optional OpenGL backend. They use the same named
constant, inverse-square, and polynomial attenuation policies, optional range,
and smoothstep spot-cone rule. OpenGL packs the authored non-ambient light
sequence into fixed uniform records, so it retains the frame's light order
rather than approximating finite sources as directional lights.

@bold{Current limitation.} The OpenGL implementation has explicit fixed
limits of four directional, eight point, and four spot lights per lit view.
It rejects an over-limit frame before drawing. V9 adds directional/spot maps,
but point-light cube shadows remain deferred.

