#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
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
          "../version.rkt")

@(define release-label
   (format "~a — version ~a" animate-stage animate-version))

@title[#:tag "animate"]{Visual Animation — @|release-label|}

@defmodule[animate]

Visual Animation is a small, immutable animation library for Racket. It is an early step toward a Manim-like system. The library keeps
semantic scene data separate from Pict rendering and file output.

The public API in this manual is version @tt{@|animate-version|}. This is a
prototype, so the repository improves names and behavior directly: internal
callers, examples, tests, and documentation are updated together, and obsolete
spellings are removed rather than retained as compatibility aliases.

@table-of-contents[]

@include-section["guide/getting-started.scrbl"]
@include-section["guide/source-programs.scrbl"]
@include-section["guide/interactive-preview.scrbl"]
@include-section["guide/rendering-a-video.scrbl"]
@include-section["guide/project-planning.scrbl"]
@include-section["concepts/immutable-scenes.scrbl"]
@include-section["concepts/formula-source-maps.scrbl"]
@include-section["concepts/relation-phases.scrbl"]
@include-section["reference/module-boundaries.scrbl"]
@include-section["reference/authoring.scrbl"]
@include-section["reference/preview.scrbl"]
@include-section["reference/project.scrbl"]
@include-section["cookbook/canonical-examples.scrbl"]


@include-section["guide/package-source.scrbl"]
@include-section["reference/scene.scrbl"]
@include-section["reference/geometry-and-plots.scrbl"]
@include-section["reference/visuals-and-relations.scrbl"]
@include-section["reference/experimental.scrbl"]
@include-section["reference/rendering.scrbl"]
@include-section["cookbook/reference-recipes.scrbl"]
