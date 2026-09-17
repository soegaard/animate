#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/examples.rkt" "../private/learning-illustrations.rkt")
@title[#:tag "guide-timing"]{Control time and visibility}
@; requires: visual coordinates identity scene request duration sampling state pict hold

This chapter compares animations built from the same starting Scene. They are
alternatives, not changes you should paste into one timeline in order.
The complete source is @filepath{scribblings/examples/timing-and-visibility.rkt}.

@verbatim{#lang racket/base
(require animate)}
@example-part["timing-and-visibility.rkt" "start"]

@section[#:tag "guide-together"]{Start two movements together}
@; introduces: simultaneous-motion

Requests in one ordinary @racket[scene-play] run together. Both objects below
move for two seconds. The Scene lasts two seconds, not four.
@example-part["timing-and-visibility.rkt" "together"]
@learning-frames["together"]

@section[#:tag "guide-in-order"]{Run one movement after another}
@; introduces: sequential-motion

Pass the result of the first @racket[scene-play] to the second. Each call appends
a new interval. Here the circle moves for one second; then the square moves for
one second. The total is again two seconds, but the picture tells a different story.
@example-part["timing-and-visibility.rkt" "in-order"]
@learning-frames["in-order"]

Two separate calls both starting from @tt{initial} would create two alternative
Scenes. They would not join automatically. Return values connect the timeline.

@section[#:tag "guide-overlap"]{Delay the second start}
@; introduces: timed-request

A @racket[timed] wrapper gives a request its own start and duration. Used directly
inside @racket[scene-play], its start is measured from that call's play interval,
not from the beginning of the whole video. Both requests must finish within the
enclosing duration.
@example-part["timing-and-visibility.rkt" "overlapping"]

@tabular[#:sep @hspace[2]
 (list (list @bold{Object} @bold{Starts} @bold{Finishes})
       (list "Circle" "0 s" "2 s")
       (list "Square" "0.5 s" "2.5 s"))]
@learning-frames["overlapping"]

The last finish is 2.5 seconds, so the outer duration is @racket[5/2].
Exact fractions are useful here: @racket[1/2] means precisely half a second.
A later play interval may use another @racket[#:start 0]; that means its own start.

Try changing the square's start to one second. Increase the outer duration to
three seconds too. The circle still finishes at two seconds; the square finishes
at three. Changing only the delay would put its endpoint outside the old interval.

More compact composition tools include @racket[succession],
@racket[animation-group], and @racket[lagged-start]. They are not needed for this
example. Their allocation rules are in @secref["animations"]; in particular,
timing nested inside a composition can be scaled to the enclosing interval.
Do not assume that the direct @racket[timed] example describes every nested case.

@section[#:tag "guide-native-easing"]{Change the speed, not the schedule}
@; introduces: native-easing

An @bold{easing function} maps elapsed progress to movement progress.
Halfway through a two-second interval, elapsed progress is @racket[1/2].
Without an explicit choice, these movements use constant-speed @racket[linear].
@racket[(smooth)] makes them start and finish gently without changing the duration.
@example-part["timing-and-visibility.rkt" "ease"]
@learning-frames["eased"]

These sample times are the same as in the first strip. Compare the distance
travelled during the first half-second. The middle and final positions agree;
the positions between them need not. Write @racket[(smooth)], with parentheses:
it constructs the callable rate value that @racket[scene-play] expects.
The slide API later uses a different spelling, a named choice such as @tt{'smooth}.

@section[#:tag "guide-entering"]{Introduce an object}
@; introduces: opacity presence entrance-exit

@bold{Opacity} controls how visible an object is: zero is transparent, one is
fully visible. @bold{Presence} says whether the object exists in the scene state
at all. These are different questions.

@racket[fade-in] introduces an absent object. Start with an empty Scene; do not
add @tt{dot} with @racket[scene-add] first.
@example-part["timing-and-visibility.rkt" "entrance"]
@learning-frames["appearing"]

@section[#:tag "guide-hidden-vs-absent"]{Hide an object, or remove it}

@racket[fade-to] changes opacity but keeps the object present. @racket[fade-out]
changes opacity and removes the object at the end of the interval.
@example-part["timing-and-visibility.rkt" "invisible"]
@learning-frames["invisible"]
@example-part["timing-and-visibility.rkt" "removed"]
@learning-frames["removed"]

The final pictures look alike. The scene states do not:
@verbatim{(scene-state-has? (scene-sample invisible 1) 'dot) ; #t
(scene-state-has? (scene-sample removed 1) 'dot)   ; #f}

That determines how to bring the circle back:
@example-part["timing-and-visibility.rkt" "restore"]

Use @racket[fade-to] for the existing invisible object; use @racket[fade-in] for
the absent one. A zero-opacity object cannot be introduced a second time under
the same ID. An absent object cannot be targeted as though it were still present.

@section[#:tag "guide-time-check"]{Keep a last picture on screen}

A movie normally samples times before the exact final endpoint. Add
@racket[scene-wait] when viewers should see the completed state for a while.
For example, @racket[(scene-wait in-order 1)] gives the finished pair one extra
second, making a three-second Scene.

Continue with @secref["guide-function-graph"] for a small mathematical diagram,
or take the layout-based route at @secref["guide-slides"].
