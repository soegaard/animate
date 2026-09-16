# Themeable layouts in animate
## Design and video-authoring guide

**Revision 2 — 16 September 2026.** Updated for unprefixed authoring within `animate`, with separate `slide` syntax and procedural `make-slide`. The layout, timing, preparation, and output contracts remain unchanged.

**Status:** historical design document. `animate/slides` now implements the
core authoring, layout, timing, Pict, Scene, mathematics, geometry, rendering,
and project interfaces described here. This document retains ideas that remain
outside the implemented scope; use `api.md`, `user-guide.md`, and
`validation.md` for the current contract and validation evidence.

The central model is:

> **Author content as slides, give those slides timed performances, and assemble the performances into a video. Use the same content for static picts.**

A slide is not necessarily a page in a presentation. It can be a title card, a diagram with commentary, a worked-example workspace, or a composition that stays on screen for a minute while its mathematical contents change.

## 1. The five authoring concepts

| Concept | What the author decides |
|---|---|
| **Theme** | Colors, semantic typography, spacing, decorations, and safe areas. |
| **Layout** | Which content roles exist and how their regions are arranged. |
| **Slide** | The content assigned to those roles, with stable local identities. |
| **Slide clip** | How a slide is presented over time: reveals, pauses, narration, and embedded animations. |
| **Storyboard** | The ordered clips, transitions, appearance context, and media policy for a complete video. |

One refinement to the earlier proposal is important: **`slide` returns an immutable description, not a Scene.** Conversion is explicit:

```text
slide + optional timed build
             |
      resolve and prepare
             |
     shared resolved composition
          /             \
   slide->pict       slide->scene
                         |
                ordinary animate Scene
```

A storyboard also converts to an ordinary authored timeline when it contains narration, subtitles, or section information. There is no new frame renderer and no second global animation clock.

The current repository already has semantic typography, immutable project declarations, authored media timelines, and an explicit preparation boundary in `animate/math`. The implementation builds on those facilities rather than replacing them. See source notes R1–R4.

## 2. Your first slide: one description, two outputs

### Imports and public names

The primary authoring environment is ordinary Racket with `animate`. Supported combinations of the new modules must work with ordinary, unprefixed imports:

```racket
(require animate
         animate/slides
         animate/slides/pict
         animate/slides/scene)
```

Authors should not need `prefix-in`, `except-in`, or `rename-in` to combine these modules. The same requirement applies when adding `animate/math` with `animate/slides/math`, or the corresponding geometry adapter; the supported combinations have regression coverage.

Choose concise names where their meaning is clear. Keep a qualifying word when it distinguishes an actual concept within `animate`, rather than to avoid vocabulary in an unrelated library:

| Public name | Purpose |
|---|---|
| `slide` | Authoring syntax for an immutable slide description with named slots. |
| `make-slide` | Procedural constructor for the same kind of description. |
| `slide?` | Recognize a slide description produced by either constructor. |
| `slide->pict`, `slide->scene` | Convert to a static pict or an ordinary Scene. |
| `build-slide`, `hold-slide` | Give a slide a timed performance. |
| `beat` | Declare a named interval within that performance. |
| `reveal-slot`, `conceal-slot`, `emphasize-slot` | Act on a semantic slot or a named content path within it. |
| `replace-content`, `play-content` | Replace slot content or advance its embedded animation. |
| `slide-transition` | Declare a bridge between slide performances. |
| `storyboard` | Assemble a video from shots and transitions. |
| `storyboard-shot`, `storyboard-cut` | Declare an occurrence of a clip or a zero-duration edit between occurrences. |

The slot-action names distinguish semantic layout targeting from operations on native Visuals. `slide-transition` is deliberately distinct from the mathematical choreography operation `transition` already exported by `animate/math` (R7). `storyboard-shot` and `storyboard-cut` identify storyboard entries, rather than content or within-slide actions. These qualifications express the operations' roles; they are not import prefixes.

Adapters export their integration operations rather than creating competing copies of existing math, typography, or scene APIs. Shared exports must reuse the original bindings. Any new naming conflicts within the documented `animate` combinations must be resolved in the package interfaces, not left as import puzzles for authors.

**`slideshow` does not constrain these names.** Its integration example qualifies the slide API at that boundary. We do not rename `slide`, `slide?`, or `slide->pict` for all video authors, and no special Slideshow naming adapter is required. A custom `#lang` is not needed for ordinary authoring.

### A first complete example

```racket
#lang racket/base

(require animate/slides
         animate/slides/pict
         animate/slides/scene)

(define welcome
  (slide
   #:id 'welcome
   #:layout 'title
   [title "Solving equations"]
   [subtitle "Keep both sides equal."]))

;; A complete static composition.
(define welcome-picture
  (slide->pict welcome))

;; The same composition, held on screen for three seconds.
(define welcome-scene
  (slide->scene
   (hold-slide welcome #:duration 3)))
```

The slot names `title` and `subtitle` express purpose, not coordinates. The theme chooses their typography; the layout chooses their placement. In `slide` syntax, the name at the start of each slot clause is a literal role name, not a reference to a globally exported variable. The content expression after it is an ordinary Racket expression.

A string in a slot becomes semantic text with that slot's default role. Explicit content constructors are available when more control is needed:

