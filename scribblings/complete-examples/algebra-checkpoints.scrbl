#lang scribble/manual
@(require (for-label racket/base animate/slides animate/slides/math)
          "../private/complete-examples.rkt")

@title[#:tag "complete-algebra-checkpoints"]{Algebra across layouts}

One mathematical derivation continues while its figure moves into a new layout.
The program subtracts five from both sides of @math{3x+5=17}, cancels the
opposite addends, and evaluates the right-hand side. It ends at @math{3x=12};
it does not yet carry out the division that would give @math{x=4}.

@complete-requirements["algebra-checkpoints"]
@complete-frames["algebra-checkpoints" "algebra"]

@section[#:tag "complete-algebra-source"]{Complete source}

@complete-source["scribblings/examples/math-checkpoints.rkt"]

@section[#:tag "complete-algebra-structure"]{How the program is organized}

The first definitions describe the held problem, the three named algebraic
steps, and their presentation plan. @racket[equation] wraps that plan as slide
content. Constructing these descriptions is separate from typesetting a picture.

The two cards use checkpoints from that same content value. Both keep a
12-by-7 local viewport, even though the surrounding slide layout changes.
The @racket['work] continuity key connects them.

During each held shot the checkpoint is still. The four-second semantic
transition advances the known interval between the checkpoints while moving the
figure. It does not invent algebra by comparing two rendered formulas.
The two holds make the complete storyboard nine seconds long.

@section[#:tag "complete-algebra-run"]{Render the movie}

@complete-command["algebra-checkpoints" "movie"]

This command prepares mathematical content and therefore needs the formula
toolchain. Building the pages in this part only reads this source and its stored
illustrations; it does not run that typesetting step.

@section[#:tag "complete-algebra-change"]{Try one change}

Change the transition duration to give viewers more time for the same algebra.
Keep both checkpoints attached to the same plan. To teach another algebraic
step, add it to the derivation and choose its named checkpoint, rather than
writing unrelated before and after formulas.

See @secref["guide-math-content"] and @secref["guide-semantic-continuity"].
