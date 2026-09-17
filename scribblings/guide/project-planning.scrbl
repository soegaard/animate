#lang scribble/manual
@(require (for-label racket/base
                     animate/project
                     animate/render
                     animate/slides
                     animate/slides/project)
          "../private/guide-examples.rkt"
          "../private/examples.rkt")
@(define project-eval (make-guide-eval))

@title[#:tag "guide-project-planning"]{Render a larger project}
@; requires: storyboard theme typography preparation rendering encoding fps source-program

For a slide video, start with the supplied runner. From the repository root:

@verbatim{racket slides/render-example.rkt --workers 10 \
  --output slides-output/manual-videos \
  scribblings/examples/slide-lesson.rkt}

The runner loads @racket[film], chooses matching color and text settings,
prepares content, renders frames, and assembles the movie. For many lessons,
that is all the project configuration you need.

The shell command is not executed while Scribble builds the manual. The pure
project declaration and planning API below @emph{are} executed.

@section[#:tag "guide-project-declare"]{Declare a project when you need more control}
@; introduces: project worker

A @bold{project} combines the source, render settings, output paths, and cache
policy. A cache keeps previously rendered work for reuse; this example turns
persistent caching off. A @bold{worker} is another Racket process that renders
assigned frames. Ten workers is a requested capacity, not a promise of a
tenfold speedup.

The maintained complete project file lives next to
@filepath{slide-lesson.rkt}. Its @racket[storyboard-source] form captures that
source module's directory:

@example-source["project.rkt"]

For the interactive documentation evaluator we spell the same source base
explicitly with @racket[make-storyboard-source]. This avoids depending on the
synthetic source location of a Scribble example:

@examples[
 #:eval project-eval
 #:hidden
 (require animate/project
          animate/render
          animate/slides
          animate/slides/project)
]

@examples[
 #:eval project-eval
 #:no-result
 (define lesson-project
   (animate-project
    #:id 'manual-lesson
    #:source
    (make-storyboard-source
     "slide-lesson.rkt"
     'film
     #:asset-base (path->complete-path "scribblings/examples"))
    #:render
    (render-spec
     #:fps 30
     #:width 1280
     #:height 720
     #:workers 10
     #:theme (slide-theme-colors lecture-light)
     #:typography (slide-theme-typography lecture-light))
    #:output
    (output-spec
     #:root "slides-output/manual-videos"
     #:name "function-lesson")
    #:cache
    (cache-spec #:policy 'off)))
]

The declaration itself is immutable data:

@examples[
 #:eval project-eval
 #:label #f
 (eval:check (animate-project? lesson-project) #t)
 (eval:check
  (render-spec-workers
   (animate-project-render lesson-project))
  10)
]

The render theme and typography must agree with the storyboard. The example
turns persistent caching off to make its behavior easy to follow.

@section[#:tag "guide-project-plan"]{Inspect the plan before writing files}

@racket[plan-project] is pure: it normalizes paths and describes the intended
job without loading the declared source or writing output.

@examples[
 #:eval project-eval
 #:no-result
 (define planned
   (plan-project lesson-project))
]

@examples[
 #:eval project-eval
 #:label #f
 (eval:check (project-plan? planned) #t)
]

@racket[prepare-project!] is the next boundary: it may load the source and
inspect required tools, but it does not render frames. The final render is a
separate effect. The real calls are:

@examples[
 #:eval project-eval
 #:label #f
 #:no-result
 (eval:alts
  (prepare-project! planned)
  (void
   (lambda ()
     (prepare-project! planned))))
 (eval:alts
  (render-project! lesson-project)
  (void
   (lambda ()
     (render-project! lesson-project))))
]

The manual displays the actual operations but evaluates only dormant lambdas for
these environment-dependent stages. This keeps documentation builds independent
of FFmpeg, output permissions, and project worker processes.

For command-line environment checks and individual-section output, see
@secref["reference-project-workflow"].

@section[#:tag "guide-project-workers"]{Math and geometry use the same worker pool}

The parent prepares the mathematical and construction data once. Workers rebuild
a sampler from that prepared data; they do not redo geometry realization or
label placement. Workers still need compatible Racket, source files, and fonts.
Static previews and video encoding are separate work.

Check the reported execution mode and actual worker starts. The probe runner
compares pictures and repeatability; it is not a test of worker speed.

@section[#:tag "guide-project-review"]{Finish with two kinds of review}

Watch your lesson for pacing, wording, and readability. Separately, use
@secref["recipe-review-slides"] to compare the library's Pict and Scene output.
A completed file or a passing numeric comparison does not establish that a
lesson communicates well.

@close-eval[project-eval]
