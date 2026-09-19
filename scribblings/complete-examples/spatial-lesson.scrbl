#lang scribble/manual
@(require (for-label racket/base (only-in racket/math pi)
                     animate animate/3d animate/slides animate/slides/scene)
          "../private/complete-examples.rkt")

@title[#:tag "complete-spatial-lesson"]{A 3D lesson in three files}

The first file makes a box and its view. The second turns the box, then moves
its camera. The third adds labels and provides a slide version. Keep the three
files together: their relative imports are part of the example.

@complete-requirements["spatial-lesson"]
@complete-frames["spatial-lesson" "lesson"]

@section[#:tag "complete-spatial-picture-file"]{First file: the object and view}

@complete-source["scribblings/examples/first-spatial-picture.rkt"]

@racket[brick] is a spatial Visual. @racket[model] is a 2D window that contains
it and has its own 3D camera. Only that window is added to the ordinary Scene.
The source also exports @racket[picture-at] for requesting a still in DrRacket.

@section[#:tag "complete-spatial-motion-file"]{Second file: motion and timing}

@complete-source["scribblings/examples/spatial-motion.rkt"]

The small motion examples are alternatives built from @racket[still]. The
@racket[make-lesson] function combines a two-second object turn, a one-second
hold, a two-second camera orbit, and another one-second hold.

A spatial request targets @racket['(model brick)]. A 3D camera request targets
@racket['model]. Ordinary @racket[move-to] also targets @racket['model], but
moves the whole window in the surrounding 2D Scene. These are three different
changes, even when they all affect the box's appearance on screen.

@section[#:tag "complete-spatial-slides-file"]{Third file: labels and the slide version}

@complete-source["scribblings/examples/spatial-slides.rkt"]

The native heading stays above the view. The projected @racket["Box"] label
follows the object's origin while remaining upright. Its target is
@racket['(brick)] because the helper receives the owning view separately.
The captioned sequence adds a two-second translation before the six-second
lesson, making eight seconds altogether.

@complete-frames["spatial-lesson" "labels"]

The slide version embeds the uncaptioned @racket[lesson]. Its own title avoids
a second title inside the figure. The slide holds for one second, plays the
inner six-second Scene, then holds for two. The resulting @racket[film] is nine
seconds long.

@complete-frames["spatial-lesson" "slide"]

@section[#:tag "complete-spatial-run"]{Render a version}

To render the slide version with the existing shared-worker runner:

@complete-command["spatial-lesson" "movie"]

To render just the six-second native Scene:

@complete-command["spatial-lesson" "native-movie"]

Neither command selects the optional OpenGL backend.

@section[#:tag "complete-spatial-change"]{Try one change}

Change the box dimensions in the first file. The later files still reuse it.
Or change @racket[make-lesson] in the second file to compare the order of the
object turn and camera orbit. Update a beat with an explicit duration when the
embedded Scene's duration changes.

See @secref["guide-3d-picture"], @secref["guide-3d-motion"], and
@secref["guide-3d-composition"].
