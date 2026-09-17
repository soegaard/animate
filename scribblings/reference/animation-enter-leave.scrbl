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

@title[#:tag "reference-animation-enter-leave"]{Adding, revealing, and removing objects}

These requests introduce or remove objects, or reveal existing content.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(fade-in [visual (and/c visual? opacity-visual?)])
         fade-in-request?]{

Creates a request that introduces the complete supplied @racket[visual] by
increasing global opacity from zero to the Visual's own semantic opacity.

The Visual's identity must be absent from the scene before the play clip.
@racket[scene-play] adds a placeholder with the same identity, position,
geometry, affine transform, style, and drawing position, but with opacity zero.
Several fade-in requests add their placeholders in request order, in front of
Visuals already present. When the supplied Visual is a group, the complete child
tree is introduced as one top-level Visual.

All requests in the play clip compile against the prepared shared start state.
Movement, rotation, scaling, and path morphing can therefore target a Visual
introduced by @racket[fade-in], even when those requests appear before the
fade-in request. These operations change different components.

At interior samples, opacity is interpolated from zero to the opacity stored in
@racket[visual]. At the structural endpoint, the supplied opacity is installed
regardless of the easing result. This guarantees that the complete Visual is
present after the clip. An unusual easing procedure can therefore cause a jump
at the exact clip boundary. A Visual whose supplied opacity is zero is
introduced structurally but remains invisible.

A fade-in changes both opacity and scene presence. It conflicts with another
same-target opacity request and with another same-target introduction or
removal request. In particular, @racket[fade-in] cannot be combined with
same-target @racket[create], @racket[uncreate], or @racket[fade-out].
}

