#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "reference-animation-motion"]{Moving, rotating, and scaling}

Choose absolute endpoints or changes relative to the current state.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(move-to [target (or/c visual? symbol?)]
                  [destination vec2?])
         move-to-request?]{

Creates an absolute translation request. At the end of its play clip, the
target's reference position is @racket[destination]. Identity, geometry, style,
rotation, scale, opacity, drawing order, and group child order are preserved.
}

@defproc[(move-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[move-to].
}

@defproc[(move-along-path
          [target (or/c visual? symbol?)]
          [path (or/c path-geometry? path-visual? derived-visual? symbol?)]
          [#:start start (real-in 0 1) 0]
          [#:end end (real-in 0 1) 1]
          [#:normal-offset normal-offset finite-real? 0])
         move-along-path-request?]{

Creates a translation request that places @racket[target] on @racket[path] by
total arc length. @racket[start] and @racket[end] are independent finite
fractions in the closed unit interval. The default traverses from the beginning
to the end; a larger @racket[start] than @racket[end] traverses the same route
in reverse. Other easing procedures remap this arc-length fraction in the same
way that they remap ordinary translation progress. Under @racket[linear], equal
time intervals cover equal total arc length.

@racket[normal-offset] adds a signed displacement perpendicular to the selected
route point. A positive value lies to the left of the @emph{actual traversal
direction}; reverse traversal therefore reverses the normal. Zero preserves the
route point exactly and does not require tangent sampling. On a sharp
polyline corner the offset is segment-local, so the offset trajectory can jump
between the adjacent offset edge lines. Smooth cubic routes give smooth normal
motion wherever their tangent is continuous.

When @racket[path] is a @racket[path-geometry?] value, its points are interpreted
directly in @racket[target]'s containing coordinate system. When it is a path Visual, derived Visual definition, or symbol identity,
@racket[scene-play] resolves the current top-level Visual from the prepared
clip-start state by stable identity. A derived definition is evaluated against
that exact state first; the concrete result must be a path Visual. The path
Visual's current affine transform is then applied to its local path points before
the resulting world-space route is measured. Passing an earlier Visual value
therefore selects the current scene value rather than capturing stale
coordinates.

The compiled route is a snapshot for that play clip. Simultaneously moving,
scaling, rotating, or morphing the path Visual does not dynamically deform the
motion route. A path Visual route is world-space after resolution and cannot be
used to drive a frame-space target. Raw path geometry may drive a frame-space
target because it is already interpreted in that target's containing coordinate
system.

Motion requires a positive finite route with exactly one positive-length
subpath. Compound drawings with multiple positive-length subpaths are valid path
geometry but are rejected here so the target cannot silently teleport across a
gap. Closed single-subpath routes are allowed, including their implicit closing
edge.

The request changes the ordinary translation animation component. It conflicts
with same-target @racket[move-to] or another @racket[move-along-path], but may
run with disjoint rotation, scale, opacity, path-geometry, formula-part, and
camera components. Sampling places the target at the selected route point plus
any requested normal offset even when its prior reference position differs; put
the target at that complete @racket[start] position before the clip when a
continuous clip boundary is required.
}

@defproc[(move-along-path-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[move-along-path].
}

@defproc[(orient-along-path
          [target (or/c visual? symbol?)]
          [path (or/c path-geometry? path-visual? derived-visual? symbol?)]
          [#:start start (real-in 0 1) 0]
          [#:end end (real-in 0 1) 1]
          [#:rotation-offset rotation-offset finite-real? 0])
         orient-along-path-request?]{

Creates a rotation request that points @racket[target]'s local positive x axis
along the tangent of @racket[path] at the current total-arc-length fraction.
The target must implement @racket[gen:affine-visual]. @racket[start] and
@racket[end] use the same partial and reverse traversal semantics as
@racket[move-along-path]. Reverse traversal negates the stored forward tangent,
so the Visual points in the actual direction of motion. @racket[rotation-offset]
is a constant angle in radians added after tangent alignment.

Path source resolution, clip-start snapshot semantics, transformed path Visual
handling, frame/world coordinate rules, positive finite length requirements,
and single-positive-subpath continuity requirements are the same as for
@racket[move-along-path]. Tangents are provided by
@racket[path-geometry-tangent-at].

The request changes only the ordinary rotation animation component. It may run
simultaneously with same-target @racket[move-along-path], scale, opacity, and
disjoint components, but conflicts with same-target @racket[rotate-to],
@racket[rotate-by], or another @racket[orient-along-path]. The rotation at a
sample is derived directly from the sampled tangent rather than interpolated
between endpoint angles, so bends and curved routes are followed geometrically.
}

@defproc[(orient-along-path-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[orient-along-path].
}

@defproc[(rotate-to [target (or/c visual? symbol?)]
                    [angle finite-real?])
         rotate-to-request?]{

Creates an absolute rotation request. @racket[angle] is the requested final
counter-clockwise rotation in radians. The target must implement
@racket[gen:affine-visual]. Identity, geometry, style, position, scale, opacity,
drawing order, and group child order are preserved.
}

@defproc[(rotate-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[rotate-to].
}

@defproc[(rotate-by [target (or/c visual? symbol?)]
                    [delta finite-real?])
         rotate-by-request?]{

Creates a relative rotation request. The final rotation is the rotation at the
start of the clip plus @racket[delta]. Positive values rotate
counter-clockwise. The target must be an affine Visual. Identity, geometry,
style, position, scale, opacity, drawing order, and group child order are
preserved.
}

@defproc[(rotate-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[rotate-by].
}

@defproc[(scale-to [target (or/c visual? symbol?)]
                   [scale scale-factor?])
         scale-to-request?]{

Creates an absolute scale request. The final x and y scale factors are the
normalized form of @racket[scale]. The target must be an affine Visual.
Identity, geometry, style, position, rotation, opacity, drawing order, and group
child order are preserved.

A built-in group accepts only a uniform endpoint. @racket[scene-play] rejects a
request whose normalized x and y factors differ. For every affine target,
compilation also checks that @racket[visual-with-scale] returns an affine
Visual, preserves identity, and installs the requested endpoint exactly. These
checks occur before timeline sampling.
}

@defproc[(scale-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[scale-to].
}

@defproc[(scale-by [target (or/c visual? symbol?)]
                   [factor scale-factor?])
         scale-by-request?]{

Creates a relative scale request. The start scale is multiplied
componentwise by @racket[factor]. The target must be an affine Visual.
Identity, geometry, style, position, rotation, opacity, drawing order, and group
child order are preserved.

For a built-in group, the computed endpoint must remain uniform.
@racket[scene-play] rejects a relative factor that produces unequal x and y
components. For every affine target, compilation checks the resulting endpoint
through the same @racket[visual-with-scale] protocol rules as
@racket[scale-to].
}

@defproc[(scale-by-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[scale-by].
}

@defproc[(apply-affine [target (or/c visual? symbol? visual-path?)]
                       [map affine2?])
         apply-affine-request?]{

Creates a general affine-map request. At each sampled interior time,
the identity-to-@racket[map] entry-wise interpolation is applied after
@racket[target]'s current outer affine map. The map therefore acts in world
coordinates; it can express shears, reflections, arbitrary linear maps, and
translation in one request.

The target may be a top-level world Visual or an ordinary nested
@racket[visual-path?]. A nested request is rebased through enclosing semantic
affine maps so its requested map still has world-coordinate meaning. The
enclosing map must be invertible; derived Visuals and frame-space overlays are
still rejected during scene compilation. The resulting endpoint is an
@racket[affine-map-visual?], so a later @racket[apply-affine] composes maps
without rasterizing the prior result. Existing movement, rotation, and scale
requests conflict with @racket[apply-affine] for the same target during an
overlapping interval.
}

@defproc[(apply-affine-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request made by
@racket[apply-affine].
}

@defproc[(apply-matrix [target (or/c visual? symbol? visual-path?)]
                       [matrix linear2?])
         apply-affine-request?]{

Convenience form of @racket[apply-affine] for a translation-free linear map
about the world origin.
}

@section[#:tag "pointwise-maps"]{Robust Pointwise Maps}

Pointwise mapping is the nonlinear counterpart of affine mapping. It acts on
world-space points and samples a path before mapping it, so a line
under a nonlinear map becomes a visible curve rather than a chord joining two
transformed endpoints. The exact caller Visual is retained at clip time zero.
Adaptive refinement checks the deviation of a mapped midpoint from its mapped
chord, while a failed map sample can split the result into separate subpaths.