```racket
(define goal
  (slide
   #:id 'goal
   #:layout 'title+body
   [title "What are we trying to find?"]
   [body
    (bullets
     [value "Find a value of x."]
     [test "Substitute it into the original equation."]
     [truth "Check that the equation becomes true."])]))
```

The bullet identities are authored names, not numerical positions. An animation can target `'(body truth)` even after another bullet is inserted before it.

### Generating slides with `make-slide`

Use `slide` when writing named slots directly. Use `make-slide` when computing a slot mapping in ordinary Racket:

```racket
(define (make-chapter-slide id heading explanation)
  (make-slide
   #:id id
   #:layout 'title
   #:slots
   (hash 'title heading
         'subtitle explanation)))

(define generated-opening
  (make-chapter-slide 'chapter-one
                      "Solving equations"
                      "Keep both sides equal."))

(slide? generated-opening) ; => #t
```

`slide` and `make-slide` construct the same immutable value type and share the same layout and content validation. Neither constructs a Scene or starts rendering. The syntax is the convenient named-clause frontend; the procedure accepts a hash from slot-name symbols to content values. Placement follows the layout's named regions, not hash iteration order. Shared options such as `#:id`, `#:layout`, `#:theme`, and `#:notes` have the same meaning in both interfaces.

In a clause such as `[title heading]`, `title` names the slot and `heading` is evaluated for its content. Thus `[title title]` is also well-defined inside a function whose argument is called `title`: the first occurrence is the slot name and the second is the argument. The same convention applies to the named items in `bullets`.

### What belongs in a slot?

The basic content forms are strings, paragraphs, lists, images, picts, and native Visuals. Optional adapters accept scenes and semantic math or geometry plans.

Images and other external resources are declarations until preparation. A pict supplied as a value is already drawn content: its internal colors and font choices cannot automatically become theme-aware. A pict factory can instead use the resolved theme, as shown later.

Author notes are separate metadata, supplied with `#:notes`. They never become visible text or narration automatically.

## 3. The precise meaning of `slide->pict` and `slide->scene`

These two functions should have deliberately different output types but the same underlying layout decisions.

| Input | `slide->pict` | `slide->scene` |
|---|---|---|
| A plain slide | Fully populated static composition; embedded animated content uses its declared poster state. | Zero-duration static Scene with the same composition. |
| A slide clip | Its declared poster frame, or the explicitly requested time. | Its complete timed Scene. |
| A prepared slide or clip | Same behavior, using its frozen assets, theme, and geometry. | Same behavior, using that same preparation. |

A plain slide does not acquire an arbitrary movie duration. Use `hold-slide` or `build-slide` to give it time.

Scene conversion is visual-only. Use `storyboard->timeline` to retain audio, timed subtitles, and authored section metadata; a single narrated clip can be placed in a one-shot storyboard. Pict snapshots show the slide composition by default, not the separately rendered narration subtitle track. The storyboard's reserved subtitle band is still respected. Burned-in subtitle inspection belongs to the authored-timeline preview/output path, using the same output policy as the final movie.

For a clip, `slide->pict` accepts a numerical local time or a named beat boundary:

```racket
(slide->pict explanation #:at 2.5)
(slide->pict explanation #:at '(explain end))
```

A clip's default poster is its exact endpoint, unless `build-slide` declares a different `#:poster`. Endpoint means the mathematical end state, even when the movie's last sampled frame is just before it.

**Parity contract:** given the same resolved context and time, the pict adapter and the Scene adapter must use the same content state, glyph placement, slot rectangles, and transforms. This is not a promise that different rasterizers produce byte-identical pixels.

Both converters accept `#:theme`, `#:format`, and `#:size`. The default format is 16:9, with a default output size of 1280 × 720. A different pixel size scales the resolved composition; it does not change line wrapping. An incompatible output aspect ratio requires an explicit fit policy, such as letterboxing, rather than silently stretching the slide.

### Use it with ordinary Racket Slideshow

`pict` is already the functional-picture substrate used by Slideshow. Returning an ordinary pict therefore makes the static output reusable without the video adapter. See R5–R6.

```racket
#lang slideshow

(require (prefix-in sl: animate/slides)
         (prefix-in sl: animate/slides/pict))

(define welcome
  (sl:slide
   #:layout 'title
   [title "Solving equations"]
   [subtitle "Keep both sides equal."]))

;; Unprefixed slide is Racket Slideshow's slide function.
(slide
 (scale-to-fit (sl:slide->pict welcome)
               client-w client-h))
```

This example deliberately uses `prefix-in` because it combines the APIs of two separate systems. All slide-library bindings are qualified only in this Slideshow module; ordinary `animate` examples remain unprefixed. The public names stay `slide`, `slide?`, `slide->pict`, and `slide->scene`. There is no alternate `themed-slide->pict` naming layer. The pict module must not load the movie encoder, initialize the preview GUI, or require the Scene adapter.

## 4. Choosing a layout

The initial catalogue is deliberately small and semantic:

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

Layouts also support optional footer content through shared slide chrome. Narration subtitles are a separate output layer, not another interpretation of the `caption` slot.

`title+figure` places the body beside the figure when supplied; without a body, the figure gets the full content width beneath the title. Portrait variants stack regions instead of pretending that a narrow two-column layout is always readable.

