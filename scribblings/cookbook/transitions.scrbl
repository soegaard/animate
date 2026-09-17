#lang scribble/manual
@(require scribble/example
          (for-label racket/base animate/slides)
          "../private/illustrations.rkt")

@(define transition-eval (make-base-eval))
@examples[#:eval transition-eval #:hidden
  (require animate/slides)]

@title[#:tag "cookbook-transition-comparison"]{Choose a slide transition}

The frame strips use the same outgoing and incoming gallery cards. The
transition expressions beside them are executable: Scribble constructs each
value and checks its effect name while building the manual.

@section{Blend the pictures: crossfade}

@examples[#:eval transition-eval #:no-result
  (define crossfade-transition
    (slide-transition #:effect 'crossfade #:duration 1 #:easing 'smooth))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect crossfade-transition) 'crossfade)]
@frame-strip["crossfade"]

Use this when there is no important spatial connection to explain. Both endpoint
compositions stay still while their opacity changes.

@section{Move both pictures: push}

@examples[#:eval transition-eval #:no-result
  (define push-transition
    (slide-transition #:effect 'push #:direction 'left
                      #:duration 1 #:easing 'smooth))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect push-transition) 'push)]
@frame-strip["push-left"]

The outgoing picture travels left; the incoming picture enters from the right.
Direction names describe travel, not the starting edge.

@section{Move only a boundary: wipe}

@examples[#:eval transition-eval #:no-result
  (define wipe-transition
    (slide-transition #:effect 'wipe #:direction 'left
                      #:duration 1 #:easing 'smooth))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect wipe-transition) 'wipe)]
@frame-strip["wipe-left"]

The pictures do not move. A reveal boundary sweeps across them.

@section{Move only one picture: cover and uncover}

@examples[#:eval transition-eval #:no-result
  (define cover-transition
    (slide-transition #:effect 'cover #:direction 'left
                      #:duration 1 #:easing 'smooth))
  (define uncover-transition
    (slide-transition #:effect 'uncover #:direction 'left
                      #:duration 1 #:easing 'smooth))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect cover-transition) 'cover)
  (eval:check (slide-transition-effect uncover-transition) 'uncover)]
@frame-strip["cover-left"]
@frame-strip["uncover-left"]

Cover moves the destination over the source. Uncover moves the source away from
the stationary destination.

@section{Change size: zoom}

@examples[#:eval transition-eval #:no-result
  (define zoom-transition
    (slide-transition #:effect 'zoom #:scale 0.82
                      #:duration 1 #:easing 'smooth))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect zoom-transition) 'zoom)]
@frame-strip["zoom"]

Zoom combines centered scaling with fading. It does not identify corresponding
objects. For that, use a match.

@section{Pass through a color: fade-through}

@examples[#:eval transition-eval #:no-result
  (define fade-through-transition
    (slide-transition #:effect 'fade-through #:color "#101820" #:duration 1))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect fade-through-transition) 'fade-through)]
@frame-strip["fade-through"]

The middle is the selected opaque color.

@section{Retain an idea: match}

@examples[#:eval transition-eval #:no-result
  (define match-transition
    (slide-transition #:effect 'match #:keys '(topic) #:duration 1))]
@examples[#:eval transition-eval #:label #f
  (eval:check (slide-transition-effect match-transition) 'match)]

Give the corresponding contents a shared key. Follow
@secref["guide-shared-title"] for whole-title movement and
@secref["guide-semantic-continuity"] for named children and domain checkpoints.
A @racket[(storyboard-cut)] has zero duration and no intermediate frames.

@section{Limit motion without changing the timing}

Storyboard @racket[#:motion] @racket['reduced] replaces spatial transitions with
crossfades of the same duration. Exact defaults and unsupported options belong
in @secref["reference-slide-transitions"].

@close-eval[transition-eval]
