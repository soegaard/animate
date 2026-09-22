#lang scribble/manual

@(require "../version.rkt")

@title[#:tag "animate"]{Animate}

@defmodule[animate]

Animate is a Racket library for making animations and videos. You describe the
objects, give them names, and say how they change over time. The same animation
can produce a still picture, a preview, or a video.

This manual describes version @tt{@|animate-version|} of the checked-out source,
at implementation stage @tt{@(symbol->string animate-stage)}.
Examples use ordinary Racket. You do not need a special language.

@bold{Choose a starting point}

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Part} @bold{Use it to})
  (list @secref["part-concepts"] "Understand scenes, time, layouts, and identity.")
  (list @secref["part-cookbook"] "Find a short solution to a particular task.")
  (list @secref["part-guide"] "Make an animation from start to finish.")
  (list @secref["part-complete-examples"] "Study whole programs and frames from their animations.")
  (list @secref["part-reference"] "Look up names, arguments, results, and limits."))]

New to Animate? Start with @secref["guide-getting-started"]. It makes one moving
circle. Continue through the Guide to save a movie, add slides, and use richer
content. The slide route starts at @secref["guide-slides"]; its only Animate
prerequisites are the Scene and Pict introduced in the Quick Start.

The Cookbook is for returning to a particular task.
@secref["part-complete-examples"] shows whole source programs beside their
results. The Reference keeps complete contracts separate from the learning path.

Beyond the first circle, @secref["guide-objects"] teaches groups, timing,
and graphs. Use @secref["reference-find-task"] to find a task or API name,
and @secref["concept-words-values"] to distinguish similar terms.

@table-of-contents[]

@include-section["concepts.scrbl"]
@include-section["cookbook.scrbl"]
@include-section["guide.scrbl"]
@include-section["complete-examples.scrbl"]
@include-section["reference.scrbl"]
