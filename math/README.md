# animate/math — semantic mathematical animation

Version **0.3.3** · drop-in `math/` subcollection for `soegaard/animate`

Held mathematical expressions → checked, traceable derivations → independently
choreographed presentations → ordinary native `animate` scenes.

Unzip the archive in the root of your existing `animate` checkout. It adds only
this directory. No parent files are patched, and neither CAS is mandatory.
When that checkout is installed as the `animate` collection, use:

```racket
(require animate/math)
```

Relative imports in the supplied examples also work directly from the checkout.

**Migration from 0.1.1:** mathematical authoring stays in `animate/math`.
Native preparation now comes from `animate/math/render`, and CAS execution comes
from `animate/math/cas`. Effectful entry points have `!` suffixes, including
`math-plan->scene!`, `prepare-math-plan!`, and `verify-derivation!`.
Raw internal constructors are no longer public. See
[the house-style revision and migration notes](docs/house-style-review.md).

## Upgrading an existing `math/` tree

Prefer replacing the directory rather than copying new files over an old one:

```bash
rm -rf math
unzip animate-math-v0.3.3-cancellation-case-handoff.zip
```

If you have already overlaid files, remove Racket bytecode caches before testing:

```bash
find math -type d -name compiled -prune -exec rm -rf {} +
```

This matters because a previously compiled `.zo` can be newer than freshly copied
source files and can therefore expose an older public API even though `main.rkt` on
disk contains the new bindings. `run-style-checks.rkt` checks for this mismatch.


## Revision from the dark-video review

Numeric evaluations and opaque rewrites now retire the entire outgoing focus
before revealing the result. Preserved expressions keep their occurrence
identity even when SVG crop metrics differ. Cancellation holds its survivors
until compaction. Square-root branch copies now appear already at their final
branch positions instead of crossing one another; complete radicals are revealed
afterward. Reordered additive focuses use a whole-focus fade-out/fade-in while
the surrounding fraction/equation structure is preserved, avoiding transient
products or detached minus signs. Additive cancellation now preserves any infix
separator bracketed by the same adjacent surviving terms, so `x^2+6x` never
loses its `+` while `+5-5` retires. The first working copy of a parameter case
also fades in directly at its destination row instead of overlapping the shared
checkpoint and moving through it.

The general quadratic completes its common derivation once and lasts **54.9 s**
by default, with all six cases retained. Redundant proved restrictions are hidden
from headers, not removed from evidence. The concrete quadratic now motivates
adding nine with a separate `(6/2)^2=9` inset.

Read [the timestamp-to-fix revision notes](docs/video-review-revision.md).
The previous public authoring and rendering calls remain available; the new
options and inset phase are additive to the 0.2.0 API.

## Start here

From the repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

# Base-only mathematical, provenance and native-contract tests.
"$RACKET" math/run-tests.rkt

# Separate source, dependency and public-reference coverage audit.
"$RACKET" math/run-style-checks.rkt

# Inspect the complete mathematical derivation without rendering.
"$RACKET" math/examples/linear-concrete.rkt --steps

# Actual native rendering / random-access visual probes.
"$RACKET" math/run-probes.rkt --dark math-output/review-v0.3/probes

# Render the first lesson with ten shared subprocess frame workers and encode an MP4.
"$RACKET" math/examples/linear-concrete.rkt \
  --workers 10 \
  --mp4 math-output/videos/linear-concrete.mp4 \
  math-output/frames/linear-concrete
```

Rendering requires the normal `animate` dependencies, **latex**, **dvisvgm**, and
**ffmpeg** for MP4 output. On macOS, TeX executables are commonly exposed through
`/Library/TeX/texbin`; make sure they are on PATH. No Rust, new renderer, or CAS
installation is required for these lessons.

## The four worked examples

| Source | Mathematical content |
|---|---|
| `examples/linear-concrete.rkt` | `3x+5=17`; held subtraction, cancellation, explicit division, `1·x`, and `x=4` |
| `examples/linear-general.rkt` | `ax+b=c`; ordinary, identity and inconsistent coefficient cases |
| `examples/quadratic-concrete.rkt` | `x²+6x+5=0`; completing the square, both roots, candidate checks |
| `examples/quadratic-general.rkt` | Scaled completing-the-square derivation and all six real coefficient/discriminant cases |

Each exports `problem`, `solution`, `plan`, and `make-demo-scene`.
The concrete examples also export their candidate-check objects.
Requiring an example does not typeset formulas or write files.

Useful example flags:

```sh
"$RACKET" math/examples/quadratic-general.rkt --list-cases
"$RACKET" math/examples/quadratic-general.rkt --steps --case quadratic/two-real-roots
"$RACKET" math/examples/quadratic-general.rkt \
  --dark --case quadratic/two-real-roots --workers 10 \
  --mp4 math-output/videos/quadratic-formula-dark.mp4 \
  math-output/frames/quadratic-formula-dark
