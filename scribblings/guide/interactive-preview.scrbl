#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy)
                     animate/preview))

@section{Interactive Preview}

@racketmodname[animate/preview] is the optional GUI surface. It uses exactly
the normal scene sampling and Pict rendering semantics, at a lower pixel scale
when requested. Start it from GRacket or through @tt{raco animate preview};
see @filepath{examples/source-block-hot-reload.rkt} for the complete program.

@racketblock[
(require animate/preview)
(open-program-preview "derivative.rkt" 'derivative-video
                      #:fps 30
                      #:pixel-scale 1/2)]

The preview is an inspection workbench. An @racket[open-project-preview] whose
project requests audio monitoring prepares a cached PCM WAV proxy and waveform
from its authored audio cues. Reuse requires both the normalized cue plan and
the content hashes of its source files to match, so replacing narration at the
same pathname does not play stale audio. When @tt{ffplay} is available, playback follows
the same absolute semantic timeline as the visual preview; without it, the
waveform and visual preview remain usable. A module-backed project uses an
isolated renderer process that can be restarted after a blocked render. Direct
Scene previews remain in-process and therefore support cooperative—not
forced—cancellation.

Every scheduled preview request has an explicit outcome: @racket['complete],
@racket['canceled], @racket['superseded], @racket['failed],
@racket['timed-out], or @racket['worker-restarted].  Scrubbing normally makes
the preceding request @racket['superseded]; that is expected scheduler work,
not an author error.  A project-worker timeout is reported as
@racket['timed-out] and records a separate worker-restart diagnostic before
the current frame is requested again.  The last good bitmap stays visible
through that recovery.

Clicking or dragging the playhead in the production timeline seeks to an exact
semantic time. Shift-dragging marks a half-open review range. @tt{Play range}
reviews it once; @tt{Loop range} stores it in the headless controller and
repeats it from the same absolute semantic times. The @tt{block}, @tt{section},
and @tt{cue} selectors jump to the corresponding authored location when that
kind of declaration is present. The adjacent speed menu changes realtime
playback and the optional audio monitor together.
@tt{Save A} and @tt{Save B} retain two independent, dotted comparison ranges;
@tt{Play A} and @tt{Play B} review either one without replacing the marked
range or changing the loop.
When a project has an available audio backend, the @tt{Mute} control silences
only that backend. The visual playhead, scene sampling, timeline lanes, and
frame cache continue unchanged; unmuting restarts audio from the controller's
current absolute timeline time. The control is disabled when the preview has
no audio monitor (for example, when @tt{ffplay} is unavailable).
Exact playback intentionally favors every rendered frame over wall-clock speed,
so it is useful for visual review but not synchronized audio monitoring.

The same transport and cue operations are available without a GUI widget. This
is useful for editor integrations and for testing an authored timeline:

@racketblock[
(preview-scrub! preview 12.5)
(preview-jump-to-section! preview 'explanation)
(preview-jump-to-cue! preview 'definition)
(preview-set-loop-range! preview 12 18)
(preview-play! preview)
]

The cue selector is intentionally absent for a plain Scene, and the block
selector is intentionally absent unless the preview was opened from a
source program. These controls never invent sections, cues, or blocks from
rendered pixels.

After a program reload, a current Visual selection is retained only when its
identity is unambiguous: Animate tries its exact path, then a unique named
formula part, then the same canonical formula source and mapped source span.
The preview explains the outcome beside the selection; a repeated candidate is
cleared rather than silently retargeted.

Selecting a mapped formula leaf promotes the inspector subject to its exact
source-map unit. The preview then draws thin golden boxes around all mapped
units and a crimson box around the selected one. These are inspector overlays,
not Scene Visuals: they are measured from the existing sampled scene and never
enter a final render or bitmap-cache key. Shared or unmapped leaves select the
enclosing formula instead of guessing which source occurrence was intended.
The Formula source panel also displays the canonical source directly. Clicking
a mapped character selects that exact source unit and highlights every one of
its mapped leaves, even when the unit corresponds to more than one leaf.
Whitespace, unsafe ranges, and source with no visible mapped ink keep the
formula panel selected and explicitly report that there is no rendered leaf;
they never snap to a neighbouring character. The row-level @tt{Select mapped
source unit} command remains a convenient shortcut when the unit has exactly
one rendered leaf, and deliberately stays inert for a multi-leaf unit rather
than choosing a glyph by drawing order.
Headless integrations can apply the same policy with
@racket[scene-inspector-subject-at-path] and then construct an immutable
@racket[scene-inspector-document].

While a @racket[transform-matching-strings] clip is active, the String
matching inspector lists the retained planner decisions and draws its planned
routes in gold. The routes come from the compiled formula transition plan, so
they stay meaningful during an interior cross-fade whose temporary rendered
layers deliberately have no source-map identities. Like every inspector
overlay, they are preview chrome and never affect the rendered video.

Selecting a relation also exposes its declared phase, structure,
cacheability, and dependencies. Visual and anchor dependencies receive thin
purple inspection arrows from their measured current boxes to the relation;
value dependencies remain textual because a scalar has no honest canvas
location. These arrows are preview chrome only and are never added to the
sampled scene.

Every inspector document also has a Camera section taken from the same
immutable scene sample as the displayed frame. A source-program preview adds a
Source block section only when the playhead lies in a retained compiled block;
it reports the exact half-open interval, generation, branch mode, and source
location rather than guessing from timeline pixels. When a render has
published timing/cache data, a Render diagnostics section displays a copied
snapshot. A plain Scene has no source block, and a frame that has not rendered
yet has no render-diagnostic fields; the inspector reports neither as if it
were known.

The optional @tt{Diagnostics} control shows measured preview state, including
the requested and displayed frames, semantic visual lag, render time, cache
usage, canceled work, and worker cancellation capability. The same immutable
snapshot is available headlessly through
@racket[preview-session-diagnostics], so a bug-report or editor integration
does not need to interrogate GUI widgets.
