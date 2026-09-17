#lang scribble/manual
@(require "../private/illustrations.rkt")

@title[#:tag "concept-slides-and-continuity"]{Slides, builds, and continuity}

A @bold{slide} says what the content is. A @bold{layout} says where it goes.
A @bold{theme} chooses colors, type, spacing, and decoration. A @bold{slide clip}
says when things appear or change. A @bold{storyboard} puts clips in order.

Changing the theme does not rewrite your lesson. Changing the timing does not
require copying the slide content.

@section{Hidden is not absent}

A hidden title still has its place in the layout. Fading it in should not move
the rest of the slide. The layout is fixed before playback.

An omitted optional slot is different. A built-in layout may give its space to
another slot. For example, @tt{title+figure} gives the figure more room when there
is no body text. Custom layouts follow their own explicit region tree.

@section{Builds happen within a clip}

A @bold{beat} is a named interval in a clip. Beats run in order. Actions inside
one beat can run together, or start at different offsets.

@tt{reveal-slot} is a build in. @tt{conceal-slot} is a build out.
@tt{emphasize-slot} draws attention to content already there.
@tt{play-content} advances an embedded animation. The slot build effects are
currently fade and instant, not all of the slide-transition effects.

A plain slide has no duration. @tt{hold-slide} gives it a duration and holds its
content at the selected poster state. @tt{build-slide} starts ordinary embedded
animations at local time zero and lets you advance them with actions.

@frame-strip["title-build"]

These are three states of the same four-second clip, not three layouts.

@section{Transitions happen between clips}

A transition has its own interval:

@verbatim{outgoing clip | transition | incoming clip}

Its duration adds to the video length. Usually the outgoing endpoint and the
incoming starting state stay frozen throughout this interval.

A semantic match can make a deliberate exception for matched @tt{content-state}
checkpoints: it replays the selected child interval while the surrounding clips
remain frozen. This is not the same as letting both clips keep playing.

@section{A role is not an identity}

@tt{title} is a role. Two unrelated slides can both have a title. A continuity
key, written with @tt{#:key}, says that two slot contents represent the same
thing across slides. The matching transition lists the keys it should retain.

Named children inside a @tt{semantic-group} give a finer correspondence.
@tt{left/label} and @tt{right/label} are different names even when their text
is identical. Names, not drawing order or similar-looking letters, control
which child goes where.

@frame-strip["title-match"]

Here one title moves from a centered introduction to the next card's heading.
The supporting text changes separately.

@section{What semantic matching can and cannot do}

Named parts can change position while the outer slot moves. A changed child can
crossfade inside its moving rectangle. Added and removed children fade in or out.

Two compatible @tt{content-state} checkpoints can instead replay the original
math, geometry, or native Scene interval. The domain author supplied that
animation already. The slide transition reuses it; it does not derive algebra
from two pictures or infer a construction from two unrelated diagrams.

Opaque Picts do not expose named inner parts. Give them an explicit semantic
group when you need that structure, or accept whole-object matching/crossfade.

@section{Preparation and rendering are still separate}

Preparation resolves layout, content, and matching. @tt{slide->pict} and
@tt{slide->scene} use that same prepared result. Their antialiased edge pixels
can differ slightly, but they should show the same state and placement.

For a worked example, see @secref["guide-slides"]. For matching options and
fallback rules, see @secref["reference-slide-transitions"].
