# Themeable layouts: implementation guide

Version 0.1.4 · 16 September 2026

This guide describes the **supplied implementation**, rather than proposed future
syntax. It accompanies source that has not yet been compiled or executed in a
Racket runtime in the delivery environment. Run the supplied suites and visual
probes on the target checkout before treating it as production-ready.

## 1. Content, appearance, and timing

A **theme** combines Animate's existing color and typography snapshots with
spacing and decoration choices. A **layout** assigns named content roles to
regions. A **slide** supplies content for those roles. A **clip** gives that slide
a timed presentation. A **storyboard** orders clips, transitions, appearance,
and media policy for the video.

These are immutable values. Changing a theme or adding a clip does not mutate the
slide used elsewhere. A slide may be a title card, a normal content slide, a
mathematical workspace, or a frame around a native animated diagram.

Normal authoring uses `#lang racket/base`, not a special language or a second
rendering system. The supported Animate imports do not require prefixes.

```racket
#lang racket/base
(require animate/slides
         animate/slides/pict
         animate/slides/scene)

(define welcome
  (slide #:id 'welcome #:layout 'title
    [title "Solving equations"]
    [subtitle "Keep both sides equal."]))

(define picture (slide->pict welcome))
(define scene (slide->scene (hold-slide welcome #:duration 3)))
```

The labels `title` and `subtitle` are literal names in the `slide` syntax, not
variable references or names that the library exports into your program.

## 2. The two output functions

`slide->pict` of a plain slide produces its fully populated static composition.
`slide->scene` of that same slide produces a **zero-duration native Scene** with
that composition. Neither function invents a movie duration.

A slide clip has a duration, an initial visibility policy, named beats, and a
poster selection. Its default poster is its exact endpoint. An embedded animation
can independently choose its static poster, typically its endpoint. That does
not advance its local clock inside a running clip.

```racket
(define opening
  (build-slide welcome #:initial 'hidden
    (beat 'heading #:duration 1
      (reveal-slot 'title #:duration 0.4))
    (beat 'explanation #:duration 3
      (reveal-slot 'subtitle #:duration 0.5))))

(slide->pict opening)                         ; default poster: endpoint
(slide->pict opening #:at 1.25)               ; a timed frame
(slide->pict opening #:at '(heading end))     ; exact named boundary
(slide->scene opening)                        ; full four-second animation
```

Both adapters use the same prepared rectangles and time-state calculation.
They do not independently lay out each animation frame. Pixel antialiasing may
vary between drawing paths or hosts, but content states and placement agree.

`storyboard->pict` samples the assembled video. `storyboard->picts` produces one
poster per shot. `storyboard->scene` is visual-only; `storyboard->timeline` also
preserves sections, cue markers, narration audio, and timed subtitles in an
ordinary Animate authored timeline.

## 3. Supplying content

A string becomes text using the role assigned by the layout. For explicit text
content, use `paragraph-content`:

```racket
(define goal
  (slide #:id 'goal #:layout 'title+body
    [title "What are we trying to find?"]
    [body
     (bullets
      [value "Find a value of x."]
      [test "Substitute it into the original equation."]
      [truth "Check that the equation becomes true."]) ]))
```

Bullet IDs are stable names. Use `'(body truth)` rather than a positional index.
Bullet items currently accept strings and `paragraph-content`, not arbitrary
nested figures. `(bullets #:ordered? #t ...)` produces numbered items.

`paragraph-content` can select a typography role or line alignment:

```racket
(paragraph-content "A line of explanation.\nA second line."
                   #:role 'body #:align 'left)
```

This is deliberately different from Animate's existing native `paragraph`
constructor. Reusing that name for a different type would make the intended
unprefixed module combination conflict.

### Programmatic slides

`slide` and `make-slide` create the same type. Use the latter for computed slots:

```racket
(define (chapter-card id heading description)
  (make-slide #:id id #:layout 'section
    #:slots (hash 'title heading 'subtitle description)))

(define chapter-two
  (chapter-card 'chapter-two "Quadratic equations" "A new problem, the same principle."))
```

`slot-content` provides the procedural counterpart of slot-clause options:

