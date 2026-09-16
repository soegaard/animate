# animate/slides — public API, v0.4.0

This is the implemented public interface. The historical design document records
ideas beyond the current surface; see `validation-v040.md` and the worked
examples in `user-guide.md` for validated behavior and known scope limits. The
gallery and transition features are documented in `gallery-and-transitions.md`.

All numbers used for authoring geometry are world units. A widescreen canvas is
16 × 9 units. Time values are seconds. Identifiers are nonempty interned symbols.
Constructors return immutable descriptions; their private struct constructors are
not public API. A preparation object is tied to its resolved appearance and format.

## `animate/slides`

### Slide construction and inspection

```racket
(slide #:id 'slide #:layout 'blank #:theme #f #:notes ""
  [slot-name #:key #f #:align #f #:valign #f #:fit #f content]
  ...)

(make-slide #:id 'slide #:layout 'blank #:theme #f #:notes ""
            #:slots (hash))

(slot-content content #:key #f #:align #f #:valign #f #:fit #f)
```

`slide` is syntax. The slot labels are literal names, not global variables. Supply
keyword options before slot clauses. Unknown or duplicate slots and absent
required slots are errors. `make-slide` accepts a hash or association list whose
values are content or `slot-content` wrappers. It is the procedural counterpart of
the syntax. `#:layout` accepts a catalogue symbol or a custom layout value.

`#:align` is `#f`, `'left`, `'center`, or `'right`; `#:valign` is `#f`, `'top`,
`'center`, or `'bottom`. False inherits the layout choice. `#:fit` is false or one
of `'contain`, `'cover`, and `'natural`. Text is wrapped, not implicitly reduced to
fit. A continuity key is either false or a symbol, unique within the slide.

`slide?`, `slide-id`, `slide-layout`, `slide-slots`, `slide-appearance`, and
`slide-notes` inspect a description. `slide-ref` takes a slide and slot symbol and
returns the content, without its slot options. `slide-slots` exposes the immutable
slot mapping for inspection; do not construct or depend on the private wrapper
representation. `slide-appearance` returns the explicit theme or false, not a
resolved inherited theme.

### Deferred content

```racket
(paragraph-content text #:role #f #:align #f)
(bullets #:ordered? #f [item-name content] ...)
(make-bullets (list (cons 'item-name content) ...) #:ordered? #f)
(pict-content picture-or-factory #:fit 'contain)
(image-content path #:fit 'contain #:asset-base source-module-directory)
```

Plain strings adopt the receiving slot's typography role. `paragraph-content`
optionally overrides that role and its internal line alignment. The name avoids
conflicting with Animate's concrete native `paragraph` constructor.

`bullets` is syntax; `make-bullets` is its procedural form. Items have stable IDs
and can be addressed with selectors such as `'(body item-name)`. This version
accepts text items, not nested rich bullet figures. Empty bullet lists have no drawable leaf; revealing an empty selector is
diagnosed. Empty strings retain an empty text line and its line metrics.

`pict-content` accepts an existing Pict or a one-argument factory receiving a
content context. The Pict module is loaded at resolution rather than authoring.
Factories run during preparation/measurement, never during frame sampling; a
factory must be pure and tolerate measurement calls at different widths. A Pict
is opaque to semantic part matching. Its native Pict dimensions use 100 drawing
units per authoring unit before explicit fitting.

`image-content` is syntax that captures its declaring module's directory. An
explicit `#:asset-base` replaces that default; code without a source module must
supply a base or a complete path. Images are loaded at explicit preparation.

`content?` recognizes a string or a declared content descriptor. Raw Picts and
native Visuals are accepted by their adapters but are not themselves descriptors.

### Formats

```racket
(slide-format #:id id #:width width #:height height)
```

Width and height must be positive finite numbers. Predicates and accessors are
`slide-format?`, `slide-format-id`, `slide-format-width`, `slide-format-height`.
The built-ins are `widescreen` (16 × 9), `standard` (12 × 9), `portrait` (9 × 16),
and `square-format` (12 × 12).

