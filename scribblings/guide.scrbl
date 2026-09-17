#lang scribble/manual
@title[#:tag "part-guide" #:style '(toc grouper)]{Guide}

Read this part in order for a first animation. Each chapter builds on the terms
and code introduced just before it. The first result is a picture, then a movie;
more advanced layout and project tools follow only when there is a use for them.

Know ordinary Racket already? The slide route starts at @secref["guide-slides"].
It uses a Pict for a still picture and a Scene for a timed animation, as explained
in @secref["guide-getting-started"]. Recipes are independent tasks, not prerequisites.

@local-table-of-contents[]
@include-section["guide/getting-started.scrbl"]
@include-section["guide/rendering-a-video.scrbl"]
@include-section["guide/slides.scrbl"]
@include-section["guide/storyboards.scrbl"]
@include-section["guide/slide-appearance.scrbl"]
@include-section["guide/narration.scrbl"]
@include-section["guide/embedded-content.scrbl"]
@include-section["guide/semantic-continuity.scrbl"]
@include-section["guide/source-programs.scrbl"]
@include-section["guide/interactive-preview.scrbl"]
@include-section["guide/project-planning.scrbl"]
