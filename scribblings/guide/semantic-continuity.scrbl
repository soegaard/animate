#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "guide-semantic-continuity"]{Keep parts connected across slides}
@; requires: continuity-key transition storyboard theme easing viewport content-clock preparation math-plan construction

A title match moves one retained object. There are two ways to retain more
structure: name the parts inside an object, or use checkpoints from one existing
animation. These solve different problems.

@section[#:tag "guide-named-parts"]{Name the parts you want to follow}

A @tt{semantic-group} contains named @tt{semantic-part} children. Each child gets
a rectangle in the group's coordinates. Unlike ordinary Scene centers, these
rectangles start at the @bold{top-left}: x goes right, y goes down.

The function below makes two arrangements. @tt{#f} selects the first arrangement;
@tt{#t} selects the second. The words @tt{Observe} and @tt{Explain} keep their
names, while @tt{question} is replaced by the new child @tt{conclusion}.
@; introduces: semantic-group semantic-part part-coordinates
@example-part["matched-parts.rkt" "parts"]

Now place those arrangements in slots with the same outer continuity key:
@example-part["matched-parts.rkt" "slides"]

@tt{#:depth 'semantic} asks for a supported inner correspondence, not merely
whole-slot movement. The figure moves and the named children rearrange:
@; introduces: matching-depth
@example-part["matched-parts.rkt" "match"]
@frame-strip["semantic-parts"]

Matching uses names, not similar-looking text or declaration order. A group
can contain another group; child names are scoped by their parent. A changed
appearance crossfades inside its moving rectangle. Newly added children fade
in; removed children fade out.

@section[#:tag "guide-checkpoint"]{Freeze a point in an existing animation}

A @bold{checkpoint}, made with @tt{content-state}, freezes an existing content
source at a selected local time. This is different from a playing figure.
Use the equation and plan from @secref["guide-math-content"].

Both checkpoints below use the same twelve-by-seven @bold{canonical viewport}.
That shared local window lets the outer slide layout change without typesetting
two unrelated versions of the equation.
@; introduces: checkpoint canonical-viewport
@example-part["math-checkpoints.rkt" "before"]
@example-part["math-checkpoints.rkt" "after"]

@section{Replay the known interval while changing the layout}

The match below advances the original math plan from the first checkpoint to
the second while it moves the figure. It does not guess algebra from two pictures.
@example-part["math-checkpoints.rkt" "match"]
@frame-strip["semantic-math"]

During the held shots, each checkpoint is still. Only the bridge advances the
selected child interval. The equation ends at @tt{3x = 12}; this example is not
yet the complete solution @tt{x = 4}.

@section{The same idea works for a construction}

Use checkpoints from one @tt{geometry-content} value. In the gallery, the first
checkpoint is @tt{'(1 end)}, after the two given points have appeared; the second
is @tt{'end}. That is why the starting picture is not an empty viewport.
@verbatim{(define construction (geometry-content equilateral-triangle))
(define before (content-state construction #:at '(1 end) #:viewport '(12 7)))
(define after (content-state construction #:at 'end #:viewport '(12 7)))}
@frame-strip["semantic-geometry"]

These frames are from @tt{semantic-geometry} in the gallery. The original
construction controls the circles, lines, and labels throughout the bridge.
It is not a morph between independently solved constructions.

@section{Let two domains advance in one bridge}

A named group can contain both the mathematical checkpoint and the construction
checkpoint. Each retains its own identity and local interval while the outer
panel changes arrangement. The @tt{semantic-math-geometry} gallery example does
this; it is not a second animation engine.
@frame-strip["semantic-math-geometry"]

To render that complete example, see @secref["recipe-gallery-select"]. Its source
is @filepath{slides/examples/gallery/semantic-domains.rkt}.

@section{Choose the strictness and inspect the result}

@tt{#:depth 'auto}, the default, uses supported inner matching and otherwise
falls back to ordinary matching or a crossfade. @tt{#:depth 'semantic} reports
unsupported correspondence. @tt{#:depth 'slot} keeps the older whole-slot policy.

After preparation, @tt{(storyboard-match-report prepared)} explains what was
matched, replayed, or left to a fallback. Reduced motion crossfades the frozen
endpoints without replay. Replay is visual-only; it does not copy or stretch
narration. See @secref["reference-semantic-content"] for the full contracts.
