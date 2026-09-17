#lang scribble/manual
@(require "../private/illustrations.rkt")

@title[#:tag "concept-overview"]{Objects, scenes, and output}

An animation answers two questions: what is on screen, and how does it change?
Animate keeps those answers separate from the choice of output file.

@section{A few useful words}

A @bold{Visual} is an object that can be drawn: a circle, some text, a formula,
or a group of other objects. Its name, called an @bold{ID}, lets an animation
refer to it later.

A @bold{Scene} describes the animation built so far. It includes its objects,
camera, and timed changes. It is not just one frame. A @bold{scene state} is
what you get when you ask for that Scene at a particular time.

A @bold{camera} chooses the visible area and output size. @bold{Sampling} means
asking what should be visible at a time. @bold{Rendering} means drawing that
result. @bold{Encoding} means turning the rendered frames into a video file.

@verbatim{
objects + timed changes
          |
        Scene
          |
   sample at a time
          |
      scene state
          |
    picture or PNG

many rendered frames + encoder -> video
}

@frame-strip["circle-motion"]

One Scene produces all five pictures. A Visual describes the circle; a sampled
state places it at one time. The complete program is in @secref["guide-getting-started"].

@section{Two ways to arrange a video}

Use ordinary Scenes when you want direct control over objects and their motion.
Use @tt{animate/slides} when named regions such as title, explanation, and figure
are a better starting point. A layout places those regions for you.

Slides are not a separate renderer. @tt{slide->pict} gives a Racket Pict;
@tt{slide->scene} gives an ordinary Animate Scene. See
@secref["concept-slides-and-continuity"].

@section{Preparation does the work that must happen first}

Some content needs work before it can be drawn. Text must be measured. A formula
may need TeX. A construction needs fixed points and label positions. A recording
needs a measured duration. Animate calls this @bold{preparation}.

For slides, prepare once and then sample the result at different times. Workers
can share prepared math and geometry data without repeating their layout work.
This does not mean that every possible Racket value is transferable.

@section{Where to put your code}

Keep descriptions in normal modules. Put preview and file-writing commands in
an explicit runner or a @tt{module+ main} block. Then loading a lesson to inspect
it does not unexpectedly open a window or render a video.

The @secref["reference-module-boundaries"] chapter shows which module provides
each group of operations.
