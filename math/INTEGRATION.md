# Integration contract — 0.5.0

This delivery replaces only `<animate repository>/math/`. Its baseline is Animate
commit `525253b2c8d6aa47bf7a5ddad1c51f82d322ccb0`, including the completed shared
process renderer. No parent repository changes are required by this archive.

## Mathematical model

`animate/math` remains pure and native-independent. `private/steps.rkt` describes
unapplied recipes. `private/derivation.rkt` builds an ordered move forest alongside
the existing flat primitive `rewrite-step?` list.

A leaf's `rewrite-step-name`, mathematical revision, state, occurrence IDs,
conditions, and trace are unchanged when it is wrapped in a move. A composite
stores its path, exact before/after states, and children; it is not another
primitive rewrite. Public APIs expose predicates/accessors, not raw constructors.

The schedule uses canonical derivation-relative leaf keys: a symbol for a flat
root leaf and a symbol list for a nested leaf. Native step compilation resolves
that exact key within its segment. No phase is synthesized for the composite
itself, and no native row/timing behavior is inferred from a string label.

The shipped four examples use top-level move groups matching their original
explicit partitions. Their elementary states, phase timings, and native request
sequences are preserved.

## Preparation and worker reconstruction

`animate/math/render` owns explicit preparation and scene construction. The
portable payload is `animate-math-prepared-plan-v2`, whose plan identity includes
move-tree structure, elementary addresses, case paths, schedule, and the existing
prepared layout data. A worker enumerates its own mathematical states and rebinds
layouts by stable keys rather than parent pointer identity. A v1 payload is
rejected, not silently interpreted as v2.

Formula measurement, global fit, row geometry, and explanation-layout preparation
remain parent work. The existing SVG glyph-definition canonicalizer and staged
content-addressed assets are retained. Workers consume the completed preparation
and never call `prepare-math-plan!` or the typesetter.

## Lazy example adapters

The four example modules retain explicit `math-render-preparer` and
`math-render-builder` exports. The signatures match the actual generic source
loader:

```text
preparer: context options -> source-preparation
builder:  context options payload -> scene
```

`examples/private/library-example.rkt` gives fixed-arity wrappers that load
`library-example-runtime.rkt` only when invoked. `examples/private/run.rkt`
performs inspection locally and loads `project-render.rkt` only for rendering.
The runtime helper explicitly declares its complete discoverable import closure
as preparation dependencies through the existing generic input-manifest facility.
This avoids losing input-integrity coverage behind the lazy boundary.

There is no second source loader, process supervisor, scheduler, renderer,
serialization service, or mutable native registry. The existing generic project
executor still chooses local versus subprocess work, handles caches and leases,
and writes frames. Parent-side MP4 assembly remains unchanged.

## Inspection and APIs

`--tree`, `--steps`, and `--list-cases` do not invoke the rendering adapter, create
workers, or generate assets. New move/leaf addresses are printed with slashes for
readability; the actual API address is a list of symbols.

`derive/proc` and `steps/proc` accept `(cons name operation-or-recipe)` entries.
Recipes are not accepted by the elementary `apply-math-operation` interface or
implicitly lifted by `each-branch`. Branchwise recipes explicitly wrap their
primitive operations in `each-branch`.

Use `derivation-node-at` to inspect either a move or leaf. Use `derivation-step`
for an elementary rewrite and `after` for either kind's final state. Conditions,
verification status, and relationship summaries remain separate.

## Validation boundaries

`run-tests.rkt` checks mathematics, lineage, group/address behavior, the four
original flat declarations, portable reconstruction, and synthetic native
requests. `run-style-checks.rkt` audits dependency boundaries and defining public
reference coverage. `run-process-contracts.rkt` moves prepared data between
independent real Racket processes using synthetic native geometry.

These are not substitutes for actual native rendering. On a configured checkout:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" math/run-probes.rkt --dark --compare-flat math-output/moves-v0.4/probes
```

The optional `--compare-flat` mode typesets the frozen flat lesson declarations
and compares their actual native pixels at the same checkpoint/intermediate times.
The standard dense probe manifest and random-access checks are retained.

See `docs/validation.md` for executed results, not merely intended test coverage.
External TeX/CAS/native callbacks retain their existing trust boundary; manifests
are not a universal sandbox or hermetic-execution guarantee.

## Gallery integration

The concept gallery is an example collection under `examples/gallery/`, with one
pure catalogue and five chapter modules. No gallery records enter the pure algebra
facade. The existing math compiler now has a private `append-prepared-math-plan!`
helper: it appends a replay to an ordinary scene and returns the visual/scalar IDs
the gallery must remove. Its public single-plan wrapper retains the original
behavior and defaults.

The gallery parent callback prepares each selected replay once. Bounded, canonical
per-view `.gallery.rktd` files contain existing v2 portable math payloads; they and
all SVGs are generic verified preparation artifacts. Worker callbacks consume
those files, never call the typesetter, and create no extra process pool. Both
lazy gallery and native renderer import closures are explicitly declared as local
input dependencies.

See `docs/gallery.md` for selection, native probes, frame/cache accounting, and
review output. The gallery has no new public `animate/math` or `animate/math/render`
bindings. Its example facade exports its own explicit preparer/builder callbacks.
