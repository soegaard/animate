#lang scribble/manual
@(require (for-label racket/base animate)
          "../private/complete-examples.rkt")

@title[#:tag "complete-function-graph"]{Draw and move a function graph}

This program makes a graph of @math{y=x^2/4-1}. It exports two animations:
@racket[film] draws the curve and holds it, while @racket[moving-diagram] moves
the completed curve and its axes together. They are alternatives, not consecutive
sections of one movie.

@complete-requirements["function-graph"]
@complete-frames["function-graph" "draw"]

@section[#:tag "complete-graph-source"]{Complete source}

@complete-source["scribblings/examples/first-function-graph.rkt"]

@section[#:tag "complete-graph-structure"]{How the program is organized}

@racket[coordinates] sets both the numeric ranges and the drawn lengths of the
axes. @racket[curve] samples the function 81 times and stores the resulting path.
@racket[create] reveals that path over two seconds; it does not evaluate the
function again for every movie frame. @racket[film] adds a one-second hold.

The second animation puts the axes and the complete curve in @racket[diagram].
Moving that group keeps the two together. Moving only the axes would leave the
already-built curve behind.

@complete-frames["function-graph" "move"]

@section[#:tag "complete-graph-run"]{Render either animation}

To render the three-second reveal:

@complete-command["function-graph" "movie"]

To render the separate two-second group movement:

@complete-command["function-graph" "move-movie"]

@section[#:tag "complete-graph-change"]{Try one change}

Replace the numerical function, then check that its range fits the axes. Change
@racket[#:sample-count] to compare geometric approximation, or change
@racket[#:duration] to change the reveal speed. Those are different choices.

See @secref["guide-function-graph"] for the learning route and
@secref["guide-graph-group"] for why the group matters.
