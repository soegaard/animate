#lang scribble/manual

@title[#:tag "part-cookbook" #:style '(toc grouper)]{Cookbook}

Pick a task. Short Racket recipes on these pages are executable documentation:
Scribble evaluates the code while building the manual and shows or checks the
result. Hidden setup is used only for imports and other boilerplate that is not
part of the task.

Complete source files are kept only when the file boundary, several related
bindings, or an external toolchain is part of the example. Those programs live
under @filepath{scribblings/examples/} and are called out explicitly.

A recipe is not a replacement for the @secref["part-reference"]. Use the
Reference when you need every option, contract, or restriction.

@local-table-of-contents[]
@include-section["cookbook/native-tasks.scrbl"]
@include-section["cookbook/plots-and-camera.scrbl"]
@include-section["cookbook/themed-mathematics.scrbl"]
@include-section["cookbook/slide-tasks.scrbl"]
@include-section["cookbook/transitions.scrbl"]
@include-section["cookbook/3d-tasks.scrbl"]
@include-section["cookbook/render-and-review.scrbl"]
@include-section["cookbook/canonical-examples.scrbl"]