```racket
(make-slide #:id 'recap #:layout 'title+body
  #:slots
  (hash 'title (slot-content "Functions" #:key 'lesson-heading)
        'body "A function maps an input to an output."))
```

Mutable strings, lists, and hash inputs are copied into immutable declarations.
Opaque Picts, native values, and author factories retain their own adapter
contracts. Factories must not depend on uncontrolled mutable state.

## 4. Layout catalogue and fixed geometry

| Layout | Required slots | Optional slots |
|---|---|---|
| `title` | title | subtitle |
| `section` | title | subtitle |
| `title+body` | title, body | — |
| `title+two-column` | title, left, right | — |
| `title+figure` | title, figure | body |
| `figure+caption` | figure | caption |
| `figure-full` | figure | — |
| `equation-focus` | equation | annotation |
| `equation+explanation` | equation, body | title |
| `theorem` | title, statement | body |
| `quote` | quote | attribution |
| `blank` | — | content |

Every layout also permits a `footer`. A footer is not a narration subtitle.
`figure-full` deliberately uses the full available canvas, excluding any reserved
footer/subtitle band. Other layouts use the safe margins.

All built-ins support widescreen, standard, portrait, and square formats.
Side-by-side layouts stack content in portrait orientation. In particular,
`title+two-column` uses the natural heights of the two text regions plus one
section gap instead of stretching the pair over the full portrait canvas.
`title+figure` gives natural-height explanatory text to the upper region and the
remaining area to the figure; it releases the body region entirely when `body`
is omitted. `equation-focus` centers the equation and optional annotation as one
rhetorical block. Hiding supplied content does **not** release its region.

Text is measured at a fixed authoring scale of 100 pixels per world unit; final
output resolution does not change wrapping. All declared replacement alternatives
are prepared before playback. Header regions reserve their maximum required
height, and body slots retain their resolved regions for the whole clip.

Natural text overflow fails rather than silently shrinking. Images and opaque
figures can use `contain` (preserve aspect), `cover` (explicitly crop), or `natural`.
Cover crops produce an informational diagnostic. Bullet lists retain natural
text size. Native math preparation rejects fitting below the theme's
`math-minimum-scale`, initially 0.7 of the mathematical plan's requested size.

Layout validation does not prove that arbitrary moving native geometry never
collides. Native components retain a declared viewport and require visual review.

## 5. Themes and formats

Use the same source with either built-in theme:

```racket
(slide->pict goal #:theme lecture-light)
(slide->pict goal #:theme lecture-dark)
```

`slide-theme` extends the existing Animate color and typography systems:

```racket
(require animate/typography)

(define course-type
  (typography-theme #:id 'course-type
    #:extends (slide-theme-typography lecture-dark)
    #:styles
    (hash 'title
          (text-style-update
           (typography-ref (slide-theme-typography lecture-dark) 'title)
           #:font-family 'roman #:font-size 0.72))))

(define course-theme
  (slide-theme #:id 'course #:extends lecture-dark
    #:typography course-type
    #:spacing (hash 'safe-x 0.8 'safe-y 0.55 'column-gap 0.7)
    #:decorations (hash 'title-rule? #t)))
```

Theme sizes are authoring units. The predefined formats are `widescreen` (16×9),
`standard` (12×9), `portrait` (9×16), and `square-format` (12×12).
`slide-format` creates another explicit format.

A plain slide inherits the converter's requested theme, or the built-in light
theme. In a storyboard it inherits the storyboard theme. An explicit `#:theme`
on the slide takes precedence. Prepared content is frozen: requesting different
appearance or format from a prepared value is an error; prepare the original
source again instead.

```racket
(storyboard-with-theme film lecture-dark)
(storyboard-with-format film portrait)
```

Portrait conversion is not a guarantee that any amount of text fits. Inspect and
validate the alternate format. A different output size with the same aspect
ratio needs no reflow; a different aspect requires another format or explicit
`#:fit 'letterbox`.

```racket
(slide->pict welcome #:size '(1920 1080))
(slide->pict welcome #:size '(800 800) #:fit 'letterbox)
```