### Themes

```racket
(slide-theme #:id id
             #:extends #f
             #:colors #f
             #:typography #f
             #:spacing (hash)
             #:decorations (hash))
```

The optional parent is another slide theme. Colors and typography are the
existing Animate theme values, not a new text/font vocabulary. Without a parent,
colors default to the native light palette and typography to the slide lecture
roles. Overrides are copied into complete immutable snapshots.

`lecture-light` and `lecture-dark` are the default companions. Accessors are
`slide-theme?`, `slide-theme-id`, `slide-theme-colors`, `slide-theme-typography`,
`slide-theme-spacing`, and `slide-theme-decorations`. `theme-spacing` takes a theme
and either a spacing-token symbol or a nonnegative literal; `role-style` takes a
theme and typography-role symbol and returns a native text style.

Default spacing tokens:

| Token | Value |
|---|---:|
| `safe-x`, `safe-y` | 0.65, 0.50 |
| `section-gap`, `column-gap` | 0.35, 0.60 |
| `bullet-gap`, `paragraph-gap` | 0.23, 0.25 |
| `footer-height`, `subtitle-height` | 0.35, 0.85 |
| `title-band`, `caption-band` | 1.20, 0.85 |
| `math-minimum-scale` | 0.70 |

The band/paragraph tokens are available to custom themes; built-in heading and
caption sizes are measured from text rather than forced to those band heights.
`math-minimum-scale` must be in [0,1]. Custom numeric spacing tokens may be added.
The implemented decoration keys are `title-rule?` and `footer-rule?`, both false
by default. Other decoration keys are rejected.

### Layouts

```racket
(layout #:id id #:slots (list slot-specification ...)
        #:arrange wide-tree
        #:standard #f #:portrait #f #:fallback #f)

(slot-spec name #:required? #f #:role 'body)

(region name #:basis 0 #:grow 0 #:align 'left #:valign 'top
        #:padding 0 #:min 0 #:max +inf.0)

(hbox #:basis 0 #:grow 0 #:gap 'column-gap
      #:padding 0 #:min 0 #:max +inf.0 child ...)

(vbox #:basis 0 #:grow 0 #:gap 'section-gap
      #:padding 0 #:min 0 #:max +inf.0 child ...)
```

`basis` is a nonnegative number or `'content`; growth is a nonnegative weight.
Minimum and maximum constrain a child's main-axis allocation. A numeric gap or
spacing-token symbol separates children. Padding is a nonnegative literal in
world units. No general constraint search is performed.

Every supplied tree contains every declared region exactly once. `footer` is
reserved shared chrome and cannot be declared as a custom region. A missing
optional content value still leaves its custom region in the tree; custom trees
do not silently collapse regions. Built-in layouts have documented omission
rules. Built-in portrait `title+two-column` stacks its two content regions
at natural height with `section-gap`, and built-in `equation-focus` centers the
equation plus optional annotation as one block. These are fixed preparation-time
layout rules, not animation-time reflow. A standard custom format defaults to the
wide tree. Portrait needs an explicit portrait tree. Other formats need
`#:fallback 'wide` in this version.

`layout?`, `layout-id`, `layout-slots`, `slot-spec?`, `slot-spec-name`,
`slot-spec-required?`, `slot-spec-role` inspect the values. `(layout-names)` returns
the twelve built-in names. `(layout-ref name-or-layout)` resolves a built-in name
or returns a supplied layout value.

### Clips and beats

```racket
(build-slide slide #:initial 'visible #:poster 'end #:motion #f beat ...)
(hold-slide slide #:duration seconds)
(beat name #:duration #f #:narration #f #:tail-hold 0 action ...)
```

`#:initial` is `'visible`, `'hidden`, or a list of selectors. A selector is a slot
symbol or a nonempty path of symbols. Hidden content reserves geometry. A clip
has sequential beats; actions within one beat run concurrently at their own
local offsets. Beat names are unique. Each beat needs an explicit duration or
narration. `#:motion` is false, `'normal`, or `'reduced`.

