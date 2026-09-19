#lang scribble/manual

@(require (for-label racket/base
                     racket/contract
                     racket/math
                     animate
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl
                     animate/project))

@title[#:tag "ref3d-materials-and-lights"]{3D: Materials and lights}

@declare-exporting[animate/3d #:use-sources (animate/3d)]

@seclink["3d-algebra"]{3D reference map} · @seclink["guide-3d-picture"]{First 3D picture}


@defproc[(material3d [#:color color color-spec? "cornflowerblue"]
                      [#:shading shading (or/c 'unlit 'flat 'smooth) 'flat]
                      [#:lighting lighting (or/c 'lambert 'blinn-phong) 'lambert]
                      [#:ambient ambient nonnegative-real? 1]
                      [#:diffuse diffuse nonnegative-real? 1]
                      [#:specular specular nonnegative-real? 0]
                      [#:specular-color specular-color color-spec? "white"]
                      [#:roughness roughness (and/c positive-real? (<=/c 1)) 1]
                      [#:emission emission color-spec? "black"]
                      [#:emission-strength emission-strength nonnegative-real? 0]
                      [#:double-sided? double-sided? boolean? #f]
                      [#:casts-shadow? casts-shadow? boolean? #t]
                      [#:receives-shadow? receives-shadow? boolean? #t]
                      [#:wireframe? wireframe? boolean? #f])
         material3d?]{
Constructs an immutable surface material. Its three colour fields retain
@racket[color-spec?] values, including theme roles and expressions; all are
resolved once from the frame's selected theme before either built-in renderer
classifies opacity or shades fragments. @racket['unlit] uses its base colour
and then adds @racket[emission * emission-strength], without consulting
lights. @racket['flat] evaluates one face normal using ambient and directional
lights; @racket['smooth] interpolates supplied vertex normals. @racket['lambert]
uses ambient plus diffuse illumination. @racket['blinn-phong] additionally
adds a directional-light highlight, scaled by @racket[specular] and
@racket[specular-color]. The colour may include alpha; the renderer's explicit
transparent pass controls its compositing policy.

The OpenGL preparation resolves the complete ordered light list once under the
same request-owned color context. Uniform packing and shadow-light selection
consume those numerical RGBA values; authored light values remain unchanged for
inspection. A resolved translucent light is rejected before a GPU draw.

For Blinn--Phong the roughness @italic{r} maps identically in the reference
and OpenGL renderers to @racketblock[n = max(1, 2/r^2 - 2)]. @racket[roughness]
must be finite in @math{(0,1]}; ambient, diffuse, specular, and
@racket[emission-strength] must be finite and nonnegative. Coefficients larger
than one are intentionally accepted for illustrative effects; the current
renderers retain their linear energy through composition and apply the owning
viewport's final tone-map policy only when storing output pixels.

@racket[emission] is added after ambient, diffuse, and specular terms and is
therefore not reduced by shadows. @racket[casts-shadow?] and
@racket[receives-shadow?] are durable material policy. The software and OpenGL renderers include only opaque mesh instances with
@racket[casts-shadow?] in a depth map and apply receiver policy to diffuse and
specular illumination. Transparent surfaces, strokes, markers, and billboards
do not cast shadows or receive a shadow-map lookup.
OpenGL shadow reuse is keyed by the prepared eligible-caster set, so a themed
vertex-alpha change that adds or removes a caster refreshes the depth map while
an RGB-only change may reuse it.
}
@defproc[(material3d? [value any/c]) boolean?]{Recognizes a material.}
@defproc[(material3d-color [material material3d?]) color-spec?]{Returns the retained base colour specification.}
@defproc[(material3d-shading [material material3d?]) (or/c 'unlit 'flat 'smooth)]{Returns its active shading mode.}
@defproc[(material3d-lighting [material material3d?]) (or/c 'lambert 'blinn-phong)]{Returns its lighting model.}
@defproc[(material3d-ambient [material material3d?]) nonnegative-real?]{Returns ambient coefficient.}
@defproc[(material3d-diffuse [material material3d?]) nonnegative-real?]{Returns diffuse coefficient.}
@defproc[(material3d-specular [material material3d?]) nonnegative-real?]{Returns specular coefficient.}
@defproc[(material3d-specular-color [material material3d?]) color-spec?]{Returns the retained highlight colour specification.}
@defproc[(material3d-roughness [material material3d?]) (and/c positive-real? (<=/c 1))]{Returns roughness.}
@defproc[(material3d-specular-exponent [material material3d?]) positive-real?]{Returns
the derived @math{max(1,2/r^2-2)} Blinn--Phong exponent shown by the spatial inspector.}
@defproc[(material3d-emission [material material3d?]) color-spec?]{Returns the retained additive emission colour specification.}
@defproc[(material3d-emission-strength [material material3d?]) nonnegative-real?]{Returns emission strength.}
@defproc[(material3d-double-sided? [material material3d?]) boolean?]{Reports whether back-face culling is disabled for this mesh.}
@defproc[(material3d-casts-shadow? [material material3d?]) boolean?]{Returns shadow-caster policy. Only opaque mesh instances with true policy enter a software depth map.}
@defproc[(material3d-receives-shadow? [material material3d?]) boolean?]{Returns whether an opaque mesh receiver applies the software shadow factor.}
@defproc[(material3d-wireframe? [material material3d?]) boolean?]{Returns retained wireframe intent.}
@defproc[(material3d-with-color [material material3d?] [color color-spec?]) material3d?]{Returns
@racket[material] with only its base colour replaced.}
@defproc[(material3d-with-roughness [material material3d?]
                                     [roughness (and/c positive-real? (<=/c 1))])
         material3d?]{Returns @racket[material] with only its roughness replaced.}
@defproc[(material3d-with-emission [material material3d?] [emission color-spec?]
                                   [#:strength strength nonnegative-real?
                                    (material3d-emission-strength material)])
         material3d?]{Returns @racket[material] with emission fields replaced.}
@defproc[(material3d-with-shadow-policy [material material3d?]
                                        [#:casts-shadow? casts-shadow? boolean?
                                         (material3d-casts-shadow? material)]
                                        [#:receives-shadow? receives-shadow? boolean?
                                         (material3d-receives-shadow? material)])
         material3d?]{Returns @racket[material] with its shadow policy replaced.}

