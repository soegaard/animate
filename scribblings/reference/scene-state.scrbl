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

@title[#:tag "scene-state"]{Scene states}

@declare-exporting[animate #:use-sources (animate/main)]

Scene-state values are immutable. Their raw constructor and fields are not
part of the public API.

@defproc[(scene-state? [value any/c]) boolean?]{

Returns @racket[#t] when @racket[value] is a scene-state value.
}

@defthing[empty-scene-state scene-state?]{

An empty scene state with no top-level Visuals, no named semantic values, and an empty drawing order.
}

@defproc[(scene-state-count [state scene-state?])
         exact-nonnegative-integer?]{

Returns the number of top-level Visuals in @racket[state]. A group counts as
one top-level Visual regardless of the number of descendants it contains. A
derived definition likewise counts as one top-level Visual.
}

@defproc[(scene-state-has? [state scene-state?]
                           [target (or/c visual? symbol? visual-path?)])
         boolean?]{

Returns @racket[#t] when @racket[state] contains the addressed Visual. A Visual
argument is resolved through @racket[visual-id]; a @racket[visual-path?] follows
built-in group children. Frame-space Visuals are not valid @racket[camera-follow]
targets.
}

@defproc[(scene-state-ref [state scene-state?]
                          [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the stored Visual identified by @racket[target]. A nested path returns
its locally stored child, without inheriting parent transforms. Raises an
exception when the identity is not present. For a derived Visual this returns the persistent
@racket[derived-visual?] definition rather than evaluating its resolver; use
@racket[scene-state-resolved-ref] when concrete geometry is required.
}

@defproc[(scene-state-visuals-in-drawing-order [state scene-state?])
         (listof visual?)]{

Returns the stored top-level Visuals in back-to-front drawing order. The first
Visual is painted first. The last Visual is painted on top. A group's separate
child order is available through @racket[group-visual-children]. Derived entries
remain persistent @racket[derived-visual?] definitions in this raw list; use
@racket[scene-state-resolved-visuals-in-drawing-order] for concrete rendering
values.
}

@defproc[(scene-state-resolved-ref
          [state scene-state?]
          [target (or/c visual? symbol? visual-path?)])
         visual?]{

Returns the concrete addressed Visual for @racket[target] in @racket[state].
Ordinary Visuals are returned unchanged. A @racket[derived-visual?] is evaluated
against a read-only context built from this exact immutable state. The resolver may recursively request other top-level Visuals. Dependency
cycles are rejected, and each result is validated for concrete-Visual type and
identity preservation.
}

@defproc[(scene-state-resolved-visuals-in-drawing-order
          [state scene-state?])
         (listof visual?)]{

Returns concrete top-level Visuals in significant back-to-front order,
resolving every derived definition against @racket[state]. All entries share one
local dependency-resolution traversal, so shared dependencies resolve
consistently even when the dependent appears before its dependency in drawing
order. The Pict scene adapter uses this operation without mutating stored state.
}

@defproc[(scene-state-value-has? [state scene-state?]
                                 [id (or/c symbol? scene-parameter?)]) boolean?]{
Returns @racket[#t] when @racket[state] contains the named semantic value
identified by @racket[id]. Named values are semantic state and are not rendered.
Value and Visual identifiers share one global scene namespace.
}

@defproc[(scene-state-value-ref [state scene-state?]
                                 [id (or/c symbol? scene-parameter?)]) any/c]{
Returns the named interpolable semantic value identified by @racket[id]. Raises an exception
when the value is absent.
}
