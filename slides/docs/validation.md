# Validation report — animate/slides v0.1.4 source preview

Date: 16 September 2026.
Baseline: `soegaard/animate` commit
`6608411f8176404f80063cdebc439c898b465e0f`.

## Status

The implementation has now been exercised on the target macOS checkout with
Racket 9.3.0.2. The user reported the complete nine-suite integration run green:
**33/33 named v0.1.3 test cases passed**, including actual TeX/math preparation,
geometry integration, generated-media probing, and the two-worker subprocess
project path. The subsequent visual runner completed **158 Pict/Scene comparisons**
with `--repeat 2`, math, and geometry enabled, and recorded **zero probe errors**.

The visual review found one substantive Pict/Scene discrepancy: the exact cut at
3 seconds in `function-lesson` selected the incoming shot in direct Pict sampling
but the outgoing shot in the native Scene path. This was traced to floating-point
interpolation of the Scene's global semantic clock. v0.1.4 canonicalizes only the
native Scene clock when it is infinitesimally close to an authored beat, event,
shot, or bridge boundary; direct near-boundary Pict queries remain literal.

The same review identified two composition improvements implemented in v0.1.4:
portrait `title+two-column` now stacks short text regions compactly instead of
splitting the whole remaining height 50/50, and `equation-focus` centers the
equation and annotation as one rhetorical unit rather than pinning the annotation
to the bottom safe edge. These v0.1.4 changes include three additional named
regression cases and still require rerunning Racket and the gallery after overlay.

The delivery container itself still has no `racket` or `raco` executable. Therefore
all v0.1.4 runtime claims are deliberately limited to the v0.1.3 user-run baseline
plus the static source checks recorded with this overlay.

## Checks performed in the delivery environment

The archive includes the Python scripts and their machine-readable output under
`slides/tools/` and `integration/`. These checks are deliberately independent of
Racket and do not substitute for its reader, expander, module system, or evaluator.

| Check | Result / evidential limit |
|---|---|
| Lexical scan of all delivered `.rkt` files | No bracket, unterminated-string, or recognized string-escape errors found. The scan is a limited auxiliary lexer, not Racket's reader. |
| Source-shape scan | No checked `define`, `if`, `set!`, or private struct-constructor arity mistakes found; test cases remained inside declared suites. Macro expansion, binding resolution, and contracts are not evaluated. |
| Local module-path inventory | Packaged relative module dependencies were checked for existence; native repository dependencies are recorded separately. This does not establish native exports or phase correctness. |
| Native interface review | The current repository's Scene, Pict, colors, typography, math, geometry, media, and project entry points were inspected through GitHub. This was source review, not execution. |
| Drawing API review | Racket's official `record-dc%` and Pict documentation were checked for recording/replay and text-font behavior. |
| Archive/inventory check | The final ZIP was read back and its CRCs and SHA-256 inventory checked. This only establishes archive integrity. |

Exact source counts and scan outputs are recorded in `integration/static-checks.json`.
The check scripts are included to make the limited evidence reproducible.

## Tests supplied, but not executed

There are **36 named RackUnit test cases in nine suites** in v0.1.4. Several cases contain
parameterized loops and multiple assertions; 36 is the number of named cases,
not the number of individual assertions.

| Suite | Named cases | Coverage |
|---|---:|---|
| `model-test.rkt` | 7 | Literal slot syntax, procedural equivalence, copied mutable input, required/duplicate slots, theme values, pure declarations. |
| `layout-test.rkt` | 9 | All twelve layouts under two themes and four formats; fit/overflow, custom regions, preparation contexts, explicit crop. |
| `timing-test.rkt` | 8 | Reserved geometry, named bullets, direct seeking, replacement alternatives, action conflicts, narration duration, transition boundaries. |
| `native-test.rkt` | 7 | Unprefixed supported import combinations, ordinary Scene conversion, Pict comparison, native slot transforms, child local clocks, authored metadata. |
| `codec-test.rkt` | 1 | Parent drawing preparation, worker replay, payload transfer, repeated sampling, and artifact tamper detection. |
| `math-test.rkt` | 1 | Actual TeX preparation and exact native mathematical step cues. Optional. |
| `geometry-test.rkt` | 1 | Actual geometry construction and native adapter. Optional. |
| `media-test.rkt` | 1 | Generated PCM WAV, real `ffprobe` duration and trimming. Optional. |
| `project-test.rkt` | 1 | Actual project preparation and two subprocess workers. Optional. |

Default test execution loads the first five suites. The optional flags require the
corresponding installed tools and domain dependencies. The complete v0.1.3 run was
reported green; v0.1.4 adds the exact-cut and portrait/equation layout regressions,
so those new cases remain to be rerun on the target checkout.

## Run the acceptance checks

From the checkout root after unpacking this overlay:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACKET" slides/install.rkt
"$RACO" make -l animate/slides -l animate/slides/pict \
  -l animate/slides/scene -l animate/slides/render \
  -l animate/slides/math -l animate/slides/geometry -l animate/slides/project

"$RACKET" slides/run-tests.rkt
"$RACKET" slides/run-tests.rkt --math --geometry --media --project

"$RACKET" slides/run-probes.rkt --repeat 2 --math --geometry \
  slides-output/layout-review
```

Use a new gallery directory for each run. The gallery runner refuses to overwrite
an existing review directory or ZIP. A failing probe is recorded and produces a
nonzero exit status after the review artifacts are written.

Also run the existing repository's normal suite and release checks; the guarded
integration modifies three native files and the new subcollection is not exempt
from broader regressions. This source preview does not claim to have updated the
root CI catalogue or passed `raco animate check-repo`.

## Visual acceptance

The review runner is configured to produce 96 static theme/format/layout specimens,
each with both direct Pict and native Scene output. It adds short-video samples in
reverse seek order, exact beat/bridge boundaries, and one frame on either side.
With `--math` and `--geometry`, it includes real domain examples. Repeated samples
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

The implementation guide describes the current behavior and takes precedence
over the retained historical design document.

## Source references reviewed

These references identify the native interfaces the implementation targets. They
are not evidence that integration tests ran.

- Repository baseline: <https://github.com/soegaard/animate/tree/6608411f8176404f80063cdebc439c898b465e0f>
- Native Scene timeline: `private/scene.rkt` and `private/scene-state.rkt` at that commit.
- Pict composition: `private/pict-adapter.rkt`, `private/pict-renderer.rkt`, and `private/relative-layout.rkt`.
- Theme snapshots: `colors.rkt`, `typography.rkt`, and their private implementations.
- Mathematical preparation: `math/render.rkt`, `math/private/prepare.rkt`, `math/private/animate-adapter.rkt`, and `math/private/prepared-plan-codec.rkt`.
- Geometry sampling: `geometry/animate.rkt` and `geometry/core.rkt`.
- Media/project integration: `private/authoring-timeline.rkt`, `project.rkt`, `private/project-execution.rkt`, and source-preparation modules.
- Racket drawing recordings: <https://docs.racket-lang.org/draw/record-dc_.html>
- Pict constructor/text contract: <https://docs.racket-lang.org/pict/Basic_Pict_Constructors.html>