Without an explicit duration, a narration-driven beat has duration
`max(narration-end, action-end) + tail-hold`. An explicit duration must accommodate
that entire span. Overrun, unknown selectors, and conflicting property writes
are errors. Reduced motion suppresses emphasis scaling and makes slot visibility
changes instant, while retaining the authored intervals. It does not replace the
internal choreography of embedded mathematical or native scenes.

A poster selector is `'start`, `'end`, a nonnegative time, or `'(beat start/end)`.
`hold-slide` presents each embedded component at its poster state; `build-slide`
initially pauses each component at local time zero. `slide-clip?` and
`slide-clip-slide` inspect a clip. `beat?`, `beat-name`, and `slide-action?` inspect
the corresponding authoring values.

### Actions

```racket
(reveal-slot selector #:at 0 #:duration 0.4 #:effect 'fade)
(conceal-slot selector #:at 0 #:duration 0.4 #:effect 'fade)
(emphasize-slot selector #:at 0 #:duration 0.8 #:scale 1.08)
(replace-content slot content #:at 0 #:duration 0.4 #:effect 'crossfade)
(play-content slot #:at 0 #:from #f #:to 'end
              #:duration #f #:retime #f)
```

Reveal/conceal support `'fade` and `'instant`. Replacement supports `'crossfade`
and `'instant` and targets one complete slot. All replacement alternatives are
prepared before playback. Emphasis is temporary scaling around a content box;
it restores the base scale and does not allocate extra space.

`play-content` requires a single animated component in the selected slot. False
`#:from` continues its clock; an explicit source time resets it. `#:to` accepts an
embedded numeric time, `'start`, `'end`, or an adapter-provided cue. The natural
interval lasts `to - from`. To supply a different duration, explicitly select
`#:retime 'stretch`. Imported audio cannot be time-stretched by this action.
Backwards intervals are not supported. Visibility changes do not advance clocks.

### Narration

```racket
(narration text #:audio #f #:draft-duration #f #:at 0
           #:source-start 0 #:duration #f #:captions #f
           #:asset-base source-module-directory)

(make-narration text #:audio #f #:draft-duration #f #:at 0
                #:source-start 0 #:duration #f #:captions #f
                #:asset-base #f)
```

Exactly one of audio and positive draft duration must be supplied. Draft
narration is silent text plus timing, not synthesized speech. Recorded durations
are obtained through `ffprobe` during explicit preparation. Source trimming is
for recordings only. Captions are a nonoverlapping ordered list of
`(list start end text)` segments relative to the selected narration interval.
False captions derive one segment from the text. An empty list suppresses them.
The syntax captures a source-relative asset base; the procedure does not.
`narration?` recognizes the description.

### Storyboards

```racket
(storyboard #:id 'storyboard #:theme lecture-light #:format widescreen
            #:motion 'normal #:subtitles? #t entry ...)
(storyboard-shot occurrence-id clip)
(storyboard-cut)
(slide-transition #:effect 'crossfade #:duration 0.6 #:keys '()
                  #:direction #f #:easing 'linear #:scale #f #:color #f #:depth #f)
```

A storyboard begins and ends with a shot. Shots must have unique occurrence IDs;
the same slide/clip may be used more than once under different occurrences.
Adjacent shots imply a zero-time cut. A transition occupies an additional
interval, holding the outgoing clip at its endpoint and the incoming clip at its
start. Consecutive transitions are errors. `storyboard-cut` is the separate
zero-duration cut; all other transitions require a positive finite duration.

| Effect | Behavior and options |
|---|---|
| `'crossfade` | Fade the source out while the destination fades in. |
| `'match` | Move compatible content named by `#:keys`; unmatched or incompatible content crossfades. |
| `'push` | Move both compositions by one canvas extent. |
| `'wipe` | Keep both compositions stationary; move the reveal boundary. |
| `'cover` | Move the destination over a stationary source. |
| `'uncover` | Move the source away from a stationary destination. |
| `'zoom` | Source grows from 1 to `1/scale`; destination grows from `scale` to 1, with a crossfade. |
| `'fade-through` | Fade to an opaque intermediate color, then reveal the destination. |

