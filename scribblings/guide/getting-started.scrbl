#lang scribble/manual
@(require (for-label racket/base animate) "../private/examples.rkt" "../private/illustrations.rkt")

@title[#:tag '("guide-getting-started" "quick-start")]{Quick Start: a moving circle}

Make one blue circle move to the right. This chapter assumes basic Racket:
@tt{require}, @tt{define}, and calling a function. Run the code in DrRacket so
that a picture value can be displayed. No video encoder or TeX is needed.

@section[#:tag "guide-first-object"]{Describe one object}

A @bold{Visual} is an object Animate can draw. Here it is a circle.
@tt{(vec2 x y)} gives a position: x increases to the right and y increases upward.
The units describe the drawing, not output pixels. The circle below has its center
three units left of the origin. Its @bold{ID}, @tt{'moving-circle}, is the name
we will use to move it later.
@; introduces: visual coordinates identity

@verbatim{#lang racket/base
(require animate)}
@example-part["moving-circle.rkt" "object"]

@section[#:tag "guide-first-scene"]{Put it in a Scene}

A @bold{Scene} describes an animation, including what happens over time.
@tt{make-scene} starts an empty one. @tt{scene-add} puts our circle into it.
Adding an object does not itself make time pass.
@; introduces: scene
@example-part["moving-circle.rkt" "scene"]

@section[#:tag "guide-first-move"]{Give it a movement}

@tt{move-to} describes a requested change. @tt{scene-play} adds that change to
our Scene. @tt{#:duration 1} gives the movement one second.
The result is a new Scene; @tt{initial} still describes the unmoving starting point.
@; introduces: request duration
@example-part["moving-circle.rkt" "motion"]

@frame-strip["circle-motion"]

The frames are evenly spaced in time. The circle moves at constant speed because
we have not selected a different speed curve.

@section[#:tag "guide-first-picture"]{Ask for a picture}

@bold{Sampling} asks for the Scene at one time. It returns a @bold{scene state},
not a movie. @tt{scene-state->pict} draws that state as a Racket @bold{Pict}.
After running the file, enter this in DrRacket's interactions area:
@; introduces: sampling state pict
@verbatim{(scene-state->pict (scene-sample movement 1/2))}

You will see the middle frame above. Loading the source in a terminal only
defines these values, so it can finish without showing anything.

@section[#:tag "guide-first-hold"]{Keep the result visible}

@tt{scene-wait} adds time without changing the picture. This adds half a second
at the right-hand end, bringing the total to 1.5 seconds.
@; introduces: hold
@example-part["moving-circle.rkt" "hold"]

The complete program is @filepath{scribblings/examples/moving-circle.rkt}.
That is the same source used by the illustration recipe. Continue with
@secref["guide-rendering-a-video"] to save pictures and a movie, or
@secref["guide-slides"] to use slide layouts.
