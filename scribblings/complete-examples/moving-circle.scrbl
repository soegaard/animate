#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/complete-examples.rkt")

@title[#:tag "complete-moving-circle"]{A moving circle}

One circle moves from left to right, then stays at its destination. This is the
smallest complete example of the pattern used throughout Animate: describe an
object, put it in a Scene, add a change, and keep the result visible.

@complete-requirements["moving-circle"]
@complete-frames["moving-circle" "motion"]

@section[#:tag "complete-circle-source"]{Complete source}

@complete-source["scribblings/examples/moving-circle.rkt"]

@section[#:tag "complete-circle-structure"]{How the program is organized}

@racket[disc] is the original Visual. @racket[initial] puts it in a Scene without
adding time. @racket[movement] adds one second of motion; @racket[animation]
adds the final half-second hold. These are separate values, so the program can
inspect the starting Scene without undoing the movement.

The movie uses @racket[animation], not just @racket[movement]. Its total duration
is 1.5 seconds. The final hold gives the viewer time to see the completed move.

@section[#:tag "complete-circle-run"]{Render the movie}

@complete-command["moving-circle" "movie"]

@section[#:tag "complete-circle-change"]{Try one change}

Change the destination in @racket[move-to], or change the duration of the move.
Keep a final hold. To see a still while editing in DrRacket, evaluate
@racket[(scene->pict animation 1)].

See @secref["guide-getting-started"] for the explanation of each constructor and
@secref["guide-rendering-a-video"] for the difference between rendering and encoding.
