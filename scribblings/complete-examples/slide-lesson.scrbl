#lang scribble/manual
@(require (for-label racket/base animate/slides animate/slides/project
                     animate/project animate/render)
          "../private/complete-examples.rkt")

@title[#:tag "complete-slide-lesson"]{A complete slide lesson}

The lesson introduces a rule, applies it to one input, and ends with a recap.
The source separates the words and layouts from their timing. A shared heading
stays connected across the final transition.

@complete-requirements["slide-lesson"]
@complete-frames["slide-lesson" "lesson"]

@section[#:tag "complete-slide-source"]{Complete lesson source}

@complete-source["scribblings/examples/slide-lesson.rkt"]

@section[#:tag "complete-slide-structure"]{How the program is organized}

@racket[opening] is a three-second title clip. @racket[rule-slide] contains the
rule and the worked input; @racket[rule-clip] reveals them in named beats.
The recap follows the same split between content and timing.

@racket[film] puts the clips in order. The opening lasts 3 seconds, the rule
clip 11, the transition 0.6, and the recap 5: 19.6 seconds in all. Transition time
is additional. The title's @racket['lesson-heading] key identifies what should
remain connected, rather than asking the renderer to infer identity from words.

@section[#:tag "complete-slide-run"]{Render the lesson}

@complete-command["slide-lesson" "movie"]

The runner loads the exported @racket[film]. Merely running the lesson source
file does not ask it to create a movie.

@section[#:tag "complete-slide-project"]{Keep render settings in a project file}

This optional second file belongs beside @filepath{slide-lesson.rkt}. It refers
to that file rather than making another copy of the lesson. The relative source
path is resolved from the project module; the output path is resolved from the
working directory used to run the project.

@complete-source["scribblings/examples/project.rkt"]

Use the project command instead of the earlier slide-runner command:

@complete-command["slide-lesson" "project"]

The project requests ten frame workers and uses the light theme's color and
text settings. The worker count is a capacity request, not a promised speedup.

@section[#:tag "complete-slide-change"]{Try one change}

Use a different input in the worked example and update the recap to match.
Or change one beat duration without changing the layout. When changing the
storyboard theme, keep the project's color and typography settings in agreement.

See @secref["guide-slides"], @secref["guide-storyboards"], and
@secref["guide-project-planning"].
