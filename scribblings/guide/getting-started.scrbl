#lang scribble/manual

@(require (for-label racket/base
                     animate))

@title[#:tag "guide-getting-started"]{Getting Started}

Use @racketmodname[animate] to make animated videos. Construct immutable
Scenes and sample them at any time.

Use @racket[scene-state->pict] to turn a scene state into a Pict.

A minimal example with a moving circle:

@racketblock[
(require animate)

(define dot
  (circle #:id 'dot #:center (vec2 -2 0) #:radius 1 #:fill "tomato"))
(define scene
  (scene-play
   (scene-add (make-scene) dot)
   (move-to dot (vec2 2 0))
   #:duration 2))

(scene-state->pict (scene-sample scene 1))]

Five frames from the video:

@centered[
 @tabular[
  #:sep @hspace[1]
  (list (list @image["scribblings/guide/figures/moving-circle-0.svg"]
              @image["scribblings/guide/figures/moving-circle-1.svg"]
              @image["scribblings/guide/figures/moving-circle-2.svg"]
              @image["scribblings/guide/figures/moving-circle-3.svg"]
              @image["scribblings/guide/figures/moving-circle-4.svg"]))]]

This creates no window and writes no files. Add @racketmodname[animate/render]
only when final frame or media output is wanted.
