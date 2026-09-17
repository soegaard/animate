#lang scribble/manual

@title[#:tag "reference-slide-tools"]{Slide command-line tools}

These tools are source files in the repository. Run them from the repository
root. @tt{racket} below can be replaced with the path to your Racket executable.
Gallery and probe output directories must not already exist.

@section[#:tag "reference-gallery-cli"]{Gallery runner}

@verbatim{racket slides/run-gallery.rkt [options] [directory]}

The default directory is @tt{slides-output/gallery}. The runner writes an HTML
index, posters, sampled PNG strips, a manifest, and reusable storyboard sources.
It makes a sibling ZIP unless disabled. Videos are optional.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Option} @bold{Meaning})
  (list @tt{--list} "List selected entries without rendering.")
  (list @tt{--entry ID} "Select an entry. Repeat to select several in order.")
  (list @tt{--category NAME} "layouts, transitions, or integration.")
  (list @tt{--light / --dark} "Choose the lecture theme; default light.")
  (list @tt{--format NAME} "widescreen, standard, portrait, or square.")
  (list @tt{--videos / --mp4} "Also produce an MP4 for each selected entry.")
  (list @tt{--workers N} "Positive frame-worker capacity; default 1.")
  (list @tt{--fps N} "Positive integer video frame rate; default 30.")
  (list @tt{--width N} "Positive pixel width; default 960. Height follows format.")
  (list @tt{--repeat N} "Repeat static samples; default 2.")
  (list @tt{--reduced-motion} "Use the storyboard reduced-motion policy.")
  (list @tt{--in-process} "Explicitly use local video rendering.")
  (list @tt{--no-zip} "Do not create a ZIP."))]

An explicit entry/category combination must agree. Unknown IDs are errors.
The current catalogue has 42 entries; use @tt{--list} rather than assuming
that a name is present in an older installation.

Geometry videos use the module-backed project path and honor the requested
worker capacity. The console and manifest report actual worker starts.
The number requested is not proof that that many workers did useful work.
The gallery's repeat check is not the Pict/Scene comparison performed by the
separate probe runner.

@section[#:tag "reference-probe-cli"]{Visual probe runner}

@verbatim{racket slides/run-probes.rkt [options] [directory]}

The default directory is @tt{slides-output/probes}. Options are @tt{--repeat N}
(default 2), @tt{--gallery}, @tt{--math}, @tt{--geometry}, and @tt{--no-zip}.
There is no @tt{--workers} option on this tool. A probe review is not a
measurement of subprocess rendering performance.

The base run covers the built-in layouts in both themes and four formats, plus
selected ordinary examples. @tt{--gallery} adds gallery samples in light/dark and
wide/portrait formats. Math and geometry flags enable their optional examples.
Samples include boundaries and interior times, in reverse seek order.

Each comparison produces a @tt{-pict.png} and @tt{-scene.png}. The runner checks
that repeat renders within each path have identical pixel bytes. It separately
compares the two rendering paths, which may differ at antialiased edges.

@section{Files and transcript scope}

@tt{index.html} shows paired pictures and links to @tt{stdout.txt} and
@tt{stderr.txt}. The runner still writes to the terminal. Logging starts after
argument validation and output-directory creation, so errors before that point
are not recorded there. The logs contain output sent through the runner's
Racket output/error ports; this is not a general operating-system transcript
of every possible child-process file descriptor.

On normal completion, the runner prints its summary, flushes the logs, and then
creates the ZIP. Thus the ZIP contains those transcripts through the summary.
ZIP-creation failures cannot be recorded inside a successfully completed ZIP
that does not exist.

@section{Manifest fields}

The probe manifest is JSON with this schema label:
@tt{animate-slides-probes-v3}. It records:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Field} @bold{Meaning})
  (list @tt{schema} "Manifest format label.")
  (list @tt{racket} "Racket version that ran the probes.")
  (list @tt{repeat} "Number of repeated renders per sample.")
  (list @tt{composition-mean-threshold} "Pict/Scene mean-channel threshold: 0.10.")
  (list @tt{stdout} "stdout.txt")
  (list @tt{stderr} "stderr.txt")
  (list @tt{comparisons} "Sample names, image names, SHA-1 values, and pixel differences.")
  (list @tt{errors} "Probe names and recorded exception messages."))]

The threshold uses raw 8-bit channel units, on a 0--255 scale. It is not 10 percent
and not a geometric distance in pixels. A mean difference above 0.10 fails the
comparison. A nonzero maximum difference alone does not fail it. Inspect a
reported failure before changing the tolerance.

The runner exits with status 0 when its recorded errors list is empty and 1
otherwise. Earlier fatal setup errors can stop it before a manifest exists.
No probe count or absence of errors proves that a lesson is well designed.

@section{Test runner}

@verbatim{racket slides/run-tests.rkt --math --geometry --media --project}

Without flags, the runner selects its base suites. The flags add the relevant
integration suites, including real external tools and worker paths. Use the
reported suite results as evidence for the installation you actually tested.
Do not infer a pass count from a release label in this manual.
