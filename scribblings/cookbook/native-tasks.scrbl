#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/examples.rkt")
@title[#:tag "cookbook-native-tasks"]{Common Scene tasks}

Use this page after the first Scene lessons. Each entry names the result,
points to complete runnable source, and calls out a likely mistake. The Guide
contains the frame strips and explains the ideas in order.

@section[#:tag "recipe-target-child"]{Move one part of a diagram}

Use a group to give the diagram a shared position, then a path to name a child.
Load @filepath{scribblings/examples/objects-and-groups.rkt}; @tt{grouped} and
@tt{child-moves} are alternative Scenes from that source.
@example-part["objects-and-groups.rkt" "move-child"]

The destination uses parent-local coordinates. For the full worked picture,
see @secref["guide-first-path"]. Do not treat a path of IDs as a movement route.

@section[#:tag "recipe-delay-start"]{Start the second animation later}

Use @racket[timed] directly inside one @racket[scene-play]. This example uses
@tt{initial} from @filepath{scribblings/examples/timing-and-visibility.rkt}:
@example-part["timing-and-visibility.rkt" "overlapping"]

The outer duration includes the delay. Its schedule and five sampled frames
are at @secref["guide-overlap"]. For two non-overlapping steps, two ordinary
@racket[scene-play] calls are simpler.

@section[#:tag "recipe-restore-object"]{Bring a faded object back}

First decide whether it still exists. @racket[fade-to] leaves an object present;
@racket[fade-out] removes it. With the values defined in the timing example:
@example-part["timing-and-visibility.rkt" "restore"]

The distinction is visible in the state even when both final images are empty.
See @secref["guide-hidden-vs-absent"] for the state queries.

@section[#:tag "recipe-graph-reveal"]{Reveal a mathematical graph}

Construct a curve with @racket[function-graph], then introduce it with
@racket[create]. @filepath{scribblings/examples/first-function-graph.rkt} exports
both the complete @tt{film} and the shorter @tt{drawing} without its final hold.
@example-part["first-function-graph.rkt" "draw"]

Do not add @tt{curve} before calling @racket[create]. See
@secref["guide-function-graph"] for the axes, numerical sampling, and images.

@section[#:tag "recipe-sample-frame"]{Inspect a frame without making a movie}

Load one of the example modules, then sample one of its exported Scenes. For a
fixed ordinary camera, this is enough to inspect the middle of the reveal:
@verbatim{(require "scribblings/examples/first-function-graph.rkt")
(scene-state->pict (scene-sample drawing 1))}

Enter it from a file or interactions session rooted at the checkout directory,
with @tt{animate} required. With a moving ordinary camera, also sample that
camera and pass it to the renderer; see @racket[scene-camera-at]. The 3D camera
inside a @tt{view3d} is a separate part of that view's sampled value.
