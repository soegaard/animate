#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "cookbook-transition-comparison"]{Choose a slide transition}

These comparisons use the same outgoing and incoming gallery cards. A pale tint
separates their backgrounds. Each picture strip follows one transition, not a
sequence of different effects. The brief program below is complete; replace
@tt{'push-left} to inspect another catalogue entry.
@example-source["transition-gallery.rkt"]

@section{Blend the pictures: crossfade}
@verbatim{(slide-transition #:effect 'crossfade #:duration 1 #:easing 'smooth)}
@frame-strip["crossfade"]

Use this when there is no important spatial connection to explain. Both endpoint
compositions stay still while their opacity changes.

@section{Move both pictures: push}
@verbatim{(slide-transition #:effect 'push #:direction 'left #:duration 1 #:easing 'smooth)}
@frame-strip["push-left"]

The outgoing picture travels left; the incoming picture enters from the right.
Direction names describe travel, not the starting edge.

@section{Move only a boundary: wipe}
@verbatim{(slide-transition #:effect 'wipe #:direction 'left #:duration 1 #:easing 'smooth)}
@frame-strip["wipe-left"]

The pictures do not move. A reveal boundary sweeps across them. This is useful
when their positions should stay comparable.

@section{Move only one picture: cover and uncover}
@verbatim{(slide-transition #:effect 'cover #:direction 'left #:duration 1 #:easing 'smooth)}
@frame-strip["cover-left"]

Cover moves the destination over the source. Uncover moves the source away from
the stationary destination:
@verbatim{(slide-transition #:effect 'uncover #:direction 'left #:duration 1 #:easing 'smooth)}
@frame-strip["uncover-left"]

@section{Change size: zoom}
@verbatim{(slide-transition #:effect 'zoom #:scale 0.82 #:duration 1 #:easing 'smooth)}
@frame-strip["zoom"]

Zoom combines centered scaling with fading. It does not identify corresponding
objects. For that, use a match rather than a whole-slide zoom.

@section{Pass through a color: fade-through}
@verbatim{(slide-transition #:effect 'fade-through #:color "#101820" #:duration 1)}
@frame-strip["fade-through"]

The middle is the selected opaque color. Use the full @tt{fade-through} gallery
entry to try the effect before using it for a chapter break.

@section{Retain an idea: match}

Give the contents a shared key and use @tt{#:effect 'match}. Follow
@secref["guide-shared-title"] for whole-title movement and
@secref["guide-semantic-continuity"] for named children and domain checkpoints.
A cut, @tt{(storyboard-cut)}, has zero duration and no intermediate frames.

@section{Limit motion without changing the timing}

Storyboard @tt{#:motion 'reduced} replaces spatial transitions with crossfades
of the same duration. Ordinary endpoint states stay frozen. Deliberate replay
between matching checkpoints is also replaced by a crossfade. Exact defaults,
unsupported options, and opacity requirements belong in
@secref["reference-slide-transitions"].
