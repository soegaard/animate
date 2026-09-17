# Writing the Animate manual

The entry point is `scribblings/animate.scrbl`. The published manual has four
parts, in this order:

| Part | Reader's question | What belongs here |
| --- | --- | --- |
| Concepts | What does this mean? | Explanations, distinctions, small diagrams. |
| Cookbook | How do I do this one task? | Short recipes with imports, code, result, and one warning. |
| Guide | How do I finish a whole job? | A step-by-step example that grows into a useful program. |
| Reference | What does this name accept and return? | Signatures, defaults, restrictions, errors, and module ownership. |

Do not put a release history before a beginner's explanation. Do not make a
reader leave the manual for a Markdown file to learn the public slide API.
Development notes and test reports remain useful, but they are not the tutorial.

## Language

Use short sentences and concrete verbs. Define a technical term the first time
it is needed. Keep real API names unchanged. Prefer these explanations:

| Avoid in introductory prose | Prefer |
| --- | --- |
| effectful rendering boundary | the step that writes files or runs an encoder |
| renderer-neutral snapshot | the prepared content both renderers use |
| arbitrary-time evaluation | ask for a frame at any time |
| semantic provenance witness | the original plan that records what changed |
| portable preparation payload | prepared data sent to workers |

Precision still matters. A Scene is an animation description, not a single frame.
A scene state is a sample at a time. A Pict is a value, not a saved PNG.
Preparing a slide is not encoding a video. A passing test is not a visual review.

## Examples

Standalone manual programs are in `scribblings/examples/`. Display them with
`example-source` from `scribblings/private/examples.rkt`; do not maintain a second
copy in the prose. This helper reads the file as text and does not execute it.
Declare exports and keep file output out of module-level code. Each program must
show its imports and must not use an undefined placeholder as a complete example.
Clearly label small fragments that require a preceding example.

Test those source files from the repository root:

```sh
racket scribblings/check-examples.rkt
racket scribblings/check-examples.rkt --math --geometry
```

The second command performs real math preparation and needs its TeX toolchain.
Neither command makes MP4 files. Tests do not open a preview GUI.

## Navigation and compatibility

The four part files use Scribble's `toc`/`grouper` styles, so they remain clear
parts in the multi-page manual. Chapters keep their existing explicit tags when
rewritten. Links should target explicit tags, not generated HTML filenames.

`cookbook/reference-recipes.scrbl` is included by `reference.scrbl`: despite its
historical filename, it contains number-line and decoration API definitions.
The path is retained to avoid breaking source references. New recipes live in
the Cookbook; new API definitions live in the Reference.

## Validate and build

```sh
python3 scribblings/check-structure.py .
racket scribblings/check-examples.rkt --math --geometry
racket tools/check-documentation.rkt slides-output/manual-docs
```

The last command uses the repository's existing documentation builder and
Animate-owned unresolved-link check. Open
`slides-output/manual-docs/animate/index.html` after it succeeds. Build from the
repository root, as the retained figure paths expect that working directory.

## Keeping the manual current

For a changed function, update its Reference entry first. Then update any recipe
and guide that uses it. Keep implementation version numbers out of output folder
names in general instructions. A new installation should use `--list` to discover
gallery IDs. Record actual test evidence in the test report, not in a permanent
claim that the current checkout is validated.

## Illustrated revision r2

The old `reference/scene.scrbl` was titled “Quick Start”, although it held thousands
of lines of API documentation. The update splits it into scenes, scene states,
model details, and smaller animation-reference chapters. The old plotting example
moves to the Cookbook. Its definitions and their accompanying prose are preserved
by the updater, not regenerated from guessed contracts. The `quick-start` section
tag now leads to the actual short first-animation chapter.

The Guide's reading order is deliberate:

1. Make one Visual, add it to a Scene, move it, sample a picture, then add a hold.
2. Render frames and encode a movie.
3. Put content in slots, give a slide time, then reveal content with beats.
4. Order shots in a storyboard; only now use continuity keys and transitions.
5. Choose themes and formats, then add narration.
6. Give embedded content its own viewport and clock; introduce preparation here.
7. Use named parts and checkpoints to preserve continuity.
8. Organize source modules, open the preview, and configure a larger project.

The `requires` / `introduces` comments in Guide sources record this teaching
spine. The source checker checks that order and the API calls in displayed code
snippets. It is an editorial guard, not a proof that prose teaches every idea well.

Use `example-part` to display a named `;; doc: ... begin/end` region from a
standalone program. Avoid dumping a long program before explaining its parts.
Complete programs remain available in the Cookbook and source tree.

### Illustrations

Use `frame-strip` from `private/illustrations.rkt`. Each animation strip has
three or five actual sampled frames, with times and a short caption. A static
picture or a comparison of themes/formats is labeled as such instead of pretending
to show animation. Narrow two- or three-column arrangements keep strips within a
manual page; full-resolution PNGs remain in the generated documentation assets.

The initial 75 PNGs are unmodified captures from the supplied `layout-review-v040`
review. Eight circle/source-block SVGs are existing repository illustrations. `figures/illustrations.json`
records where each picture came from, its sample time, recipe, and checksum.
`figures/index.html` is an illustration review page, not a compiled manual.

Regenerate explicitly, never as an incidental effect of building documentation:

```sh
racket scribblings/render-illustrations.rkt slides-output/manual-illustrations
```

For a small check without TeX or geometry:

```sh
racket scribblings/render-illustrations.rkt \
  --strip title-build --strip push-left \
  slides-output/manual-illustration-smoke
```

The complete run includes real mathematics and needs the same typesetting tools as
the math examples. Review new pictures before replacing the checked-in catalogue
and frames. Different hosts may have different text rasterization. A selective
run's catalogue contains only the selected strips; it must not replace the complete
catalogue. The renderer refuses an existing output directory.

The new example runner has twelve base cases and two optional domain cases.
Its updated durations and names match the displayed programs. Run all three checks:

```sh
python3 scribblings/check-structure.py .
racket scribblings/check-examples.rkt --math --geometry
racket tools/check-documentation.rkt slides-output/manual-illustrated
```

The source checker needs Python 3.9 or later. It cannot replace the Racket example
run or Scribble's own cross-reference check. The reference redistribution receipt
is `reference/reorganization-r2.json`; it records the preservation check and the
resulting file hashes.