For push/wipe/cover/uncover, `#:direction` is `'left`, `'right`, `'up`, or `'down`
(default `'left`). Direction names describe travel, not the incoming edge: left
means the destination enters from the right; a leftward wipe reveals it from
its right edge. Backgrounds, decorations, and existing crops participate.
These four effects require opaque endpoint backgrounds.

`#:easing` is `'linear` (the unchanged default), `'smooth` (cubic smoothstep),
`'ease-in`, `'ease-out`, or `'ease-in-out` (quadratic curves). The same eased
progress controls all geometry, masks, and opacity. No arbitrary procedure is
stored in a transferable transition description.

`#:scale` is exclusive to zoom: a finite number strictly between 0 and 1,
default 0.85. `#:color` is exclusive to fade-through: an Animate color
specification, default black. Semantic colors resolve under the destination
slide's theme and must resolve to an opaque color. The intermediate frame is
solid when eased progress is 1/2; asymmetric easing changes its clock time.
Inapplicable keywords are errors, not silently ignored settings.

Keys are accepted only for matching. Missing, ambiguous, or hidden endpoints
are diagnosed. Matching defaults to `#:depth 'auto`: it plans recursive named children and
witnessed domain-state replay, then falls back to conservative prepared-asset
matching or crossfade. `#:depth 'semantic` requires a supported correspondence;
`#:depth 'slot` disables the new mechanisms. See [Semantic matching](semantic-matching.md)
for exact endpoint, timing, and fallback contracts. No glyph similarity search is used.

Storyboard `#:motion 'reduced` replaces match, push, wipe, cover, uncover, and
zoom with a crossfade of the **same duration and easing**. Cuts and fade-through
retain their behavior. Per-clip motion overrides govern clip actions, not the
storyboard's bridge policy.

`slide-transition?` recognizes all transition descriptions, including cuts.
The read-only accessors are `slide-transition-effect`, `slide-transition-duration`,
`slide-transition-keys`, `slide-transition-direction`, `slide-transition-easing`,
`slide-transition-depth`,
`slide-transition-scale`, and `slide-transition-color`. Inapplicable direction,
scale, and color fields are `#f`; effective defaults are stored explicitly.
Colors are normalized through the native color-data codec so configuration
round-trips preserve their semantic value.

The portable preparation schema is `animate-slides-preparation-v2`. Rebuild
prepared storyboards when upgrading; v1 payloads are explicitly rejected.

`storyboard?`, `storyboard-id`, `storyboard-theme`, `storyboard-format`,
`storyboard-motion`, and `storyboard-subtitles?` inspect the description.
`storyboard-with-theme` and `storyboard-with-format` return changed descriptions.
`(storyboard-ref board occurrence-id)` returns a clip with its inherited context,
or the corresponding prepared clip if the storyboard is prepared.

`(check-storyboard board)` returns declaration/preparation diagnostic records. It
does not run an external tool or convert a declaration into a measured scene.
Fatal errors occur through constructors or explicit resolution/preparation.

### Diagnostics

`diagnostic?`, `diagnostic-severity`, `diagnostic-code`, `diagnostic-path`,
`diagnostic-message`, `diagnostic-details` inspect nonfatal records.
`exn:fail:slides?`, `exn:fail:slides-code`, `exn:fail:slides-path`, and
`exn:fail:slides-details` inspect fatal slide-specific exceptions. Native domain
errors retain their original exception types.

## `animate/slides/pict`

```racket
(slide->pict source #:at #f #:theme #f #:format #f
             #:size #f #:fit 'error #:debug '())
(storyboard->pict source #:at 'end #:size #f #:fit 'error #:debug '())
(storyboard->picts source #:size #f #:fit 'error #:debug '())
```

