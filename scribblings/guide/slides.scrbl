#lang scribble/manual

@title[#:tag "guide-slides"]{Themeable Slide Layouts}

The @tt{animate/slides} subcollection describes immutable slides, rather than
adding a second renderer or video timeline. A slide assigns named content roles
to a layout; a theme supplies colors, typography, spacing, and decoration. A
timed clip adds beats, transitions, and local content clocks. The resolved result
can be rendered as either a static Pict or an ordinary Animate Scene.

@verbatim{
(require animate/slides
         animate/slides/pict
         animate/slides/scene)

(define welcome
  (slide #:id 'welcome #:layout 'title
    [title "Solving equations"]
    [subtitle "Keep both sides equal."]))

(define picture (slide->pict welcome))
(define animation (slide->scene (hold-slide welcome #:duration 3)))}

The slide syntax captures literal slot names such as @tt{title} and
@tt{subtitle}. @tt{make-slide} is the equivalent procedural API. A plain
@tt{slide->scene} has duration zero; use @tt{hold-slide} or
@tt{build-slide} when authoring time.

Use @tt{animate/slides/pict} for static Pict conversion and
@tt{animate/slides/scene} for Scene conversion. The explicit
@tt{animate/slides/render} and @tt{animate/slides/project} modules prepare
reusable layouts and project sources. @tt{animate/slides/math} and
@tt{animate/slides/geometry} embed prepared mathematical plans and geometry
programs respectively; geometry uses the in-process route because it does not
yet have a portable preparation codec.

The complete authoring and production guide is bundled with the source at
@tt{slides/docs/user-guide.md}; its compact API reference is
@tt{slides/docs/api.md}. Run the ordinary suite with
@tt{racket slides/run-tests.rkt}; add @tt{--math --geometry --media --project}
for the real integration checks. Review render output belongs under
@tt{slides-output/}, which is intentionally ignored by Git.
