#lang scribble/manual
@(require (for-label racket/base animate animate/authoring)
          "../private/complete-examples.rkt")

@title[#:tag "complete-source-blocks"]{A source-block program}

This program gives three stages names: setup, movement, and a final hold. It
exports both the source program and its compiled Scene. The same organization
is useful when a longer lesson will be edited in the interactive preview.

@complete-requirements["source-blocks"]
@complete-frames["source-blocks" "blocks"]

@section[#:tag "complete-blocks-source"]{Complete source}

@complete-source["scribblings/examples/source-blocks.rkt"]

@section[#:tag "complete-blocks-structure"]{How the program is organized}

Each @racket[scene-block] receives the Scene built so far and returns the next
one. The setup lasts one second, movement lasts two, and the final hold lasts
one. @racket[compile-scene-program] evaluates those blocks; it does not render
frames or open a window. The @racket[animation] export is the resulting
four-second Scene.

A block's name identifies a source-level unit that the preview can track. It is
not an object ID, and it does not introduce a second animation clock.

@section[#:tag "complete-blocks-run"]{Render the compiled Scene}

@complete-command["source-blocks" "movie"]

@section[#:tag "complete-blocks-preview"]{Open the maintained interactive variant}

The repository also contains @filepath{examples/source-block-hot-reload.rkt}.
It uses the same setup, movement, and hold, and adds the explicit preview launch.
It is a separate interactive example, not the headless module printed above.

@complete-command["source-blocks" "preview"]

@section[#:tag "complete-blocks-change"]{Try one change}

Change the destination or duration inside the movement block. While using the
preview, save the file and inspect which blocks were rebuilt. Keep file output
out of block bodies so recompiling a source program does not write a movie.

See @secref["guide-source-programs"] and @secref["guide-interactive-preview"].
