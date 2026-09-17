#lang scribble/manual
@title[#:tag "part-guide" #:style '(toc grouper)]{Guide}

Start with the Quick Start and saving a video. Then choose a route.
Within a route, each lesson introduces what the next example needs.
You do not need to read the slide lessons to make a native 2D animation.

Know ordinary Racket already? The slide route starts at @secref["guide-slides"].
It uses a Pict for a still picture and a Scene for a timed animation, as explained
in @secref["guide-getting-started"]. Recipes are independent tasks, not prerequisites.

The 3D route begins at @secref["guide-3d-picture"]. Its first two chapters
need only the Quick Start. The third combines 3D with text and, optionally,
the slide and embedded-content tools introduced above.

@bold{Choose a route}
@tabular[#:sep @hspace[2]
 (list
  (list @bold{Goal} @bold{Read next})
  (list "Animate a diagram or graph" @secref["guide-objects"])
  (list "Build a slide-based lesson" @secref["guide-slides"])
  (list "Make a 3D animation" @secref["guide-3d-picture"])
  (list "Edit and preview a source program" @secref["guide-source-programs"])
  (list "Diagnose a wrong result" @secref["guide-troubleshooting"]))]

The Concepts part is a place to look up an idea, not required reading before
any code. The Cookbook has independent tasks; Reference has the contracts.

@local-table-of-contents[]
@include-section["guide/getting-started.scrbl"]
@include-section["guide/rendering-a-video.scrbl"]
@include-section["guide/objects-and-groups.scrbl"]
@include-section["guide/timing-and-visibility.scrbl"]
@include-section["guide/first-function-graph.scrbl"]
@include-section["guide/slides.scrbl"]
@include-section["guide/storyboards.scrbl"]
@include-section["guide/slide-appearance.scrbl"]
@include-section["guide/narration.scrbl"]
@include-section["guide/embedded-content.scrbl"]
@include-section["guide/3d-picture.scrbl"]
@include-section["guide/3d-motion.scrbl"]
@include-section["guide/3d-composition.scrbl"]
@include-section["guide/semantic-continuity.scrbl"]
@include-section["guide/source-programs.scrbl"]
@include-section["guide/interactive-preview.scrbl"]
@include-section["guide/project-planning.scrbl"]
@include-section["guide/troubleshooting.scrbl"]
