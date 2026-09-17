#lang scribble/manual
@(require (for-label racket/base
                     (only-in animate/colors theme-accent)
                     animate/slides
                     animate/slides/pict)
          "../private/guide-examples.rkt"
          "../private/illustrations.rkt")
@(define appearance-eval (make-guide-eval))

@title[#:tag "guide-slide-appearance"]{Change appearance and format}
@; requires: slide storyboard theme pict

A theme changes appearance without changing a lesson's words or timing. The
examples below build a small review card so this chapter is executable on its
own.

@examples[
 #:eval appearance-eval
 #:hidden
 (require animate/slides animate/slides/pict)
 (define appearance-card
   (slide #:layout 'title+two-column
     [title "One lesson, different appearance"]
     [left "The mathematical idea stays the same."]
     [right "Theme and format control presentation."]))
 (define film
   (storyboard #:id 'appearance-demo #:theme lecture-light
     (storyboard-shot 'review
                      (hold-slide appearance-card #:duration 2))))
]

These calls return new storyboard descriptions and leave @racket[film]
unchanged:

@examples[
 #:eval appearance-eval
 #:no-result
 (define light-film
   (storyboard-with-theme film lecture-light))
 (define dark-film
   (storyboard-with-theme film lecture-dark))
]

The theme choices are ordinary immutable data and can be checked directly:

@examples[
 #:eval appearance-eval
 #:label #f
 (eval:check
  (equal? (storyboard-theme film) lecture-light)
  #t)
 (eval:check
  (equal? (storyboard-theme dark-film) lecture-dark)
  #t)
]

The two descriptions render the same words with different appearance:

@examples[
 #:eval appearance-eval
 #:label #f
 (eval:alts
  (storyboard->pict light-film #:at 1)
  (guide-pict (storyboard->pict light-film #:at 1)))
 (eval:alts
  (storyboard->pict dark-film #:at 1)
  (guide-pict (storyboard->pict dark-film #:at 1)))
]

The gallery also keeps a compact side-by-side review of the same idea:

@frame-strip["lesson-themes"]

An explicit theme on an individual slide takes precedence over the storyboard's
theme. Use that only when the card should deliberately keep its own appearance.

@section[#:tag "guide-slide-format"]{Format is not resolution}
@; introduces: format

A @bold{format} chooses the canvas shape and size in layout units.
@racket[widescreen] is 16 by 9; @racket[portrait] is 9 by 16. The other
built-ins are @racket[standard] and @racket[square-format].

@examples[
 #:eval appearance-eval
 #:no-result
 (define tall-film
   (storyboard-with-format film portrait))
]

@examples[
 #:eval appearance-eval
 #:label #f
 (eval:check
  (equal? (storyboard-format tall-film) portrait)
  #t)
 (eval:alts
  (storyboard->pict tall-film #:at 1)
  (guide-pict (storyboard->pict tall-film #:at 1)))
]

A new shape can change line wrapping and stack columns vertically. Inspect it; a
layout cannot fit an unlimited amount of text. Increasing the pixel resolution
of the same 16-by-9 format is different: it should not reflow the text.

@frame-strip["layout-formats"]

These three review images use the same @racket['title+two-column] content in
widescreen, standard, and portrait. They are alternatives, not consecutive
movie frames.

@section[#:tag "guide-slide-typography"]{Choose a text style only when needed}
@; introduces: typography

@bold{Typography} covers properties such as font family, size, and line spacing.
A typography role says what the text is for: title, body, label, or caption. The
theme supplies the style for that role.

Use the built-in theme first. The complete @secref["recipe-slide-theme"] recipe
shows how to replace a title style and widen the margins without restyling every
slide. Native colors such as @racket[theme-accent] name a purpose rather than
one fixed RGB value.

Continue with @secref["guide-slide-narration"] for pacing and voice-over, or
@secref["guide-embedded-content"] for an animated figure.

@close-eval[appearance-eval]
