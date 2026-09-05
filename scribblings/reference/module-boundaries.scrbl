#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental))

@section{Public Module Boundaries}

@defmodule[#:multi (animate/authoring
                    animate/preview
                    animate/render
                    animate/project
                    animate/experimental)]

@itemlist[
 @item{@racketmodname[animate] defines scenes, Visuals, animation requests,
       formulas, relations, geometry, cameras, and pure sampling.}
 @item{@racketmodname[animate/authoring] defines source programs and authored
       timeline declarations.}
 @item{@racketmodname[animate/preview] defines sessions, transport, reload,
       inspection, and the preview REPL.}
 @item{@racketmodname[animate/render] defines PNG output, section rendering,
       encoding, subtitles, media assembly, and effectful project execution.}
 @item{@racketmodname[animate/project] defines immutable source, render,
       preview, output, encoder, and cache declarations plus pure plans.}]

@racketmodname[animate/experimental] contains explicit lower-level escape
hatches such as @racket[derived-visual].  Prefer @racket[relation-visual] for
new live dependencies: it declares its inputs and cacheability semantically.

Only the preview implementation initializes GUI support. Bang-suffixed output
operations are intentionally absent from the central @racketmodname[animate]
module.
