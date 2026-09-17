#lang scribble/manual
@(require "../private/illustrations.rkt")
@title[#:tag "guide-slide-appearance"]{Change appearance and format}
@; requires: slide storyboard theme pict

A theme changes the appearance without changing your lesson's words or timing.
Start with the lesson from @secref["guide-storyboards"]. These calls return new
storyboards and leave @tt{film} unchanged:
@verbatim{(define light-film (storyboard-with-theme film lecture-light))
(define dark-film (storyboard-with-theme film lecture-dark))}
The title-card gallery example shows the same content in the two themes:
@frame-strip["lesson-themes"]

An explicit theme on an individual slide takes precedence over the storyboard's
theme. Use that only when the card should deliberately keep its own appearance.

@section{Format is not resolution}

A @bold{format} chooses the canvas shape and size in layout units.
@tt{widescreen} is 16 by 9; @tt{portrait} is 9 by 16. The other built-ins are
@tt{standard} and @tt{square-format}.
@; introduces: format
@verbatim{(define tall-film (storyboard-with-format film portrait))}

A new shape can change line wrapping and stack columns vertically. Inspect it;
a layout cannot fit an unlimited amount of text. Increasing the pixel resolution
of the same 16-by-9 format is different: it should not reflow the text.
@frame-strip["layout-formats"]

These three examples use the same @tt{title+two-column} static review card in
widescreen, standard, and portrait. They are alternatives, not consecutive movie frames.

@section{Choose a text style only when needed}

@bold{Typography} covers properties such as font family, size, and line spacing.
A typography role says what the text is for: title, body, label, or caption.
The theme supplies the style for that role.
@; introduces: typography

Use the built-in theme first. The complete @secref["recipe-slide-theme"] recipe
shows how to replace a title style and widen the margins without restyling every
slide. Native colors such as @tt{theme-accent} name a purpose rather than one
fixed RGB value.

Continue with @secref["guide-slide-narration"] for pacing and voice-over, or
@secref["guide-embedded-content"] for an animated figure.
