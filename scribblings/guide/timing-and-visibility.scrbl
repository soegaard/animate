#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/guide-examples.rkt"
          "../private/learning-illustrations.rkt")
@(define timing-eval (make-guide-eval))

@title[#:tag "guide-timing"]{Control time and visibility}
@; requires: visual coordinates identity scene request duration sampling state pict hold

This chapter compares animations built from the same starting Scene. They are
alternatives, not changes you should paste into one timeline in order. The
examples are evaluated while the manual is built. A complete standalone version
is @filepath{scribblings/examples/timing-and-visibility.rkt}.

Start with two Visuals and one Scene:

@examples[
 #:eval timing-eval
 #:no-result
 (require animate)
 (define dot
   (circle #:id 'dot #:center (vec2 -3 1) #:radius 1/2
           #:fill "dodgerblue" #:stroke "navy"))
 (define tile
   (rectangle #:id 'tile #:center (vec2 -3 -1) #:width 1 #:height 1
              #:fill "gold" #:stroke "sienna"))
 (define initial (scene-add (make-scene) dot tile))
]

Before comparing schedules, look at the common starting state:

@examples[
 #:eval timing-eval
 #:label #f
 (eval:alts
  (scene->pict initial 0)
  (guide-pict (scene->pict initial 0)))
]

@section[#:tag "guide-together"]{Start two movements together}
@; introduces: simultaneous-motion

Requests in one ordinary @racket[scene-play] run together. Both objects below
move for two seconds. The Scene lasts two seconds, not four.

@examples[
 #:eval timing-eval
 #:no-result
 (define together
   (scene-play initial
               (move-to 'dot (vec2 3 1))
               (move-to 'tile (vec2 3 -1))
               #:duration 2))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check (scene-duration together) 2)
]

@learning-frames["together"]

@section[#:tag "guide-in-order"]{Run one movement after another}
@; introduces: sequential-motion

Pass the result of the first @racket[scene-play] to the second. Each call
appends a new interval. Here the circle moves for one second; then the square
moves for one second. The total is again two seconds, but the picture tells a
different story.

@examples[
 #:eval timing-eval
 #:no-result
 (define first-move
   (scene-play initial
               (move-to 'dot (vec2 3 1))
               #:duration 1))
 (define in-order
   (scene-play first-move
               (move-to 'tile (vec2 3 -1))
               #:duration 1))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check (scene-duration in-order) 2)
]

@learning-frames["in-order"]

Two separate calls both starting from @racket[initial] would create two
alternative Scenes. They would not join automatically. Return values connect
the timeline.

@section[#:tag "guide-overlap"]{Delay the second start}
@; introduces: timed-request

A @racket[timed] wrapper gives a request its own start and duration. Used
directly inside @racket[scene-play], its start is measured from that call's play
interval, not from the beginning of the whole video. Both requests must finish
within the enclosing duration.

@examples[
 #:eval timing-eval
 #:no-result
 (define overlapping
   (scene-play initial
               (timed (move-to 'dot (vec2 3 1))
                      #:start 0 #:duration 2)
               (timed (move-to 'tile (vec2 3 -1))
                      #:start 1/2 #:duration 2)
               #:duration 5/2))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check (scene-duration overlapping) 5/2)
]

@tabular[#:sep @hspace[2]
 (list (list @bold{Object} @bold{Starts} @bold{Finishes})
       (list "Circle" "0 s" "2 s")
       (list "Square" "0.5 s" "2.5 s"))]

@learning-frames["overlapping"]

The last finish is 2.5 seconds, so the outer duration is @racket[5/2].
Exact fractions are useful here: @racket[1/2] means precisely half a second.
A later play interval may use another @racket[#:start 0]; that means its own
start.

Try changing the square's start to one second. Increase the outer duration to
three seconds too. The circle still finishes at two seconds; the square finishes
at three. Changing only the delay would put its endpoint outside the old
interval.

More compact composition tools include @racket[succession],
@racket[animation-group], and @racket[lagged-start]. They are not needed for
this example. Their allocation rules are in @secref["animations"]; in
particular, timing nested inside a composition can be scaled to the enclosing
interval. Do not assume that the direct @racket[timed] example describes every
nested case.

@section[#:tag "guide-native-easing"]{Change the speed, not the schedule}
@; introduces: native-easing

An @bold{easing function} maps elapsed progress to movement progress.
Halfway through a two-second interval, elapsed progress is @racket[1/2].
Without an explicit choice, these movements use constant-speed @racket[linear].
@racket[(smooth)] makes them start and finish gently without changing the
duration.

@examples[
 #:eval timing-eval
 #:no-result
 (define eased
   (scene-play initial
               (move-to 'dot (vec2 3 1))
               (move-to 'tile (vec2 3 -1))
               #:duration 2
               #:easing (smooth)))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check (scene-duration eased) 2)
]

@learning-frames["eased"]

These sample times are the same as in the first strip. Compare the distance
travelled during the first half-second. The middle and final positions agree;
the positions between them need not. Write @racket[(smooth)], with parentheses:
it constructs the callable rate value that @racket[scene-play] expects. The
slide API later uses a different spelling, a named choice such as
@racket['smooth].

@section[#:tag "guide-entering"]{Introduce an object}
@; introduces: opacity presence entrance-exit

@bold{Opacity} controls how visible an object is: zero is transparent, one is
fully visible. @bold{Presence} says whether the object exists in the scene state
at all. These are different questions.

@racket[fade-in] introduces an absent object. Start with an empty Scene; do not
add @racket[dot] with @racket[scene-add] first.

@examples[
 #:eval timing-eval
 #:no-result
 (define appearing
   (scene-play (make-scene)
               (fade-in dot)
               #:duration 1))
]

@learning-frames["appearing"]

The final state really contains the introduced object:

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check
  (scene-state-has? (scene-sample appearing 1) 'dot)
  #t)
]

@section[#:tag "guide-hidden-vs-absent"]{Hide an object, or remove it}

@racket[fade-to] changes opacity but keeps the object present.
@racket[fade-out] changes opacity and removes the object at the end of the
interval.

@examples[
 #:eval timing-eval
 #:no-result
 (define invisible
   (scene-play (scene-add (make-scene) dot)
               (fade-to 'dot 0)
               #:duration 1))
 (define removed
   (scene-play (scene-add (make-scene) dot)
               (fade-out 'dot)
               #:duration 1))
]

@learning-frames["invisible"]
@learning-frames["removed"]

The final pictures look alike. The scene states do not. These two statements are
checked when the documentation is built:

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check
  (scene-state-has? (scene-sample invisible 1) 'dot)
  #t)
 (eval:check
  (scene-state-has? (scene-sample removed 1) 'dot)
  #f)
]

That difference determines how to bring the circle back:

@examples[
 #:eval timing-eval
 #:no-result
 (define visible-again
   (scene-play invisible
               (fade-to 'dot 1)
               #:duration 1))
 (define reintroduced
   (scene-play removed
               (fade-in dot)
               #:duration 1))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check
  (scene-state-has? (scene-sample visible-again 2) 'dot)
  #t)
 (eval:check
  (scene-state-has? (scene-sample reintroduced 2) 'dot)
  #t)
]

Use @racket[fade-to] for the existing invisible object; use
@racket[fade-in] for the absent one. A zero-opacity object cannot be introduced
a second time under the same ID. An absent object cannot be targeted as though
it were still present.

@section[#:tag "guide-time-check"]{Keep a last picture on screen}

A movie normally samples times before the exact final endpoint. Add
@racket[scene-wait] when viewers should see the completed state for a while.
For example:

@examples[
 #:eval timing-eval
 #:no-result
 (define with-hold (scene-wait in-order 1))
]

@examples[
 #:eval timing-eval
 #:label #f
 (eval:check (scene-duration with-hold) 3)
]

This gives the finished pair one extra second.

Continue with @secref["guide-function-graph"] for a small mathematical diagram,
or take the layout-based route at @secref["guide-slides"].

@close-eval[timing-eval]
