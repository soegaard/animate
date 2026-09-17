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

@title[#:tag "reference-animation-paths"]{Drawing and morphing paths}

Draw a path or change one path into another with compatible structure.

@declare-exporting[animate #:use-sources (animate/main)]

@defproc[(morph-to [target (or/c path-visual? symbol?)]
                             [destination path-geometry?])
         morph-to-request?]{

Creates a request that interpolates the present path Visual identified by
@racket[target] to @racket[destination]. The destination is local semantic path
geometry, not a destination Visual and not a rendered Pict.

The target must be present when @racket[scene-play] compiles the request. When
@racket[target] is a symbol, the built-in path-Visual requirement is checked at
that time. The target's current path at the beginning of the clip must be
compatible with @racket[destination] according to
@racket[path-geometry-morph-compatible?]. Incompatible structure raises an
exception before the clip is added.

At each sample, @racket[morph-to] uses @racket[path-geometry-lerp] with the
clip's eased progress. It interpolates subpath starts, line endpoints, cubic
control points, and cubic endpoints. It preserves the target's identity,
affine transform, opacity, fill, stroke, stroke width, and drawing position. It
does not copy style or placement from another Visual.

A morph can run at the same time as movement, rotation, scaling, or opacity
fading for the same identity because those requests change different
components. This includes morphing a Visual introduced by @racket[fade-in] or
removed by @racket[fade-out]. A second strict, normalized, or aligned morph,
@racket[create], or @racket[uncreate] for the same identity conflicts because
all of them change the path-geometry component.

Like translation, rotation, and scale, morphing follows the easing result at
the clip endpoint. It has no special structural completion rule. An unusual
easing function that does not map one to one can therefore leave the final
path between the source and destination, or at the source.
}

@defproc[(morph-to-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to].
}

@defproc[(morph-to-normalized
          [target (or/c path-visual? symbol?)]
          [destination path-geometry?])
         morph-to-normalized-request?]{

Creates a request that morphs a present path Visual to @racket[destination]
after applying the limited deterministic normalization described by
@racket[path-geometry-normalize-for-morph]. The destination is local semantic
path geometry, not another Visual and not a Pict.

When @racket[scene-play] compiles the request, it reads the target's current
path and normalizes that path together with @racket[destination]. Compilation
requires the pair to satisfy @racket[path-geometry-morph-normalizable?]. A
subpath-count, closure, or point-only/nonempty mismatch raises an exception
before the clip is added.

At eased progress zero, the exact original source path is used. At eased
progress one, the exact requested @racket[destination] is used. At interior
progress values, the normalized cubic source and destination are interpolated
with @racket[path-geometry-lerp]. This preserves the visible source and
destination figures while allowing stored line-versus-cubic and segment-count
differences supported by the normalizer.

The operation preserves Visual identity, reference position, rotation, scale,
opacity, fill, stroke, stroke width, and drawing order. Movement, rotation,
scaling, and opacity fading may run simultaneously for the same identity. A
strict morph, another normalized or aligned morph, @racket[create], or
@racket[uncreate] conflicts because all of them change path geometry.

Like @racket[morph-to], this request follows the easing result and has no
structural endpoint override. An easing function that returns zero at the clip
endpoint therefore leaves the exact source path. An easing function that
returns one produces the exact requested destination.

This request does not reverse a path, rotate a closed path's starting point,
reorder subpaths, add or remove subpaths, change closure, or invent drawn
segments for a point-only subpath.
}

@defproc[(morph-to-normalized-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[morph-to-normalized].
}

@defproc[(create [visual path-visual?]) create-request?]{

Creates a request that introduces @racket[visual] by revealing a prefix of its
local path from fraction zero through fraction one.

The Visual's identity must be absent from the scene before the play clip. Its
computed local path length must be finite. Line portions use Euclidean length,
and cubic portions use the deterministic approximation documented by
@racket[path-subpath-length]. @racket[scene-play] prepares an
empty-path placeholder with the same identity, style, affine transform, and
opacity at clip start. The complete supplied path is stored at the structural
endpoint.

A @racket[create] request can run with movement, rotation, scaling, and
@racket[fade-to] requests for the same identity because those requests change
different animation components. It conflicts with @racket[morph-to],
@racket[morph-to-normalized], @racket[morph-to-aligned],
@racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], @racket[morph-to-compound-aligned], and @racket[uncreate] because they change path
geometry. It also conflicts with @racket[fade-in] and @racket[fade-out] because
all three operations change scene presence. The complete Visual carried by
@racket[create] supplies the shared start position, rotation, scale, opacity,
style, and path.

Several creation requests in one play clip introduce their Visuals in request
order, in front of Visuals already in the scene.

A zero-length path has no positive interior prefix. It therefore remains empty
at interior samples and is restored to its complete semantic structure at the
structural endpoint. This matters for point-only and explicitly empty paths.
}

@defproc[(create-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[create].
}

@defproc[(uncreate [target (or/c path-visual? symbol?)]) uncreate-request?]{

Creates a request that retracts the visible prefix of a present path Visual
from fraction one toward fraction zero. The target is removed from the scene's
structural endpoint after the play clip completes.

When @racket[target] is a symbol, its path-Visual requirement is checked when
the request is compiled by @racket[scene-play]. A missing target or a target
that is not a built-in path Visual raises an exception. The current path must
also have a finite computed local length. Cubic portions use the same
deterministic approximate length and partial extraction as @racket[create].

Movement, rotation, scaling, and @racket[fade-to] may run at the same time for
the same target. A second @racket[uncreate], @racket[morph-to],
@racket[morph-to-normalized], @racket[morph-to-aligned],
@racket[morph-to-open-aligned], @racket[morph-to-open-compound-aligned], @racket[morph-to-compound-aligned], or same-target @racket[create] conflicts because
all of them change the path-geometry component. Same-target @racket[fade-in] or
@racket[fade-out] also conflicts because those requests change scene presence.

A zero-length path has no positive interior prefix, so it is empty at interior
samples and is removed at the structural endpoint.
}

@defproc[(uncreate-request? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a request created by
@racket[uncreate].
}
