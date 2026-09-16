# animate/slides — themeable layouts

**Version 0.4.0 — parent-prepared geometry workers.** Built on the integrated repository at
`0c5f863e8ccbfc4388123adce388a4443689323e` plus the v0.3.1 semantic-gallery updates.

Immutable slides resolve to Picts or ordinary native Scenes. In addition to the
existing transition family, `match` now supports nested named parts and replay
between witnessed math, geometry, and native Scene checkpoints.

**Validation:** Racket 9.3.0.2 compiled the public modules and passed all **105
named cases across sixteen suite files**, including the optional mixed-domain
worker suite. The run also produced a real two-worker geometry gallery MP4.
See [validation-v040.md](docs/validation-v040.md) for the exact scope and
[semantic-matching.md](docs/semantic-matching.md) for the design, API, examples,
and explicit limitations.

## Browse the gallery

The gallery contains **42 selectable examples**: twelve layouts, twenty-three
transition examples, and seven native integration examples. It explains the APIs
and exports reusable storyboard sources as well as pictures and optional videos.

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Data-only catalogue: no rendering or external preparation.
"$RACKET" slides/run-gallery.rkt --list

# Playable transition gallery: HTML, MP4s, posters, timestamp strips, review ZIP.
"$RACKET" slides/run-gallery.rkt --category transitions \
  --videos --workers 10 --dark slides-output/transitions-v040

open slides-output/transitions-v040/index.html

# Complete light gallery. Math requires TeX/dvisvgm; videos also require FFmpeg.
"$RACKET" slides/run-gallery.rkt --videos --workers 10 \
  --light slides-output/gallery-v040

# Portrait layout comparison, without MP4 encoding.
"$RACKET" slides/run-gallery.rkt --category layouts \
  --format portrait --dark slides-output/portrait-v040

# A focused gallery of real domain integration.
"$RACKET" slides/run-gallery.rkt --category integration \
  --videos --workers 10 slides-output/integration-v040
```

Use a fresh output directory. The sibling ZIP includes final videos and images,
not temporary project frames. **Geometry now uses the same module-backed project
workers as math and ordinary slides.** The parent realizes the construction and
freezes annotation layout once; workers reconstruct verified prepared data.
The console and manifest report actual worker starts. `--in-process` remains an
explicit one-worker override. Static previews use the shared Pict composition.
See [Geometry workers](docs/geometry-workers.md) for the plan, contract, and checks.

`slides/examples/gallery.rkt` is also an executable gallery entry point. Its
original `gallery-slides` and `gallery-film` specimen exports remain available
for the diagnostic probes.

Full instructions: [Gallery and transitions](docs/gallery-and-transitions.md).

## A first slide

```racket
#lang racket/base
(require animate/slides animate/slides/pict animate/slides/scene)

(define welcome
  (slide #:layout 'title
    [title "Solving equations"]
    [subtitle "Keep both sides equal."]))

(define opening
  (build-slide welcome #:initial 'hidden
    (beat 'heading #:duration 1
      (reveal-slot 'title #:duration 0.4))
    (beat 'explanation #:duration 3
      (reveal-slot 'subtitle #:duration 0.5))))

(define still (slide->pict welcome))
(define animation (slide->scene opening))
```

A plain slide has no implicit movie duration. `hold-slide` or `build-slide`
supplies time. Deferred slide paragraphs are `paragraph-content`, leaving
Animate's existing native `paragraph` operation unchanged.

## Slide transitions

```racket
(slide-transition #:effect 'push #:direction 'left
                  #:duration 0.8 #:easing 'smooth)

(slide-transition #:effect 'wipe #:direction 'up #:duration 1)

(slide-transition #:effect 'zoom #:scale 0.82 #:duration 0.9)

(slide-transition #:effect 'fade-through #:color "#101820" #:duration 0.8)

(slide-transition #:effect 'match #:keys '(topic) #:duration 0.7)
```

Cut, crossfade, match, push, wipe, cover, uncover, zoom, and fade-through are
available. Direction describes travel: left means an incoming composition enters
from the right. Easing is linear, smooth, ease-in, ease-out, or ease-in-out.
Backgrounds, decorations, and content clipping follow the transition together.

Bridges add their own duration and freeze both endpoint content clocks. Reduced
motion substitutes same-duration crossfades for spatial transitions, including
matched relocation. Matching remains conservative: it is not an automatic glyph
or mathematical-expression morph.

## Gallery as a storyboard

```racket
(require animate/slides animate/slides/gallery)

(define film
  (make-slide-gallery #:entries '(layout-title+figure push-left math-derivation)
                      #:theme lecture-dark))
```

Prepare and convert `film` using the ordinary slide APIs. The catalogue module is
safe to require for metadata-only inspection; native example builders are loaded
when selected.

The ready-made transition tour exports an ordinary `film` value:

```sh
"$RACKET" slides/render-example.rkt --workers 10 \
  slides/examples/gallery-tour.rkt
```

## Compile, test, and visually review

```sh
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make -l animate/slides -l animate/slides/pict \
  -l animate/slides/scene -l animate/slides/render \
  -l animate/slides/math -l animate/slides/geometry -l animate/slides/project \
  -l animate/slides/gallery slides/run-gallery.rkt &&
"$RACKET" slides/run-tests.rkt --math --geometry --media --project

"$RACKET" slides/run-probes.rkt --repeat 2 --math --geometry --gallery \
  slides-output/review-v040
```

The complete runner now contains **105 named cases across sixteen suite files**; these are
supplied tests, not a claim that this version passed them here. The existing CI
command picks them up through `slides/run-tests.rkt`. The expanded visual runner
covers transition interiors, exact endpoints, both themes, portrait/widescreen,
and real mathematical/geometry content in one review ZIP.

## Documentation and limits

[API reference](docs/api.md) · [New gallery/transition guide](docs/gallery-and-transitions.md)
· [Core authoring guide](docs/user-guide.md) · [Validation](docs/validation-v040.md)
· [Changes](CHANGES.md)

Geometry preparation belongs to the parent; rendering can use subprocess workers.
No new automatic text/formula morph,
forced alignment, speech generation, interactive layout editor, or arbitrary
renderer-factory transfer is claimed. Mathematical context headings and working
margins remain owned by the existing math adapter. The preparation payload is now
version 4; prepare again instead of reusing an older payload.

## Semantic continuity

```racket
(content-state (math-content plan) #:at '(subtract-five start) #:viewport '(12 7))
(slide-transition #:effect 'match #:keys '(equation) #:depth 'semantic #:duration 4)
```

`semantic-group` / `semantic-part` expose explicitly named children.
`content-state` freezes a checkpoint from an existing domain plan. A compatible
matched bridge replays that plan while moving the containing slot.
`storyboard-match-report` exposes the prepared correspondence without live handles.

The gallery entries are `semantic-parts`, `semantic-math`, `semantic-geometry`,
and `semantic-math-geometry`. The full guide is
[Semantic continuity between slides](docs/semantic-matching.md).
