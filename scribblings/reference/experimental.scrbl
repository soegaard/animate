#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate
                     animate/experimental))

@title[#:tag "derived-visuals"]{Experimental Derived Visuals}

@declare-exporting[animate/experimental #:use-sources (animate/experimental)]

@racketmodname[animate/experimental] contains lower-level escape hatches.  New
scene dependencies should normally use @racket[relation-visual] from
@racketmodname[animate], which declares its inputs and cacheability.  A derived
Visual remains useful when an author intentionally needs a pure arbitrary
resolver over a sampled scene state.

@defproc[(derived-visual [template visual?]
                          [resolver (-> derived-context? visual? visual?)])
         derived-visual?]{

Creates an immutable Visual definition driven by a pure resolver.  The concrete
@racket[template] supplies identity and ordinary affine placement.  At each
sample the resolver receives a read-only context and must return a non-derived
Visual with the same identity.  Direct animation of a derived Visual is not
valid; animate the named values or ordinary inputs on which it depends.
}

@defproc[(derived-visual? [value any/c]) boolean?]{Recognizes a derived Visual.}
@defproc[(derived-context? [value any/c]) boolean?]{Recognizes a derived resolver context.}

@defproc[(derived-context-value-has? [context derived-context?]
                                     [id (or/c symbol? scene-parameter?)])
         boolean?]{
Reports whether the sampled state has the requested named semantic value.
}

@defproc[(derived-context-value-ref [context derived-context?]
                                    [id (or/c symbol? scene-parameter?)])
         any/c]{
Returns the requested named sampled value, raising an exception when absent.
}

@defproc[(derived-context-visual-has? [context derived-context?]
                                      [id (or/c symbol? visual-path?)])
         boolean?]{
Reports whether a top-level or nested Visual path is present without forcing a
derived dependency to resolve.
}

@defproc[(derived-context-visual-ref [context derived-context?]
                                     [id (or/c symbol? visual-path?)])
         visual?]{

Resolves the requested Visual in the current sampled state.  Nested values are
returned in composed world coordinates.  Cycles are rejected; successful
results are memoized only within this one resolution traversal.
}

@bold{Limitation:} a derived resolver is an arbitrary procedure, so it is
memory-only for persistent caching unless its enclosing project supplies an
explicit cache identity.