Motion is separate from appearance. `#:motion 'reduced` removes emphasis scaling
and uses immediate reveals while preserving action and beat intervals. This
release has `normal` and `reduced`, not arbitrary motion-profile objects.

## 6. Beats and actions

Beats are sequential. Actions within a beat are parallel; `#:at` is an offset
relative to that beat. An action that overruns an explicitly timed beat is an
error. Conflicting writes to the same property, including overlapping parent
and child visibility actions, are errors rather than source-order tie-breaks.

```racket
(define explanation
  (build-slide goal #:initial '(title)
    (beat 'steps #:duration 4
      (reveal-slot '(body value) #:duration 0.3)
      (reveal-slot '(body test) #:at 1 #:duration 0.3)
      (reveal-slot '(body truth) #:at 2 #:duration 0.3))
    (beat 'attention #:duration 2
      (emphasize-slot '(body truth) #:duration 1))
    (beat 'read #:duration 2)))
```

`#:initial` accepts `visible`, `hidden`, or a list of selectors. Visibility changes
persist; `conceal-slot` does not remove layout space. Emphasis restores the base
scale. `replace-content` replaces a complete slot, crossfading prepared alternatives.
It is not an algebra operation or a glyph-matching engine.

```racket
(beat 'result #:duration 3
  (replace-content 'body "The output is seven." #:duration 0.5))
```

The initial reveal vocabulary is `fade` and `instant`; replacement supports
`crossfade` and `instant`. Unsupported effect names are rejected. Native path
writing and mathematical choreography belong inside native components.

## 7. Medium example: a complete short video

`examples/function-lesson.rkt` contains the complete source below. It requires no
TeX or audio assets and produces a 19.6-second silent video.

```racket
#lang racket/base
(require animate/slides)
(provide film)

(define opening
  (hold-slide
   (slide #:id 'opening #:layout 'title
     [title "A function is a rule"]
     [subtitle "Double, then add one."])
   #:duration 3))

(define rule-slide
  (slide #:id 'rule #:layout 'title+two-column
    [title #:key 'heading "A function is a rule"]
    [left (bullets [double "Double the input."] [add "Add one."])]
    [right (paragraph-content "Input: 3\nDouble it: 6\nAdd one: 7")]))

(define rule-clip
  (build-slide rule-slide #:initial '(title)
    (beat 'rule #:duration 4 (reveal-slot 'left #:duration 0.5))
    (beat 'example #:duration 5 (reveal-slot 'right #:duration 0.5))
    (beat 'read #:duration 2)))

(define recap-clip
  (build-slide
   (slide #:id 'recap #:layout 'title+body
     [title #:key 'heading "A function is a rule"]
     [body (bullets [rule "The rule is f(x) = 2x + 1."]
                     [example "For input 3, the output is 7."])])
   #:initial '(title)
   (beat 'summary #:duration 5 (reveal-slot 'body #:duration 0.5))))

(define film
  (storyboard #:id 'functions #:theme lecture-light
    (storyboard-shot 'opening opening)
    (storyboard-cut)
    (storyboard-shot 'rule rule-clip)
    (slide-transition #:effect 'match #:keys '(heading) #:duration 0.6)
    (storyboard-shot 'recap recap-clip)))
```

The title is visible at the incoming clip's start because the transition retains
it. The body then enters once, during its beat. A title that is hidden at the
incoming endpoint cannot be used for a visible keyed match.

## 8. Transition time and identity

Transitions occupy an extra interval between clips. Their endpoints are the
source clip's exact end and the destination clip's exact start. Neither local
content clock advances during the bridge.

Total duration is the sum of clip durations plus transition durations. Adjacent
shots without a transition receive a zero-duration cut.

A role is not an identity. Both slides can have `title` slots without sharing a
heading. A continuity key explicitly requests a conceptual correspondence.
Matching identical prepared text retains it and interpolates its position/size.
Different text or reflowed lines crossfade. Opaque Picts and arbitrary native
components currently crossfade even when keyed; no unsupported internal matching
is invented. Mathematical term matching remains the responsibility of `animate/math`.

