#lang scribble/manual
@(require (for-label racket/base
                     (only-in animate scene-duration scene?)
                     animate/slides
                     animate/slides/pict
                     animate/slides/scene)
          "../private/guide-examples.rkt"
          "../private/illustrations.rkt")
@(define slide-eval (make-guide-eval))

@title[#:tag "guide-slides"]{Make a slide and give it time}
@; requires: pict scene duration

A @bold{slide} holds content. A @bold{layout} places that content into named
regions, called @bold{slots}. For a title card, the slots are @racket[title] and
@racket[subtitle]. Start a @racketmod[racket/base] file by requiring
@racketmodname[animate/slides].
@; introduces: slide layout slot

The examples below are evaluated while the manual is built.

@examples[
 #:eval slide-eval
 #:hidden
 (require animate/slides
          animate/slides/pict
          animate/slides/scene
          (only-in animate scene-duration scene?))
]

@section[#:tag "guide-slide-card"]{Write a title card}

@examples[
 #:eval slide-eval
 #:no-result
 (define welcome
   (slide #:id 'welcome #:layout 'title
     [title "Solving equations"]
     [subtitle "Keep both sides equal."]))
]

The names @racket[title] and @racket[subtitle] are part of the
@racket[slide] syntax. They are not variables you must define.

A slide is a description with no duration of its own. Draw it directly with
@racket[slide->pict]:

@examples[
 #:eval slide-eval
 #:label #f
 (eval:alts
  (slide->pict welcome)
  (guide-pict (slide->pict welcome)))
]

@frame-strip["title-card"]

A plain slide lowered to an ordinary Scene has duration zero. The documentation
build checks that statement:

@examples[
 #:eval slide-eval
 #:label #f
 (eval:check
  (scene-duration (slide->scene welcome))
  0)
]

@section[#:tag "guide-slide-hold"]{Make a clip}

A @bold{slide clip} gives the slide a timed presentation.
@racket[hold-slide] makes a clip that keeps the populated card unchanged for a
chosen duration.
@; introduces: slide-clip

@examples[
 #:eval slide-eval
 #:no-result
 (define held-title
   (hold-slide welcome #:duration 3))
]

A clip retains its authored duration when lowered to an ordinary Scene:

@examples[
 #:eval slide-eval
 #:label #f
 (eval:check
  (scene-duration (slide->scene held-title))
  3)
]

@section[#:tag "guide-slide-build"]{Reveal the title, then the subtitle}

For changes within the card, use @racket[build-slide]. A @bold{beat} is a named
interval in the clip. Beats run one after another. An @bold{action} describes a
change within a beat. @racket[reveal-slot] is an action that makes content
appear.

Here, both slots start hidden. The title takes 0.4 seconds to fade in during a
one-second beat. The subtitle starts in the next beat.
@; introduces: beat slot-action visibility

@examples[
 #:eval slide-eval
 #:no-result
 (define opening
   (build-slide welcome #:initial 'hidden
     (beat 'heading #:duration 1
       (reveal-slot 'title #:duration 0.4))
     (beat 'explanation #:duration 3
       (reveal-slot 'subtitle #:duration 0.5))))
]

The clip lasts four seconds. The action durations fit inside their beats; they
are not added to the beat durations:

@examples[
 #:eval slide-eval
 #:label #f
 (eval:check
  (scene-duration (slide->scene opening))
  4)
]

@frame-strip["title-build"]

Hidden slots keep their places, so the subtitle does not move when the title
appears.

@section[#:tag "guide-slide-bullets"]{Give individual bullets names}

@racket[bullets] makes a list whose items can be targeted separately. The item
names are not printed. A selector such as @racket['(body identity)] means the
item named @racket[identity] inside the @racket[body] slot.
@; introduces: bullet selector

@examples[
 #:eval slide-eval
 #:no-result
 (define card
   (slide #:id 'layout-title+body #:layout 'title+body
     [title "Explain one idea"]
     [body
      (bullets
       [structure "Choose a layout."]
       [identity "Name what matters."]
       [timing "Reveal it at the right moment."])]))
 (define clip
   (build-slide card #:initial 'hidden
     (beat 'heading #:duration 0.7
       (reveal-slot 'title))
     (beat 'structure #:duration 0.9
       (reveal-slot '(body structure)))
     (beat 'identity #:duration 0.9
       (reveal-slot '(body identity)))
     (beat 'timing #:duration 0.9
       (reveal-slot '(body timing)))
     (beat 'read #:duration 1.6)))
]

@frame-strip["bullet-build"]

The five frames show the empty start, heading, and three settled bullet states.
The last beat simply leaves the completed list on screen.

To inspect a named boundary directly, ask @racket[slide->pict] for that point in
the clip:
@; introduces: named-time

@examples[
 #:eval slide-eval
 #:label #f
 (eval:alts
  (slide->pict clip #:at '(identity end))
  (guide-pict (slide->pict clip #:at '(identity end))))
]

@section[#:tag "guide-slide-actions-in-beat"]{Actions within a beat}

Two actions in one beat start together. Add @racket[#:at] to delay one relative
to the start of that beat. For example, this body reveal starts half a second
later:

@examples[
 #:eval slide-eval
 #:no-result
 (define delayed-card
   (build-slide
    (slide #:layout 'title+body
      [title "One beat"]
      [body "The body starts later."])
    #:initial 'hidden
    (beat 'show #:duration 2
      (reveal-slot 'title #:duration 0.4)
      (reveal-slot 'body #:at 0.5 #:duration 0.4))))
]

@racket[conceal-slot] fades content out; it does not free layout space.
@racket[emphasize-slot] briefly enlarges visible content and restores its size.
The slot entrance and exit effects are @racket['fade] and @racket['instant];
the slide transition effects in the next chapter are a different vocabulary.

Continue with @secref["guide-storyboards"]. Complete standalone programs for the
main examples are @filepath{scribblings/examples/first-slide.rkt} and
@filepath{scribblings/examples/builds.rkt}.

@close-eval[slide-eval]
