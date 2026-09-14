# Dark-video review revisions — 0.3.3

This release revises the compiler rather than special-casing the four lessons.
Replace the existing `math/` directory with this archive's folder. No parent
repository files, renderer protocols, or CAS modules are changed.



## Third dark-video review: cancellation separators and case handoff

The 0.3.2 rerender confirmed that branch splitting and numerator reordering were
fixed. Two additional presentation defects remained.

**Surviving additive separators.** In the concrete quadratic, cancelling the
last `+5-5` changed the held tree shape from a nested sum/subtraction to a
shorter sum. The operands were correctly preserved, but the `+` between `x^2`
and `6x` was classified as outgoing notation and disappeared until the new sum
separator appeared. The transition planner now infers a separator witness only
when the same two adjacent surviving addends bracket it before and after the
rewrite. Such a separator is preserved and repositioned with the survivors; a
new separator between formerly non-adjacent terms is still created normally.

**Case-start copies.** The first working copy of a parameter case used to be
added at the exact checkpoint position and then moved to the next row, producing
a transient doubled/bold formula. Case starts now retain the checkpoint row and
fade the working copy in at its final row. Ordinary non-case lessons keep the
explicit copy-and-move choreography. No-op history moves are omitted.

**Whole-relation replacement.** When both sides of a root relation are atomic
replacement scopes, the complete assertion is now atomic. This prevents an
isolated equality sign from remaining between fade-out and fade-in in the
`single-root` branch.

These are presentation-lowering changes only; the mathematical checkpoint trees
and durations are unchanged.

## Second dark-video review: transition safety

The 0.3.1 rerender confirmed that evaluation, cancellation, completing the square
and fraction reduction were fixed. Two families still produced misleading
intermediate frames, so 0.3.2 makes their native lowering deliberately more
conservative.

**Branch copy.** A semantic `copy` relation no longer implies visible transport
from one source position to two destination positions. After retiring the old
working line, the duplicated shared bases are installed invisibly at their exact
final branch positions and faded in there. The following phase reveals the new
relation and radical material. This preserves the mathematical copy provenance
without crossed glyph trajectories.

**Reordering.** `reorder-addends` still records exact source/target occurrence
lineage in the derivation. For presentation, however, every affected additive
focus is atomic. The old numerator/RHS fades out as one coherent unit, preserved
surrounding structure may reposition, and the new additive focus fades in as a
whole. No sign, radical, or term inside that focus receives a `move-to` request.
A future collision-free term-permutation planner can opt back into rigid term
motion explicitly.

These rules are defaults of the presentation compiler, not special cases in the
quadratic examples.

## Findings and revisions

| Observed in the 0.2.0 dark videos | Revision | Executed regression |
|---|---|---|
| Linear cancellation briefly loses unrelated right-hand ink, around 2.6–3.3 s | Mathematical links no longer fail because two SVG crops differ slightly in size. Cancellation retires only unpreserved material, holds survivors, then compacts. | Complete token partitions; intentionally differing metrics; RHS visibility during cancellation and unit removal |
| `17−5 → 12` briefly shows `12−5`, around 3.8–4.3 s | Treat the entire evaluated focus as one visibility unit. Retire all old ink, move preserved units, then reveal all new ink. | Intermediate contract-frame samples prove outgoing and incoming units are never simultaneously visible |
| `12/3 → 4` briefly resembles `4/3`, around 8.4–9.0 s | Fraction bar, numerator and denominator belong to the evaluated unit; the result cannot appear beside an old denominator. | Fraction-bar ownership fixture and atomic evaluation samples |
| Completing a square overlays or interweaves the polynomial with its square | Checked target rewrites use the same full-focus visibility barrier, not digit or glyph matching. Unaffected equation parts stay visible. | Concrete quadratic `make-square` intermediate samples and all-step partition checks |
| Square-root splitting produces a malformed combination of the source and two targets | Retire the old working line, reveal semantic copies already at their final branch positions, then reveal each complete radical RHS and new relation material. | Copied-source witnesses; whole-radical creation; zero move requests during branch-copy appearance |
| Signs and fraction pieces travel independently while reordering | Treat every affected additive focus as one atomic replacement. Preserve the surrounding equation/fraction structure; fade the complete old focus out and the complete reordered focus in. | Atomic reorder-focus paths; complete outgoing/incoming partitions; no movement matches inside the focus |
| General quadratic repeats completing the square for all three discriminant cases | Add shared-prefix presentation, used by this example. Derive once to `(2ax+b)^2=Δ`, then visit each case from that checkpoint. | One `make-square` checkpoint; six terminal cases; full prefix restored for a selected standalone case |
| Headers include redundant consequences such as `2a≠0` | Display authored assumptions and only restrictions not already established by those assumptions/definitions. Keep all restrictions in evidence. | Redundant guards suppressed; original `x≠0` exclusion retained |
| Choice of nine is unmotivated | Add an independent `(6/2)^2=9` inset before `add-nine`, with a short caption. | Inset content, reserved preparation, checkpoint stability and cleanup |

