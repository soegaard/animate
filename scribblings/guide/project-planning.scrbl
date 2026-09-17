#lang scribble/manual
@(require "../private/examples.rkt")
@title[#:tag "guide-project-planning"]{Render a larger project}
@; requires: storyboard theme typography preparation rendering encoding fps source-program

For a slide video, start with the supplied runner. From the repository root:
@verbatim{racket slides/render-example.rkt --workers 10 \
  --output slides-output/manual-videos \
  scribblings/examples/slide-lesson.rkt}

The runner loads @tt{film}, chooses matching color and text settings, prepares
content, renders frames, and assembles the movie. For many lessons, that is all
the project configuration you need.

@section{Declare a project when you need more control}

A @bold{project} combines the source, render settings, output paths, and cache
policy. A cache keeps previously rendered work for reuse; this example turns
persistent caching off. A @bold{worker} is another Racket process that renders assigned frames.
Ten workers is a requested capacity, not a promise of a tenfold speedup.
@; introduces: project worker

This complete file lives next to @tt{slide-lesson.rkt}. The
@tt{storyboard-source} form resolves that relative filename from its source module.
@example-source["project.rkt"]

The render theme and typography must agree with the storyboard. The example
turns persistent caching off to make its behavior easy to follow.

@section{Inspect the plan before writing files}

@tt{plan-project} describes the planned job. @tt{prepare-project!} performs the
needed source and resource preparation without rendering frames. The final
render command is separate:
@verbatim{(require "scribblings/examples/project.rkt"
         animate/project animate/render)
(project-plan->datum (plan-project lesson-project))
(render-project! lesson-project)}

Run these expressions from the repository root. For command-line environment
checks and individual-section output, see @secref["reference-project-workflow"].

@section{Math and geometry use the same worker pool}

The parent prepares the mathematical and construction data once. Workers rebuild
a sampler from that prepared data; they do not redo geometry realization or
label placement. Workers still need compatible Racket, source files, and fonts.
Static previews and video encoding are separate work.

Check the reported execution mode and actual worker starts. The probe runner
compares pictures and repeatability; it is not a test of worker speed.

@section{Finish with two kinds of review}

Watch your lesson for pacing, wording, and readability. Separately, use
@secref["recipe-review-slides"] to compare the library's Pict and Scene output.
A completed file or a passing numeric comparison does not establish that a
lesson communicates well.