The default catalogue defines variants for widescreen, standard 4:3, and portrait formats. A custom layout must explicitly provide a compatible variant or declare an intentional fallback. Unsupported combinations produce a diagnostic.

Missing required slots, unknown slots, and duplicate slot assignments are errors. An omitted optional slot is structurally absent; a hidden slot is still present and reserves its layout space. Each layout documents whether an omitted optional slot releases its region. The `title+figure` behavior above is one such documented rule.

### Layout is resolved before playback

The title does not occupy less space because it is initially transparent. Revealing a bullet does not push the following bullets down.

All known replacement contents are measured before playback. A slot can reserve the maximum required envelope across those alternatives. Deliberate rearrangement is a transition between resolved states, not an accidental consequence of measuring every frame.

Changing output resolution alone does not reflow content. Changing typography, format, layout, or text requires a new resolution pass.

## 5. Changing the appearance without rewriting content

A slide normally inherits its theme from the storyboard. Previewing it independently can select a theme explicitly:

```racket
(slide->pict goal #:theme lecture-light)
(slide->pict goal #:theme lecture-dark)
```

A slide theme aggregates the existing color-theme and typography-theme values, plus layout spacing and decorations. It does not invent another font-style system. The current semantic-typography example already uses role-based text styles and explicit light/dark rendering snapshots; this proposal extends that approach to placement. See R1.

```racket
(require animate)

(define course-typography
  (typography-theme
   #:id 'course-type
   #:extends animate-typography-theme
   #:styles
   (hash
    'title
    (text-style-update
     (typography-ref animate-typography-theme 'title)
     #:font-size 0.68)
    'body
    (text-style-update
     (typography-ref animate-typography-theme 'body)
     #:font-size 0.38))))

(define course-theme
  (slide-theme
   #:id 'course
   #:extends lecture-dark
   #:typography course-typography
   #:spacing
   (hash 'safe-x 0.75
         'safe-y 0.55
         'column-gap 0.60)))
```

Sizes here are authoring units. The widescreen format is 16 × 9 units; standard format is 12 × 9; portrait is 9 × 16. The output camera supplies the conversion to pixels. Format-specific theme variants can adjust typography for a portrait composition.

Theme precedence is explicit: the built-in default is replaced by the storyboard theme; an explicit slide theme replaces that inherited choice; content-level overrides affect only the specified content. Theme inheritance through `#:extends` copies and overrides named entries rather than introducing mutable global state.

A prepared slide freezes its appearance context. Rendering it under a conflicting typography or color context must either rebuild it explicitly or report a mismatch—not recolor only some of its contents.

### Appearance is separate from motion

Motion defaults belong to a separate `#:motion` profile on the storyboard or clip. A color or font change must not silently change narration timing.

A reduced-motion profile changes how an interval is presented while preserving its authored duration. For example, it may replace a moving entrance with an instantaneous reveal followed by the same hold.

## 6. Giving a slide a timed performance

A **slide clip** combines a slide with a build sequence. Builds consist of named beats.

```racket
(define explanation
  (build-slide
   goal
   #:initial 'hidden
   #:poster '(explain end)

   (beat 'heading #:duration 1
     (reveal-slot 'title #:duration 0.4))

   (beat 'explain #:duration 5
     (reveal-slot 'body #:duration 0.5))

   (beat 'hold #:duration 2)))
```

This clip lasts eight seconds. The body enters at local time 1 and remains visible. The final beat is an explicit two-second pause.

Beats run sequentially. Actions within one beat run in parallel; `#:at` is an offset from that beat's start:

```racket
(beat 'steps #:duration 4
  (reveal-slot '(body value) #:duration 0.3)
  (reveal-slot '(body test) #:at 1 #:duration 0.3)
  (reveal-slot '(body truth) #:at 2 #:duration 0.3))
```

Visibility operations on a group expand to its content leaves. An individually revealed bullet can therefore appear without requiring the author to reveal an invisible ancestor separately. This logical visibility behavior does not override an explicitly authored native opacity animation on an ancestor.

`#:initial` accepts `'visible`, `'hidden`, or a list of initially visible selectors, such as `'(title)`. Slide backgrounds and decorative chrome are not hidden by hiding the content.

### The small action vocabulary

| Action | Meaning |
|---|---|
| `reveal-slot` | Make selected content visible, normally with a fade. |
| `conceal-slot` | Hide selected content without removing its reserved region. |
| `emphasize-slot` | Apply temporary attention styling, then restore the base appearance. |
| `replace-content` | Substitute declared content in the same slot; its alternatives are measured in advance. |
| `play-content` | Advance an embedded animation on its local timeline. |

Visibility persists after an action completes. Emphasis is temporary. Replacement persists. Actions begin from the state at their own start, not from whatever was sampled on a previous rendered frame.

The default effect for `reveal-slot` and `conceal-slot` is a 0.4-second fade. Authors can specify `#:duration` and `#:effect`. Drawing or writing effects require content with a suitable prepared path/part representation; an opaque bitmap does not silently acquire stroke animation.

An action that exceeds an explicitly timed beat is an error. Two simultaneous actions writing the same property of the same target are also an error, including overlapping group/child writes. The system must not silently truncate one action or use source order as an accidental winner.