The old timestamps above identify the reviewed defects, not locations in the
new videos. The new probe manifest supplies active step and phase names.

## Visibility and motion contract

`private/transition-plan.rkt` is a pure planner. It obtains movement and visibility
units from the applied step's typed events and source/target occurrence links.
It accounts for every source and destination token, including operator ink.
There is no geometric fallback claiming that similar glyphs are the same
mathematical occurrence.

A default replacement uses 45% of its duration to fade out the old focus, 10%
to move survivors, and 45% to fade in the destination focus. This deliberately
passes through a temporary gap instead of cross-fading incompatible arithmetic
at the same location. Mathematical assertions remain the committed checkpoints,
not partially faded frames.

The native compiler still emits ordinary `move-to`, `fade-to`, scene composition,
and waits. Moving views keep their original SVG assets; exact destination
assets are installed at each endpoint. No CAS or TeX work runs during sampling.
Custom choreography that reveals replacement material too early, or compacts
before retiring obsolete structure, fails explicitly.

These are conservative presentations, not newly reconstructed algebra proofs.
A many-to-one merge without a trustworthy fine trace uses a coarse replacement;
this release does not add a dedicated morph of several terms into one glyph.

## Authoring additions

```racket
(present solution #:case-layout 'shared-prefix #:groups groups-by-complete-case)
```

The default remains `'complete-paths`. Shared mode validates group declarations
on complete paths, then projects them onto common and branch segments. Conflicting
shared-prefix partitions are rejected. `plan-segment-shared?` identifies an
intermediate common segment; it is not a terminal solution case. `--list-cases`
prints the six actual leaves, and `--case quadratic/two-real-roots` starts at
the original equation with the common prefix restored.

```racket
(choreograph plan
  [add-nine
    (explain-math '(= (expt (/ 6 2) 2) 9)
                  #:caption "Half the coefficient of x, then square it"
                  #:duration 2)
    (prepare-space #:duration 11/25)
    (reveal-created #:duration 9/25)])
```

The inset is separately prepared and fitted into a reserved lower band. Its
caption is snapshotted and must be one line. It changes presentation time, not
the mathematical derivation or checkpoint index. `presentation-phase-annotation`
exposes its held state and caption for inspectors. This is explanatory authoring,
not an automatic verification operation.

Formatting also parenthesizes fraction, radical and nested-power bases when
raising them to another power. This avoids double superscripts and ambiguous
power attachment while preserving the original held datum. All marked/unmarked
TeX regression pairs remain identical.

## Default durations

| Example | Revised duration |
|---|---:|
| Concrete linear | 54/5 s = 10.8 s |
| General linear | 39/2 s = 19.5 s |
| Concrete quadratic, including the inset | 88/5 s = 17.6 s |
| General quadratic, including all six terminal cases | 549/10 s = 54.9 s |

The general quadratic was 74.7 seconds in the reviewed version. No mathematical
states, assumptions, branch guards or solution results were removed from its
underlying derivation. All four mathematical checkpoint trees were compared
against the 0.2.0 archive and are identical.

## Render and inspect the revision

From the animate repository root:

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" math/run-tests.rkt
"$RACKET" math/run-style-checks.rkt
"$RACKET" math/run-probes.rkt --dark math-output/review-v0.3/probes

mkdir -p math-output/review-v0.3/videos
for example in linear-concrete linear-general quadratic-concrete quadratic-general
do
  "$RACKET" "math/examples/${example}.rkt" \
    --dark --workers 10 \
    --mp4 "math-output/review-v0.3/videos/${example}.mp4" \
    "math-output/review-v0.3/frames/${example}" || break
done
```

Fresh output paths avoid mixing previous frames with shorter rerenders.
The probe runner now samples intermediate phases in **all four** examples and
includes the replacement-barrier boundaries. Each PNG's manifest entry includes
active `step`, `phase`, `phase-progress`, last `checkpoint-step`, mathematical
datum, exact time and theme. `--checkpoints-only` gives a smaller endpoint set.

Watch the concrete linear evaluation and cancellation first, then the quadratic
square/root split, then whole-focus numerator reordering and shared cases. A coherent
pause/gap is intentional; mixed old arithmetic and new answers are not.

## Validation boundary

This revision passed the mathematical, source, API-contract and real-TeX tests
listed in `validation.md`. **The actual animate/dvisvgm pipeline and revised MP4s
were not run in this delivery environment.** In particular, contract-model
frames do not establish macOS renderer correctness or subjective pacing. The
updated actual native runner is included to make that remaining review precise.