Missing keys and wholly invisible matched endpoints fail preparation. Ambiguous
keys within a slide fail construction. Source and destination chrome/colors are
part of the bridge state as well.

## 9. Narration and subtitles

Start with a silent draft that provides pacing and transcript text:

```racket
(beat 'meaning
  #:narration
  (narration "We are looking for a value that makes the equation true."
             #:draft-duration 4)
  (reveal-slot 'body #:duration 0.5))
```

Replace it with a recording when available:

```racket
(beat 'meaning
  #:narration
  (narration "We are looking for a value that makes the equation true."
             #:audio "voice/meaning.wav")
  #:tail-hold 0.4
  (reveal-slot 'body #:duration 0.5))
```

The narration macro captures the declaring module's asset directory. Programmatic
`make-narration` needs an absolute path or explicit `#:asset-base` for relative
assets. No duration is guessed from word count, and no speech is synthesized.

Without explicit beat duration, the duration is the maximum visual/audio extent,
plus `#:tail-hold`. With explicit duration, all of those intervals must fit.
Recordings are inspected by `ffprobe` at preparation; source trimming is explicit
through `#:source-start` and `#:duration`. `#:at` delays the narration inside the
beat without shifting visual action offsets.

Subtitles are enabled by default for storyboard narration, including drafts.
A consistent subtitle band is reserved for the whole storyboard when narration
or explicitly imported child media is present. The ordinary Pict/Scene output
does not burn these subtitles into the composition: they are a separate authored
timeline track, consumed by the existing media system. Figure captions remain
ordinary visible slot content.

`#:captions` on narration can provide ordered `(list start end text)` segments
relative to the selected recording interval. An empty list suppresses that
narration's subtitles. Overlapping or overlong caption segments are errors.
`#:subtitles? #f` disables the storyboard subtitle track and its reservation.

## 10. Medium example: a mathematical explanation

The slide layer does not implement algebra. It embeds a mathematical presentation
plan, prepares it for the assigned region, and drives its native local clock.

```racket
#lang racket/base
(require animate/math animate/slides animate/slides/math)
(provide film)

(define problem
  (math '(= (+ (* 3 x) 5) 17) #:id 'problem
        #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-rhs (evaluate #:at (rhs))]))

(define plan
  (present working #:style classroom
    #:groups '((subtract-five cancel-five evaluate-rhs))))

(define card
  (slide #:id 'subtraction #:layout 'title+figure
    [title "Subtract five from both sides"]
    [figure (math-content plan #:poster 'end)]))

(define clip
  (build-slide card
    (beat 'goal #:narration
      (narration "Remove the added five from the left side." #:draft-duration 4))
    (beat 'subtract #:narration
      (narration "Subtract five on both sides." #:draft-duration 3)
      (play-content 'figure #:to '(subtract-five end)))
    (beat 'cancel #:narration
      (narration "The opposite terms cancel." #:draft-duration 3)
      (play-content 'figure #:to '(cancel-five end)))
    (beat 'calculate #:narration
      (narration "Seventeen minus five is twelve." #:draft-duration 3)
      (play-content 'figure #:to '(evaluate-rhs end)))
    (beat 'read-result #:duration 3)))

(define film
  (storyboard #:id 'subtraction #:theme lecture-dark
    (storyboard-shot 'subtract-five clip)))
```

This teaches the subtraction step and ends at `3x = 12`. It is not the full
solution. The current native math presentation retains mathematical context and
branch headings inside its viewport; the adapter suppresses a duplicate lesson
title but does not redesign those mathematical layouts.

`play-content` resumes from the previously reached local time unless `#:from`
explicitly resets it. Named cue times come from actual native compilation,
including copy/hold phases, not an estimate from the abstract plan duration.
Ambiguous unqualified math step names are omitted; use `(list segment-index
step-name 'start)` or `... 'end` for a qualified boundary.

A different playback duration requires `#:retime 'stretch`. Imported audio may
not be stretched. During a parent hold or transition, the local mathematical
clock stays still. A plain slide Pict uses the component's `#:poster`; a timed
clip follows its authored clock, initially zero.

## 11. Picts, native scenes, and geometry

