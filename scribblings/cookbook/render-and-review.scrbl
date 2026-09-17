#lang scribble/manual

@title[#:tag "cookbook-render-review"]{Render and review recipes}

Run these commands from the repository root. They use @tt{racket} from your PATH.
For a particular Racket installation, replace it with the full executable path
or your existing @tt{"$RACKET"} variable. All output directory names below are
examples; choose a new name for each review run.

@section[#:tag "recipe-render-workers"]{Render a slide video with ten workers}

@verbatim{
racket slides/render-example.rkt --workers 10 \
  --output slides-output/manual-videos \
  scribblings/examples/slide-lesson.rkt
}

The source module exports a storyboard named @tt{film}. The runner configures the
project's colors and typography from that storyboard. Replace the filename with
@tt{scribblings/examples/geometry-slide.rkt} to use the same route for geometry,
or @tt{scribblings/examples/math-checkpoints.rkt} for the math example.

This asks for up to ten frame workers. Preparation and video encoding have
separate work, so the complete job is not necessarily ten times faster.
FFmpeg is needed for the MP4; the math example also needs TeX preparation.

@bold{Details:} @secref["reference-slide-project"].

@section[#:tag "recipe-gallery-dark"]{Render a dark gallery}

@verbatim{
racket slides/run-gallery.rkt --videos --workers 10 --dark \
  slides-output/gallery-dark
}

Open @tt{slides-output/gallery-dark/index.html}. On macOS:

@verbatim{open slides-output/gallery-dark/index.html}

Omit @tt{--videos} for posters and sampled frames only. Geometry videos use the
same worker capacity as other videos. The reported worker counts tell you what
actually happened, not just what was requested.

@section[#:tag "recipe-gallery-select"]{Render only the examples you need}

First list the catalogue:

@verbatim{racket slides/run-gallery.rkt --list}

Then select entries by ID. For example:

@verbatim{
racket slides/run-gallery.rkt \
  --entry semantic-parts --entry semantic-math \
  --entry semantic-geometry --entry semantic-math-geometry \
  --videos --workers 10 --dark slides-output/semantic-review
}

Or inspect all layout variants in portrait without making movies:

@verbatim{
racket slides/run-gallery.rkt --category layouts --format portrait \
  --dark slides-output/portrait-review
}

@bold{Watch for:} an unknown entry usually means the requested name is wrong or
the update providing it was not applied. Check @tt{--list} before a long render.
@bold{Details:} @secref["reference-gallery-cli"].

@section[#:tag "recipe-review-slides"]{Compare Pict and Scene output and keep the logs}

@verbatim{
racket slides/run-probes.rkt --repeat 2 --gallery --math --geometry \
  slides-output/layout-review
}

The output contains paired PNGs, @tt{index.html}, @tt{manifest.json},
@tt{stdout.txt}, and @tt{stderr.txt}. The sibling @tt{layout-review.zip} includes
the transcripts written before it is created. You do not need to redirect the
shell output to capture the runner's normal output.

Do not create @tt{layout-review} first. The runner refuses an existing file or
directory so it cannot mix new results with an older run. Setup errors before
transcript creation and errors while creating the ZIP may still require terminal
output; a failed ZIP cannot contain messages written after its creation failed.

Start by reading the @tt{errors} array in the manifest. Then open the HTML page
and inspect the pictures. A successful comparison is not proof that your
wording, spacing, or timing is good.

@bold{Details:} @secref["reference-probe-cli"].

@section[#:tag "recipe-diagnose-slide"]{Find the cause of a failed slide render}

First distinguish three failures. @bold{Compilation} errors happen before the
program runs. @bold{Preparation} errors include missing assets, bad selectors,
and content that does not fit. @bold{Rendering or encoding} errors happen after
those stages.

For layout issues, inspect a shot in its storyboard context:

@verbatim{
(require animate/slides/pict)
(slide->pict (storyboard-ref film 'rule)
             #:at '(example end)
             #:debug '(slots safe-area baselines))
}

Here @tt{film} is the example from @secref["guide-slides"]. A standalone preview
of its card can use different inherited settings, so it may not show the same
problem. Reduce the text or choose another layout before reducing its font size.

For semantic matching, prepare the storyboard and inspect
@tt{storyboard-match-report}. For worker failures, retain the execution report
and terminal output. See @secref["reference-slide-inspection"].
