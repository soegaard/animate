# House-style revision and migration — 0.2.0

This revision starts from the delivered `math/` version 0.1.1. It uses the
repository's `HOUSE_STYLE.md` blob
`8b5acb39ca016d523889bba38296e34dd665971b` as the style reference.
Only `math/` is changed; the rest of the animate checkout is untouched.

## Changes by responsibility

### Pure mathematics and explicit external work

`math/main.rkt` now has a pure dependency closure. Its former lazy native
convenience wrappers and CAS-execution re-exports have moved out of that facade.
Rendering lives in `math/render.rkt`; explicit backend queries and verification
live in `math/cas.rkt`. Provider construction stays lazy.

Service records were separated from their executor in `cas/model.rkt`.
Prepared token/layout data and pure layout operations were separated from TeX,
filesystem preparation, and native scene compilation. A native-loader global
mutable cache was removed; native resolution remains explicit at the adapter
boundary. No second animation runtime was introduced.

### Public invariants and immutable inputs

The public facades now list their exports explicitly. Internal edit, operation,
state, derivation, rewrite-commit, and presentation constructors no longer leak
into the public API. Existing predicates and read-only accessors remain, and
checked template rules are the public extension path.

Construction validates selector paths, phase options, case-branch shapes,
callback arities, evidence proposition identity, boolean flags, and duplicate
choreography keys. Scoped revision tags accept symbols or false, not arbitrary
mutable values. Prepared source ranges, token geometry, identity ordering and
copied diagnostic strings are checked at their boundaries.

A substitution descriptor now snapshots a mutable input hash immediately. The
same operation therefore has the same result after the caller changes that hash.
Verification details similarly snapshot acyclic ordinary data containers,
including boxes, vectors, strings and hashes. Cycles, procedures and opaque
native resources are rejected. Nested validated verification records are legal.
External result values may remain opaque at the CAS boundary, but the verifier
retains only copied status, evidence and diagnostics in its mathematical report.

### Exact time and explicit order

Default phase durations, pauses and schedule constants use exact rational
seconds. The concrete linear example's default duration is **`54/5` seconds**.
Caller-supplied inexact times remain permitted; the implementation does not
silently convert all user numbers to exact rationals.

Occurrence descendants follow numeric operand preorder. Custom rule checks
follow metavariable declaration order rather than hash enumeration. Preparation
diagnostics follow derivation order, and native introduction/movement lists
retain their intended source order. These changes make identity, diagnostics and
layer ordering independent of incidental hash traversal.

Native probe manifests preserve the exact time as a string and use an ordinary
JSON number for plotting. Thus exact rational schedules remain JSON-compatible.

### External API and failure handling

The positional-camera regression remains fixed everywhere: native Pict calls use
`#:camera`. The native contract model now has a keyword-only camera signature, so
the previous two-positional-argument mistake would fail the mandatory suite.

`math-plan->pict!` forwards `#:renderers` and retains a prepared plan's theme when
no override is supplied. The renderer override affects final painting; layout
still uses prepared SVG metrics and does not remeasure arbitrary renderer padding.

CAS callbacks returning `#f` are diagnosed as invalid responses, not timeouts.
Non-success statuses cannot contribute mathematical decisions. Evidence for a
different proposition is rejected. Backend disagreements and undecided queries
remain explicit rather than being promoted to established results.

### Source and reference documentation

Modules have responsibility headers and named sections. Top-level definitions
have contract and purpose comments; structure fields are documented immediately
after their definitions. Public facades use explicit exports, and broad external
imports are narrowed where only a few bindings are used.

`math/scribblings/math.scrbl` supplies defining reference entries for **272 public
bindings**, including constructors, predicates, accessors, parameters and macros.
`docs/public-api.json` records the inspected export/signature inventory.
`math/info.rkt` registers that manual without editing parent repository metadata.
The optional Rhombus example imports ordinary Racket values from the same API.

## Migrating source written for 0.1.1

Mathematical authoring remains:

```racket
(require animate/math)
```

Add the adapter module only where external work is performed:

```racket
(require animate/math
         animate/math/render)

(define lesson-scene (math-plan->scene! plan))
```

For backend queries:

```racket
(require animate/math
         animate/math/cas
         animate/math/cas/racket-cas
         animate/math/cas/calcura)

(define services
  (math-services #:local (racket-cas-service)
                 #:extended (calcura-service)))
(verify-derivation! solution #:services services)
```

An unconfigured Calcura service reports unavailable; it is not silently selected
as a working backend. Supply the module or query hook described in the reference
for a live integration.

| Previous binding | Binding in 0.2.0 | Module |
|---|---|---|
| `prepare-math-plan` | `prepare-math-plan!` | `animate/math/render` |
| `math-plan->scene` | `math-plan->scene!` | `animate/math/render` |
| `math->visual` | `math->visual!` | `animate/math/render` |
| `math-plan->pict` | `math-plan->pict!` | `animate/math/render` |
| `cas-query` | `cas-query!` | `animate/math/cas` |
| `cas-calculate` | `cas-calculate!` | `animate/math/cas` |
| `verify-proposition` | `verify-proposition!` | `animate/math/cas` |
| `verify-derivation` | `verify-derivation!` | `animate/math/cas` |
| `call-with-math-services` | `call-with-math-services!` | `animate/math/cas` |

The obsolete names are not retained as aliases. The four bundled examples and
current user guide have been migrated. `docs/proposal-v0.1.md` is a historical
design document; it is not a current signature reference.

Raw `math-operation`, `edit`, `make-edit`, `finish-step`, and state/trace/plan
constructors are private. Replace direct use with built-in operations,
`make-math-rule`/`define-math-rule`, or the documented evidence/prover protocol.
Private modules remain implementation details, not a compatibility API.

## Regression evidence

The mandatory suite passes **1,317 checks**, including the original **1,243**
and **74** added assertions. All four example `--steps` outputs have been compared
with 0.1.1; their mathematical checkpoints and notation are identical. The intended
duration change is excluded from that textual comparison.

The separate source audit passes **927 checks** covering headers, contract
comments, immediate structure-field documentation, explicit facade exports,
pure dependency closure, constructor hiding and defining-reference coverage.
This audit checks specified source patterns; it is not a complete semantic style
checker and does not substitute for building Scribble.

Real `latex`/`dvipng` regression still produces **59 byte-identical marked/unmarked
PNG pairs** from 118 pages. This confirms unchanged TeX layout for the example
corpus in the test environment, not an executed dvisvgm/native-renderer round trip.

## Remaining integration boundaries

Actual animate rendering, the dvisvgm extraction round trip, live CAS providers,
parallel native PNG/MP4 output, the Scribble build and the Rhombus example were
not executed in this delivery environment. Those limitations are recorded in
`validation.md`. The actual native probe runner is included and still uses the
real checkout rather than the contract test model.

The algebraic scope is unchanged: real scalars, explicit derivations and
conservative evidence. Target rewrites can remain visually coarse; merge traces
do not gain a dedicated many-to-one path morph from this style revision. This
revision does not add an automatic tutor, complex solution branches or a new GUI.
