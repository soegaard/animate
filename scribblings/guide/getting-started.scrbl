#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/guide-examples.rkt"
          "../private/illustrations.rkt")
@(define quick-eval (make-guide-eval))

@title[#:tag '("guide-getting-started" "quick-start")]{Quick Start: a moving circle}

Make one blue circle move to the right. This chapter assumes basic Racket:
@racket[require], @racket[define], and calling a function. The examples below
are evaluated while this manual is built. No video encoder or TeX is needed.

@section[#:tag "guide-first-object"]{Describe one object}

A @bold{Visual} is an object Animate can draw. Here it is a circle.
@racket[(vec2 x y)] gives a position: x increases to the right and y increases
upward. The units describe the drawing, not output pixels. The circle below has
its center three units left of the origin. Its @bold{ID},
@racket['moving-circle], is the name we will use to move it later.
@; introduces: visual coordinates identity

@examples[
 #:eval quick-eval
 #:no-result
 (require animate)
 (define disc
   (circle #:id 'moving-circle
           #:center (vec2 -3 0)
           #:radius 3/4
           #:fill "dodgerblue"
           #:stroke "navy"
           #:stroke-width 3))
]

In a source file, put @tt{#lang racket/base} at the top before these forms.

@section[#:tag "guide-first-scene"]{Put it in a Scene}

A @bold{Scene} describes an animation, including what happens over time.
@racket[make-scene] starts an empty one. @racket[scene-add] puts our circle into
it. Adding an object does not itself make time pass.
@; introduces: scene

@examples[
 #:eval quick-eval
 #:no-result
 (define initial
   (scene-add (make-scene) disc))
]

@section[#:tag "guide-first-picture"]{See the Scene}

@bold{Sampling} asks for a Scene at one time. @racket[scene->pict] samples and
draws in one operation, producing a Racket @bold{Pict}. The expression shown
below is the expression you would use in DrRacket; the documentation build only
scales and frames its resulting Pict for the page.
@; introduces: sampling pict

@examples[
 #:eval quick-eval
 #:label #f
 (eval:alts
  (scene->pict initial 0)
  (guide-pict (scene->pict initial 0)))
]

The lower-level @racket[scene-sample] operation returns a @bold{scene state}.
That state is the immutable collection of Visual values at the requested time;
@racket[scene-state->pict] can draw such a state explicitly.
@; introduces: state

@section[#:tag "guide-first-move"]{Give it a movement}

@racket[move-to] describes a requested change. @racket[scene-play] adds that
change to our Scene. @racket[#:duration 1] gives the movement one second.
The result is a new Scene; @racket[initial] still describes the unmoving starting
point.
@; introduces: request duration

@examples[
 #:eval quick-eval
 #:no-result
 (define movement
   (scene-play initial
               (move-to 'moving-circle (vec2 3 0))
               #:duration 1))
]

The duration claim is checked as part of the documentation build:

@examples[
 #:eval quick-eval
 #:label #f
 (eval:check (scene-duration movement) 1)
]

@frame-strip["circle-motion"]

The frames are evenly spaced in time. The circle moves at constant speed because
we have not selected a different speed curve.

To inspect one exact time without making a movie, sample and draw the Scene
directly:

@examples[
 #:eval quick-eval
 #:label #f
 (eval:alts
  (scene->pict movement 1/2)
  (guide-pict (scene->pict movement 1/2)))
]

The midpoint is also available as semantic state, independently of the pixels:

@examples[
 #:eval quick-eval
 #:label #f
 (eval:check
  (visual-position
   (scene-state-ref (scene-sample movement 1/2) 'moving-circle))
  (vec2 0 0))
]

@section[#:tag "guide-first-hold"]{Keep the result visible}

@racket[scene-wait] adds time without changing the picture. This adds half a
second at the right-hand end, bringing the total to 1.5 seconds.
@; introduces: hold

@examples[
 #:eval quick-eval
 #:no-result
 (define animation (scene-wait movement 1/2))
]

@examples[
 #:eval quick-eval
 #:label #f
 (eval:check (scene-duration animation) 3/2)
]

A complete standalone version is
@filepath{scribblings/examples/moving-circle.rkt}. The checked-in frame strip is
generated from that maintained example; the short expressions above are
independently executed by Scribble so stale Guide code fails the manual build.

Continue with @secref["guide-rendering-a-video"] to save pictures and a movie,
or @secref["guide-objects"] to build a larger native Scene.

@close-eval[quick-eval]
