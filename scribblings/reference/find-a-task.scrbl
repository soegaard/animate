#lang scribble/manual
@(require (for-label racket/base animate
                     animate/slides animate/slides/scene animate/slides/pict
                     animate/slides/render))
@title[#:tag "reference-find-task"]{Find a task or a name}

Use the Guide to learn a workflow. Use this map when you already know the task
and need the relevant API. The links below lead to definitions, not to new
copies of their contracts.

@section[#:tag "find-native-task"]{Ordinary Scenes}
@tabular[#:sep @hspace[2]
 (list (list @bold{Task} @bold{Start with})
       (list "Build the timeline" @racket[make-scene])
       (list "Put an object on screen immediately" @racket[scene-add])
       (list "Hold the current state" @racket[scene-wait])
       (list "Append one or more changes" @racket[scene-play])
       (list "Ask for a state at a time" @racket[scene-sample])
       (list "Move a named object" @racket[move-to])
       (list "Share placement among children" @racket[group])
       (list "Give a request a local start" @racket[timed])
       (list "Introduce a faded object" @racket[fade-in])
       (list "Keep an object but make it invisible" @racket[fade-to])
       (list "Fade an object away and remove it" @racket[fade-out]))]

For the pictures and timing comparison, see @secref["guide-objects"] and
@secref["guide-timing"]. Use @secref["visuals"] for Visual protocols and kinds;
custom protocol implementation is not needed to use a built-in circle or group.

@section[#:tag "find-graph-task"]{Graphs and mathematical content}

@racket[function-graph] turns a numerical function into a sampled path.
@racket[parametric-curve] samples two coordinates from a parameter.
@racket[data-plot] uses observations in their declared order.
@racket[create] reveals stored path geometry. These are distinct tasks.
See @secref["guide-function-graph"] for the simple case.

An ordinary formula Visual displays typeset mathematics. A mathematical
presentation plan carries an authored explanation with its own steps.
The slide math adapter wraps that plan; it does not infer algebra from a picture.
See @secref["guide-math-content"] before choosing a formula-transition API.

@section[#:tag "find-slide-task"]{Slides and continuity}
@tabular[#:sep @hspace[2]
 (list (list @bold{Task} @bold{Start with})
       (list "Make a still slide" @racket[slide])
       (list "Keep the slide visible for an interval" @racket[hold-slide])
       (list "Add builds inside the slide" @racket[build-slide])
       (list "Arrange clips and bridges" @racket[storyboard])
       (list "Put native animation in a figure" @racket[scene-content])
       (list "Advance that figure's local clock" @racket[play-content])
       (list "Freeze one domain checkpoint" @racket[content-state])
       (list "Name children for recursive matching" @racket[semantic-group])
       (list "Inspect the prepared match" @racket[storyboard-match-report])
       (list "Get a still picture" @racket[slide->pict])
       (list "Get a native Scene" @racket[slide->scene]))]

Full slide contracts are at @secref["reference-slides"]. Gallery/probe flags are
at @secref["reference-slide-tools"]. For 3D content, use the separate task map at
@secref["3d-algebra"]. For a wrong result, use @secref["guide-troubleshooting"].