## 7. Medium example: a complete three-slide video

This example needs no TeX and no audio assets. Formula-like text is intentionally ordinary text; semantic mathematical transformations belong to the math adapter discussed later.

```racket
#lang racket/base

(require animate/slides
         animate/slides/pict
         animate/slides/scene
         animate/render)

(provide film)

(define opening
  (hold-slide
   (slide
    #:id 'opening-card
    #:layout 'title
    [title "A function is a rule"]
    [subtitle "A small example: double, then add one."])
   #:duration 3))

(define rule-slide
  (slide
   #:id 'rule-card
   #:layout 'title+two-column
   [title #:key 'lesson-heading "A function is a rule"]
   [left
    (bullets
     [double "Double the input."]
     [add "Add one."])]
   [right
    (paragraph
     "Input: 3\nDouble it: 6\nAdd one: 7")]))

(define rule-clip
  (build-slide
   rule-slide
   #:initial '(title)
   (beat 'rule #:duration 4
     (reveal-slot 'left #:duration 0.5))
   (beat 'example #:duration 5
     (reveal-slot 'right #:duration 0.5))
   (beat 'read #:duration 2)))

(define recap-slide
  (slide
   #:id 'recap-card
   #:layout 'title+body
   [title #:key 'lesson-heading "A function is a rule"]
   [body
    (bullets
     [rule "The rule is f(x) = 2x + 1."]
     [example "For input 3, the output is 7."])]))

(define recap-clip
  (build-slide
   recap-slide
   #:initial '(title)
   (beat 'summary #:duration 5
     (reveal-slot 'body #:duration 0.5))))

(define film
  (storyboard
   #:id 'function-lesson
   #:theme lecture-light
   #:format widescreen
   (storyboard-shot 'opening opening)
   (storyboard-cut)
   (storyboard-shot 'rule rule-clip)
   (slide-transition
    #:effect 'match
    #:keys '(lesson-heading)
    #:duration 0.6)
   (storyboard-shot 'recap recap-clip)))

;; One poster per shot, with the storyboard's inherited appearance.
(define storyboard-pictures
  (storyboard->picts film))

;; Ordinary animate output types.
(define film-scene
  (storyboard->scene film))

(define film-timeline
  (storyboard->timeline film))

(module+ main
  (render-authored-mp4!
   film-timeline
   "out/functions/frames"
   "out/functions.mp4"
   #:fps 30))
```

The intended duration is **19.6 seconds**: 3 + 11 + 0.6 + 5. The transition adds its own time; it does not consume time from either clip.

The `render-authored-mp4!` call is the existing rendering boundary, not a new slide-specific encoder. The proposed conversion supplies its ordinary authored-timeline input. See R2.

This division of labor matters: revise the wording in `rule-slide`, revise pacing in `rule-clip`, and revise the sequence in `film`. None requires rewriting the other two.

## 8. Transitions, continuity, and identity

A layout role is not an object identity. Two unrelated slides may both have a `title` slot. That does not mean their titles should morph into one another.

Three names serve different purposes:

```text
rule                         storyboard shot / occurrence
  title                      local content role and animation selector
    #:key lesson-heading     optional cross-shot continuity identity
```

Slot paths are namespaced by the shot occurrence. Reusing a slide in two different shots is safe because the occurrences have separate identities.

Matching is explicit. In the medium example, both title contents have `#:key 'lesson-heading`, and the transition opts into that key with `#:keys`.

Unchanged compatible content can remain visible while its placement or scale changes. Different text with the same key does not automatically become a glyph morph: the transition crossfades that content unless an appropriate content-specific matcher is explicitly selected. A math identity is not a proof that two expressions are equal.

An explicitly requested key that is missing or ambiguous is an error. Duplicate continuity keys within one visible composition are also errors. Other, unmatched content uses the transition's ordinary exit/entry effect.

### Transitions occupy an explicit interval

The first design uses additive, frozen-endpoint transitions:

```text
outgoing clip | bridge transition | incoming clip
```

During the bridge, the source is sampled at its exact endpoint and the destination at its exact start. Neither clip's local clock advances. The incoming clip then starts at time zero.

A cut has zero duration. Adjacent shots without a declared transition receive a cut. Leading, trailing, or consecutive transitions are invalid storyboard structure.

This policy makes reordering and narration predictable. More sophisticated overlapping transitions can be added later under a different, explicit contract; they should not complicate the initial meaning of `slide-transition`.

