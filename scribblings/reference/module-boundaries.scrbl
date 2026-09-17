#lang scribble/manual
@(require (for-label racket/base animate animate/authoring animate/preview
                     animate/render animate/project animate/experimental
                     animate/slides animate/slides/pict animate/slides/scene
                     animate/slides/render animate/slides/math
                     animate/slides/geometry animate/slides/project
                     animate/slides/gallery))

@title[#:tag "reference-module-boundaries"]{Modules to require}

@defmodule[#:multi (animate/authoring animate/preview animate/render
                    animate/project animate/experimental animate/slides
                    animate/slides/pict animate/slides/scene animate/slides/render
                    animate/slides/math animate/slides/geometry
                    animate/slides/project animate/slides/gallery)]

Choose the module for the task. You do not need to import every adapter merely
to write a slide description. The supported Animate slide combinations use
ordinary, unprefixed imports.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Module} @bold{Use it for})
  (list @racketmodname[animate] "Visuals, Scenes, cameras, animation requests, and sampling.")
  (list @racketmodname[animate/authoring] "Source-program blocks and authored timelines.")
  (list @racketmodname[animate/preview] "Interactive preview, reload, and inspection.")
  (list @racketmodname[animate/project] "Source, render, output, encoder, and cache declarations.")
  (list @racketmodname[animate/render] "PNG files, video encoding, media assembly, and project execution.")
  (list @racketmodname[animate/slides] "Content, layouts, themes, slide clips, and storyboards.")
  (list @racketmodname[animate/slides/pict] "Static pictures and sampled Picts.")
  (list @racketmodname[animate/slides/scene] "Native Scenes/timelines and native content wrappers.")
  (list @racketmodname[animate/slides/render] "Slide preparation and match-plan inspection.")
  (list @racketmodname[animate/slides/math] "Mathematical presentation plans as slide content.")
  (list @racketmodname[animate/slides/geometry] "Geometry programs/timelines as slide content.")
  (list @racketmodname[animate/slides/project] "Restartable storyboard sources for render projects.")
  (list @racketmodname[animate/slides/gallery] "Gallery entries and selected gallery storyboards."))]

@racketmodname[animate/slides/render] prepares content; despite its name, it does
not encode the final video. File output and project execution belong to
@racketmodname[animate/render]. Geometry in slides uses parent-prepared data
when a project sends work to subprocesses.

Use @racketmodname[animate/experimental] only for lower-level extensions such as
@racket[derived-visual]. For an object that follows other scene values, prefer
@racket[relation-visual], which declares its inputs explicitly.

Importing the description modules should not open a preview window or render a
movie. Keep calls that do so in an explicit runner. See
@secref["concept-overview"] and @secref["guide-slides"].
