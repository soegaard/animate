#lang scribble/manual
@(require (for-label racket/base animate animate/render))
@title[#:tag "guide-rendering-a-video"]{Save frames and make a video}
@; requires: scene sampling pict duration

Use @tt{animation} from the Quick Start. Until now, it has only been a value in
memory. @bold{Rendering} draws pictures. @bold{Encoding} combines those pictures
into a movie. These are two separate operations.
@; introduces: rendering encoding

@section{Render the frames}

An output @bold{frame} is one picture. The frame rate, or @bold{FPS}, says how
many of those pictures the movie shows each second. The command below samples
our 1.5-second animation at 30 FPS, producing 45 numbered PNG files.
@; introduces: frame fps
@verbatim{
(require animate/render)
(render-frames! animation "out/circle-frames" #:fps 30)
}

Use an unused output directory. The frames run from time 0 through 44/30.
The exact mathematical endpoint, 1.5, is not another output frame. The final
half-second hold is why the viewer has time to see the completed movement.

@section{Encode an MP4}

Encoding needs FFmpeg installed on the render machine. It is not needed just
to sample a Scene or show a Pict.
@verbatim{(encode-mp4! "out/circle-frames" "out/circle.mp4" #:fps 30)}

Use the same FPS for rendering and encoding. Otherwise, the movie will play
at a different speed. Open @tt{out/circle.mp4} in a video player.

@section{Keep file-writing commands separate}

The example file describes the animation; the commands above request files.
Keeping them separate lets a preview, another module, or a test load the example
without starting an encoder. Later, @secref["guide-source-programs"] shows how to
organize longer source files. There is no need to learn that machinery for this movie.

Continue with @secref["guide-slides"]. A slide uses a layout instead of requiring
you to choose a position for every title and paragraph.
