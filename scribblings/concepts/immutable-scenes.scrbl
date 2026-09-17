#lang scribble/manual
@(require (for-label racket/base animate))

@title[#:tag "concept-immutable-scenes"]{Scenes and time}

An operation returns a new Scene. It does not edit the Scene you passed in.
This is what @italic{immutable} means here. You can keep the old value and use
it again, for example to make a second version of a lesson.

@section{A frame does not depend on the previous frame}

To find a frame, Animate uses the Scene and the requested time. You can ask for
the end first, then the middle, then the start. For a Scene long enough to contain
these times:

@racketblock[
(scene-sample scene 3/2)
(scene-sample scene 1/2)
(scene-sample scene 0)]

This is why scrubbing and parallel rendering can use the same description.
Your own factories and callbacks must follow the same rule: do not make their
answers depend on a mutable counter, a previous frame, or uncontrolled randomness.

@section{Durations and frame numbers are different}

Times are in seconds. Frame numbers start at zero. A two-second video at
30 frames per second has 60 frames, sampled at @racket[0], @racket[1/30],
and so on through @racket[59/30].

The exact endpoint at two seconds is useful for a still picture or a transition.
It is not an extra 61st encoded frame. Add a hold when you want the finished
picture to remain visible for longer.

@section{Several clocks may be involved}

A storyboard has a whole-video clock. Each shot has a local clock. An embedded
construction or mathematical presentation can have its own clock too.
Revealing a slot changes its visibility; it does not start its embedded animation.
See @secref["concept-slides-and-continuity"] for the slide rules and
@secref["reference-slide-actions"] for @tt{play-content}.
