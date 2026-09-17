#lang scribble/manual

@title[#:tag "part-cookbook" #:style '(toc grouper)]{Cookbook}

Pick a task. Each new recipe gives the required imports, a small example, the
expected result, and a link to more detail. Complete programs are also stored in
@filepath{scribblings/examples/}; the displayed code is read from those files.

A recipe is not a replacement for the @secref["part-reference"]. Use the
reference when you need all the options or exact restrictions.

@local-table-of-contents[]
@include-section["cookbook/native-tasks.scrbl"]
@include-section["cookbook/3d-tasks.scrbl"]

@include-section["cookbook/slide-tasks.scrbl"]
@include-section["cookbook/transitions.scrbl"]
@include-section["cookbook/render-and-review.scrbl"]
@include-section["cookbook/plots-and-camera.scrbl"]
@include-section["cookbook/themed-mathematics.scrbl"]
@include-section["cookbook/canonical-examples.scrbl"]