@defproc[(fade-in-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[fade-in].
}

@defproc[(fade-out
          [target (or/c symbol? (and/c visual? opacity-visual?))])
         fade-out-request?]{

Creates a request that lowers a present Visual's global opacity from its current
value to zero and then removes the Visual from the scene.

When @racket[target] is a symbol, @racket[scene-play] checks that the current
Visual implements the opacity protocol and returns a valid opacity. A missing
target or a Visual without semantic opacity raises an exception.

Movement, rotation, scaling, and path morphing may run at the same time for the
same identity. The Visual remains present at interior samples, so those
components continue to update while it fades. At the structural endpoint, the
Visual is removed regardless of the easing result. A group and its complete
child tree are removed as one top-level Visual. An unusual easing procedure can
therefore leave it visibly opaque just before the boundary and absent at
the boundary.

A fade-out changes both opacity and scene presence. It conflicts with another
same-target opacity request and with another same-target introduction or
removal request. In particular, it cannot be combined with same-target
@racket[fade-in], @racket[create], @racket[uncreate], or @racket[fade-to].
}

@defproc[(fade-out-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[fade-out].
}

@defproc[(enter
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [#:translation-offset translation-offset vec2? origin]
          [#:scale-factor scale-factor any/c 1]
          [#:rotation-offset rotation-offset finite-real? 0]
          [#:opacity-factor opacity-factor (real-in 0 1) 0]
          [#:about about (or/c 'center 'reference vec2?) 'center])
         enter-request?]{

Introduces an absent affine, opacity-aware @racket[visual] from a relative
appearance. The translation offset is in the Visual's local reference frame;
the scale factor is a nonnegative finite real or a @racket[vec2] with
nonnegative components; rotation is additive; and opacity is the authored
opacity multiplied by @racket[opacity-factor]. Consequently, the default
appearance is invisible but the endpoint retains the Visual's authored opacity
rather than assuming opacity one.

@racket[#:about] is @racket['center], @racket['reference], or an explicit local
@racket[vec2]. In this first affine implementation, the named choices both
mean the Visual's stable local reference origin; the explicit point supplies a
distinct pivot without renderer-measured layout. A zero scale factor denotes a
semantic collapse. Since ordinary affine Visuals require positive authored
scales, only interior samples use a small private positive scale; the
invisible start and exact final Visual remain unambiguous.

At its local start, the target identity is present with the relative
appearance. At its exact local endpoint, the supplied @racket[visual] is
restored regardless of easing. @racket[enter] writes scene presence and only
the affine/opacity components whose factor or offset differs from identity.
Thus an opacity-only entrance can run alongside a same-target rotation, while
two requests that both change translation conflict normally. The target must
be absent at the local start.
}

@defproc[(enter-request? [value any/c]) boolean?]{
Recognizes an @racket[enter] request.
}

@defproc[(leave
          [target (or/c visual? symbol? visual-path?)]
          [#:translation-offset translation-offset vec2? origin]
          [#:scale-factor scale-factor any/c 1]
          [#:rotation-offset rotation-offset finite-real? 0]
          [#:opacity-factor opacity-factor (real-in 0 1) 0]
          [#:about about (or/c 'center 'reference vec2?) 'center]
          [#:remove? remove? boolean? #t])
         leave-request?]{

Transforms a present affine, opacity-aware target toward the same relative
appearance used by @racket[enter]. A direct Visual target is validated at
construction; a symbol or nested Visual path is resolved and validated against
the exact local start state. With the default @racket[#:remove? #t], the target
remains present at interior samples and is absent exactly at the local endpoint.
With @racket[#:remove? #f], it retains its identity and the concrete relative
final appearance.

Only changed affine/opacity components are written; scene presence is reserved
only when removal is requested. This keeps, for example, an opacity-only leave
compatible with a same-target movement while preserving ordinary conflict
checks for components it changes. No endpoint relies on a prior sampled frame.
}

@defproc[(leave-request? [value any/c]) boolean?]{
Recognizes a @racket[leave] request.
}

@defproc[(reveal-front? [value any/c]) boolean?]{
Recognizes an immutable local hard-clip front constructed by
@racket[linear-reveal-front] or @racket[radial-reveal-front]. A front contains
no scene or renderer state.
}

@defproc[(reveal-front-path
          [front reveal-front?]
          [box layout-box?]
          [progress (real-in 0 1)])
         path-geometry?]{

Returns the pure local clip path for a frozen @racket[box] at
@racket[progress]. It is useful for deterministic testing and custom semantic
clip composition. A zero-area front returns @racket[empty-path-geometry], not
a degenerate polygon.
}

@defproc[(reveal-in
          [visual (and/c visual? affine-visual? opacity-visual?)]
          [front reveal-front?])
         reveal-in-request?]{

Introduces an absent Visual behind a local hard clip. At the local start, the
target identity is present but its clip is empty. When the play clip compiles,
the Pict layout adapter measures the Visual's untransformed local layout once;
all later samples use that immutable box and the immutable @racket[front]. At
the exact endpoint, the supplied @racket[visual] is restored and the temporary
clip wrapper is gone.

The effect clips local geometry and then applies the target's ordinary affine
placement and opacity. It can therefore run with same-target movement,
rotation, scaling, and opacity animation. It reserves scene presence and the
clip-replaced style, path, formula, and pointwise-map components, which are
rejected when overlapping rather than being made request-order dependent.
Hard clipping currently requires the ordinary Pict rendering path.
}

@defproc[(reveal-in-request? [value any/c]) boolean?]{
Recognizes a @racket[reveal-in] request.
}

@defproc[(reveal-out
          [target (or/c visual? symbol? visual-path?)]
          [front reveal-front?])
         reveal-out-request?]{

Clips a present target with @racket[front] in reverse. The exact source is
visible at local time zero; interior samples use progressively smaller local
clips; and the target is removed exactly at the structural endpoint. Direct
Visual targets are validated immediately, while symbols and nested visual paths
are resolved at the clip's local start. Layout freezing, component composition,
and the Pict-renderer requirement are the same as for @racket[reveal-in].
}

@defproc[(reveal-out-request? [value any/c]) boolean?]{
Recognizes a @racket[reveal-out] request.
}

@defproc[(shrink-out
          [target (or/c visual? symbol? visual-path?)]
          [#:about about (or/c 'center 'reference vec2?) 'center])
         leave-request?]{

Returns a @racket[leave] request with zero scale factor and unchanged opacity.
It collapses toward @racket[about] at interior samples and removes the target
exactly at completion.
}

@defproc[(reveal-subsets
          [targets (or/c list? vector?)]
          [make-entry procedure?]
          [#:order order (or/c 'forward 'reverse animation-order?) 'forward]
          [#:lag-ratio lag-ratio (and/c finite-real? (>=/c 0)) 1])
         lagged-start-animation-request?]{

Eagerly maps a one- or two-argument entry factory over a nonempty list or
vector, with the same source-order evaluation and original zero-based indexes
as @racket[eager-stagger-map]. The result is an ordinary @racket[lagged-start]
composition, not a specialized renderer effect.

Every produced entry remains after completion. One-at-a-time presentation has
its own explicit @racket[crossfade-subsets] timing model rather than an ambiguous
boolean option on a lagged composition.
}
