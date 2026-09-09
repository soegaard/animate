# Effects and composition semantics

This note records the semantics used by the corrected animation-composition
API.  It is intentionally implementation-independent: renderers and project
workers may compile the same request tree differently, but must preserve these
observable rules.

## Time and local starts

An authored request has a time relative to its enclosing composition.  A child
is compiled against the immutable scene state at that child's local start, not
against the scene state at authoring time and not against the order in which
frames happen to be sampled.  A succession applies each child's exact endpoint
before compiling the following child.  Parallel children share their common
local-start state.  Samples at arbitrary times are pure functions of the scene
and requested time.

## Target order and mapped composition

`target-sequence?` values are immutable queries.  A mapped composition resolves
one query exactly once at its local start and snapshots the resulting target
references.  Membership never changes later within that mapped operation.

There are three distinct orders:

- source order is the query's deterministic resolution order;
- scheduled order is the result of the explicit order policy;
- visual order is renderer/layout specific and is never inferred by an ordinary
  target query.

`target-ref` records a stable path, source index, scheduled index after ordering,
the resolved value when safe, and query-origin metadata.  Templates receive one
`target-ref`; factories are not selected by arity.  `stagger-map` is semantic and
deferred only for `target-sequence?` input.  `eager-stagger-map` and
`stagger-requests` retain explicit eager collection expansion.

Order and delay are separate policies. `#:order` assigns scheduled indexes;
`index-delay` uses those indexes for the historical lagged timing. Constant
delay creates an explicit group lead-in. Distance, radial, and wave plans use
frozen world-space 2D positions from the mapped node's local start and reject
targets without that capability rather than inventing an approximate layout.

Procedure-backed templates are intentionally nonserializable.  A serializable
project representation must use a transparent named template with a separately
registered implementation; arbitrary closures must never be advertised as
serializable.

## Structural lifecycle

Before a request is compiled, its structural preconditions are checked against
the local-start presence state.  Introductions require absence and end present;
removals require presence and end absent; ordinary transforms require and retain
presence.  Temporary helpers exist only in an open interval and must be absent
at exact endpoints.  A succession propagates structural endpoints to following
children; overlapping incompatible structural writes are conflicts.

`repeat-animation` and `ping-pong` validate every iteration/pair through the
same local-start lifecycle rules.  A repeated bare `enter`, for example, fails
at the second iteration before any frame is emitted.  Diagnostics identify the
high-level operation, iteration, target/path when available, and the underlying
lifecycle failure.

Lifecycle summaries use immutable effects with a target, required presence,
endpoint result, temporary-helper flag, and exact-endpoint flag. They are used
in repeated-cycle diagnostics so a structural failure identifies the lifecycle
contract that was being validated.

## Exact endpoints and helper identities

At an effect's exact end the authored target Visual is restored exactly, or is
absent for a removal.  Transient overlays do not survive the endpoint.

An explicitly supplied helper `#:id` is authoritative.  Otherwise helper IDs
are derived solely from effect kind, target identity/path, immutable expansion
origin, and local helper index.  The origin contains the clip index, request
path, source/scheduled indices, local index, and kind.  It is independent of
frame sampling and unrelated request construction, and is exposed in inspection
and failure data where available.

## Deterministic randomness

Seeded effects use the versioned keyed random plan.  A random draw is addressed
by plan version, seed, effect kind, item index, and a named property key (for
example `x-position`, `rotation`, or `shuffle-swap`).  It consumes no global
random state, and construction and sampling order cannot change a plan.

The current default plan version is part of a request's observable plan data.
Changing it is a deliberate compatibility event; existing version values retain
their published mixing semantics.

## Text and renderer capability policy

Text reveal is source-ordered for the currently supported Pict path.  The
whitespace/non-whitespace segmentation unit is named `'run`; `'word` remains
reserved for a future Unicode word-boundary implementation.

The Pict backend retains a final whole layout for all text, but only advertises
exact fragment masks for a conservative unwrapped single-run LTR subset.  It
does not approximate ligatures, complex scripts, bidirectional text, rich spans,
or wrapped text by shaping prefixes again.  Unsupported interior text frames
fail with capability diagnostics; exact initial and final states remain valid.
Future shaped backends must obtain their clusters from the same final shaping run
that they draw, and must state whether reveal order is logical source order or
visual order.

## Reveal geometry

Explicit reveal-front vectors must be finite, and linear directions must be
nonzero.  Radial fronts are semantic circles; a polygonal backend fallback
chooses tessellation from projected size and a pixel-error bound.  The full
endpoint covers the expanded layout bounds, including every corner.
