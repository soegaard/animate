
## Clean upgrades

When replacing one drop-in `math/` revision with another, remove the previous
`math/` directory first. If an overlay has already been performed, remove all
`math/**/compiled/` directories before invoking Racket. Stale `.zo` files can
otherwise present an older export set than the source visible on disk.

# Integration contract — 0.3.0

Place this directory at `<animate repository>/math/`. This delivery replaces
only the math subcollection. No parent repository file is modified.

## Public module boundaries

| Module | Responsibility | External work at require time |
|---|---|---|
| `animate/math` (`math/main.rkt`) | Held states, contexts, selectors, operations, rules, derivations, notation and presentation descriptions | None; its local dependency closure contains no native renderer or CAS execution module |
| `animate/math/render` (`math/render.rkt`) | Explicit native preparation, scene/Visual/Pict conversion and prepared-data inspection | Native loading, TeX and asset creation occur on an explicit preparation/conversion call |
| `animate/math/cas` (`math/cas.rkt`) | Validated service/response records and bounded query/verification entry points | No backend query until an explicit call |
| `animate/math/cas/racket-cas` | Optional lazy racket-cas provider | No racket-cas load merely to describe a service |
| `animate/math/cas/calcura` | Optional configured parser/Eval provider or supplied query callback | No Calcura load merely to describe a service |

Use `!`-suffixed entry points for external work: `prepare-math-plan!`,
`math-plan->scene!`, `math->visual!`, `math-plan->pict!`, `cas-query!`,
`cas-calculate!`, `verify-proposition!`, `verify-derivation!`, and
`call-with-math-services!`. The examples have already been migrated.

Raw state, edit, operation, trace, derivation, and presentation constructors
are private. Public predicates and accessors permit inspection without exposing
an invariant-bypassing construction path. Use checked rule constructors to
extend mathematical authoring. The exported CAS record constructors have guards;
their query callbacks are explicitly trusted effectful adapter code.

## Internal responsibilities

`private/validation.rkt` provides pure validation and acyclic metadata copying.
`cas/model.rkt` holds service descriptions without executing callbacks.
`private/typeset-model.rkt` describes frozen prepared token/layout data, while
`private/token-layout.rkt` handles geometry without I/O.
`private/transition-plan.rkt` selects typed semantic units from occurrence links,
partitions incoming/outgoing ink, and groups rigid copies and signed reorders.
It does not invoke native graphics or guess glyph correspondences from geometry.
`private/typeset.rkt` and `private/prepare.rkt` own actual typesetting,
measurement, and asset preparation. `private/animate-adapter.rkt` compiles
prepared steps into the existing native timeline.

The native bridge resolves the parent checkout relatively, not a second
installed copy of animate. There is no process-global mutable native binding
cache or renderer registry. The bridge invokes the existing tagged-formula
constructor on a complete marked source and emits standard SVG image Visuals.
No new native Visual protocol, frame evaluator, renderer registration, or parent
`main.rkt` edit is required.

All frame sequencing uses the native scene engine. The presentation schedule is
an inspectable compilation description, not another animation evaluator.
The scene's `<id>.checkpoint` value is a numeric index; its full mathematical
record is in `plan-checkpoints`. This preserves the native named-value contract.
Sampling a compiled scene performs no CAS queries or TeX calls.

## Camera, layout and renderer contracts

The native Pict boundary uses `scene-state->pict` with **`#:camera`**, never a
second positional camera argument. `math-plan->pict!` forwards the caller's
`#:renderers` list unchanged; `#f` selects native defaults. Its omitted theme
retains a prepared plan's captured theme rather than replacing dark with light.
Prepared plans capture camera and appearance. Conflicting conversion overrides
are rejected and require explicit repreparation.

Preparation fits complete-SVG artifact metrics to the captured camera. It does
not measure padding introduced by an arbitrary custom Pict renderer. A custom
renderer that changes extents may need explicit layout adjustment. Final-paint
renderer forwarding is not a claim of generic custom-renderer-aware fitting.

## Assets and trust

The SVG cache defaults to `animate-math/svg-v1` under
`(find-system-path 'pref-dir)`. Files are content-addressed and must remain
available while native workers render a compiled scene. The mathematical core
performs no cache cleanup or user-file deletion. A caller can select a persistent
`#:cache-directory` at preparation.

TeX, native modules, and CAS callbacks are trusted execution boundaries, not a
security sandbox. CAS timeouts bound owned query work; they do not make arbitrary
backend code safe. Verification metadata is copied into immutable acyclic data.
Opaque backend result handles remain in adapter results and are excluded from
mathematical verification details.

## Documentation and optional integrations

`math/info.rkt` registers `math/scribblings/math.scrbl` as this subcollection's
public reference. The parent `scribblings/animate.scrbl` is deliberately not
rewritten in a folder-only delivery. Build the reference explicitly from the
repository root with:

```sh
scribble --htmls --dest math-output/docs math/scribblings/math.scrbl
```

`examples/rhombus/held-mathematics.rhm` illustrates importing the ordinary
Racket API and worked lesson from Rhombus. It is excluded from ordinary Racket
compilation because Rhombus remains optional.

See `docs/validation.md` for the checks actually executed. Native rendering,
live CAS, the Scribble build and the Rhombus example are not represented as
locally passing tests.
