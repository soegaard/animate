#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "guide-slides"]{Make a slide and give it time}
@; requires: pict scene duration

A @bold{slide} holds content. A @bold{layout} places that content into named
regions, called @bold{slots}. For a title card, the slots are @tt{title} and
@tt{subtitle}. Start with this import in a new file:
@; introduces: slide layout slot
@verbatim{#lang racket/base
(require animate/slides)}

@section[#:tag "guide-slide-card"]{Write a title card}
@example-part["first-slide.rkt" "card"]

The names @tt{title} and @tt{subtitle} are part of the @tt{slide} syntax.
They are not variables you must define. To see the whole card in DrRacket:
@verbatim{(require animate/slides/pict)
(slide->pict welcome)}
@frame-strip["title-card"]

A slide has no duration. @tt{slide->pict} draws the supplied content;
@tt{slide->scene} of a plain slide would make a zero-duration Scene.

@section[#:tag "guide-slide-hold"]{Make a clip}

A @bold{slide clip} gives the slide a timed presentation. @tt{hold-slide} makes
a clip that keeps the populated card unchanged for a chosen duration.
@; introduces: slide-clip
@verbatim{(define held-title (hold-slide welcome #:duration 3))}

@section[#:tag "guide-slide-build"]{Reveal the title, then the subtitle}

For changes within the card, use @tt{build-slide}. A @bold{beat} is a named
interval in the clip. Beats run one after another. An @bold{action} describes a
change within a beat. @tt{reveal-slot} is an action that makes content appear.

Here, both slots start hidden. The title takes 0.4 seconds to fade in during a
one-second beat. The subtitle starts in the next beat.
@; introduces: beat slot-action visibility
@example-part["first-slide.rkt" "build"]
@frame-strip["title-build"]

The clip lasts @tt{1 + 3 = 4} seconds, not 4.9 seconds. Actions fit inside their
beats; their durations are not added again. Hidden slots keep their places, so
the subtitle does not move when the title appears.

@section[#:tag "guide-slide-bullets"]{Give individual bullets names}

@tt{bullets} makes a list whose items can be targeted separately. The item names
are not printed. A selector such as @tt{'(body identity)} means the item named
@tt{identity} inside the @tt{body} slot.
@; introduces: bullet selector
@example-part["builds.rkt" "content"]
@example-part["builds.rkt" "beats"]
@frame-strip["bullet-build"]

The five frames show the empty start, heading, and three settled bullet states.
The last beat simply leaves the completed list on screen. To inspect a named
boundary, use @tt{(slide->pict clip #:at '(identity end))}.
@; introduces: named-time

@section{Actions within a beat}

Two actions in one beat start together. Add @tt{#:at} to delay one relative to
the start of that beat. For example, this body reveal starts half a second later:
@verbatim{(beat 'show #:duration 2
  (reveal-slot 'title #:duration 0.4)
  (reveal-slot 'body #:at 0.5 #:duration 0.4))}

@tt{conceal-slot} fades content out; it does not free layout space.
@tt{emphasize-slot} briefly enlarges visible content and restores its size.
The slot entrance and exit effects are @tt{fade} and @tt{instant}; the slide
transition effects in the next chapter are a different vocabulary.

Continue with @secref["guide-storyboards"]. Full programs for this chapter are
@filepath{scribblings/examples/first-slide.rkt} and
@filepath{scribblings/examples/builds.rkt}.
