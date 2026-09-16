#lang scribble/manual

@title[#:tag "guide-slides"]{Themeable Slide Layouts}

The @tt{animate/slides} subcollection describes immutable slides, rather than
adding a second renderer or video timeline. A slide assigns named content roles
to a layout; a theme supplies colors, typography, spacing, and decoration. A
clip adds beats and local content clocks, while a storyboard arranges clips and
transitions. The resolved result can be a static Pict or an ordinary Animate Scene.

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
@tt{subtitle}. @tt{make-slide} is the procedural API. A plain
@tt{slide->scene} has duration zero; use @tt{hold-slide} or
@tt{build-slide} when authoring time.

Use @tt{animate/slides/pict} for static conversion and
@tt{animate/slides/scene} for Scene and authored-timeline conversion. The explicit
@tt{animate/slides/render} and @tt{animate/slides/project} modules prepare
reusable layouts and project sources. @tt{animate/slides/math} and
@tt{animate/slides/geometry} embed mathematical plans and geometry programs;
geometry supports the module-backed worker route using parent-prepared data.

@section{An author-facing gallery}

The optional @tt{animate/slides/gallery} module exposes 42 entries covering
twelve layouts, twenty-three transition examples, and seven native integration
examples, including simultaneous geometry and algebra. Catalogue inspection
does not typeset formulas or write output.

@verbatim{
(require animate/slides animate/slides/gallery)

(define film
  (make-slide-gallery
   #:entries '(layout-title+figure push-left math-derivation)
   #:theme lecture-dark))}

@tt{select-slide-gallery-entries} accepts @tt{#:entries} or @tt{#:category}
(@tt{'layouts}, @tt{'transitions}, or @tt{'integration}). Explicit selection order
is preserved. Each entry exposes its ID, title, description, required subsystems,
authoring example, and source path through the @tt{slide-gallery-entry-} accessors.

The command-line gallery writes a browsable HTML index, posters, timestamped
frame strips, reusable storyboard sources, and a review ZIP. Videos are optional:

@verbatim{
racket slides/run-gallery.rkt --list
racket slides/run-gallery.rkt --category transitions --videos --workers 10 --dark slides-output/transitions
racket slides/run-gallery.rkt --category layouts --format portrait slides-output/portrait
racket slides/run-gallery.rkt --category integration --videos --workers 10 slides-output/integration}

Use a fresh output directory. Open its @tt{index.html} to view the gallery.
Geometry-containing videos now use the existing module-backed project executor
with the requested worker capacity. The console and manifest record actual worker
starts. @tt{--in-process} remains an explicit local override. Required TeX/dvisvgm or FFmpeg
failures are reported per entry, not replaced by fabricated preview images.

@section{Transitions}

@verbatim{
(storyboard-cut)
(slide-transition #:effect 'crossfade #:duration 0.6)
(slide-transition #:effect 'match #:keys '(topic) #:duration 0.7)
(slide-transition #:effect 'push #:direction 'left #:easing 'smooth #:duration 0.8)
(slide-transition #:effect 'wipe #:direction 'up #:duration 1)
(slide-transition #:effect 'cover #:direction 'left #:duration 0.8)
(slide-transition #:effect 'uncover #:direction 'right #:duration 0.8)
(slide-transition #:effect 'zoom #:scale 0.82 #:duration 0.9)
(slide-transition #:effect 'fade-through #:color "#101820" #:duration 0.8)}

Direction names describe travel. For example, a leftward push brings the
incoming composition from the right. A wipe moves only the reveal boundary;
cover moves only the destination; uncover moves only the source. These effects
move or clip backgrounds and decorations consistently with content and require
opaque endpoint backgrounds.

Easing choices are @tt{'linear}, @tt{'smooth}, @tt{'ease-in}, @tt{'ease-out}, and
@tt{'ease-in-out}; linear remains the default. Zoom's scale is strictly between
zero and one. Its source grows from one to the reciprocal scale, and the incoming
composition grows from the scale to one. Fade-through accepts an opaque color,
resolved under the destination theme, and passes through it at eased progress
one half. Inapplicable options are rejected.

Transitions have their own duration and freeze the outgoing endpoint and incoming
starting state. Storyboard @tt{#:motion 'reduced} replaces spatial transitions,
including matched relocation, with same-duration/easing crossfades. Matching
retains compatible prepared assets; it does not invent glyph or formula morphs.
Both output adapters consume the same resolved transition geometry.

@section{Tests and documentation}

The core authoring guide is at @tt{slides/docs/user-guide.md}. The current API is
@tt{slides/docs/api.md}; the gallery and transition guide is
@tt{slides/docs/gallery-and-transitions.md}. The v0.4.0 execution status is recorded
in @tt{slides/docs/validation-v040.md}, separately from the v0.1.4 evidence.

@verbatim{
racket slides/run-tests.rkt --math --geometry --media --project
racket slides/run-probes.rkt --repeat 2 --math --geometry --gallery slides-output/review-v040}

The extended probe run includes transition interiors as well as boundaries,
light/dark and wide/portrait views, and real domain content. Output belongs under
@tt{slides-output/}, intentionally ignored by Git. Prepared payloads use schema
version 4; older payloads must be prepared again.


@section{Semantic continuity}

@tt{semantic-group} contains explicitly named @tt{semantic-part} children,
including nested groups. A matched outer slot can therefore change layout while
its children change position independently. Added and removed children fade;
changed appearances crossfade without guessing glyph correspondences.

@tt{content-state} freezes a checkpoint of an existing mathematical presentation,
geometry timeline, or native Scene. Two compatible checkpoints of the same domain
source can replay the original interval while the containing slot moves:

@verbatim{
(content-state (math-content plan)
               #:at '(subtract-five start) #:viewport '(12 7))

(slide-transition #:effect 'match #:keys '(equation)
                  #:depth 'semantic #:duration 4 #:easing 'smooth)}

The default matching depth is @tt{auto}; @tt{semantic} rejects unsupported
correspondences, and @tt{slot} retains the earlier prepared-asset policy.
@tt{storyboard-match-report} from @tt{animate/slides/render} returns the actual
prepared correspondence as immutable data. Reduced motion crossfades the frozen
endpoints without replay. Content-state replay is visual-only.

This mechanism does not infer algebra from unrelated expressions or re-solve
changed free-point assignments in independent constructions. The existing domain
timeline supplies the witness. The full design, contracts, and examples are in
@tt{slides/docs/semantic-matching.md}; the gallery entries are
@tt{semantic-parts}, @tt{semantic-math}, @tt{semantic-geometry}, and
@tt{semantic-math-geometry}.


@section{Geometry in the shared worker pool}

The parent captures drawable geometry, reveal provenance, resolved styles,
annotation placement, and the original presentation event schedule once.
Content-addressed data artifacts are verified through the ordinary project
preparation manifest. Workers reconstruct the native sampler without repeating
construction realization or annotation layout. Mathematical and geometry
checkpoint replays can share the same worker pool.

The plan, wire contract, safeguards, and runnable acceptance commands are in
@tt{slides/docs/geometry-workers.md}. Workers still need the same Racket version,
installed fonts, and package source as the parent. This is not a new renderer or
an automatic guarantee of tenfold speedup.