A source is a description, context-bound reference, or compatible prepared value.
Simple in-memory sources resolve automatically. Sources needing effects report
that preparation is required. A plain slide is static; a clip uses its poster
when `#:at` is false. Explicit clip selectors have the forms described above.
Storyboard sampling takes numeric time or `'start`/`'end`.

`#:size` is false or `(list width-in-pixels height-in-pixels)`, with positive exact
integers. False selects 80 pixels per world unit. A different aspect ratio is an
error unless `#:fit 'letterbox` is explicit. Debug flags are `'slots`, `'safe-area`,
and `'baselines`. The main output excludes the separate narration-subtitle track.
`storyboard->picts` returns one poster Pict per shot.

The Pict factory context helpers are `content-color` (context and color-role
symbol → drawing color), `content-width`, `content-height`, `content-theme`, and
`content-format`. Contexts supplied for intrinsic measurement may have a
provisional height; a factory should use its declared fit policy for final size.

## `animate/slides/render`

```racket
(prepare-slide! source #:theme #f #:format #f #:asset-base #f)
(prepare-storyboard! source #:asset-base #f)
```

These are explicit resource and measurement boundaries. They load images, probe
recorded audio, prepare mathematical formulas, and freeze layout and timing. They
do not render the final video. Conversion of a prepared value does not repeat
those preparation steps. Changing a frozen theme/format requires re-preparing the
original description.

`prepared-slide?`, `prepared-slide-clip?`, `prepared-storyboard?`, and
`prepared-duration` inspect prepared objects. Static slides have duration zero.

## `animate/slides/scene`

```racket
(slide->scene source #:theme #f #:format #f #:size #f #:fit 'error)
(storyboard->scene source #:size #f #:fit 'error)
(storyboard->timeline source #:size #f #:fit 'error)

(scene-content scene-or-timeline #:fit 'contain #:poster 'end
               #:media #f #:background? #f)
(visual-content visual #:fit 'contain #:width #f #:height #f)

(scene-slot-id selector)
(scene-slot-ref scene selector #:at (scene-duration scene))
```

Scene conversion returns an ordinary Animate Scene. Timeline conversion returns
the native authored timeline carrying shot sections, beat cues, narration,
subtitles, and explicitly imported child media. A zero-duration slide remains
zero-duration; it does not acquire an implicit movie hold.

For an isolated slide, a native slot selector is a symbol such as `'title`. In a
storyboard use `'(shot-id title)`. IDs are deterministically encoded to avoid
collisions. The reference returns the current concrete native group. At a clip's
endpoint those groups are frozen into its native current state, so subsequent
ordinary `scene-play` operations can move/fade them. Slot selectors do not expose
arbitrary inner native geometry or formula IDs through a new aliasing mechanism.

A Scene content descriptor retains the native Scene and local clock. Its
background is transparent unless explicitly enabled. A media-bearing authored
timeline requires an explicit `'visual-only` or `'import` policy. Imported media
plays only while the local clock advances. Audio requires explicit bounded cues;
partial playback through a faded cue is rejected rather than changing its
amplitude envelope. Parent and imported subtitles may not overlap.

A raw Visual may instead be wrapped in `visual-content`; dimensions can be
supplied or measured. Native source authors remain responsible for preparing
external resources in arbitrary native scenes. Use `math-content` for the
integrated mathematical preparation path.

## `animate/slides/math` and `animate/slides/geometry`

```racket
(math-content presentation-plan #:poster 'end #:fit 'contain #:aspect 16/9)
(geometry-content program-or-timeline #:poster 'end #:fit 'contain #:aspect 16/9)
```

`#:aspect` is a positive finite preferred width/height ratio used for intrinsic
measurement in content-sized regions. It prevents an unbounded measurement
viewport from triggering native preparation. It does not change mathematical
meaning or stretch geometry: preparation still receives the actual slot region.

