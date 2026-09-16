#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental
                     animate/slides
                     animate/slides/pict
                     animate/slides/scene
                     animate/slides/render
                     animate/slides/math
                     animate/slides/geometry
                     animate/slides/project))

@title[#:tag "reference-module-boundaries"]{Public Module Boundaries}

@defmodule[#:multi (animate/authoring
                    animate/preview
                    animate/render
                    animate/project
                    animate/experimental
                    animate/slides
                    animate/slides/pict
                    animate/slides/scene
                    animate/slides/render
                    animate/slides/math
                    animate/slides/geometry
                    animate/slides/project)]

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

@itemlist[
 @item{@racketmodname[animate/slides] defines immutable themes, layouts,
       content, slides, clips, beats, and storyboards without rendering.}
 @item{@racketmodname[animate/slides/pict] and
       @racketmodname[animate/slides/scene] convert resolved slide content to
       a static Pict or an ordinary native Scene.}
 @item{@racketmodname[animate/slides/render] and
       @racketmodname[animate/slides/project] provide explicit preparation,
       rendering, and project-source adapters.}
 @item{@racketmodname[animate/slides/math] and
       @racketmodname[animate/slides/geometry] wrap the corresponding Animate
       subsystems as slide content; geometry remains in-process because it has
       no portable preparation codec.}]

@racketmodname[animate/experimental] contains explicit lower-level escape
hatches such as @racket[derived-visual].  Prefer @racket[relation-visual] for
new live dependencies: it declares its inputs and cacheability semantically.

Only the preview implementation initializes GUI support. Bang-suffixed output
operations are intentionally absent from the central @racketmodname[animate]
module.
