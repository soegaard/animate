#lang scribble/manual
@(require (for-label racket/base animate))
@title[#:tag "guide-troubleshooting"]{Find the cause of a wrong result}

Start with the smallest example that shows the problem. Check a single sampled
frame before rendering a whole video. Change one thing, then compare the same
time again. This page is a lookup aid, not another set of prerequisites.

@section[#:tag "trouble-no-picture"]{The program finishes without showing anything}

A source file can define and export a Scene without opening a window or writing
files. In DrRacket, sample it and turn the result into a Pict, as in
@secref["guide-first-picture"]. For saved output, follow
@secref["guide-rendering-a-video"].

A zero-duration Scene has no animation interval. @racket[scene-add] does not add
time. Use @racket[scene-wait] for a still video, or @racket[scene-play] for a change.
A plain slide similarly needs @tt{hold-slide} or @tt{build-slide} to give it time.

@section[#:tag "trouble-last-frame"]{The finished object never appears in the movie}

An instantaneous addition at the exact end has no following interval to display
it. Frame grids normally stop before the exact Scene endpoint. Add a hold after
the change rather than inventing a tiny extra movement. See
@secref["guide-time-check"].

@section[#:tag "trouble-target"]{An object is missing, or its ID is already present}

Check both its path and its presence. A child may need @tt{'(pair dot)} rather
than @tt{'dot}. A faded-to-zero object still exists; a faded-out object is removed
at the endpoint. Native @tt{fade-in} and @tt{create} introduce absent objects,
so do not add them first. See @secref["guide-hidden-vs-absent"].

Remember that a Racket variable may still hold an earlier Visual value. The
current Scene is the place to inspect an animated object.

@section[#:tag "trouble-movement"]{The wrong thing moves}

Distinguish the whole group from one child, and local from world coordinates.
In 3D, distinguish a spatial path, the 3D camera, and the enclosing 2D view.
A movement route is geometry; a target path is a list of IDs. These are not
interchangeable. The worked 2D cases are at @secref["guide-objects"].

A graph is built from an axes snapshot. Moving the axes alone does not move the
stored curve. See @secref["guide-graph-group"].

@section[#:tag "trouble-time"]{Two changes happen together when they should not}

Ordinary requests in one @tt{scene-play} share the interval. Use two calls for
simple succession, or a direct @tt{timed} wrapper for an explicit delay.
Its local start is not a whole-video timestamp. See @secref["guide-timing"].
Two overlapping requests that both write one object's position conflict;
putting them in a different argument order is not a way to resolve the conflict.

Native Scene easing takes @tt{(smooth)}, not the constructor @tt{smooth}.
Slide transitions instead take a symbol such as @tt{'smooth}.

@section[#:tag "trouble-embedded"]{The embedded figure is visible but frozen}

Visibility and playback are separate. A slide reveal does not start the
embedded animation's clock. Use @tt{play-content}, then check its endpoint and
the beat's duration. A @tt{content-state} is deliberately a frozen checkpoint.
See @secref["guide-content-clock"] and @secref["guide-semantic-continuity"].

@section[#:tag "trouble-output"]{The runner refuses the output directory}

Gallery and probe runners require a fresh destination so old and new results
cannot be mixed. Choose a new directory. Do not delete an earlier review merely
to make the command run. Output/cache rules for project rendering are separate;
look up the tool you are actually running at @secref["reference-slide-tools"].

@section[#:tag "trouble-review"]{A build or review reports errors}

Read the first failure before the later summary. Passing example tests does not
prove that Scribble links are valid. Creating an HTML file does not prove that
the documentation checker passed. A Pict/Scene comparison checks two rendering
paths; it is not a proof that the layout is attractive or that every frame is
correct. Do not raise a tolerance merely to silence an unexplained discrepancy.

For a slide probe report, retain @tt{manifest.json}, @tt{index.html}, the PNGs,
and @tt{stdout.txt}/@tt{stderr.txt}. For a manual build, the new
@filepath{scribblings/build-manual.py} keeps each stage's output and exit code
under the chosen destination's @tt{build-logs/} directory. Its
@tt{build-report.json} states which stages actually completed.