```

Also supported: `--fps`, `--width`, `--height`, `--supersample`, `--light`, and
`--help`. The optional positional argument is the frames directory.
Without `--steps` or `--list-cases`, the example renders frames.

Ordinary rendering uses Animate's source-aware project executor. The parent
selects the case, camera, and appearance, then completes TeX and formula-layout
preparation exactly once. Restarted workers validate and rebind that prepared
layout data before rendering; they do not prepare formulas themselves. With
`--workers 1` rendering stays in-process; higher values use the shared
restartable subprocess workers. Only the supported `--light` and `--dark`
themes are accepted, and `--fps` is intentionally a positive integer because
the shared executor renders an integer frame grid.

Prepared SVGs are content-addressed in the ignored
`examples/.animate-math-preparation-artifacts-v1/` directory. They are checked
as source-preparation artifacts for the current render rather than stored as a
persistent preparation manifest. `--steps` and `--list-cases` stop before
preparation, rendering, output cleanup, or MP4 encoding. PNG rendering accepts
odd dimensions; the H.264 `yuv420p` MP4 encoder requires even width and height.

## Minimal authoring example

```racket
#lang racket/base
(require animate/math
         animate/math/render)

(define problem
  (math '(= (+ (* 3 x) 5) 17)
        #:id 'lesson
        #:context (math-context #:real '(x))))

(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five   (cancel-addends #:at (lhs))]
    [evaluate-rhs  (evaluate #:at (rhs))]))

(define plan
  (present working #:style classroom
           #:groups '((subtract-five cancel-five evaluate-rhs))))

;; Explicit preparation boundary: produces a normal animate scene.
(define (make-demo-scene)
  (math-plan->scene! plan #:title "Subtract the same amount from both sides"))
```

The intermediate `3x+5−5=17−5` is retained. Construction does not call
`racket-cas` smart constructors or normalize display expressions.

## Documentation and validation

Read **[docs/user-guide.md](docs/user-guide.md)** for the implemented API, four
examples, custom rules, CAS configuration, scene inspection, and limitations.
The original discussion document is retained as
`docs/proposal-v0.1.md`; it is historical, not the implementation reference.

The public reference is [scribblings/math.scrbl](scribblings/math.scrbl),
registered by this subcollection's `info.rkt`. It defines all **275 public
bindings**. [INTEGRATION.md](INTEGRATION.md) explains the module boundaries.

**Executed validation:** **1,817** mathematical/property/adapter-contract checks
and **1,036** separate source/dependency/reference audit checks passed. All four
mathematical checkpoint trees match 0.2.0 exactly. **70** complete TeX formulas
were rendered with and without semantic markers; all **70 PNG pairs** were
byte-identical. See [docs/validation.md](docs/validation.md).

**Not executed in the delivery environment:** the actual `animate` + dvisvgm
rendering integration, live CAS integrations, Scribble build, and Rhombus example. The environment had a base-only
Racket runtime, not the installed animate dependencies or dvisvgm. The adapter
contract model is explicitly not presented as native rendering validation.
`math/run-probes.rkt` runs the real integration on your checkout and writes PNGs
and a manifest for inspection.

## Scope of this release

This is a real-scalar algebra implementation, not an automatic tutor or general
proof assistant. It includes held expressions, stable occurrence lineage,
conservative condition checking, case derivations, exact local algebra checking,
custom template rules, staged choreography, full-formula TeX/SVG tagging, native
scene compilation, and optional bounded CAS service adapters.

Target-based algebraic replacements are checked but can be visually coarse;
fine-grained correspondence is never fabricated from an opaque CAS result.
The case player presents guarded branches sequentially. Optional
`#:case-layout 'shared-prefix` presents common work once; the general quadratic
example uses it. Selecting one case still produces a self-contained lesson.
Simultaneous branch columns and a graphical decision-tree layout remain outside
this release. There is no new GUI inspector; structured
inspection records and the native visual probes are provided instead.