**Avoid double entrances.** A target that should be visible during the bridge must already be visible at the incoming clip's start. The example uses `#:initial '(title)`, then reveals the body afterward. A requested match to an invisible endpoint is diagnosed. Crossfading into a deliberately blank initial state remains possible but is flagged for review.

## 9. Narration, pauses, and subtitles

A beat can be timed by narration instead of by a manually maintained number of seconds.

Start with a silent draft:

```racket
(beat 'meaning
  #:narration
  (narration
   "We are looking for a value that makes the equation true."
   #:draft-duration 4)
  (reveal-slot 'body #:duration 0.5))
```

Later, substitute a recording declaration:

```racket
(beat 'meaning
  #:narration
  (narration
   "We are looking for a value that makes the equation true."
   #:audio "voice/meaning.wav")
  #:tail-hold 0.4
  (reveal-slot 'body #:duration 0.5))
```

Narration has exactly one timing source: a recorded asset or an explicitly declared draft duration. Draft narration is text plus timing; **it does not silently generate speech**. A generated voice recording can later be supplied as an ordinary audio asset through an explicit external preparation workflow.

Paths are resolved relative to the declaring source module, not an accidental current working directory. Programmatically constructed sources must supply an explicit asset base.

For narration-driven beats:

```text
beat duration = max(visual action extent, narration extent) + tail hold
```

Both extents are relative to the beat start, including any declared offsets. Tail hold defaults to zero. Recorded duration is determined during preparation. Without narration, a beat must state `#:duration`; with narration, the duration is inferred unless explicitly supplied.

An explicitly supplied beat duration is authoritative. Its actions, narration, and requested tail hold must all fit. The system does not speed up a voice, trim its last word, or extend the beat behind the author's back.

A narration recording is not a word-level alignment file. Word-precise action timing requires explicit cue markers; automatic forced alignment is outside this subsystem.

### Subtitles are on by default

Storyboard narration produces subtitles by default, including in silent drafts. Subtitle intervals follow the narration interval, not an unrelated later hold. Long transcripts can be split into explicit caption segments; the system must not invent word timings.

The subtitle policy reserves a bottom band consistently across all shots in a storyboard, even in a shot with no spoken line. This avoids layout shifts when a subtitle appears. Bare static slides do not reserve that band unless requested in their context.

A figure's `caption` is authored slide content; narration subtitles are a separate timed output layer. Speaker notes remain separate from both.

The authored timeline contains one subtitle track. Burned-in, embedded, and sidecar outputs are selected at the rendering boundary. They are not accidentally displayed twice. Disabling subtitle display is distinct from discarding the transcript metadata.

## 10. Medium example: a narrated mathematical explanation

Mathematical operations should still be authored in `animate/math`. The slide layer provides the surrounding composition and narration; it must not recreate subtraction, cancellation, occurrence matching, or proof checks as generic shape transitions.

The current math library already separates held expressions, derivations, presentation plans, and effectful native preparation. Its subtraction example retains the intermediate equation instead of immediately normalizing it. See R3.

The new adapter accepts a **presentation plan**, not a prematurely rendered movie. It supplies the resolved theme and available region during preparation, removes standalone scene chrome, and retains the mathematical identities inside its slot namespace.

```racket
#lang racket/base

(require animate/math
         animate/slides
         animate/slides/math
         animate/slides/pict
         animate/slides/scene
         animate/slides/render
         animate/render)

(provide film)

;; Existing animate/math authoring.
(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'problem
        #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five   (cancel-addends #:at (lhs))]
    [evaluate-rhs  (evaluate #:at (rhs))]))

(define math-plan
  (present working
           #:style classroom
           #:groups '((subtract-five cancel-five evaluate-rhs))))

;; Proposed layout and narration authoring.
(define subtraction-slide
  (slide
   #:id 'subtract-card
   #:layout 'title+figure
   [title "Subtract five from both sides"]
   [figure
    (math-content math-plan #:poster 'end)]))

(define subtraction-clip
  (build-slide
   subtraction-slide
   #:initial '(title figure)

   (beat 'goal
     #:narration
     (narration
      "We want to remove the added five from the left side."
      #:draft-duration 4))

   (beat 'subtract
     #:narration
     (narration
      "Subtract five on both sides. Cancel the opposite terms, then calculate the right side."
      #:draft-duration 7)
     #:tail-hold 0.5
     (play-content 'figure))

   (beat 'read-result #:duration 3)))

(define film
  (storyboard
   #:id 'subtract-five-lesson
   #:theme lecture-dark
   #:format widescreen
   (storyboard-shot 'subtract-five subtraction-clip)))

(module+ main
  ;; Explicit boundary for TeX, asset loading, and measured preparation.
  (define prepared
    (prepare-storyboard! film))

  ;; Preview a frame with the exact inherited, prepared composition.
  (define result-picture
    (slide->pict
     (storyboard-ref prepared 'subtract-five)
     #:at '(read-result end)))

  ;; Existing renderer consumes the lowered authored timeline.
  (render-authored-mp4!
   (storyboard->timeline prepared)
   "out/subtract-five/frames"
   "out/subtract-five.mp4"
   #:fps 30))
```

The example ends at `3x = 12`; it teaches this subtraction step, not the complete solution of the original equation. The two draft narrations are silent until recordings are supplied, but provide timing and subtitle text.

Inside a timed clip, embedded math starts at its local time zero. `play-content` advances it from that state and leaves it at its endpoint. It does not restart when a new video frame is requested.

For the plain `subtraction-slide`, the declared poster is the final math state. This makes a useful static illustration. For a time-specific pict of the clip, the embedded state follows the clip's clock instead.

The narration-driven subtraction beat lasts as long as the longer of the prepared math animation and the seven-second draft line, then adds its half-second pause. Narration does not accidentally cut the animation short, and math does not stretch the voice.

For phase-by-phase narration, `play-content` also accepts `#:to`, using the embedded plan's named cue boundaries:

```racket
;; Each action plays from the child's current local position.
(play-content 'figure #:to '(subtract-five end))
(play-content 'figure #:to '(cancel-five end))
(play-content 'figure #:to '(evaluate-rhs end))
```

Place these actions in separate narration-driven beats. They advance the same embedded presentation rather than create three independent copies. The default destination is `'end`; the default source is the current local position. Explicit `#:from` selects a different start, so a restart is authored rather than inferred. Backward destinations without an explicit reset/reverse policy are errors.

The adapter publishes the named boundaries from the prepared math plan, including intermediate checkpoints retained inside presentation groups. An unavailable cue is a preparation error; the slide layer never guesses cancellation timestamps. Its cue map is also available to the inspector.

## 11. Picts, diagrams, and existing animated scenes

### A small theme-aware pict example

This example uses the existing `pict` constructors through a proposed content factory:

```racket
(require (only-in pict colorize disk))

(define disc-slide
  (slide
   #:layout 'figure+caption
   [figure
    (pict-content
     (lambda (ctx)
       (colorize
        (disk 140)
        (content-color ctx 'accent)))
     #:fit 'contain)]
   [caption "The figure uses the theme's accent color."]))
```

`content-color` returns a resolved drawing color suitable for `pict`. The factory receives immutable theme and region information. It is evaluated during resolution, potentially more than once across rebuilds, never as an effectful per-frame callback. It must not depend on mutable global state or the order of calls.

A plain pict is an opaque figure: the parent can move or fade it, but cannot target its internal mathematical terms. Use semantic content or a native Visual when internal identities matter. Pict's own custom drawing contracts remain applicable. See R5.

### Embedding an existing Scene

The Scene adapter provides `scene-content`:

```racket
(scene-content existing-scene
               #:fit 'contain
               #:poster 'end)
```

Here `existing-scene` is an already constructed ordinary Scene, not a filename or an assumed example helper. Its authored camera viewport defines its default stable extent. The adapter preserves its local coordinate system and adds the slot placement transform outside it; it does not export the Scene to video and re-import the pixels.

Within a clip, the embedded Scene is initially paused at local time zero. `play-content` starts it; after completion it holds its endpoint. Hiding and revealing it does not implicitly reset or advance its clock. Replaying or retiming it requires an explicit request.

The first `play-content` defaults to the remaining native duration. A requested different duration must select a retiming policy explicitly. By default, an explicitly timed parent beat that is too short is an error.

Animated bounds are not measured anew at each frame. A component must supply a stable viewport or conservative envelope. A declared slot clip can intentionally hide overflow; default layout diagnostics must not silently crop labels or geometry.

An embedded authored timeline with audio or subtitles must explicitly choose whether its media is imported or the embedding is visual-only. Media times, when imported, follow the same local-to-parent clock mapping and are assembled once.

### Native animation remains available

After `slide->scene`, the result is an ordinary Scene. A proposed `scene-slot-ref` helper retrieves the resolved Visual for a slot, including its slot placement:

```racket
(require animate)

(define sc
  (slide->scene welcome))

(define title-visual
  (scene-slot-ref sc 'title))

(define fading-title
  (scene-play sc
              (fade-out title-visual)
              #:duration 0.5))
```

For a storyboard, the selector is occurrence-qualified, for example `'(rule title)`. A native Scene modified this way is a new value; it does not mutate the original slide description or retroactively change `slide->pict` of that description.

## 12. Reuse and larger authoring projects

Ordinary Racket functions are the first reuse mechanism. No separate template language is needed:

```racket
(define (chapter-card id title subtitle)
  (slide
   #:id id
   #:layout 'section
   [title title]
   [subtitle subtitle]))

(define chapter-two
  (chapter-card 'chapter-two
                "Quadratic equations"
                "A new problem, the same principle."))
```

A medium-sized project can separate course appearance, reusable layouts, chapter content, narration assets, and final sequencing:

```text
lesson/
  appearance.rkt
  layouts.rkt
  opening.rkt
  worked-example.rkt
  summary.rkt
  film.rkt
  voice/
```

Export slides and clips from the chapter modules. Let `film.rkt` assemble them. Keep rendering in `module+ main` or an explicit project runner so importing a chapter does not typeset formulas, start a GUI, write frames, or encode video.

The IDs passed to `storyboard-shot` identify occurrences and must be unique. The same clip can appear in multiple shots. Beat names are unique within a clip. Local content IDs are unique among siblings. These scopes keep selectors stable without requiring globally unique names everywhere.

`storyboard-ref` returns the clip in its storyboard context, not a context-free copy. Use it for accurate previews:

```racket
(slide->pict
 (storyboard-ref film 'rule)
 #:at '(example end))
```

This preserves inherited theme, format, subtitle reservation, and prepared assets. An isolated preview of `rule-slide` can deliberately use different defaults and is not automatically a frame from `film`.

Theme and format changes return new storyboards:

```racket
(define light-film
  (storyboard-with-theme film lecture-light))

(define portrait-film
  (storyboard-with-format light-film portrait))
```

The second operation selects portrait layout variants and requires new validation. It does not promise that every amount of content will fit a narrow screen without editing.

## 13. Defining a layout

Most users should pick a catalogue layout. A course author can define another with deterministic box and grid composition; a general-purpose constraint solver is unnecessary for the initial design.

```racket
(define comparison-layout
  (layout
   #:id 'comparison
   #:slots
   (list
    (slot-spec 'title #:required? #t #:role 'title)
    (slot-spec 'before #:required? #t #:role 'body)
    (slot-spec 'after #:required? #t #:role 'body))
   #:arrange
   (vbox
    #:gap 'section-gap
    (region 'title #:basis 'content)
    (hbox
     #:grow 1
     #:gap 'column-gap
     (region 'before #:grow 1)
     (region 'after #:grow 1)))))

(define comparison-slide
  (slide
   #:layout comparison-layout
   [title "Two ways to present a calculation"]
   [before "Only show the answer."]
   [after "Show what changed and why."]))
```

The root receives the available safe rectangle. `#:basis 'content` requests measured content size. Positive `#:grow` values divide remaining space proportionally; `#:gap` can name a theme spacing token.

Regions also support explicit alignment, padding, and minimum/maximum sizes. Layouts own placement; contents own intrinsic measurement and their supported fitting behavior. Text wraps to an assigned width at the selected font size. Images normally preserve aspect ratio. Math does not silently shrink below the theme's readability threshold.

This particular custom layout is a wide arrangement. A production definition should provide a portrait variant, normally replacing the inner horizontal box with a vertical one. Format selection is explicit, not based on whichever arrangement happened to fit during an uncontrolled search.

Constraint cycles in an advanced anchor extension, unsatisfiable minimum sizes, missing measurements, and unsupported format variants are diagnostics—not instructions to improvise a layout.

## 14. Reviewing the video before rendering

The ordinary workflow is: author the static compositions, inspect their posters, add named builds, assemble the storyboard, prepare measured resources, inspect representative times, then render through the existing project machinery.

`check-storyboard` returns structured diagnostics. On an unprepared storyboard it validates declarations and reports which measurements remain pending. On a prepared storyboard it also checks actual fit, timing, and resource information.

```racket
(check-storyboard film)

(slide->pict
 (storyboard-ref film 'rule)
 #:at '(example end)
 #:debug '(slots safe-area baselines))
```

Debug overlays belong only to the requested inspection output. They are not inserted into the authored video.

Useful diagnostics must identify the shot, beat or slot, and the violated constraint. For example:

```text
shot rule / slot right
  measured height 4.8 exceeds available height 4.1
  overflow: 0.7 authoring units

shot summary / beat closing
  narration ends at 5.2 s; explicit beat duration is 4.0 s

transition rule -> recap
  requested continuity key lesson-heading is absent at destination
```

These are illustrative diagnostic formats, not output from implemented tools.

Structural mistakes, timing conflicts, and required-slot overflow fail validation. Explicitly requested clipping is allowed but recorded. The checker also reports missing fonts, low-resolution figures, unsupported reveal capabilities, and unused narration text as appropriate. It does not “repair” a mathematical expression or shrink an entire slide until an error disappears.

The layout gallery should show every catalogue layout in light and dark themes, selected aspect ratios, and representative build states. It should include deliberately difficult specimens: long titles, multiline captions, tall fractions, matrices, wide equations, and content with unusually large bounds.

Static fit validation is not a proof that no moving objects overlap. Known animation envelopes can be checked, and arbitrary native content requires declared bounds or review probes. Deterministic direct-time probes around beat and transition boundaries should accompany the gallery.

## 15. Preparation and integration with animate

The public module boundaries should be:

| Proposed module | Responsibility |
|---|---|
| `animate/slides` | Immutable themes, layout/content declarations, clips, narration declarations, and storyboards. |
| `animate/slides/pict` | Static resolution and pict output; no movie engine or GUI required. |
| `animate/slides/scene` | Native Scene and authored-timeline adapters, including embedded Scene content. |
| `animate/slides/render` | Explicit external-resource and measured preparation entry points. |
| `animate/slides/project` | A storyboard source adapter for the existing project executor. |
| `animate/slides/math` | Deferred adaptation of `animate/math` plans. |
| `animate/slides/geometry` | Deferred adaptation of geometry plans. |

The concrete implementation may keep private helpers differently. These are dependency boundaries and public responsibilities, not a request to build another theme, timeline, or rendering engine.

### Unprefixed module-composition requirement

The implementation must include module-loading checks for the documented authoring combinations. At minimum, these cover the slide core with its pict adapter; the slide core with `animate` and its Scene adapter; `animate/math` with the slide/math adapter; the corresponding geometry combination; and the project/render adapter combinations used by the guide. The native core and math adapter should also be checked together in one authoring module.

The checks must use ordinary `require` forms, without hiding new conflicts with user-side prefixes or exclusions. Where adapters expose an existing operation, they must preserve its original binding rather than define another operation with the same spelling. Existing unrelated library conflicts are not a reason to add a namespace prefix to every slide example; a conflict in a supported combination must be addressed deliberately at its API boundary.

Slideshow interoperability is a separate boundary check, using the prefixed integration example in section 3. It does not impose alternative constructor or converter names on the main API. No import tests or implementation tests are claimed by this design revision.

### Pure description, explicit preparation

Constructing a slide or storyboard does not read audio, invoke TeX, or write a cache. Basic in-memory text and pict compositions can be resolved by the converters without external-tool work.

When external resources are needed, use `prepare-slide!` or `prepare-storyboard!`. A converter presented with an unresolved TeX, image-file, or audio dependency reports that preparation is required; it must not unexpectedly invoke a subprocess through a function without an effectful boundary.

Prepared values retain resolved fonts, geometry, measured media durations, resource fingerprints, and source-to-output identity maps. Repeated snapshots use those prepared values rather than performing preparation for every frame.

### One project context, one timeline

The storyboard lowers shot intervals and named beats to the existing authored section/cue model. Audio and subtitles lower to the existing authored-media model. The Scene adapter produces normal Visual trees and timeline requests; the renderer does not know what a `title+figure` layout is.

For production work, adapt storyboard sources to the existing `module-builder-source` preparation and reconstruction protocol. The parent prepares resources once; workers reconstruct immutable scenes from the source module and prepared data. Do not serialize arbitrary pict closures or rerun TeX independently in each frame worker. The current project API and math rendering workflow provide the relevant boundaries. See R3–R4.

The proposed `animate/slides/project` module provides a source declaration:

```racket
;; film.rkt must explicitly export its immutable storyboard as film.
(storyboard-source "film.rkt" 'film)
```

This value is passed to the existing project's `#:source`. It loads the exported storyboard in the source preparation context and lowers to the existing source-builder protocol; it does not create a parallel executor. Movie dimensions, fps, worker count, and encoding stay in the existing project/render specifications. In particular, using ten workers is a project choice, not a property of a slide.

A module source/builder declaration is required for restartable process rendering; an anonymous in-memory storyboard remains suitable for in-process work. Programmatic sources with options use a source builder receiving the existing immutable build context.

A production plan has one authoritative appearance/format snapshot. A mismatch between a prepared storyboard and project render settings must be rejected or explicitly re-prepared. The pict adapter should resolve color/typography tokens through the same snapshot used for the Scene adapter.

### Determinism and caching

Frame state is a function of prepared content, the selected appearance context, and time. Sampling frame 200 before frame 20 must not change either result. Embedded clocks, transitions, and replacements follow that rule too.

Preparation and layout caches include their real dependencies: content, theme and typography fingerprints, format, subtitle reservation, layout variant, declared replacement alternatives, fonts, and external resources. Output-resolution changes can reuse authoring-unit layout where the content supports that separation; resolution-dependent native content declares the extra dependency.

Absolute pixel equality across machines with different fonts or rendering stacks is not promised. Deterministic geometry and repeatable output within a fixed, recorded preparation environment are the target contracts.

## 16. Scope and design commitments

The initial subsystem should be complete enough to author static slides, short silent videos, narrated mathematical lessons, and reusable course layouts. It should include semantic slots, stable selectors, light/dark themes, named beats, explicit transition bridges, media lowering, both output adapters, and useful diagnostics.

It should not start by building a slide editor, a second encoder, an unrestricted constraint solver, automatic speech synthesis, automatic word alignment, automatic algebraic reasoning, or arbitrary shape morphing. Those are different responsibilities.

The essential promises are:

**Authoring is unprefixed within animate.** Supported module combinations share a coherent public vocabulary. `slide` is convenient syntax, `make-slide` is its procedural counterpart, and third-party naming conflicts are handled at the integration boundary.

**Content is reusable.** A still, a video clip, and a longer lesson can share one slide description.

**Appearance is replaceable.** Layout and typography are resolved from an explicit theme and format before playback.

**Time is authored.** Beats, narration, embedded clocks, and transition durations have unambiguous contracts.

**Identity is explicit.** Layout roles provide structure; continuity keys and mathematical identities provide matching.

**Both outputs are first-class.** `slide->pict` is not a screenshot convenience, and `slide->scene` is not an export to a competing animation engine.

## Source notes

These sources establish existing integration points, not the proposed `animate/slides` API. R1–R6 are retained from the original design prepared on 2026-09-16. R7 records the mathematical export interface inspected during the naming discussion. This revision edits the proposal; it does not report a new repository-wide compatibility audit.

- **R1:** `soegaard/animate`, `examples/semantic-typography.rkt`, blob `85981518a6524266cc87b7d04a0d841c4a7e81cd`: semantic text roles, typography themes, and explicit project appearance snapshots.
- **R2:** `soegaard/animate`, `examples/authored-media-assembly.rkt`, blob `f6ce35be6de21782d349203db48f14b8aed8754e`: authored sections, audio cues, subtitles, and `render-authored-mp4!`.
- **R3:** `soegaard/animate`, `math/README.md`, blob `917b5af020574130850dd59e9e0b2f21e0b3a7bd`: mathematical authoring, explicit native preparation, and shared process rendering.
- **R4:** `soegaard/animate`, `project.rkt`, blob `e4648a143b992d4e114dcca78e8399ac724c4cc8`: immutable projects, source builders, preparation payloads, and render contexts.
- **R5:** Official Racket documentation, *Pict: Functional Pictures*, especially *Basic Pict Constructors* and its custom drawing contracts.
- **R6:** Official Racket documentation, *Slideshow: Figure and Presentation Tools*, including its use and re-export of `pict`.
- **R7:** `soegaard/animate`, `math/main.rkt`, blob `57f56da4dff08d8da6f8736f0a57266ee64c6498`: mathematical authoring exports, including the existing choreography operation `transition`.
