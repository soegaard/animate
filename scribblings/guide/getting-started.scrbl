#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate))

@title[#:tag "guide-getting-started"]{Getting Started}

@racketmodname[animate] is the headless semantic language: it constructs
immutable Scenes and samples them at arbitrary times. A minimal executable
example is @filepath{examples/moving-circle.rkt}.

@racketblock[
(require animate)

(define dot
  (circle #:id 'dot #:center (vec2 -2 0) #:radius 1 #:fill "tomato"))
(define scene
  (scene-play
   (scene-add (make-scene) dot)
   (move-to dot (vec2 2 0))
   #:duration 2))

(scene-sample scene 1)]

This creates no window and writes no files. Add @racketmodname[animate/render]
only when final frame or media output is wanted.
