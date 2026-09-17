#lang scribble/manual
@(require scribble/example
          (for-label racket/base
                     (only-in pict pict?)
                     animate/slides
                     animate/slides/pict
                     animate/slides/render))

@(define review-eval (make-base-eval))
@examples[#:eval review-eval #:hidden
  (require animate/slides animate/slides/pict (only-in pict pict?))]

@title[#:tag "cookbook-render-review"]{Render and review recipes}

Run the shell commands in this chapter from the repository root. Shell commands
are not executed while Scribble builds the manual: they create files, may invoke
FFmpeg or TeX, and should remain explicit user actions.

@section[#:tag "recipe-render-workers"]{Render a slide video with ten workers}

@verbatim{
racket slides/render-example.rkt --workers 10 \
  --output slides-output/manual-videos \
  scribblings/examples/slide-lesson.rkt
}

The source module exports a storyboard named @racket[film]. Replace the filename
with @filepath{scribblings/examples/geometry-slide.rkt} for geometry or
@filepath{scribblings/examples/math-checkpoints.rkt} for the math example.
This asks for up to ten frame workers; preparation and encoding are separate
work. FFmpeg is needed for MP4 output, and the math example also needs TeX
preparation.

@bold{Details:} @secref["reference-slide-project"].

@section[#:tag "recipe-gallery-dark"]{Render a dark gallery}

@verbatim{
racket slides/run-gallery.rkt --videos --workers 10 --dark \
  slides-output/gallery-dark
}

Open @tt{slides-output/gallery-dark/index.html}. On macOS:

@verbatim{open slides-output/gallery-dark/index.html}

Omit @tt{--videos} for posters and sampled frames only. Reported worker counts
describe what actually happened, not merely what was requested.

@section[#:tag "recipe-gallery-select"]{Render only the examples you need}

First list the catalogue:

@verbatim{racket slides/run-gallery.rkt --list}

Then select entries by ID:

@verbatim{
racket slides/run-gallery.rkt \
  --entry semantic-parts --entry semantic-math \
  --entry semantic-geometry --entry semantic-math-geometry \
  --videos --workers 10 --dark slides-output/semantic-review
}

Or inspect layout variants in portrait without movies:

@verbatim{
racket slides/run-gallery.rkt --category layouts --format portrait \
  --dark slides-output/portrait-review
}

An unknown entry usually means the requested ID is wrong. Check @tt{--list}
before a long render. @bold{Details:} @secref["reference-gallery-cli"].

@section[#:tag "recipe-review-slides"]{Compare Pict and Scene output and keep the logs}

@verbatim{
racket slides/run-probes.rkt --repeat 2 --gallery --math --geometry \
  slides-output/layout-review
}

The output contains paired PNGs, @tt{index.html}, @tt{manifest.json},
@tt{stdout.txt}, and @tt{stderr.txt}; the sibling ZIP contains the transcripts.
Do not create the output directory first. Start by reading the manifest's
@tt{errors} array, then inspect the pictures. A successful pixel comparison is
not proof that wording, spacing, or timing is good.

@bold{Details:} @secref["reference-probe-cli"].

@section[#:tag "recipe-diagnose-slide"]{Inspect a slide in storyboard context}

Unlike the shell commands above, this small diagnostic recipe is safe to run at
document-build time. It constructs a tiny storyboard and asks for a debug Pict:

@examples[#:eval review-eval #:no-result
  (define review-card
    (slide #:id 'review-card #:layout 'title+body
      [title "Inspect the layout"]
      [body "Show slots, the safe area, and baselines."]))
  (define review-film
    (storyboard #:id 'review-film #:theme lecture-light
      (storyboard-shot 'rule (hold-slide review-card #:duration 1))))
  (define debug-picture
    (slide->pict (storyboard-ref review-film 'rule)
                 #:debug '(slots safe-area baselines)))]

@examples[#:eval review-eval #:label #f
  (eval:check (pict? debug-picture) #t)]

A standalone card can inherit different settings from a storyboard. When a
layout fails, inspect the shot in the context in which it will actually render.
For semantic matching, prepare the storyboard and inspect
@racket[storyboard-match-report]. See @secref["reference-slide-inspection"].

@close-eval[review-eval]
