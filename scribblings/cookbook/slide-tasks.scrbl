#lang scribble/manual
@(require "../private/examples.rkt" "../private/illustrations.rkt")
@title[#:tag "cookbook-slide-tasks"]{Slide recipes}

These recipes use existing public operations. Complete programs are in
@filepath{scribblings/examples/}. Run one file in DrRacket before evaluating
expressions that refer to its definitions. Do not paste several @tt{#lang}
programs into one file.

@section[#:tag "recipe-slide-picture"]{Make a title card}
@verbatim{#lang racket/base
(require animate/slides animate/slides/pict)}
@example-part["first-slide.rkt" "card"]
@verbatim{(slide->pict welcome)}
@frame-strip["title-card"]

To give that card a duration, use @tt{(hold-slide welcome #:duration 3)}.
A plain slide and its Pict do not have a movie duration.
See @secref["reference-slide-output"].

@section[#:tag "recipe-slide-builds"]{Reveal one bullet at a time}
@example-source["builds.rkt"]
@frame-strip["bullet-build"]

The clip lasts five seconds. Select the second settled bullet state with
@tt{(slide->pict clip #:at '(identity end))}. To hide the complete list later,
append a beat containing @tt{(conceal-slot 'body #:duration 0.5)}.
To draw attention first, use @tt{emphasize-slot} on a visible item.
Neither operation frees layout space. See @secref["reference-slide-actions"].

@section[#:tag "recipe-slide-theme"]{Use your own theme}
@example-source["theme.rkt"]

Use @tt{course-theme} on a storyboard or when converting an unprepared slide:
@verbatim{(slide->pict welcome #:theme course-theme)}

This changes the title style and spacing; it does not rewrite the slide.
The following comparison uses the built-in light and dark themes rather than
this custom theme, so the underlying color choice is easy to see.
@frame-strip["lesson-themes"]

A prepared slide already has a measured layout. Change the original description
and prepare again. See @secref["reference-slide-appearance"].

@section[#:tag "recipe-slide-transition"]{Keep a title between slides}
@example-source["matched-title.rkt"]
@frame-strip["title-match"]

The two contents share @tt{'topic}. The text itself is aligned left at both
endpoints; the slot changes placement. Both endpoints must be visible.
See @secref["reference-slide-transitions"].

@section[#:tag "recipe-matched-parts"]{Move children as their panel changes layout}
@example-source["matched-parts.rkt"]
@frame-strip["semantic-parts"]

Names establish which child continues into the next arrangement. A part's x/y
coordinates are measured from its containing group's top-left, not its center.
See @secref["reference-semantic-content"].

@section[#:tag "recipe-math-checkpoints"]{Move an equation while doing its algebra}
@example-source["math-checkpoints.rkt"]
@frame-strip["semantic-math"]

Prepare with @tt{prepare-storyboard!} before sampling the result; this needs the
math typesetting toolchain. The bridge replays the existing derivation, ending
at @tt{3x = 12}. It does not infer steps from unrelated pictures.
See @secref["guide-checkpoint"] and @secref["reference-semantic-content"].

@section[#:tag "recipe-geometry-slide"]{Reuse an animated construction}
@example-source["geometry-slide.rkt"]
@frame-strip["geometry-play"]

The imported program supplies the equilateral construction. The slide owns its
title and placement. @tt{play-content} starts the local animation; revealing the
slot alone would not. The draft narration is silent.
Use the ordinary slide project runner for workers; there is no automatic
geometry-to-one-worker fallback. See @secref["recipe-render-workers"].