A Pict factory receives a frozen theme/format/region context during preparation:

```racket
(require (only-in pict disk colorize))

(define disc-card
  (slide #:layout 'figure+caption
    [figure
     (pict-content
      (lambda (ctx)
        (colorize (disk 140) (content-color ctx 'accent))))]
    [caption "A theme-aware Pict."]))
```

The context offers `content-color`, `content-width`, `content-height`,
`content-theme`, and `content-format`. Factories must be deterministic and should
use this explicit context rather than a mutable global theme. A ready-made Pict
is also accepted and retains its own literal appearance. Its internal objects
are not promoted into semantic selectors.

`scene-content` embeds an ordinary Scene without pre-rendering a movie. Its
camera viewport supplies a stable envelope, and its Visual state is sampled at
the embedded clock. The included `examples/native-scene.rkt` demonstrates this.
Use `visual-content` for a single native Visual; optional `#:width`/`#:height`
provide its envelope. Native scenes with resource-dependent formulas must already
satisfy their own preparation contract; `math-content` is the supported automatic
TeX-preparation route.

An authored timeline carrying media requires an explicit `#:media 'import` or
`#:media 'visual-only`. Imported media only plays while its local clock advances.
Cues need explicit durations. Full faded cues retain their envelopes; partial
trimming through a faded envelope is rejected rather than approximated. Imported
recordings should use `define-runtime-path` or another complete path. Overlapping
parent/child subtitles are rejected so that the author chooses the intended track.

`geometry-content` accepts a geometry program or timeline and retains native
construction animation. Geometry's labels/markers use its own prepared layout.
**Its portable worker-preparation codec is not included in this release.** Use a
direct, prepared timeline and the in-process executor, or the supplied runner's
`--in-process` flag. This is not a claim that geometry can never use subprocesses;
it is the boundary of this adapter version.

## 12. Continue with ordinary Animate

A converted result is a native Scene. Its named slot groups have their own
centers and can receive normal animation after conversion:

```racket
(require animate)

(define sc (slide->scene welcome))
(define title-visual (scene-slot-ref sc 'title))
(define fading-title
  (scene-play sc (fade-out title-visual) #:duration 0.5))
```

For direct requests by ID, use `(scene-slot-id 'title)`. For a storyboard,
`'(rule title)` qualifies the occurrence. The encoded IDs avoid collisions with
internal clocks and roots. At a clip endpoint, live layout relations are replaced
in the Scene's current state by concrete groups; appending native animation does
not fight a layout resolver.

The historical clip remains directly seekable. The new Scene does not mutate the
original slide or change `slide->pict` of that source. An embedded native viewport
remains a component boundary: its inner formula terms are not ordinary outer
Scene selection paths. Choreograph its internals through its own source/API.

## 13. A custom layout

Box composition is deterministic; it is not a general constraint solver.

```racket
(define comparison-layout
  (layout #:id 'comparison
    #:slots (list (slot-spec 'title #:required? #t #:role 'title)
                   (slot-spec 'before #:required? #t)
                   (slot-spec 'after #:required? #t))
    #:arrange
    (vbox
     (region 'title #:basis 'content)
     (hbox #:grow 1
       (region 'before #:grow 1)
       (region 'after #:grow 1)))
    #:portrait
    (vbox
     (region 'title #:basis 'content)
     (region 'before #:grow 1)
     (region 'after #:grow 1))))
```

The root receives the safe rectangle. Numeric `#:basis` reserves space on the
parent's main axis; `'content` asks for measured intrinsic size. `#:grow` divides
remaining space proportionally, respecting minima and maxima. `#:gap` accepts a
number or theme spacing key. Regions support alignment and padding.

Every variant declares each semantic region exactly once. Optional custom regions
remain governed by that explicit tree; hiding or omitting content does not cause
an uncontrolled re-layout. Standard output uses the standard variant, or the wide
one when absent. Portrait needs a portrait variant. Other custom formats require
an explicit `#:fallback 'wide` or a suitable new layout.

Unsatisfiable basis sizes, negative available space, undeclared regions, missing
required slots, and unsupported variants fail preparation. There is no cyclic
anchor language or general automatic responsive search in this release.

