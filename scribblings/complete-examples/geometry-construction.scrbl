#lang scribble/manual
@(require (for-label racket/base animate/slides animate/slides/geometry)
          "../private/complete-examples.rkt")

@title[#:tag "complete-geometry-construction"]{A geometry construction lesson}

This program places the library's equilateral-triangle construction in a slide.
The construction controls its points, circles, lines, and labels. The slide
provides the heading, narration timing, and a final hold.

@complete-requirements["geometry-construction"]
@complete-frames["geometry-construction" "construction"]

@section[#:tag "complete-construction-source"]{Complete source}

@complete-source["scribblings/examples/geometry-slide.rkt"]

The construction itself is an imported library example,
@filepath{geometry/examples/equilateral-triangle.rkt}. This is a complete
@emph{slide program} that uses that construction; it does not duplicate the
construction's implementation.

@section[#:tag "complete-construction-structure"]{How the program is organized}

@racket[geometry-content] adapts the construction for the figure slot.
@racket[play-content] advances its local clock. Making the slot visible on its
own would not start the construction.

The narration is a silent four-second draft: it supplies words and pacing, not
a generated voice. The construction beat has no explicit duration, so preparation
allows enough time for both the draft and the figure's playback. The final beat
holds the completed construction for another two seconds.

@section[#:tag "complete-construction-run"]{Render the movie}

@complete-command["geometry-construction" "movie"]

The existing slide runner prepares the domain content before it gives frame
work to subprocesses. There is no separate geometry-specific movie renderer to
learn for this example.

@section[#:tag "complete-construction-change"]{Try one change}

Replace the draft narration with your own explanation, or substitute another
exported construction program. Keep the playback action and check the resulting
beat duration rather than assuming every construction takes four seconds.

See @secref["guide-geometry-content"], @secref["guide-content-clock"], and
@secref["guide-slide-narration"].
