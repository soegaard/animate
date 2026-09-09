#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/authoring))

@title[#:tag "guide-source-programs"]{Source Programs}

@racketmodname[animate/authoring] makes source-block metadata an immutable
declaration. It stays headless, so programs can be loaded and inspected in a
batch environment. The complete tested example is
@filepath{examples/source-block-hot-reload.rkt}.

@racketblock[
(require animate
         animate/authoring)

(define-scene-program introduction
  #:initial (make-scene)
  (scene-block setup (scene)
    (scene-add scene (circle #:id 'dot #:radius 1)))
(scene-block pause (scene)
    (scene-wait scene 1)))]

Five frames from the video:

@centered[
 @tabular[
  #:sep @hspace[1]
  (list (list @image["scribblings/guide/figures/source-block-hot-reload-0.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-1.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-2.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-3.svg"]
              @image["scribblings/guide/figures/source-block-hot-reload-4.svg"]))]]

Each block consumes and returns an immutable Scene. The compiler retains
checkpoints and source locations for reliable reload diagnostics.
