#lang scribble/manual
@(require (for-label racket/base animate animate/render)
          "../private/guide-examples.rkt")
@(define render-eval (make-guide-eval))

@title[#:tag "guide-rendering-a-video"]{Save frames and make a video}
@; requires: scene sampling pict duration

Use @racket[animation] from the Quick Start. Until now, it has only been a value
in memory. @bold{Rendering} draws pictures. @bold{Encoding} combines those
pictures into a movie. These are two separate operations.
@; introduces: rendering encoding

The documentation evaluator reconstructs the Quick Start Scene privately so the
examples below remain executable without writing any output files:

@examples[
 #:eval render-eval
 #:hidden
 (require animate animate/render)
 (define disc
   (circle #:id 'moving-circle
           #:center (vec2 -3 0)
           #:radius 3/4
           #:fill "dodgerblue"
           #:stroke "navy"
           #:stroke-width 3))
 (define initial
   (scene-add (make-scene) disc))
 (define movement
   (scene-play initial
               (move-to 'moving-circle (vec2 3 0))
               #:duration 1))
 (define animation
   (scene-wait movement 1/2))
]

Before writing files, you can still inspect the Scene directly:

@examples[
 #:eval render-eval
 #:label #f
 (eval:check (scene-duration animation) 3/2)
 (eval:alts
  (scene->pict animation 1)
  (guide-pict (scene->pict animation 1)))
]

@section{Render the frames}
@; introduces: frame fps

An output @bold{frame} is one picture. The frame rate, or @bold{FPS}, says how
many of those pictures the movie shows each second.

The frame grid is pure data, so the manual can check it without creating PNG
files. A 1.5-second Scene sampled at 30 FPS has 45 frames:

@examples[
 #:eval render-eval
 #:label #f
 (eval:check
  (scene-frame-count animation #:fps 30)
  45)
]

The frame indices are therefore 0 through 44. Frame 44 is sampled at
@racket[44/30], or @racket[22/15] seconds:

@examples[
 #:eval render-eval
 #:label #f
 (eval:check
  (frame-index->time 44 #:fps 30)
  22/15)
]

The next grid time would be exactly 1.5 seconds, but there is no frame 45 in
this Scene:

@examples[
 #:eval render-eval
 #:label #f
 (eval:check
  (frame-index->time 45 #:fps 30)
  (scene-duration animation))
]

To actually write those 45 numbered PNG files, use:

@examples[
 #:eval render-eval
 #:label #f
 #:no-result
 (eval:alts
  (render-frames! animation "out/circle-frames" #:fps 30)
  (void
   (lambda ()
     (render-frames! animation "out/circle-frames" #:fps 30))))
]

The manual displays the real call, but evaluates only the dormant lambda. Thus
the binding is checked while the documentation build performs no file output.
Use an unused output directory when you run the command yourself.

The exact mathematical endpoint, 1.5 seconds, is not another output frame. The
final half-second hold is why the viewer has time to see the completed movement
before the Scene ends.

@section{Encode an MP4}

Encoding needs FFmpeg installed on the render machine. It is not needed just to
sample a Scene, show a Pict, or compute the frame grid.

After rendering the PNG sequence, encode it with:

@examples[
 #:eval render-eval
 #:label #f
 #:no-result
 (eval:alts
  (encode-mp4! "out/circle-frames" "out/circle.mp4" #:fps 30)
  (void
   (lambda ()
     (encode-mp4! "out/circle-frames" "out/circle.mp4" #:fps 30))))
]

Again, the displayed expression is the command you run. During the manual build
only the dormant lambda is created, so Scribble does not launch FFmpeg.

Use the same FPS for rendering and encoding. Otherwise, the same sequence of
frames will be played at a different rate. Open @filepath{out/circle.mp4} in a
video player after encoding it.

@section{Keep file-writing commands separate}

The example file describes the animation; the commands above request files.
Keeping them separate lets a preview, another module, or a test load the example
without starting an encoder.

This separation is also why the Guide can execute the Scene and frame-grid
examples while leaving the two external effects dormant. Later,
@secref["guide-source-programs"] shows how to organize longer source files.
There is no need to learn that machinery for this movie.

Continue with @secref["guide-objects"] for native Scene composition, or
@secref["guide-slides"] for layout-based lessons.

@close-eval[render-eval]
