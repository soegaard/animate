#lang scribble/manual
@(require (for-label racket/base animate animate/3d animate/slides animate/slides/scene)
          "../private/examples.rkt" "../private/three-d-illustrations.rkt")
@title[#:tag "guide-3d-composition"]{Combine 3D with text and slides}

@; requires: scene view3d spatial-path camera3d-motion
The previous chapter produced a Scene named @racket[lesson]. A 3D view can share
that Scene with ordinary text, formulas, and other 2D Visuals. This chapter first
adds text, then shows the optional slide route.

@section[#:tag "guide-3d-labels"]{Choose what a label follows}
@; introduces: projected-label
A heading placed in the surrounding Scene stays still when the @emph{3D} camera
moves. A @bold{projected label} instead follows a point seen through the 3D view.
It is still ordinary 2D text, so its letters stay upright and readable.

Here the heading stays above the window, while @tt{Box} follows the box's origin.
First the box moves to the side for two seconds. The six-second turn-and-orbit
sequence follows, making eight seconds in all.
The view is supplied separately to @racket[follow-projected-spatial], so this
helper's @tt{#:target} is the path @racket['(brick)] within that view. That differs
from the full @racket['(model brick)] path used by a motion request.

Save these pieces in @filepath{spatial-slides.rkt}, beside the other two files.
@example-part["spatial-slides.rkt" "imports"]
@example-part["spatial-slides.rkt" "labels"]
@three-d-frames["captioned-lesson"]

The label's offset is measured in screen pixels. Its text size is still an
ordinary 2D text size. The default label policy keeps it visible; it does not
promise to hide text behind the box. The Reference describes explicit occlusion
and placement options.

@section[#:tag "guide-3d-slide"]{Put the animation in a slide}
@; requires: slide-clip beat slot-action storyboard shot viewport content-clock
This section uses layouts, beats, and the local content clock from
@secref["guide-slides"] and @secref["guide-embedded-content"]. Readers who came
straight from the Quick Start can stop here and return after those chapters.

Wrap the existing Scene with @racket[scene-content]. Do not use
@tt{geometry-content}: that adapter is for the separate Euclidean construction
library, not for every kind of geometry or every 3D object.

Add these imports when continuing with the slide version:
@example-part["spatial-slides.rkt" "slide-imports"]
@example-part["spatial-slides.rkt" "slide"]
@three-d-frames["slide-lesson"]

The slide holds the initial picture for one second. Its @tt{play} beat advances
the embedded Scene's six-second clock. The last beat holds the final picture for
two seconds. The total is nine seconds; adding a hold to the slide does not add a
second moving clock to the 3D view.

For this embedding we use the uncaptioned @racket[lesson]. The slide supplies its
own title, so we do not place a second native title inside the figure region.
Use the ordinary slide preparation and rendering workflow after this step.

@section[#:tag "guide-3d-where-next"]{Choose the next topic when you need it}
The @seclink["3d-algebra"]{3D reference map} separates solids, materials,
cameras, curves, surfaces, relations, mesh operations, numerical flow, picking,
and rendering internals. None of the mesh-topology or renderer-protocol chapters
is a prerequisite for the examples above.

@secref["cookbook-3d"] collects the complete source programs and short answers to
common placement and camera questions.