## 14. Preparing and rendering a longer project

Descriptions are safe to export from ordinary modules. Requiring a lesson must
not typeset formulas, inspect recordings, or render frames. Use explicit adapters:

```racket
(require animate/slides/render animate/slides/scene)
(define prepared (prepare-storyboard! film))
(define timeline (storyboard->timeline prepared))
```

For production subprocesses, the existing project system owns worker count,
resolution, frame grid, encoding, and cancellation. The slide adapter supplies a
restartable source with parent-owned preparation:

```racket
(require animate/project animate/slides/project)

(define project
  (animate-project #:id 'function-video
    #:source (storyboard-source "function-lesson.rkt" 'film)
    #:render
    (render-spec #:fps 30 #:width 1280 #:height 720 #:workers 10
      #:theme (slide-theme-colors lecture-light)
      #:typography (slide-theme-typography lecture-light))
    #:output (output-spec #:root "out" #:name "function-video")
    #:cache (cache-spec #:policy 'off)))
```

Then `(render-project! project)` from `animate/render` uses the ordinary executor.
The project color/typography snapshot must match the source storyboard theme.
That check prevents layout being measured in one appearance and rendered in another.
`slides/render-example.rkt` configures these fields from the exported storyboard.

The parent prepares text/Pict drawing commands and typeset math data. Workers
rebind the data and prepared artifacts; they do not run the slide text layout,
Pict factories, or TeX preparation again. Drawing commands remain vector commands,
not a pre-rendered whole-slide image. Arbitrary native sources are reconstructed
from their declared module; those sources must honor their own no-effects contract.

Artifacts are content-addressed under `.animate-slide-preparation-v1` and, for
math, the existing `.animate-math-preparation-artifacts-v1`. They are verified
source-preparation inputs, not a promise of cross-session frame-cache reuse.
Opaque relation/viewport semantics conservatively decline persistent frame caching;
the examples use `#:policy 'off`. Prepared artifacts assume the same Racket and
font environment; no font binaries are included or transferred.

## 15. Inspection and validation

Review a shot in its storyboard context:

```racket
(slide->pict (storyboard-ref film 'rule)
             #:at '(example end)
             #:debug '(slots safe-area baselines))
```

The contextual reference preserves theme, format, and subtitle reservation.
An isolated slide preview can intentionally use different defaults.

`check-storyboard` on a declaration reports pending preparation. Constructors and
preparation validate structure, measured fit, selectors, timing, media bounds,
and continuity. On a prepared storyboard it returns collected nonfatal layout
information, such as explicit crops. Fatal errors carry `exn:fail:slides?`, a code,
a semantic path, and details. Native subsystem errors retain their original
exception type rather than being disguised as slide validation.

Font fallback and effective raster-resolution advisories are not implemented.
Explicitly named fonts should be installed on the preparation/render host. Inspect
font appearance and readability in the gallery instead of treating absence of an
error as proof of typographic quality.

The supplied runner covers all catalogue layouts in both themes and four formats,
then short videos in reversed seek order, at exact beat boundaries, and one frame
on either side. `--math` and `--geometry` add their real native lessons. It writes
actual paired PNGs, a comparison manifest, an HTML review page, and a ZIP.
There are no placeholder render results in the source archive.

Mathematical foreground/background roles must resolve to opaque colors in this
version; the TeX color adapter rejects alpha rather than silently discarding it.

## 16. Scope of this version

Implemented source includes themes, all twelve built-ins, custom boxes, immutable
slides and clips, deterministic actions, explicit bridges, narration/subtitles,
static/native adapters, domain embedding, and parent-prepared project sources.

The following are deliberately not advertised as implemented: arbitrary path
writing through slot actions, glyph morphing between slides, nested rich bullet
figures, a general constraint solver, automatic speech or word alignment, an
interactive slide-layout editor, custom renderer-factory transfer, a geometry
preparation codec, and font/low-resolution advisories.

Most importantly, **implementation status is not test status**. Read the validation
report, run the code against the target checkout, and review the real gallery.
