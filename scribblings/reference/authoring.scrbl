#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate
                     animate/authoring))

@section{Source Programs and Authored Timelines}

@declare-exporting[animate/authoring]

@racketmodname[animate/authoring] adds source-addressable authoring metadata
to immutable @racket[scene?] values.  It remains headless: compiling a program
does not open a preview window or render a frame.

@subsection{Named source blocks}

@defform[(define-scene-program program-id
            #:initial initial-scene-expr
            block-expr ...)]{

Defines @racket[program-id] as an immutable @racket[scene-program?].  The
initial expression evaluates to a Scene; each @racket[scene-block] receives the
prefix Scene built by the preceding block and returns a new Scene.  Block IDs
must be distinct.  The macro retains source locations for reload diagnostics
and preview navigation.
}

@defform[(scene-block block-id (input-id)
            (~optional (~seq #:assets (asset-path ...)))
            (~optional (~seq #:version version-datum))
            body-expr ...+)]{

Declares one block within @racket[define-scene-program].  The binding
@racket[input-id] is the immutable prefix Scene.  @racket[#:assets] lists
source files that invalidate the block on reload, and @racket[#:version] is a
literal author-controlled invalidation key.  A @racket[scene-block] is syntax,
not a standalone runtime constructor.
}

@racketblock[
(define-scene-program derivative
  #:initial (scene-add (make-scene) (plain-text 'title "Derivative"))
  (scene-block setup (scene)
    (scene-wait scene 1))
  (scene-block reveal (scene) #:version 'v1
    (scene-play scene (fade-in 'title) #:duration 1)))]

@defproc[(make-scene-program [id symbol?]
                             [initial-builder (-> scene?)]
                             [blocks (listof scene-block-spec?)])
         scene-program?]{

Constructs a source program without macro source locations.  Use it when the
program is generated as data; ordinary source files should prefer
@racket[define-scene-program].
}

@defproc[(make-scene-block [id symbol?]
                           [builder (-> scene? scene?)]
                           [#:source-location location (or/c #f source-location?) #f]
                           [#:source-fingerprint fingerprint (or/c #f bytes? string?) #f]
                           [#:assets assets (listof path-string?) '()]
                           [#:version version any/c #f])
         scene-block-spec?]{

Constructs one program block.  This lower-level form is useful for program
generators; normal source files should use the macro form above.
}

@defproc[(compile-scene-program [program scene-program?]
                                [#:generation generation exact-nonnegative-integer? 0])
         compiled-scene-program?]{

Evaluates the initial builder and each block into an immutable compiled program.
No renderer, GUI, or file operation is involved.
}

@defproc[(scene-program? [value any/c]) boolean?]{Recognizes source programs.}
@defproc[(scene-block-spec? [value any/c]) boolean?]{Recognizes declarative source blocks.}
@defproc[(compiled-scene-program? [value any/c]) boolean?]{Recognizes compiled source programs.}
@defproc[(source-location? [value any/c]) boolean?]{Recognizes retained source-location metadata.}

@bold{Limitation:} source-program builders are arbitrary procedures.  They are
safe for an in-memory preview, but persistent project caches and subprocess
previewing need a module-backed project source or an explicit cache key.
