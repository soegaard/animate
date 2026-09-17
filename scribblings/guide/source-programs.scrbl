#lang scribble/manual
@(require (for-label racket/base animate animate/authoring)
          "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "guide-source-programs"]{Organize a source program}
@; requires: scene request duration rendering

Once a short example works, put it in a reusable Racket module. Use @tt{provide}
to export the value another module should load. Keep rendering commands in a
runner or @tt{module+ main}, so loading the descriptions does not write a movie.

@section{A reusable source file}
The Quick Start already gives you a reusable module. Its export is simply:
@verbatim{(provide animation)}
Load the completed @filepath{scribblings/examples/moving-circle.rkt} in another
module with @tt{require}. Keep the @tt{render-frames!} call in a separate runner.

This is enough for many examples. A source file for a slide project instead
exports its storyboard, normally as @tt{film}.

@section{Add blocks when you need frequent edits}

A @bold{source program} can divide a longer animation into named @bold{blocks}.
Each block receives the Scene made so far and returns the next Scene. This lets
the preview rerun the changed block and later blocks instead of starting over.
@; introduces: source-program source-block
Start a separate module with @tt{#lang racket/base} and
@tt{(require animate animate/authoring)}. Then define the blocks:
@example-part["source-blocks.rkt" "blocks"]
@frame-strip["source-blocks"]

The blocks do not edit the incoming Scene. Their names appear in the preview's
block selector. Changing @tt{move-dot} can reuse @tt{setup}; changing code outside
the blocks rebuilds the source program.

The complete maintained example is @filepath{examples/source-block-hot-reload.rkt}.
The next chapter opens that exact example in a preview. Do not replace its
filename with an undefined placeholder such as @tt{derivative.rkt}.
