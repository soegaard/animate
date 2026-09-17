#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "guide-embedded-content"]{Put an animation inside a slide}
@; requires: scene coordinates slide slot slide-clip beat easing theme narration

A figure slot can hold a picture or an animation. The slide places the figure;
the figure still owns the motion inside it. Start with an ordinary moving Scene.

@section[#:tag "guide-native-viewport"]{Choose the figure's visible area}

A @bold{camera} chooses the visible world area and the pixel size. Here it shows
an eight-unit-wide world in an 800-by-450 image. This area becomes the figure's
@bold{viewport}: a stable window that the slide can place and resize.

The track is a line between two points. The disc moves along it. The color names
@tt{theme-muted} and @tt{theme-accent} adapt to the selected theme.
Native @tt{scene-play} takes a rate-function value, @tt{(smooth)}, whereas a slide
transition takes the symbol @tt{'smooth}.
@; introduces: camera viewport
@verbatim{#lang racket/base
(require animate animate/colors animate/slides animate/slides/scene)}
@example-part["native-viewport.rkt" "inner"]

@section{Embed the Scene}

@tt{scene-content} wraps the Scene as slot content. No movie file is made.
@example-part["native-viewport.rkt" "card"]

@section[#:tag "guide-content-clock"]{Start its own clock}

The figure has a @bold{local clock}. Revealing a slot changes visibility; it
does not start that clock. @tt{play-content} advances it. Here the first beat
holds the disc at its starting position for one second; the next plays the
three-second movement.
@; introduces: content-clock
@example-part["native-viewport.rkt" "play"]
@frame-strip["native-viewport"]

The captions show whole-slide times. The middle image, at 2.5 seconds, is only
1.5 seconds into the figure's motion. An empty final beat holds the reached state.
The complete source is @filepath{scribblings/examples/native-viewport.rkt}.

@section[#:tag "guide-content-preparation"]{Prepare resource-dependent content}

Some figures need work before they can be sampled. @bold{Preparation} measures
text, typesets formulas, and fixes construction points and label positions.
Afterwards, frames use those prepared results instead of repeating the work.
@; introduces: preparation
@verbatim{(require animate/slides/render)
(define prepared (prepare-storyboard! film))}

This call belongs after the storyboard named @tt{film} is defined. Keep it in a
runner rather than at the top level of a reusable lesson module.

@section[#:tag "guide-math-content"]{A mathematical explanation has its own plan}

The math subsystem starts with an expression, makes named derivation steps,
and turns those steps into a @bold{presentation plan}. @tt{math-content} wraps
that plan for a figure slot. The slide does not perform the algebra.
@; introduces: math-plan

These three short pieces come from @filepath{scribblings/examples/math-checkpoints.rkt}.
First import @tt{animate/math} and @tt{animate/slides/math} as well as
@tt{animate/slides}. Then describe the starting equation:
@example-part["math-checkpoints.rkt" "problem"]

@tt{derive} names three operations. @tt{lhs} and @tt{rhs} select the left and
right sides of the equation. We subtract first, cancel opposite terms next,
and evaluate the right side last:
@example-part["math-checkpoints.rkt" "derive"]

@tt{present} chooses how those steps are shown. This grouped classroom plan
keeps the three operations together. Only then do we wrap it as slide content:
@example-part["math-checkpoints.rkt" "plan"]

For ordinary playback, put @tt{equation} in the figure slot and use
@tt{(play-content 'figure #:to '(cancel-five end))} in a beat. The next chapter
uses this same plan to move between two frozen checkpoints.

@section[#:tag "guide-geometry-content"]{Reuse a geometry construction}

A @bold{construction program} describes named points, lines, circles, and the
steps used to reveal them. This example reuses the library's equilateral-triangle
program. Its points and labels stay under the geometry subsystem's control.
@; introduces: construction
@verbatim{(require animate/slides animate/slides/geometry
         (only-in animate/geometry/examples/equilateral-triangle
                  equilateral-triangle))}
@example-part["geometry-slide.rkt" "content"]
@example-part["geometry-slide.rkt" "play"]
@frame-strip["geometry-play"]

The draft narration supplies four seconds of text and pacing, but
@tt{play-content} may need longer. Because the beat has no explicit duration,
it uses the longer interval. The last beat holds the finished construction.
The complete program is @filepath{scribblings/examples/geometry-slide.rkt}.

Continue with @secref["guide-semantic-continuity"] to change a figure's layout
while its own animation advances. Worker rendering comes later in
@secref["guide-project-planning"]; it does not require a different construction.