Both support `'contain` and `'natural` fitting. Their constructors are pure and do
not typeset or render. Mathematical preparation uses the existing domain plan and
its native compilation. Step cues use `'(step-name start/end)`, or
`'(segment-index step-name start/end)` when a name is repeated. These are actual
native scene boundaries, not estimates from the abstract presentation schedule.

Math foreground/background roles must resolve to opaque colors because this
version's TeX preparation takes `#RRGGBB`. A formula scale below the theme's
`math-minimum-scale` is diagnosed. Existing domain context headings and working-row
margins are retained; an arbitrary native child semantic-selection API is not
provided by these adapters.

Geometry supports direct Pict/Scene output and the module-backed subprocess
route. The parent captures realized drawable values, event timing, styles, label
and marker placement, and compass provenance. Workers decode this data without
realizing the construction or repeating annotation layout. Ready timelines keep
their supplied realization; source modules must still avoid top-level preparation.
See [Geometry workers](geometry-workers.md).

## `animate/slides/project`

```racket
(storyboard-source module-path binding #:asset-base source-module-directory #:seed 0)
(make-storyboard-source module-path binding #:asset-base #f #:seed 0)
```

The syntax captures the declaring module's directory; the procedure requires a
base for relative paths. Both return an ordinary native `module-builder-source`
for an exported storyboard. The render specification must use the storyboard's
color and typography snapshots. Prepared drawings and mathematical SVGs are
handed to worker-local rebuilds through the existing source-preparation protocol.
Geometry preparation transfer and arbitrary renderer-factory transfer are not
implemented. No encoder or process pool is created by authoring these values.

The supported practical entry point is `slides/render-example.rkt`, which loads
an exported `film` storyboard and configures the normal project executor.


## `animate/slides/gallery`

This optional module exports an ordered, immutable catalogue and a storyboard
factory. Listing and selecting catalogue entries does not typeset mathematics,
realize geometry, read media, or write render output.

```racket
slide-gallery-entries
slide-gallery-categories ; '(layouts transitions integration)
(select-slide-gallery-entries #:entries #f #:category #f)
(make-slide-gallery #:entries #f #:category #f
                    #:theme lecture-light #:format widescreen #:motion 'normal)
```

The catalogue has 42 entries: 12 layouts, 23 transition examples, and 7 native
integration examples. `#:entries` is either `#f` or a nonempty duplicate-free
list of entry symbols. Explicit order is preserved. `#:category` is `#f`,
`'layouts`, `'transitions`, or `'integration`; combining it with explicit entries
requires every entry to belong to that category. Unknown IDs and categories fail.

`make-slide-gallery` returns an ordinary immutable storyboard, lazily loading the
builders for selected examples. Preparation and output remain explicit. An
aggregate gallery containing geometry can use the ordinary module-backed worker
route, including semantic snapshots nested alongside mathematical content.

Entry inspection uses `slide-gallery-entry?` and the accessors
`slide-gallery-entry-id`, `slide-gallery-entry-category`, `slide-gallery-entry-title`,
`slide-gallery-entry-description`, `slide-gallery-entry-requirements`,
`slide-gallery-entry-example`, and `slide-gallery-entry-source`. Requirements are
symbols (`math`, `geometry`); source is a path relative to `slides/`.

The command-line entry points are `slides/run-gallery.rkt` and
`slides/examples/gallery.rkt`. They write HTML, timestamped PNGs, reusable
storyboard sources, a manifest, and an optional MP4 per entry. `--list` only lists
entries. `--videos --workers 10` enables the ordinary project rendering route;
geometry entries honor the same worker capacity. `--in-process` explicitly selects local rendering. The default output is
`slides-output/gallery`; it must not already exist. See
[gallery-and-transitions.md](gallery-and-transitions.md) for all commands.


## Semantic content (v0.4.0)

`animate/slides` exports `semantic-group`, `semantic-part`, and `content-state`,
with their predicates. `animate/slides/render` exports `storyboard-match-report`.
Their signatures, invariants, current domain support, and complete examples are
in [Semantic continuity between slides](semantic-matching.md).
