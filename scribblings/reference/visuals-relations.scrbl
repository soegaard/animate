#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate/main
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@(require "../private/reference-examples.rkt")

@; Animate Visuals reference revision R1 (20260919).
@title[#:tag "ref-visuals-relations"]{Relations and Live Layout}


@declare-exporting[animate/main]


A relation records dependencies and recomputes concrete geometry from a
sampled scene state. Choose semantic resolution for model coordinates and
layout resolution for renderer-measured anchors or boxes. Following helpers
are relations too; they do not require a mutable frame updater.

See also @secref["ref-visuals-protocols"], @secref["ref-visuals-annotations"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "relation-visuals"]{First-Class Relation Visuals}

@declare-exporting[animate #:use-sources (animate/main)]

A relation is an immutable Visual whose concrete geometry is recomputed from
explicit dependencies in each sampled scene state.  No relation
uses a mutable updater or needs the preceding frame.

@defproc[(relation-visual
          [template visual?]
          [#:depends-on dependencies (listof relation-dependency?) '()]
          [#:phase phase (or/c 'semantic 'layout) 'semantic]
          [#:structure structure (or/c 'root-only 'fixed) 'root-only]
          [#:space space (or/c 'world 'local) 'world]
          [#:cache-key cache-key any/c #f]
          [resolver (-> relation-context? visual? visual?)])
         relation-visual?]{

Creates a relation with the stable identity of @racket[template]. The resolver
receives a read-only @racket[relation-context?] and a local template, and must
return one concrete Visual with the same identity. Every value, Visual,
renderer-anchor, or semantic selection read through the context must be named
in @racket[dependencies]; undeclared reads fail descriptively.

The ordinary movement, rotation, scale, opacity, fill, stroke, and stroke-width
controls form an outer envelope. They are applied after the resolver has
computed the current geometry, so a relation may be animated concurrently with
its own changing dependencies. A requested style must be supported by both the
template and the concrete result. A @racket['fixed] relation preserves the
template's complete child-ID tree and may expose nested paths; a
@racket['root-only] relation deliberately exposes only its root ID.

A @racket['semantic] relation is resolved from model data. A @racket['layout]
relation may use @racket[relation-context-anchor-ref],
@racket[relation-context-layout-box], or selection boxes after the active
renderer has measured its targets. Layout relations are currently top-level
only, and their measurements are complete Pict boxes rather than tight visible
outlines.
}

@defproc[(relation-context-layout-box [context relation-context?]
                                      [visual visual?])
         layout-box?]{

Measures one resolver-local concrete Visual in the active renderer/camera
configuration. This operation is available only to layout relations. It is
intended for relations such as @racket[follow-anchor] that must align one anchor of
their own content to an anchor of another Visual.
}

@defproc[(relation-visual? [value any/c]) boolean?]{
Recognizes an immutable relation Visual.
}

@defproc[(relation-visual-dependencies [relation relation-visual?])
         (listof relation-dependency?)]{
Returns the relation's explicitly declared dependencies in author order.
}

@defproc[(relation-visual-cacheability [relation relation-visual?])
         (or/c 'serializable 'explicit-key 'disabled)]{
Reports whether the resolver can participate in a persistent cache. Built-in
transparent specifications are @racket['serializable]; an author procedure with
@racket[#:cache-key] is @racket['explicit-key]; an opaque procedure is
@racket['disabled].
}

@defproc[(relation-dependency? [value any/c]) boolean?]{
Recognizes a declared value, Visual, anchor, or selection dependency.
}

@defproc[(relation-context? [value any/c]) boolean?]{
Recognizes the read-only context supplied to a relation resolver.
}

@defproc[(relation-context-anchor-ref [context relation-context?]
                                      [target (or/c visual? symbol? visual-path?)]
                                      [anchor symbol?])
         vec2?]{
Returns a renderer-measured anchor for a layout relation after recording the
corresponding declared @racket[anchor-dependency].
}

@defproc[(value-dependency [target (or/c symbol? scene-parameter?)])
         relation-dependency?]{Declares one sampled scalar/value input.}

@defproc[(visual-dependency [target (or/c visual? symbol? visual-path?)])
         relation-dependency?]{Declares one semantic Visual input.}

@defproc[(anchor-dependency [target (or/c visual? symbol? visual-path?)]
                            [anchor symbol?])
         relation-dependency?]{Declares one renderer-measured anchor input.}

@defproc[(selection-dependency [selection visual-selection?])
         relation-dependency?]{Declares one semantic selection input.}

@defproc[(scene-validate-relations [state scene-state?]) immutable-hash?]{

Checks declared relation dependencies and reports missing targets or deterministic
dependency cycles before rendering.
}

@defproc[(scene-relation-report [state scene-state?]
                                [target (or/c #f visual? symbol? visual-path?) #f])
         any/c]{

Returns deterministic relation-resolution report data without invoking author
resolver procedures. It records full path, drawing order, phase, structure,
declared dependencies, cacheability, and warnings. Library-owned serializable
specifications are cacheable; generic resolver procedures remain opaque unless
the author supplies @racket[#:cache-key].
}

@defproc[(scene-relation-sample-report
          [state scene-state?]
          [target (or/c #f visual? symbol? visual-path?) #f])
         any/c]{

Returns the same report shape, but additionally resolves each selected
@racket['semantic] relation once for this sampled state. The report's
@racket['used-dependencies] and @racket['unused-dependencies] fields then
distinguish declared inputs that the resolver actually read from declared
inputs it did not read at this instant. This is an opt-in diagnostic operation:
it can run the author's resolver procedure, but does not alter the immutable
scene state or renderer cache.

For a @racket['layout] relation those fields are @racket[#f]. Determining its
actual reads requires the active renderer's measured layout boxes, which this
headless report intentionally does not invent.
}

Built-in @racket[line-between], @racket[arrow-between], @racket[ray-from],
@racket[parameter-display], and @racket[follow-anchor] use serializable relation
specifications. The live
angle, brace, and curved-arrow constructors use generic relations because their
builder procedure is author-specific; therefore they deliberately do not claim
automatic persistent-cache reuse.

@defproc[(follow-anchor
          [content visual?]
          [target (or/c visual? symbol? visual-path?)]
          [#:offset offset vec2? origin]
          [#:target-anchor target-anchor
                           (or/c 'bottom-left 'bottom 'bottom-right
                                 'left 'center 'right
                                 'top-left 'top 'top-right)
                           'center]
          [#:self-anchor self-anchor
                         (or/c 'bottom-left 'bottom 'bottom-right
                               'left 'center 'right
                               'top-left 'top 'top-right)
                         'center])
         relation-visual?]{

Creates one world-space relation whose selected content anchor follows the
selected sampled anchor of @racket[target], plus @racket[offset].
@racket[target] may be a top-level Visual, its symbol identity, or a nested
path. The default centre-to-centre form is a semantic relation: it follows the
target's sampled reference point without invoking a renderer. Choosing a
non-centre target or content anchor creates a layout relation, which measures
the relevant Pict box in the active camera and renderer configuration. Both
forms follow target motion without frame-mutating callbacks.

The content must be a concrete, non-frame-space Visual, and content and target
must have distinct identities. Attachments may be animated through the normal
relation envelope. One attachment may target another when the resulting
relation graph is acyclic; they neither avoid other labels nor inherit target
rotation. Layout attachments are top-level and renderer-dependent; a semantic
centre attachment can be queried directly from a sampled scene state.
}

@; visuals-reference-r1 example: relations-1
An attachment is a relation with an inspectable built-in specification.

@examples[#:eval reference-eval
  (define attachment
    (follow-anchor (circle #:id 'follower) 'target #:offset (vec2 1 0)))
  (eval:check (relation-visual? attachment) #t)
  (eval:check (relation-visual-cacheability attachment) 'serializable)
]


@subsection[#:tag "live-layout"]{Acyclic Live Layout}

@declare-exporting[animate/main]

The live-layout procedures give renderer-aware attachments concise
relationship names.
Their relation graph is resolved from a concrete target outward at each render.
A direct or indirect cycle raises an exception; no prior frame is consulted.

@defproc[(follow-above [content visual?]
                     [target (or/c visual? symbol? visual-path?)]
                     [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's bottom anchor at the target's top anchor plus @racket[gap].
}

@defproc[(follow-below [content visual?]
                     [target (or/c visual? symbol? visual-path?)]
                     [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's top anchor at the target's bottom anchor minus @racket[gap].
}

@defproc[(follow-left-of [content visual?]
                        [target (or/c visual? symbol? visual-path?)]
                        [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's right anchor at the target's left anchor minus @racket[gap].
}

@defproc[(follow-right-of [content visual?]
                         [target (or/c visual? symbol? visual-path?)]
                         [#:gap gap (and/c finite-real? (>=/c 0)) 0])
         relation-visual?]{

Places the content's left anchor at the target's right anchor plus @racket[gap].
}

@(close-eval reference-eval)
