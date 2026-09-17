#lang scribble/manual
@(require (for-label racket/base animate/preview))

@title[#:tag "guide-interactive-preview"]{Preview, edit, and inspect}
@; requires: source-program source-block scene sampling frame

The @bold{preview} window lets you play an animation or inspect one time without
encoding a movie. It uses the same sampling and drawing as the renderer. Run a
GUI-capable Racket such as GRacket for this step.
@; introduces: preview

Unlike the headless examples in the preceding chapters, this chapter
deliberately does @emph{not} execute its GUI commands while Scribble is building
the manual. Opening windows, watching the filesystem, and waiting for edits are
interactive effects, not documentation-build tests.

@section[#:tag "guide-open-preview"]{Open the source program you just learned}

From the repository root, open the maintained example:

@racketblock[
(require animate/preview)

(open-program-preview
 "examples/source-block-hot-reload.rkt"
 'hot-reload-demo)
]

The filename identifies the module. The second argument identifies its exported
source program. Saving changes reloads the program while retaining unchanged
blocks before the changed one. This is called @bold{hot reloading}.

The complete program itself is still tested headlessly in
@secref["guide-source-blocks"]; only the GUI launch is intentionally excluded
from the Scribble evaluator.

@section[#:tag "guide-preview-range"]{Review a short interval}

Use Play and the playhead to look at the motion. Shift-drag marks a review
range; Play range runs it once and Loop range repeats it. The block selector
jumps to the named blocks in the source program. Section and cue selectors
appear only when that kind of information exists.

A quickly superseded frame request is not an error: you may have moved the
playhead again before the earlier picture was ready. The Diagnostics control
shows what was requested and what was actually displayed.

@section[#:tag "guide-preview-inspect"]{Inspect an object}

Select an object to inspect its identity and properties. Colored inspection
outlines and dependency arrows belong to the preview. They do not become
objects in the Scene or appear in the final movie.

For formula source selection, cancellation outcomes, audio monitoring, and
worker recovery, use @secref["reference-preview-workbench"]. Those details are
kept in Reference so they do not interrupt this first editing session.
