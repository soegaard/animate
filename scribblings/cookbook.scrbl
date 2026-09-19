#lang scribble/manual

@title[#:tag "part-cookbook" #:style '(toc grouper)]{Cookbook}

Pick a task. The short recipes with displayed results use executable Scribble
examples: the manual build evaluates their code and shows or checks the result.
Hidden setup supplies imports and other boilerplate. The worked-example
chapters also contain source-only code fragments and commands for complete
programs; those blocks are not evaluated by the manual build.

Recipes stay short. For whole source files, explanations of their structure,
render commands, and selected frames, see @secref["part-complete-examples"].
A recipe still uses an external file when its module or toolchain is part of
the task.

A recipe is not a replacement for the @secref["part-reference"]. Use the
Reference when you need every option, contract, or restriction.

@local-table-of-contents[]
@include-section["cookbook/native-tasks.scrbl"]
@include-section["cookbook/plots-and-camera.scrbl"]
@include-section["cookbook/themed-mathematics.scrbl"]
@include-section["cookbook/slide-tasks.scrbl"]
@include-section["cookbook/transitions.scrbl"]
@include-section["cookbook/appearance-and-text-effects.scrbl"]
@include-section["cookbook/camera-views-and-overlays.scrbl"]
@include-section["cookbook/animation-timing-recipes.scrbl"]
@include-section["cookbook/path-motion-recipes.scrbl"]
@include-section["cookbook/path-correspondence-recipes.scrbl"]
@include-section["cookbook/topology-morph-recipes.scrbl"]
@include-section["cookbook/plot-styling-recipes.scrbl"]
@include-section["cookbook/3d-tasks.scrbl"]
@include-section["cookbook/render-and-review.scrbl"]
