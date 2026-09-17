#lang scribble/manual
@(require (for-label racket/base animate animate/authoring animate/render)
          "../private/guide-examples.rkt"
          "../private/illustrations.rkt")
@(define source-eval (make-guide-eval))

@title[#:tag "guide-source-programs"]{Organize a source program}
@; requires: scene request duration rendering

Once a short example works, put it in a reusable Racket module. Use
@racket[provide] to export the value another module should load. Keep rendering
commands in a runner or @racket[module+], so loading the descriptions does not
write a movie.

@section[#:tag "guide-reusable-source"]{A reusable source file}

The Quick Start already gives you a reusable module. Its export is simply:

@racketblock[
(provide animation)
]

Loading the completed @filepath{scribblings/examples/moving-circle.rkt} defines
the animation but does not render it. Keep @racket[render-frames!] in a separate
runner.

This is intentionally shown as module source instead of an interactive
@racket[examples] form: @racket[provide] describes a module boundary, and that
boundary is the point of this example.

A source file for a slide project instead exports its storyboard, normally as
@racket[film].

@section[#:tag "guide-source-blocks"]{Add blocks when you need frequent edits}
@; introduces: source-program source-block

A @bold{source program} can divide a longer animation into named
@bold{blocks}. Each block receives the Scene made so far and returns the next
Scene. This lets the preview rerun the changed block and later blocks instead of
starting over.

The block program itself is headless, so the manual can construct and compile
it directly:

@examples[
 #:eval source-eval
 #:hidden
 (require animate animate/authoring)
]

@examples[
 #:eval source-eval
 #:no-result
 (define-scene-program hot-reload-demo
   #:initial (make-scene)
   (scene-block setup (scene)
     (scene-wait
      (scene-add
       scene
       (circle #:id 'dot
               #:center (vec2 -3 0)
               #:radius 1/2
               #:fill "tomato"
               #:stroke "firebrick"))
      1))
   (scene-block move-dot (scene)
     (scene-play scene
                 (move-to 'dot (vec2 3 0))
                 #:duration 2))
   (scene-block hold (scene)
     (scene-wait scene 1)))
 (define compiled
   (compile-scene-program hot-reload-demo))
 (define animation
   (compiled-scene-program-scene compiled))
]

@examples[
 #:eval source-eval
 #:label #f
 (eval:check (scene-program? hot-reload-demo) #t)
 (eval:check (compiled-scene-program? compiled) #t)
 (eval:check (scene-duration animation) 4)
 (eval:alts
  (scene->pict animation 4)
  (guide-pict (scene->pict animation 4)))
]

@frame-strip["source-blocks"]

The blocks do not edit the incoming Scene. Their names appear in the preview's
block selector. Changing @racket[move-dot] can reuse @racket[setup]; changing
code outside the blocks rebuilds the source program.

The complete maintained GUI example is
@filepath{examples/source-block-hot-reload.rkt}. The next chapter opens that
exact example in a preview. Do not replace its filename with an undefined
placeholder such as @filepath{derivative.rkt}.

@close-eval[source-eval]
