#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "guide-storyboards"]{Put slides together}
@; requires: slide layout slot slide-clip beat slot-action named-time

A @bold{storyboard} puts slide clips in order. A @bold{shot} gives one occurrence
of a clip a name. The same clip can appear in more than one shot, but each shot
needs its own name.
@; introduces: storyboard shot

@section{Start a short lesson}

This lesson says what a function does, works through one input, and ends with a
recap. Start a new file with @tt{#lang racket/base} and
@tt{(require animate/slides)}. First make the opening clip:
@example-part["slide-lesson.rkt" "opening"]

Next, write the rule card. Its title has a @bold{continuity key}, written with
@tt{#:key}. It says which title represents the same idea on the
next slide. The transition later in this chapter will use it.
@; introduces: continuity-key
@example-part["slide-lesson.rkt" "rule"]

Now give that card time. Its title starts visible; the left and right regions
are revealed in successive beats.
@example-part["slide-lesson.rkt" "rule-timing"]

The recap has a title and two bullets. Its title has the same continuity key.
@example-part["slide-lesson.rkt" "recap"]

@section{Join the three clips}

A @bold{cut} switches immediately. A @bold{transition} occupies its own interval
between two shots. A @tt{match} transition uses continuity keys to retain
compatible content while it moves into the next layout.

A @bold{theme} chooses colors, fonts, spacing, and decoration. This lesson uses
@tt{lecture-light}; the following chapter shows how to change that choice.
@; introduces: transition theme
@example-part["slide-lesson.rkt" "storyboard"]
@frame-strip["function-lesson"]

The three images show the opening, the worked input, and the recap. The complete
source is @filepath{scribblings/examples/slide-lesson.rkt}; the manual displays
pieces of that file rather than maintaining a second copy.

@section{Check the arithmetic of time}

The opening lasts 3 seconds, the rule clip 11, and the recap 5. The matching
bridge adds 0.6 seconds, making @tt{3 + 11 + 0.6 + 5 = 19.6}.
Ordinary transitions hold the source endpoint and the destination starting state
still while they blend or move the compositions.

@tt{storyboard->pict} samples the assembled video. @tt{storyboard->scene} converts
it to an ordinary Animate Scene:
@verbatim{(require animate/slides/pict animate/slides/scene)
(storyboard->pict film #:at 8)
(define animation (storyboard->scene film))}

@section[#:tag "guide-shared-title"]{Look closely at a matching title}

The lesson's two headings occupy similar positions. For a clearer view of
matching, use this small example. @tt{paragraph-content} keeps the title's text
alignment the same on both sides; the slot alignment changes its position.
@example-part["matched-title.rkt" "title"]
@example-part["matched-title.rkt" "cards"]

An @bold{easing} choice controls progress within the transition.
@tt{'smooth} starts and ends gently. It does not change the one-second duration.
@; introduces: easing
@example-part["matched-title.rkt" "bridge"]
@frame-strip["title-match"]

The title remains visible as it moves upward. The unmatched supporting content
crossfades. Both title endpoints must be visible for a visible match.

@section{Choose another transition}

A crossfade changes opacity. A push moves both compositions. A wipe keeps them
stationary and moves only the reveal boundary. Here are five moments of a leftward
push, followed by a wipe with the same travel direction:
@verbatim{(slide-transition #:effect 'push #:direction 'left
                  #:duration 1 #:easing 'smooth)}
@frame-strip["push-left"]
@verbatim{(slide-transition #:effect 'wipe #:direction 'left
                  #:duration 1 #:easing 'smooth)}
@frame-strip["wipe-left"]

For a leftward push, the new slide enters from the right. These comparison
frames come from the gallery's @tt{push-left} and @tt{wipe-left} examples; their
contrasting backgrounds make the movement visible. The complete comparison
program is @filepath{scribblings/examples/transition-gallery.rkt}.

See @secref["cookbook-transition-comparison"] for the other effects. Continue
with @secref["guide-slide-appearance"] to change the lesson's appearance.
