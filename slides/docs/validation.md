# Validation report — animate/slides v0.1.4

Date: 16 September 2026.

## Completed validation

The complete nine-suite integration command passes on the target macOS checkout
with Racket 9.3.0.2: **36/36 named tests passed**. That run includes actual
TeX/math preparation, native geometry integration, generated-media probing, and
the two-worker subprocess project path.

The repeat-2 visual review completed **158 Pict/Scene comparisons** with math
and geometry enabled and recorded **zero probe errors**. It found the former
exact-cut discrepancy at 3 seconds in `function-lesson`; v0.1.4 canonicalizes
only the native Scene clock when it is infinitesimally close to an authored
boundary, while direct near-boundary Pict queries remain literal. The review
also informed the compact portrait `title+two-column` arrangement and the
centered `equation-focus` composition.

The auxiliary scripts in `slides/tools/` remain useful limited source checks,
but they do not replace Racket expansion, compilation, or the test suite.

## Test coverage

There are **36 named RackUnit test cases in nine suites**. Several cases contain
parameterized loops and multiple assertions; 36 is the number of named cases,
not the number of individual assertions.

| Suite | Named cases | Coverage |
|---|---:|---|
| `model-test.rkt` | 7 | Literal slot syntax, procedural equivalence, copied mutable input, required/duplicate slots, theme values, pure declarations. |
| `layout-test.rkt` | 9 | All twelve layouts under two themes and four formats; fit/overflow, custom regions, preparation contexts, explicit crop. |
| `timing-test.rkt` | 8 | Reserved geometry, named bullets, direct seeking, replacement alternatives, action conflicts, narration duration, transition boundaries. |
| `native-test.rkt` | 7 | Unprefixed supported import combinations, ordinary Scene conversion, Pict comparison, native slot transforms, child local clocks, authored metadata. |
| `codec-test.rkt` | 1 | Parent drawing preparation, worker replay, payload transfer, repeated sampling, and artifact tamper detection. |
| `math-test.rkt` | 1 | Actual TeX preparation and exact native mathematical step cues. |
| `geometry-test.rkt` | 1 | Actual geometry construction and native adapter. |
| `media-test.rkt` | 1 | Generated PCM WAV, real `ffprobe` duration and trimming. |
| `project-test.rkt` | 1 | Actual project preparation and two subprocess workers. |

Default test execution loads the first five suites. The optional flags require
the corresponding installed tools and domain dependencies. The complete command
below runs all nine suites and is part of the standard headless CI workflow.

## Run the acceptance checks

From the checkout root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make -l animate/slides -l animate/slides/pict \
  -l animate/slides/scene -l animate/slides/render \
  -l animate/slides/math -l animate/slides/geometry -l animate/slides/project

"$RACKET" slides/run-tests.rkt --math --geometry --media --project

"$RACKET" slides/run-probes.rkt --repeat 2 --math --geometry \
  slides-output/layout-review
```

Use a new gallery directory for each probe run. The runner refuses to overwrite
an existing review directory or ZIP. A failing probe is recorded and produces a
nonzero exit status after the review artifacts are written. Review output belongs
under `slides-output/`, which is intentionally ignored by Git.

The regular repository CI also compiles the public slide modules, runs the
complete nine-suite command, builds the main manual, and checks the public
modules from a fresh source archive.

## Visual acceptance

The review runner produces 96 static theme/format/layout specimens, each with
both direct Pict and native Scene output. It adds short-video samples in reverse
seek order, exact beat/bridge boundaries, and one frame on either side. With
`--math` and `--geometry`, it includes real domain examples. Repeated samples
are compared for determinism. The manifest reports differences between the two
output paths; those comparisons do not promise universal pixel identity.

Inspect heading and caption spacing, line breaks, mathematical readability,
bullet visibility, replacement boundaries, keyed title continuity, native local
clocks, subtitle-safe areas, portrait arrangements, and endpoint holds. PNG
repeatability alone does not prove that these are good visual compositions.

## Known scope gaps

The broader design is not completely implemented in this version. In particular:

- No portable geometry preparation codec; geometry uses the in-process route.
- No slot-level glyph writing/morphing, rich nested bullet figures, or transparent
  semantic aliases into arbitrary embedded native/formula internals.
- No speech generation, forced alignment, interactive layout editor, font fallback
  audit, effective-resolution advisory, or general constraint solver.
- No custom renderer-factory transfer and no guarantee of persistent frame-cache
  reuse for opaque prepared/native content.
- Native math context headings and working margins remain; they have not been
  redesigned into separate outer-layout roles.

The implementation guide describes the current behavior; the retained historical
design document records ideas beyond the implemented scope.
