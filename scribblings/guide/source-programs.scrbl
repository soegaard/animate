#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/authoring
                     animate/preview))

@title[#:tag "guide-source-programs"]{Source Programs}

When you edit an animation, use the preview program to see the video before
you render a final file. @racket[open-program-preview] opens a preview window.
There, you can look at a single frame, play the video, or review a short part
of it.

The preview program reads a @italic{source program}: an ordinary Racket source
file that defines an animation. The call below asks the preview program to open
the animation named @racket[hot-reload-demo] in that file.

@racketblock[
(require animate/preview)

(open-program-preview "source-block-hot-reload.rkt" 'hot-reload-demo)]

The complete tested example is @filepath{examples/source-block-hot-reload.rkt}.
Run that file with GRacket to open its preview window.

For quick updates, divide a source program into named blocks. Each block
receives the Scene made by the previous block and returns the next Scene. A
Scene is Animate's description of what is on screen at a point in the video.
Give each block one small job, such as setting up a diagram, moving an object,
or holding the last picture.

The preview program watches the source program. When you save a change, it
reloads the file. This is called @italic{hot reloading}. It keeps the unchanged
blocks before the first changed block, then reruns the changed block and the
blocks after it. For example, changing @racket[move-dot] below reuses
@racket[setup], then reruns @racket[move-dot] and @racket[hold]. Changing code
outside the blocks rebuilds the whole program.

@racketblock[
(require animate
         animate/authoring)

(define dot
  (circle #:id 'dot #:center (vec2 -3 0) #:radius 1/2
          #:fill "tomato" #:stroke "firebrick"))

(define-scene-program hot-reload-demo
  #:initial (make-scene)

  (scene-block setup (scene)
    (scene-wait (scene-add scene dot) 1))

  (scene-block move-dot (scene)
    (scene-play scene (move-to 'dot (vec2 3 0)) #:duration 2))

  (scene-block hold (scene)
    (scene-wait scene 1)))]

The frames below show the three blocks in this program. A boundary frame is
shown twice: it is the last frame of one block and the first frame of the next.

@bold{@racket[setup] makes the dot and waits for one second.}

@centered[
 @tabular[
  #:sep @hspace[1]
  (list (list @image["scribblings/guide/figures/source-block-hot-reload-0.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-1.svg"])
        (list "start" "end"))]]

@bold{@racket[move-dot] moves the dot from left to right over two seconds.}

@centered[
 @tabular[
  #:sep @hspace[1]
  (list (list @image["scribblings/guide/figures/source-block-hot-reload-1.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-2.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-3.svg"])
        (list "start" "middle" "end"))]]

@bold{@racket[hold] keeps the finished picture on screen for one second.}

@centered[
 @tabular[
  #:sep @hspace[1]
  (list (list @image["scribblings/guide/figures/source-block-hot-reload-3.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-4.svg"])
        (list "start" "end"))]]

In the preview, the block selector lists these names and tells you which block
contains the current frame.
