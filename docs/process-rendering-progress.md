# Process rendering: PR-0 through PR-H progress

**Status:** PR-H complete; work stopped after the PR-H completion gate.

## Checkout and instructions

- Checkout: `/Users/soegaard/Dropbox/GitHub/animate`, `main` at
  `4b7573eb418d9d824c66c753e98a8b8961c28ad5` when reconnaissance began.
- Runtime selected for all Racket commands:
  `/Applications/Racket v9.3.0.2/bin/racket` (CS v9.3.0.2-2026-08-16), with
  the matching `raco` and `scribble` executables.
- Read `plans/animate-process-rendering-codex-plan.md` completely and the
  root `HOUSE_STYLE.md` completely.  No applicable `AGENTS.md` was present
  from the repository root through its filesystem ancestors.
- The checkout was already dirty: notably
  `scribblings/concepts/typography-and-text-styles.scrbl` and many untracked
  archives, outputs, and plans.  Those unrelated changes were not edited,
  removed, staged, or reset.

## PR-0 reconnaissance and baseline

### Existing control points

- `project.rkt` owns source declarations, planning, preparation, and render
  specifications.  `private/project-execution.rkt` invokes
  `render-frame-indices/report!` and passes `#:workers` to the existing
  in-process PNG renderer.
- `private/png-renderer.rkt` samples source indices and coordinates its local
  thread workers and writer.
- Preview already has a module-subprocess seam in
  `private/preview-worker-protocol.rkt`, `private/preview-worker-process.rkt`,
  and `private/preview-worker-main.rkt`.
- Geometry has an independent process sharder in
  `geometry/examples/private/run-example.rkt` (`run-process-sharded-render!`
  and `--worker-shard`); its public reusable rendering layer is
  `geometry/render.rkt`.
- Math example runners construct an in-memory scene and currently pass their
  worker setting to the native renderer; their preparation includes typeset
  and prepare work.

### Baseline commands and observations

All trial output was written under ignored
`logs/process-rendering-pr0/`; no user-owned output/cache directory was
cleaned.

- `raco make main.rkt project.rkt render.rkt math/main.rkt math/render.rkt
  math/cas.rkt` succeeded before implementation.
- A small direct native render (`wait` + `one` + `circle`, 2 fps) through
  `render-frames!` completed in 0.86 s and emitted two PNGs.  Both hashes were
  `64a3b0bd628cdb12d34efd40b9defc2ac0cdf0eac766f46925102584bfe2c309`.
- `math/examples/linear-concrete.rkt --fps 1 --width 160 --height 90` emitted
  11 frames with both `--workers 1` and `--workers 10`; corresponding PNG
  hashes matched.  Measured wall time was 4.69 s and 4.74 s respectively.
- `math/examples/quadratic-general.rkt --case quadratic/two-real-roots
  --fps 1 --workers 1 --width 160 --height 90` emitted 21 frames in 11.38 s.
- `geometry/examples/equilateral-triangle.rkt --frames --fps 1 --workers 1
  --width 160 --height 90` emitted 22 frames (runner-reported render time:
  138 ms; wall time: 2.42 s).  A `--fps 10 --workers 2` trial emitted 211
  frames.  Sandbox policy denied process-list inspection, so that latter run
  is evidence of the established geometry command rather than a verified PID
  count.
- The first math render needed permission to write its normal user cache under
  `~/Library/Preferences/animate-math/svg-v1`; it was rerun with that limited
  approval.  No machine configuration was changed.

The PR-0 gate is met: the source/render call paths and existing worker seams
are identified, native outputs were captured non-destructively, and baseline
limitations are recorded below.

## PR-A decisions and implementation

### Contracts frozen in this stage

- A restartable source is declared with
  `module-builder-source module-path binding #:options #:prepare #:seed`.
  The module is not loaded during planning.
- A preparer is optional and is invoked with exactly two arguments:
  `source-build-context` and the immutable builder-options snapshot.  The
  builder is invoked with exactly three: context, preparation, and options.
  Each must return exactly one value.  Builder results must be a supported
  scene/timeline/program value; arbitrary closures and serialized scenes are
  not accepted.
- `source-build-context` contains a frozen semantic construction snapshot:
  source identity, seed, appearance, normalized assets, and a base
  fingerprint.  `source-preparation` keeps a validated immutable payload and
  declared artifacts/dependencies/reuse/diagnostics for the later stages.
- The transferable data model permits finite scalar data and immutable
  snapshots of pairs, vectors, and hashes.  It has depth/node/string-size
  limits and rejects cycles, procedures, ports, bitmaps/native values,
  non-finite reals, and other opaque runtime state.
- `render-spec` gains `#:worker-mode`, one of `'auto`, `'in-process`, or
  `'subprocess`.  Its copy helpers retain the selected mode.
- `resolve-render-worker-policy` is pure and executes during planning.  A
  module value/builder source resolves `'auto` with more than one worker to
  future `'subprocess`; direct values remain local for automatic one-worker
  work and reject automatic multi-worker work.  Non-software and
  non-transferable renderer configurations are rejected before any output
  mutation when subprocess operation would be required.
- Builder sources are restartable declarations, but remain `memory-only` for
  cacheability in PR-A.  The existing frame-cache key has no preparation/input
  manifest yet, so claiming persistent frame reuse would be false.  PR-E is
  responsible for that manifest codec.

No callback is guessed, wrapped for another arity, or automatically
serialized.  These limits are deliberate and are surfaced as contract errors.

### Changed files

- `private/render-source-model.rkt` — pure source declaration, transfer,
  preparation, context, identity, and policy data model.
- `private/render-source-loader.rkt` — effectful module load plus exact
  preparer/builder invocation and result validation.
- `project.rkt` — public APIs, normalized builder source planning,
  preparation diagnostics, worker-mode/policy model, and inspection data.
- `tests/fixtures/project-builder-source.rkt` — controlled builder/preparer
  fixture and invalid-export variants.
- `tests/process-render-source-model-test.rkt` — source purity, exact arity,
  validation, identity, policy, and helper-retention coverage.
- `tests/documented-bindings-exist-test.rkt` — public binding coverage.
- `scribblings/reference/project.scrbl` and `README.md` — public contract and
  PR-A scope documentation.
- `docs/process-rendering-progress.md` — this record.

## Verification performed

All commands below used the selected Racket 9.3.0.2 runtime.

| Command | Actual result |
| --- | --- |
| `raco make main.rkt project.rkt private/render-source-model.rkt private/render-source-loader.rkt tests/process-render-source-model-test.rkt tests/documented-bindings-exist-test.rkt` | Passed. |
| `raco test tests/process-render-source-model-test.rkt tests/documented-bindings-exist-test.rkt tests/scene-eo-project-test.rkt tests/scene-eo-execution-test.rkt tests/scene-ep-worker-process-test.rkt` | **1,054 tests passed.** This exercises the new PR-A contracts and the old project/preview execution paths. |
| `racket geometry/run-tests.rkt` | **524 tests passed.** |
| `racket math/run-tests.rkt` | **1,805 checks passed; 0 failed.** |
| `racket math/run-style-checks.rkt` | **986 checks passed; 0 failed.** |
| `scribble --htmls --dest /private/tmp/animate-process-rendering-docs scribblings/animate.scrbl` | Succeeded and wrote the documentation.  Existing/general unresolved cross-reference warnings were emitted. |
| `raco make tests/*.rkt examples/*.rkt` | Passed; used only to refresh dependents after the intentional `project.rkt` public-struct change. |
| `raco test tests` (clean pass after that recompile) | **11 / 13,428 failures.** No stale-linklet errors remained.  Reported failures are unrelated color-rendering and pict-identity assertions, including `scene-at-render-test.rkt`, `scene-au-render-test.rkt`, `scene-cr-test.rkt`, and `scene-{j,k,m,n}-render-test.rkt`. |

The first full-suite attempt, made before recompiling every dependent, ended
with 20 / 13,381 failures and included `instantiate-linklet` stale-bytecode
errors.  Those errors disappeared after the documented `raco make` command;
they are not treated as source regressions.

## PR-A full-suite provenance comparison

The original PR-A report did not establish whether the 11 remaining assertions
also failed before PR-A. That gap is now closed.

- An isolated detached worktree was created at pre-PR-A commit
  `4b7573eb418d9d824c66c753e98a8b8961c28ad5` under
  `/private/tmp/animate-process-rendering-pr-a-baseline-4b7573e/animate`.
- Both comparisons used `/Applications/Racket v9.3.0.2/bin/racket` and its
  matching `raco`, the same installed user collects, and an explicit
  `PLTCOLLECTS`. The baseline root was
  `/private/tmp/animate-process-rendering-pr-a-baseline-4b7573e`; the current
  root was `/Users/soegaard/Dropbox/GitHub`. In each run,
  `(collection-file-path "main.rkt" "animate")` printed the corresponding
  source tree's `animate/main.rkt`. This prevents a package link from silently
  making both runs execute the modified checkout.
- Before each full run, `raco make tests/*.rkt examples/*.rkt` completed with
  that explicit collection root. The isolated baseline then ran the complete
  `raco test tests` order and reported **11 / 13,342** failures. The prior
  PR-A tree reported **11 / 13,428**; the difference is its added checks, not
  failures. The final PR-B full-order rerun below reports **11 / 13,468**.

Each assertion below failed in the isolated pre-PR-A full suite, in the
PR-A full suite, and again after PR-B. The full-order comparisons include all
preceding tests, so no suite-order-dependent difference was observed.

| Test assertion | Expected | Actual | Pre-PR-A? |
| --- | --- | --- | --- |
| `scene-at-render-test.rkt:58:2` (`check-equal?`) | `(rgba-color 255/2 0 255/2 1)` | `(rgba-color 187.51603067837462 0 187.51603067837462 1)` | Yes, unchanged |
| `scene-at-render-test.rkt:61:2` (`check-equal?`) | `(rgba-color 255/2 215/2 0 1)` | `(rgba-color 187.51603067837462 157.54988914084095 0 1)` | Yes, unchanged |
| `scene-au-render-test.rkt:66:2` (`check-equal?`) | `(rgba-color 255/2 0 255/2 1)` | `(rgba-color 187.51603067837462 0 187.51603067837462 1)` | Yes, unchanged |
| `scene-au-render-test.rkt:68:2` (`check-equal?`) | `(rgba-color 255/2 215/2 0 1)` | `(rgba-color 187.51603067837462 157.54988914084095 0 1)` | Yes, unchanged |
| `scene-bc-test.rkt:35:2` (`check-equal?`) | `(rgba-color 255/2 0 255/2 1)` | `(rgba-color 187.51603067837462 0 187.51603067837462 1)` | Yes, unchanged |
| `scene-bg-test.rkt:57:2` (`check-equal?`) | `(rgba-color 255/2 0 64 1)` | `(rgba-color 187.51603067837462 0 92.37353129670535 1)` | Yes, unchanged |
| `scene-cr-test.rkt:90:2` (`check-equal?`) | `(rgba-color 255/2 215/2 255/2 1)` | `(rgba-color 187.51603067837462 157.54988914084095 187.51603067837462 1)` | Yes, unchanged |
| `scene-j-render-test.rkt:172:2` (`check-eq?`) | `#<pict>` | `#<pict>` | Yes, unchanged identity failure |
| `scene-k-render-test.rkt:288:2` (`check-eq?`) | `#<pict>` | `#<pict>` | Yes, unchanged identity failure |
| `scene-m-render-test.rkt:336:2` (`check-eq?`) | `#<pict>` | `#<pict>` | Yes, unchanged identity failure |
| `scene-n-render-test.rkt:191:2` (`check-eq?`) | `#<pict>` | `#<pict>` | Yes, unchanged identity failure |

The baseline worktree necessarily contains clean committed source only: it
cannot reproduce the user's unrelated dirty files. Those files were preserved
in the working checkout and not copied into the baseline. This is the only
material limitation; the executable, installed dependencies, test order, and
collection resolution were deliberately held fixed.

## PR-B decisions and implementation

### Shared supervisor and protocol

- `private/render-worker-protocol.rkt` owns one versioned protocol (version
  1), immutable prefab records, identity fields (session, source fingerprint,
  generation, and request), an eight-byte lowercase hexadecimal frame header,
  and a 32 MiB message cap. Its reader disables reader/lang/compiled/graph
  extensions, accepts exactly one datum, and validates the declared grammar
  before either side acts on it. A bounded protocol-data predicate accepts
  complete current theme datums while still limiting depth, nodes, and scalar
  sizes.
- `private/render-worker-process.rkt` owns the child process, its process
  group and custodian, all three ports, both reader threads, a bounded 128-event
  queue, and a 64 KiB retained log suffix. Protocol output and stderr are
  drained continuously and independently. Startup and request waits use
  monotonic elapsed-time deadlines; malformed transport, EOF, write failure,
  timeout, cancellation, crash, shutdown, and restart each have an explicit
  outcome.
- Startup checks the child's reported `animate/main.rkt` against the parent's
  resolved collection path. Every received response is matched against current
  session/source/generation/request identity; stale replies are discarded and
  logged. Restart creates a fresh source module instance with a new generation.
- Source stdout and stderr are parameterized to the child stderr during both
  source loading and render sampling, so they cannot corrupt protocol stdout.
  Normal shutdown sends the protocol stop request, then reaps the still-live
  process group before observing completion; this preserves the local
  descendant-kill opportunity on macOS/Unix.

### Worker and preview integration

- `private/render-worker-main.rkt` is the explicitly launched executable entry
  point. Requiring it is inert; only its `module+ main` starts the loop. It
  handles module-value sources and reconstructs module-builder sources through
  PR-A's `make-module-builder-source`, `source-build-context`, and
  `load-module-builder-source!` contracts—there is no second loader.
- `private/preview-worker-process.rkt` is now a compatibility facade over the
  shared supervisor. It retains preview PNG-byte transport, camera and
  appearance snapshots, preview timeout/restart outcomes, and the existing
  serialized protected parent-side `read-bitmap` decode.
- `private/preview-worker-main.rkt` is an inert legacy entry-point facade over
  the shared loop. The older preview-only protocol module remains available to
  existing public re-exports but is no longer used to launch child preview
  processes.
- Mathematical scene construction, sampling, geometry, and final-render/batch
  movie paths were not changed.

### PR-B changed files

- `private/render-source-loader.rkt` — added the PR-A-contract module-value
  load and source-to-scene normalization helpers used by the shared worker.
- `private/render-worker-protocol.rkt` — new framed, bounded, validated worker
  protocol and source descriptors.
- `private/render-worker-process.rkt` — new owned process supervisor,
  deadlines, transport drains, lifecycle, and test-only raw-frame injector.
- `private/render-worker-main.rkt` — new inert-on-require worker executable.
- `private/preview-worker-process.rkt` and `private/preview-worker-main.rkt`
  — preview compatibility wrappers over the shared worker.
- `tests/render-worker-process-test.rkt` — real-process lifecycle, protocol,
  source, and cleanup coverage.
- `docs/process-rendering-progress.md` — this evidence record.

## PR-B verification performed

All commands used `/Applications/Racket v9.3.0.2/bin/racket` and matching
`raco`. The complete current collection root was explicitly set for the final
recompile and full suite.

| Command | Actual result |
| --- | --- |
| `raco make private/render-source-loader.rkt private/render-worker-protocol.rkt private/render-worker-main.rkt private/render-worker-process.rkt private/preview-worker-main.rkt private/preview-worker-process.rkt preview.rkt tests/render-worker-process-test.rkt` | Passed. |
| `raco test tests/render-worker-process-test.rkt` | **40 tests passed.** Real child process coverage includes inert require, malformed/oversized/wrong-version frames, invalid executable/export, timeout, cancellation, crash, restart/generation, stale identity rejection, PR-A builder loading, a 70 KiB noisy source whose retained log is capped at 64 KiB, space/non-ASCII paths, and cleanup. |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/documented-bindings-exist-test.rkt tests/scene-eo-project-test.rkt tests/scene-eo-execution-test.rkt tests/scene-ep-worker-process-test.rkt tests/typography-preview-worker-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt` | **1,107 tests passed.** |
| `racket geometry/run-tests.rkt` | Completed successfully (exit 0) when allowed to outlive the sandbox's 30-second command window. |
| `racket math/run-tests.rkt` | **1,805 checks passed; 0 failed.** |
| `racket math/run-style-checks.rkt` | **986 checks passed; 0 failed.** |
| `PLTCOLLECTS=/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket\ v9.3.0.2/collects raco make tests/*.rkt examples/*.rkt` | Passed before the full-suite rerun; no stale-bytecode failures. |
| Same `PLTCOLLECTS`, `raco test tests` in full order | **11 / 13,468 failures**: exactly the established 11 assertions in the provenance table, with the same values. |

### Process identity and cleanup evidence

- The real-process test recorded a positive PID returned by the supervisor,
  rendered a module under a path containing both spaces and `Ω`, captured its
  stdout and stderr in the bounded log rather than protocol output, and checked
  that the parent-visible input/output/error ports and both reader threads were
  closed/dead after `render-worker-stop!`.
- On this local macOS run, that source created one test-owned `racket -e
  "(sleep 30)"` descendant. `kill -0` observed it alive before stop and absent
  within the test's bounded two-second wait after group shutdown. This is
  direct evidence for that owned descendant on this host only.
- A system-wide process count was not verified: local process enumeration is
  unavailable here (`pgrep` reports that the `sysmond` service is unavailable).
  No Windows or post-crash-descendant guarantee is claimed; the evidence does
  not establish cleanup of arbitrary descendants after a worker has already
  exited before the owner can kill its group.

## Remaining risks and intentionally deferred work

- The full suite still has the 11 proven pre-existing color-rendering and
  pict-identity failures. They are unchanged through PR-B and are not fixed
  here because PR-B does not alter that rendering behavior.
- The supervisor currently serves preview frames only. PR-C is still required
  before final-render/batch movie export uses it.
- There is deliberately no persistent preparation artifact manifest or
  builder-frame cache key yet (PR-E), and no generic geometry/math migration
  (PR-F/PR-G).
- System-wide process inspection remains unavailable, and descendant evidence
  is local macOS evidence rather than a cross-platform guarantee.
- The supported transfer subset is intentionally narrow.  Authors with
  opaque runtime state, arbitrary callbacks, or non-software renderer setup
  must use an explicitly supported source form or wait for a later-stage
  contract; the implementation will not silently serialize it.

## PR-B completion gate

Preview wrappers use the shared supervisor; its entry point is inert unless
explicitly launched; real-child lifecycle, protocol, source, and cleanup tests
are green; focused preview/project and geometry/math regressions are green;
and the complete-suite failure set is proven unchanged from pre-PR-A source.
The work stops here, before PR-C.

## PR-C decisions and implementation

### Scope and contracts

- PR-C adds only the minimal real-child final-PNG execution seam.  It does not
  switch `project.rkt`, the native renderer, or movie assembly to this seam;
  that integration remains PR-D work.  Mathematical scene construction and
  frame sampling are unchanged.
- `private/render-frame-job.rkt` is a pure, immutable job-description module.
  A job freezes session/source/generation/request identities, source and local
  frame indices, FPS, camera, supersampling, theme, typography, the supported
  renderer selector, preparation data, and a canonical local `frame-NNNNNN.png`
  output name.  The only currently accepted renderer is explicit `'default`
  with empty renderer inputs.  `prepared-inputs` is data-only transport for a
  later preparation-artifact stage; PR-C validates and transfers it but does
  not consume it.
- The shared protocol is now version 2.  It has bounded, strictly validated
  `render-final-frame` request and metadata-only completion messages.  Each
  completion must match session, source fingerprint, generation, request ID,
  source frame, local output frame, and canonical filename.  Version-1 frames
  are rejected rather than silently interpreted.
- The PR-B worker is still loaded only through the PR-A source-loader and its
  documented preparer/builder contracts.  A source is initialized once per
  worker, not once per frame.  The worker module remains inert on `require`;
  its loop starts only in `module+ main`.
- The parent-owned `render-final-frame-jobs!` scheduler uses up to the useful
  number of persistent workers and gives each worker at most one outstanding
  request.  It observes the PR-B elapsed-time startup and request deadlines,
  propagates cancellation, stops all owned workers on failure, and publishes
  nothing unless the full frame set completed.
- A worker receives a parent-owned staging root during source loading.  It can
  write only the canonical basename below that root, first to a private
  temporary sibling and then by rename.  The parent verifies existence, byte
  count, PNG signature/IHDR dimensions, and completion metadata without
  decoding production PNG bytes; it moves the complete staging set to final
  names in local-slot order only after every request succeeds.  Existing files
  *and directories* are rejected as occupied output slots.
- Source stdout/stderr remain separated from framed protocol stdout and are
  continuously drained by PR-B's bounded logs.  PR-C therefore adds no second
  source loader, no extra protocol stream, no unbounded image-byte payload,
  and no parent-side PNG decode on the production path.

### PR-C changed files

- `private/render-frame-job.rkt` — pure, bounded immutable final-frame job and
  camera/transfer validation.
- `private/process-frame-executor.rkt` — owned staging, bounded dynamic
  scheduler, metadata/PNG-header verification, atomic publication, report,
  failure, cancellation, and cleanup handling.
- `private/render-worker-protocol.rkt` — protocol v2 final-frame request and
  completion grammar.
- `private/render-worker-process.rkt` — shared-supervisor final-frame request
  wrapper and worker staging-root loading.
- `private/render-worker-main.rkt` — final request handling and atomic worker
  PNG publication, reusing the existing frame renderer.
- `tests/fixtures/final-render-worker-scene.rkt` — deterministic moving scene
  plus a PR-A-contract builder/preparer fixture.
- `tests/process-frame-executor-test.rkt` — real-child final rendering,
  scheduling, identity, failure, cancellation, and cleanup coverage.
- `tests/render-worker-process-test.rkt` — updated wrong-version expectation
  for protocol v2.
- `docs/process-rendering-progress.md` — this PR-C evidence record.

## PR-C verification performed

Every Racket command below used
`/Applications/Racket v9.3.0.2/bin/racket` and matching `raco`, with:

```
PLTCOLLECTS=/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket\ v9.3.0.2/collects
```

| Command | Actual result |
| --- | --- |
| `raco make private/process-frame-executor.rkt tests/process-frame-executor-test.rkt` | Passed after the occupied-directory regression was added. |
| `raco test tests/process-frame-executor-test.rkt tests/render-worker-process-test.rkt` | **81 tests passed.** This is 41 final-executor and 40 shared-worker tests. |
| `raco make tests/*.rkt examples/*.rkt` | Passed before the final suite; this recompiles dependents and excludes stale-bytecode attribution. |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/documented-bindings-exist-test.rkt tests/scene-eo-project-test.rkt tests/scene-eo-execution-test.rkt tests/scene-ep-worker-process-test.rkt tests/typography-preview-worker-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt` | **1,148 tests passed.** The expected ffmpeg diagnostics were emitted by existing project tests; exit status was 0. |
| `racket geometry/run-tests.rkt` | **524 tests passed.** |
| `racket math/run-tests.rkt` | **1,805 checks passed; 0 failed.** |
| `racket math/run-style-checks.rkt` | **986 checks passed; 0 failed.** |
| `raco test tests` | **11 / 13,509 test failures.** The complete failure set and all reported expected/actual values are exactly the proven pre-PR-A baseline table above; no PR-C failure was added. |
| `racket -e '(displayln (collection-file-path "main.rkt" "animate"))'` | Printed `/Users/soegaard/Dropbox/GitHub/animate/main.rkt`; the intended checkout collection, not an installed package link, was resolved. |
| `git diff --check` | Passed for tracked changes (run after the final documentation update). |

The real-process test exercises source indices 3, 7, and 11 through one and
two actual children, compares decoded test-only ARGB pixels against the
existing in-process frame renderer, and checks the canonical local output map
0, 1, and 2.  It also covers a space/non-ASCII output path (`two workers Ω`),
workers exceeding job count, zero jobs, light/dark themes, alternate
typography, a static 71x43 camera with 2x supersampling (142x86 output),
PR-A builder/preparer initialization once per worker, invalid export,
malformed final message, identity mismatch, timeout, cancellation, worker
crash, worker-side publication collision, and staging cleanup.  Production
code does not use that test-only PNG decode.

### Process identity and cleanup evidence

- An explicit two-worker real-child probe under a temporary output root named
  `two workers Ω` reported worker PIDs **39050** and **39053**.  Its closed
  resource statuses recorded `open? #f`, input/output/error ports closed, and
  both reader threads dead for both PIDs.  The probe deleted its owned
  temporary root after reporting.
- The corresponding test suite checks two distinct positive supervisor PIDs,
  `workers-completing = 2`, no remaining `.animate-process-frame-*` staging
  directory after publication, no public PNG after timeout/cancellation/crash,
  and no `.animate-final-render-*` worker temporary after a publication
  collision.
- This is parent-visible, owned-process evidence only.  System-wide process
  enumeration remains unavailable on this host (`pgrep` cannot reach
  `sysmond`), so no global process count is claimed.  The PR-B macOS descendant
  test remains the available direct descendant-cleanup evidence; PR-C does not
  claim a platform-independent descendant guarantee after an already-crashed
  worker exits.

## Remaining risks and intentionally deferred work after PR-C

- The 11 color-rendering and pict-identity full-suite failures are proven
  pre-existing and unchanged; they remain outside PR-C scope.
- `render-final-frame-jobs!` is deliberately private and not connected to
  project rendering or batch movie export.  PR-D must define that integration
  and its user-facing progress/reporting surface.
- Only static cameras and the default software renderer are accepted.  Custom
  renderer inputs, camera animation, and actual use of prepared artifacts are
  deferred; the transported preparation field is not a persistent manifest.
- Atomic rename relies on the owned staging directory being created beneath
  the output parent, which this executor does.  Cross-filesystem publication,
  arbitrary child-side output destinations, and post-crash orphan guarantees
  are intentionally not claimed.
- No PR-D through PR-H work, geometry/math migration, or persistent
  preparation-artifact caching was begun.

## PR-C completion gate

The shared PR-B supervisor now executes a bounded, identity-checked,
real-subprocess final-PNG frame set while preserving source semantics and
publishing only a verified complete result.  Real-child lifecycle and cleanup
coverage is green, focused preview/project tests and geometry/math regressions
are green, and a freshly recompiled complete suite has exactly the established
11 baseline failures.  The work stops here, before PR-D.

## PR-D decisions and implementation

### Project execution boundary

- private/project-execution.rkt now chooses the renderer from the
  prepared-project-worker-policy decided by plan-project; it does not
  reimplement worker-policy classification. Direct sources and explicitly
  in-process requests retain the existing native render-frame-indices/report!
  path. Restartable projects selected for subprocess mode build PR-C jobs and
  call render-final-frame-jobs!.
- The subprocess adapter serializes only a normalized
  module-binding-source or module-builder-source, its documented
  source-build-context, a static effective camera, FPS, supersampling, and
  complete theme/typography datums. It transfers no parent Scene, bitmap,
  live renderer, or new source loader. Child module builders continue to run
  the existing PR-A load-module-builder-source! preparer/builder contract once
  per worker.
- Parent preparation remains necessary for ordinary project target resolution.
  PR-C's prepared-inputs field is intentionally sent as an empty immutable
  map: the worker has no consumer for a parent-prepared layout/artifact yet.
  A shared persistent preparation manifest or artifact handoff was not added;
  that is PR-E work.
- Subprocess preflight happens before make-directory*, cache-slot cleanup, or
  child launch. It rejects a custom renderer list, non-software backend,
  nonempty renderer options, unsupported camera datum, and a supplied
  prepared-label-layout3d. Those are explicit PR-C limitations, rather than
  silently changing output pixels.
- On a subprocess cache miss, only Animate's canonical numbered frame PNGs
  are removed, matching the native renderer's cleanup behavior. The existing
  module-binding cache key is unchanged; it still omits worker count and
  worker mode. A valid hit produces a normalized report with zero workers
  started and does not launch the executor. Module builders remain
  memory-only, unchanged from PR-A.

### Diagnostics and command interface

- project-frame-execution-diagnostics records resolved mode, requested
  capacity, started/completing worker counts, requested/rendered/reused
  frames, source-to-local output mapping, elapsed time, paths, and the
  native/subprocess-specific report. Its manifest-safe datum is written as
  frame-execution beside normal project report data. The native renderer has
  no per-worker completion identity, so that field is truthfully #f there;
  a cache hit uses zero for both process counts.
- preview-cli.rkt accepts --worker-mode auto|in-process|subprocess for project
  commands. It copies all other render-spec fields unchanged and includes
  normalized frame-execution data in render output. Plan remains the
  no-render/no-worker way to inspect the policy.
- No geometry or math command shape, mathematical construction, sampling
  algorithm, generic batch movie export, or PR-E preparation/cache behavior
  was changed.

### PR-D changed files

- private/project-execution.rkt — policy routing, PR-C job/source adapter,
  pre-output capability checks, normalized diagnostics, and manifest record.
- preview-cli.rkt — explicit worker-mode option and render diagnostics.
- tests/fixtures/project-subprocess-source.rkt — small restartable
  scene/timeline fixture.
- tests/project-subprocess-execution-test.rkt — normal-project
  real-process integration coverage.
- docs/process-rendering-progress.md — this PR-D record.

## PR-D verification performed

Every Racket command below used /Applications/Racket v9.3.0.2/bin/racket and
matching raco, with:

    PLTCOLLECTS=/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket\ v9.3.0.2/collects

| Command | Actual result |
| --- | --- |
| raco make private/project-execution.rkt preview-cli.rkt | Passed. |
| raco test tests/project-subprocess-execution-test.rkt | **41 tests passed.** Real subprocess projects covered auto/explicit policy, direct-source rejection/local mode, local/subprocess PNG equality, all/frame/range/section/block target maps, cache-hit zero workers, spaces/non-ASCII builder module path, PR-A preparer/builder calls in each child, early rejection without output mutation, child failure propagation/cleanup, and subprocess MP4 assembly. |
| racket preview-cli.rkt --worker-mode in-process plan examples/project-planning.rkt sample-project | Passed; the plan datum reported requested/resolved in-process policy without rendering or starting a worker. |
| Focused project/preview/worker suite listed below | Initial run reported one stale-linklet import mismatch in scene-eo-execution-test.rkt after the project-execution export change. It was not a source failure. |
| raco make tests/*.rkt examples/*.rkt | Passed; all dependents were recompiled before final attribution. |
| raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt tests/documented-bindings-exist-test.rkt tests/scene-eo-project-test.rkt tests/scene-eo-execution-test.rkt tests/scene-ep-worker-process-test.rkt tests/typography-preview-worker-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt | **1,189 tests passed.** Existing FFmpeg diagnostics were emitted; exit status was 0. |
| racket geometry/run-tests.rkt | Completed with exit status 0. Its runner emitted the individual test modules but no aggregate count in this run. |
| racket math/run-tests.rkt | **1,805 checks passed; 0 failed.** |
| racket math/run-style-checks.rkt | **986 checks passed; 0 failed.** |
| raco test tests | **11 / 13,550 failures.** They are exactly the established seven color assertions and four pict-identity assertions in the PR-A provenance table, with the same expected/actual values. No stale-bytecode or PR-D-specific failure appeared after the full recompile. |

### Process identity and cleanup evidence

- A fresh two-worker project probe rendered source frames 0–3 through actual
  workers **45502** and **45503**. The accepted assignment map records that
  PID 45503 completed local slots 0 and 2 while PID 45502 completed 1 and 3;
  the report recorded workers-started = 2, workers-completing = 2, and
  845.912 ms total elapsed time.
- After supervisor shutdown, both parent-observed resource statuses reported
  open? #f, all input/output/error ports closed, and both reader threads dead.
  A subsequent ps -p 45502,45503 -o pid=,command= produced no rows. The
  test-owned temporary project root was deleted after the observation.
- This confirms only the two owned children and their parent-visible
  resources. It does not establish a system-wide process count or arbitrary
  descendant cleanup after a crashed leader. The earlier PR-B descendant test
  remains the available direct macOS descendant evidence; pgrep/system-wide
  enumeration is still not used as a verification claim here.

## Remaining risks and intentionally deferred work after PR-D

- The 11 full-suite color/pict assertions are proven pre-existing and remain
  unchanged. They are outside PR-D rendering integration scope.
- Subprocess final rendering remains limited to restartable module sources,
  default software rendering, empty renderer options, a transferable static
  camera, and no prepared label layout. Unsupported requests fail early.
- Module-builder preparation is repeated in parent preparation and once in
  each worker; PR-D deliberately does not promise an interprocess preparation
  artifact cache, portability manifest, or cache identity for builders.
- Parent-visible child/port/thread cleanup is verified, but neither global
  process counts nor a platform-independent post-crash descendant guarantee
  is established.
- PR-E through PR-H, including persistent preparation manifests, batch movie
  export, geometry migration, and math migration, were not started.

## PR-D completion gate

Normal module-backed projects now use the selected local or subprocess
executor through public project APIs and the CLI. All target selectors use the
same prepared-project route; cache hits launch no frame workers; output
assembly remains unchanged; and reports expose the actual mode and frame map.
Real-child tests, focused project/preview tests, geometry/math regressions,
and a fully recompiled complete suite are recorded above. Work stops here,
before PR-E.

## PR-E decisions and implementation

### One parent preparation and verified reconstruction

- `prepare-project!` now records one parent-owned source preparation for a
  module builder and converts its documented PR-A payload, artifacts, frame
  reuse witness, and diagnostics into an immutable, versioned preparation
  manifest.  A child receives that manifest and reconstructs the existing
  `source-preparation` value before calling the existing PR-A source loader;
  it does not call the preparer again.  The normal loader remains the only
  source-loading implementation.
- A separate immutable render-input manifest captures the bounded canonical
  local module/import inputs, declared assets, and Racket runtime identity.
  Content size and SHA-1 are rechecked before launch, on worker readiness,
  before reuse/publication, and in the worker before source construction.
  Manifest construction rejects unsupported mutable/procedural payload data;
  artifact descriptors must be verified regular files beneath the source asset
  root.
- Protocol v4 transports the preparation manifest in the source descriptor and
  input manifest in the load request.  The obsolete per-frame
  `prepared-inputs` field was removed, preventing a second, unvalidated
  preparation transport.  A worker reports the accepted preparation identity
  in readiness, and the parent rejects a mismatch.
- Preparation artifacts are pinned through an explicit reference-counted
  lease manager for an active execution.  This is session protection, not a
  claim of a cross-session persistent artifact store.

### Cache, reuse, failure, and accounting choices

- `private/render-job-plan.rkt` is the source-independent consumer of a
  bounded frame-reuse witness.  It validates only requested target slots,
  representative/alias pairs, and cycles; geometry remains a future producer
  of the witness rather than a dependency of project execution.
- The subprocess executor separates persistent-frame-cache hits, rasterized
  representative frames, and reuse aliases before sizing workers.  It stages
  and validates cache materialization and freshly rasterized PNGs before
  canonical publication; cancellation, failed input verification, and a
  rejected completion leave canonical frame publication untouched.  Existing
  request/session/generation/attempt checks remain the authority for stale or
  duplicate worker messages; the internal retry default remains zero.
- Work accounting is carried in project execution diagnostics, including
  preparation elapsed time and cache/reuse/rasterization counts from the
  process report.  Worker capacity is deliberately not part of the frame cache
  identity.
- A PR-E full-suite rerun exposed one actual regression in
  `tests/scene-eo-execution-test.rkt`: after changing only a narration asset,
  the assertion `(positive? ...reused-frames)` expected `#t` but was `#f`.
  The first PR-E full run therefore had **12 / 13,578** failures, not the
  established 11.  Input integrity must track audio, but PNG pixels do not
  depend on narration.  Frame-cache key v5 consequently hashes a visual
  projection of the input manifest (all non-audio inputs plus runtime
  identity), while the complete manifest still guards session integrity and
  later assembly.  The repaired focused test passed and the final complete
  suite returned to the 11 established failures.

### PR-E changed files

- `project.rkt` — preparation manifests, preparation timing, persistent-cache
  eligibility, and public prepared-project accessors.
- `private/render-preparation-manifest.rkt` — bounded input/preparation
  manifest codecs, identity, construction, and verification.
- `private/render-preparation-lease.rkt` — explicit reference-counted
  preparation-artifact leases.
- `private/render-job-plan.rkt` — generic frame-reuse-plan validation and
  materialization model.
- `private/render-source-loader.rkt`, `private/render-frame-job.rkt`,
  `private/render-worker-protocol.rkt`, `private/render-worker-process.rkt`,
  and `private/render-worker-main.rkt` — one-time preparation handoff and
  strict protocol-v4 reconstruction.
- `private/project-execution.rkt` and
  `private/process-frame-executor.rkt` — preparation leases, input verification
  boundaries, cache/reuse scheduling and accounting, safe staging/publication,
  and the visual-vs-complete input cache identity.
- `scribblings/reference/project.scrbl` and
  `tests/documented-bindings-exist-test.rkt` — documented prepared-project
  accessors and reference coverage.
- `tests/process-render-preparation-test.rkt`,
  `tests/project-subprocess-execution-test.rkt`,
  `tests/process-frame-executor-test.rkt`, and
  `tests/render-worker-process-test.rkt` — real-child one-time-preparation,
  integrity, cache/reuse, and protocol coverage.
- `docs/process-rendering-progress.md` — this PR-E evidence record.

## PR-E verification performed

Every Racket command below used
`/Applications/Racket v9.3.0.2/bin/racket` and matching `raco`, with:

```
PLTCOLLECTS=/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket\ v9.3.0.2/collects
```

| Command | Actual result |
| --- | --- |
| `raco make tests/*.rkt examples/*.rkt` | Passed after the cache-key correction; dependents were recompiled before final full-suite attribution. |
| `raco test tests/process-render-preparation-test.rkt` | **25 tests passed.** It uses actual worker processes and a source directory named `source Ω` containing `shared preparation source.rkt`. |
| `raco test tests/process-render-preparation-test.rkt tests/documented-bindings-exist-test.rkt` | **943 tests passed.** |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt` | **166 tests passed.** |
| `raco test tests/color-preview-switch-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt tests/scene-3d-l-preview-overlay-test.rkt tests/scene-eh-preview-test.rkt tests/scene-ep-preview-primitives-test.rkt tests/scene-ep-worker-process-test.rkt tests/typography-preview-worker-test.rkt` | **67 tests passed.** |
| `raco test tests/scene-eo-execution-test.rkt` | **43 tests passed** after the visual-input cache-key correction (existing FFmpeg diagnostics were emitted). |
| `racket geometry/run-tests.rkt` | Completed with exit status 0; this runner listed modules but did not emit an aggregate count in this run. |
| `racket math/run-tests.rkt` | **1,805 checks passed; 0 failed.** |
| `racket math/run-style-checks.rkt` | **986 checks passed; 0 failed.** |
| `raco test tests` | **11 / 13,578 test failures.** The final set is exactly the seven color assertions and four pict-identity assertions proven pre-PR-A, with the same expected/actual values recorded in the PR-A provenance table above. The transient `scene-eo` audio-cache regression is absent. |
| `git diff --check` | Passed for tracked code changes after the PR-E documentation update. |

### Real-process, integrity, and cleanup evidence

- The 25-test PR-E real-child fixture runs one, two, and four configured
  subprocess workers.  It records exactly three parent preparer invocations
  across those runs (independent of worker count) and ten builder invocations
  (one parent build plus the configured child generations).  Its cache-hit
  rerun changes only capacity and starts zero frame workers; its partial-hit
  rerun starts one worker, reports seven cache hits, and rasterizes one frame.
- The same real process fixture verifies four representative frames plus four
  aliases, corrupt and missing preparation artifacts, a changed local helper
  module, invalid closure payloads, and overlapping artifact leases.  In each
  integrity rejection the canonical cache frame directory is empty, so no
  unverified half-result is accepted.
- Existing process-executor coverage continues to exercise malformed
  messages, crash, timeout, cancellation, stale identity/generation handling,
  duplicate completion, port/thread closure, and owned staging cleanup.  The
  PR-E test uses a real path with both spaces and non-ASCII characters; noisy
  source stdout/stderr remains separated from protocol traffic by the shared
  supervisor tests.
- Within current local permissions, PR-E observes owned-child counts and the
  supervisor resource reports.  It did **not** take an independent `ps`
  sample for the new preparation scenario, and host-wide enumeration through
  `pgrep` remains unavailable because it cannot reach `sysmond`.  Accordingly
  this PR-E record does not claim a global process count or independently
  verified descendant cleanup.  The direct macOS descendant-cleanup test and
  PID/resource observations remain the earlier PR-B/PR-D evidence above.

## Remaining risks and intentionally deferred work after PR-E

- The 11 color-rendering and pict-identity full-suite failures are proven
  baseline behavior, unchanged, and outside PR-E scope.
- The input manifest protects discoverable local module imports and declared
  assets, not arbitrary files reached through dynamic `require`, environment
  variables, network access, foreign code, or undeclared runtime paths.  SHA-1
  here is a deterministic change detector, not an adversarial-security claim.
  This is intentionally not universal hermetic source execution.
- Artifacts are protected while an execution holds a lease but are not yet a
  managed persistent preparation cache with cross-session eviction accounting.
  Existing subprocess preflight still rejects prepared 3D label-layout input;
  a general layout codec is intentionally not inferred in this PR.
- Fresh/staged PNGs are verified before publication.  An already-published
  cache PNG is currently trusted after key/existence validation rather than
  being rehashed on every hit; a manual post-publication cache corruption is a
  remaining integrity limitation.
- PR-F through PR-H remain unstarted: no geometry or math migration, no batch
  movie-export redesign, no performance benchmark/scaling claim, and no final
  integrated documentation build were added.

## PR-E completion gate

The existing project executor now shares one verified parent preparation with
real subprocess workers, distinguishes cache/reuse/raster work, and fails or
cancels without publishing an unverified canonical frame.  The observed
audio-only cache regression was fixed and retested.  Real-child preparation,
integrity, cache, reuse, lifecycle, focused preview/project, geometry, math,
and freshly recompiled full-suite evidence is recorded above; the final full
suite has only the established 11 baseline failures.  Work stops here, before
PR-F.

## PR-F decisions and implementation

### Geometry source and reuse boundary

- Each ordinary geometry example now exposes the documented PR-A pair
  `geometry-render-preparer` (two arguments) and `geometry-render-builder`
  (three arguments), alongside its existing `make-demo-timeline`.  The pair
  is constructed by `geometry/examples/private/library-example.rkt`, which
  uses the established `source-build-context` and source loader contracts;
  it does not add a second source-loading implementation.
- `geometry/private/frame-reuse.rkt` is a pure geometry-only semantic layer.
  It recognizes visually identical timeline frames from appearances and, when
  captions are enabled, narration.  It returns source-index to representative
  source-index pairs.  It imports no project, renderer, cache, process, or
  filesystem code.  `geometry/render.rkt` consumes the same helper for its
  existing local rendering API, so still/review behavior remains local.
- The generic PR-E `render-job-plan` validates and materializes the supplied
  witness, owns persistent PNG cache accounting and aliases, and executes
  representatives through the shared subprocess executor.  A geometry video
  therefore uses one outer worker pool only; no geometry worker starts a
  second renderer pool.
- Frame-reuse witnesses are transferred as immutable vectors.  This both
  preserves the PR-E bounded transfer model and avoids falsely rejecting
  ordinary long geometry timelines at the model's 64-level list-depth limit.
  The generic job plan retains its local list maps without another transfer
  snapshot because those maps never cross the worker protocol boundary.
- The generic route has a freshly generated, operation-owned private output
  sibling; only that sibling is removed on cleanup.  The user-requested
  destination, subtitle path, and persistent `.animate-geometry-render-cache`
  are not cleaned.  Geometry's legacy public `frame-000000.png` numbering,
  subtitle generation, MP4 encoding/muxing, camera/appearance handling, and
  parent-side assembly are retained.

### Geometry runner migration

- `geometry/examples/private/run-example.rkt` now uses the generic
  `render-spec`/project subprocess execution route for `--frames`, in
  automatic mode.  It reports requested, started, and completing capacity
  from the shared route; a full persistent-cache hit starts zero workers.
- The former private `--worker-shard` child CLI, process launcher, shard
  directories, merger, and nested worker allocation have been removed.  The
  old per-example command shape remains compatible for ordinary users.
- `geometry/render-all-dark.rkt` remains sequential over videos and passes
  its `--workers` value to each ordinary example.  It does not create a
  batch-wide renderer/process pool.

### PR-F changed files

- `geometry/private/frame-reuse.rkt` — new pure semantic reuse producer.
- `geometry/render.rkt` — local rendering now uses that producer without
  changing scene construction or sampling.
- `geometry/examples/private/library-example.rkt` — PR-A-contract geometry
  preparer/builder for the generic source path.
- `geometry/examples/private/run-example.rkt` — generic outer executor and
  parent-owned legacy frame/subtitle/movie publication.
- The 19 ordinary `geometry/examples/*.rkt` modules — explicit exports of the
  geometry preparer/builder pair.
- `geometry/tests/subtitle-cli-fixture.rkt` — exports the same pair for the
  existing command-line subtitle test.
- `private/render-job-plan.rkt` — accepts a vector witness and avoids applying
  protocol-transfer depth limits to its parent-local maps.
- `geometry/tests/process-render-migration-test.rkt` and
  `geometry/run-tests.rkt` — real-child migration, cache/reuse, parity, and
  lifecycle coverage.
- `geometry/README.md`, `geometry/docs/PARALLEL-RENDERING.md`,
  `geometry/docs/STATIC-FRAME-REUSE-PLAN.md`, `geometry/docs/MANUAL.md`,
  `geometry/docs/REVIEW-BUNDLES.md`,
  `geometry/animate-mathematical-authoring-dsl.md`, and
  `geometry/render-all-dark.rkt` — current user/developer-facing worker and
  reuse documentation.
- `docs/process-rendering-progress.md` — this PR-F record.

## PR-F isolated legacy comparisons

All comparisons used `/Applications/Racket v9.3.0.2/bin/racket`, matching
`raco`, the same installed collects, and an explicit `PLTCOLLECTS` whose first
entry was either the current checkout parent or the isolated source parent.
The legacy source was a test-owned `git archive` of committed
`4b7573eb418d9d824c66c753e98a8b8961c28ad5` extracted at
`/private/tmp/animate-pr-f-legacy-source-VhnkVm`.  Thus the old command
resolved `animate` to the archive and the new command resolved it to
`/Users/soegaard/Dropbox/GitHub/animate`; package links could not make the two
runs test the same tree.  Each source tree was compiled with the selected
collection root before its rendering command.

| Representative command family (all `--dark --workers 2 --width 160 --height 90`) | Legacy result | Generic PR-F result | Comparison |
| --- | --- | --- | --- |
| `equilateral-triangle --frames --fps 2` | 43 frames | 43 frames; 2 started, 2 completing | Every PNG byte and SRT byte identical. |
| `copy-angle --frames --fps 2` | 115 frames | 115 frames; 2 started, 2 completing | `diff -qr` clean (PNG and SRT). |
| `semantic-labels --frames --fps 2` | 45 frames | 45 frames; 2 started, 2 completing | `diff -qr` clean (PNG and SRT). |
| `gallery --frames --fps 1` | 203 frames | 203 frames; 2 started, 2 completing | `diff -qr` clean (PNG and SRT). |

The initial `equilateral-triangle` legacy capture was written under
`/private/tmp/animate-pr-f-legacy-Ll7smu`; all compared output used generated
test roots, never a user destination.  The archive cannot include the
checkout's untracked PR-A--PR-E implementation files or the user's unrelated
dirty changes.  That is an unavoidable reconstruction limitation, but the
legacy geometry sharder does not load those new generic files and the
comparison held executable, installed dependencies, geometry source revision,
and collection resolution fixed.  Timings (for example, 17.6 s legacy versus
3.1 s generic for `copy-angle`) are observations only, not performance claims.
The six explicitly named, test-owned `/private/tmp/animate-pr-f-*` comparison
directories were removed after this record was written; no checkout path was
cleaned.

## PR-F verification performed

Every Racket command below used the same Racket 9.3.0.2 runtime and explicit
current-checkout `PLTCOLLECTS` unless it is one of the isolated archive
comparisons above.

| Command | Actual result |
| --- | --- |
| `raco make geometry/private/frame-reuse.rkt geometry/render.rkt geometry/examples/private/library-example.rkt geometry/examples/private/run-example.rkt geometry/tests/process-render-migration-test.rkt` | Passed. |
| `raco make private/render-job-plan.rkt tests/*.rkt geometry/tests/*.rkt geometry/examples/*.rkt` | Passed; this refreshed dependent bytecode after the generic witness fix. |
| `raco test geometry/tests/process-render-migration-test.rkt` | **5 tests passed.** It uses actual generic child processes at forced capacities 1, 2, 4, and 10; checks PNG-byte equality with the former local renderer; tests cache miss/partial hit/full hit, aliases, caption and appearance variation, aspect ratio, a space/non-ASCII path, CLI subtitle output, retired shard CLI rejection, and obsolete-sharder removal. |
| `raco test geometry/tests/subtitle-render-test.rkt` | **11 tests passed.** Existing SRT/VTT and MP4/subtitle behavior remains covered through the migrated command path. |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt tests/process-render-preparation-test.rkt` | **191 tests passed.** |
| `raco test tests/color-preview-switch-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt tests/scene-3d-l-preview-overlay-test.rkt tests/scene-eh-preview-test.rkt tests/scene-ep-preview-primitives-test.rkt tests/scene-ep-worker-process-test.rkt tests/typography-preview-worker-test.rkt` | **67 tests passed.** |
| `racket geometry/run-tests.rkt` | **529 tests passed.** |
| `racket math/run-tests.rkt` | **1,805 checks passed; 0 failed.** |
| `racket math/run-style-checks.rkt` | **986 checks passed; 0 failed.** |
| `raco test tests` after the dependent recompile | **11 / 13,578 failures.** The failures are exactly the seven color assertions and four pict-identity assertions in the PR-A provenance table, with unchanged expected and actual values; no PR-F failure was added. |

### Real-process ownership and cleanup evidence

- The migration test asks the shared executor for 1, 2, 4, and 10 real child
  workers, receives a parent-visible PID for each started worker, and checks
  that PID count and uniqueness equal the useful configured capacity.  After
  each operation, it checks the supervisor status reports `open? #f`, closed
  input/output/error ports, and dead stdout/stderr reader threads for every
  owned child.
- The test checks only parent-observed owned-worker identity and resources. It
  does not independently enumerate the operating-system process table or
  claim a global process count or arbitrary descendant cleanup.  Those checks
  remain unavailable within current local permissions; the earlier PR-B owned
  descendant probe is the available direct macOS-specific evidence.
- Per-operation temporary generic output is freshly generated and its cleanup
  is owned by the runner.  The test covers cancellation/timeout/crash behavior
  in the shared executor suite cited above; PR-F adds no second process owner.

## Remaining risks and intentionally deferred work after PR-F

- The 11 color-rendering and pict-identity full-suite failures are proven
  baseline behavior and remain unchanged; they are outside geometry migration
  scope.
- The archive comparison is an equivalent committed geometry baseline, not a
  copy of the current dirty checkout.  It cannot recreate untracked PR-A--PR-E
  files, although the legacy sharder did not depend on them.
- Process identity/port/thread cleanup is verified only through the parent
  supervisor's reports.  No system-wide process count or cross-platform
  guarantee for arbitrary descendants after an already-crashed worker is
  claimed.
- PR-F deliberately does not add batch movie export, change mathematical
  scene/sampling behavior, migrate math, create a persistent preparation
  manifest, or begin PR-G/PR-H.  The existing preparation/cache integrity
  limitations recorded after PR-E remain applicable.

## PR-F completion gate

Geometry full-frame rendering now uses the existing generic source/project/
subprocess executor, with geometry retaining only semantic timeline reuse and
the user-facing parent publication/movie steps.  Real-child tests, isolated
legacy byte-for-byte comparisons, focused project/preview tests, geometry and
math regressions, and a fully recompiled root suite are recorded above.  The
root suite has only the 11 established baseline failures.  Work stops here,
before PR-G.

## PR-G decisions and implementation

### One parent preparation and a portable math layout boundary

- The four lesson modules now retain their existing `problem`, `solution`,
  `plan`, and `make-demo-scene` exports and additionally export the PR-A
  `math-render-preparer`/`math-render-builder` pair.  The shared adapter in
  `math/examples/private/library-example.rkt` uses the existing generic
  source-build context and module-builder loader; it does not introduce a
  second module/source loader.
- The parent reconstructs the selected case, exact light/dark camera, pixel
  dimensions, FPS, supersampling, and title from the immutable source options.
  It calls `prepare-math-plan!` once, stages the SVGs, and emits a bounded,
  versioned `animate-math-prepared-plan-v1` data payload.  Worker builders
  reconstruct the same local plan and validate schema, options, plan/schedule,
  state coverage/identity, notation text, token ownership, staged asset
  membership, colors, row gap, and visible-row bound before compiling the
  native scene.  They never invoke the formula typesetter or preparation API.
- `math/private/prepared-plan-model.rkt` owns the immutable prepared-plan
  record and deterministic state enumeration.  The codec uses vectors for
  transfer collections.  Stable layout keys hash the complete mathematical
  revision/datum/context rather than transmitting recursive rewrite ancestry.
  This avoids exceeding the generic nesting bound while retaining semantic
  identity.
- Prepared SVGs are copied atomically into the ignored content-addressed
  `math/examples/.animate-math-preparation-artifacts-v1/` cache.  They are
  explicit source-preparation artifacts for the current render, not a new
  persistent preparation-manifest system.
- The math CLI now makes an `animate-project` with `module-builder-source` and
  invokes the shared project executor.  It keeps historic public PNG numbering,
  selected output paths, parent-side MP4 encoding, case/camera/appearance
  behavior, and protected native PNG decoding.  `--workers 1` uses the local
  path; a higher capacity uses restartable subprocess workers.  FPS is now
  intentionally restricted to a positive integer because the generic executor
  has an integer frame grid.
- `--steps` and `--list-cases` still return before preparation, TeX, workers,
  destination cleanup, and encoding.  The opt-in preparation/typeset event
  observers are private test instrumentation only; their defaults are quiet.
- A complete quadratic-general payload exceeds the original generic transfer
  budget because it has many token/artifact records.  `private/render-source-model.rkt`
  now treats a proper list as a collection (each element at the same structural
  depth) rather than as a long cdr chain, and raises the finite node budget from
  10,000 to 100,000.  The accompanying generic source-model test covers a
  128-entry artifact-style list.  This is supporting payload transport work,
  not a second math serialization path.

### PR-G changed files

- `math/examples/private/run.rkt` and the four example modules — generic
  source-aware project declaration, parent publication/encoding, and explicit
  preparer/builder exports.
- `math/examples/private/library-example.rkt` — shared strict math source
  adapter.
- `math/private/prepared-plan-model.rkt`,
  `math/private/prepared-plan-codec.rkt`, and
  `math/private/preparation-artifacts.rkt` — portable prepared-plan model,
  validation/rebinding codec, and staged SVG artifact handling.
- `math/private/prepare.rkt` and `math/private/typeset.rkt` — private opt-in
  parent-preparation/typeset event hooks.
- `math/tests/prepared-plan-codec-test.rkt` and `math/run-tests.rkt` — pure
  no-typesetter worker rebinding and malformed payload coverage.
- `private/render-source-model.rkt` and
  `tests/process-render-source-model-test.rkt` — bounded generic transfer
  support for the validated full math payload.
- `.gitignore` and `math/README.md` — ignored prepared SVG cache and current
  worker/preparation/inspection/encoder behavior.
- `docs/process-rendering-progress.md` — this PR-G evidence record.

### Baseline and source-resolution evidence

The direct legacy captures used the same
`/Applications/Racket v9.3.0.2/bin/racket`, matching installed dependencies,
and:

```sh
PLTCOLLECTS=/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket\ v9.3.0.2/collects
```

The collection-resolution check printed
`/Users/soegaard/Dropbox/GitHub/animate/main.rkt`; the generic child tests and
real renders inherited the same explicit collection path.  Thus package links
could not redirect those runs to an installed `animate` package.

Before this migration, direct native captures of the then-current checkout's
math runner were saved in the test-owned
`/private/tmp/animate-pr-g-baseline.u29P98`: dark linear-concrete (11 frames),
linear-general (18), quadratic-concrete (18), quadratic-general (52), light
linear-concrete (11), and dark `quadratic/two-real-roots` (21).  This is a
pre-runner-migration capture from the current dirty checkout, so it correctly
includes accepted PR-A--PR-F changes but is not a separately extracted Git
archive.  Untracked PR-A--PR-F files make an otherwise equivalent archive
incomplete; that is the remaining reconstruction limitation.  The old runner
does not depend on the new PR-G source adapter or codec.

At `--dark --fps 1 --width 160 --height 90 --supersample 1`, each of the four
lessons produced 11/18/18/52 frames at capacities 1, 2, 4, and 10.  Every one
of the 396 matching PNG pairs against the direct capture was byte-identical.
The selected two-real-roots case produced 21 frames with ten workers and all
21 direct-capture comparisons matched.  Supplementary light 1-versus-10 runs
for all four lessons likewise matched exactly; the linear-concrete light run
also matched its direct capture.  After the final payload-boundary tightening,
quadratic-general at ten workers again produced 52/52 frames with **0** byte
mismatches against the dark direct capture.

For a ten-worker dark linear-concrete run, inherited opt-in logs recorded one
`prepare-math-plan!` event and eight `typeset-state!` events (the lesson's eight
prepared states).  Because every child inherited the logging environment, this
is direct evidence that restarted workers did not prepare or typeset formulas.
`--steps --case quadratic/two-real-roots` and `--list-cases` recorded zero
preparation/typeset events and did not create the selected output directory.

### PR-G verification performed

All commands below used the explicit Racket 9.3.0.2 executable and the
checkout-first `PLTCOLLECTS` shown above unless noted.

| Command | Actual result |
| --- | --- |
| `raco make math/private/prepared-plan-codec.rkt math/examples/private/library-example.rkt math/tests/prepared-plan-codec-test.rkt math/examples/private/run.rkt private/render-source-model.rkt tests/process-render-source-model-test.rkt` | Passed; refreshed the changed implementation and dependent bytecode. |
| `racket math/run-tests.rkt` | **1,817 checks passed; 0 failed.** This includes codec corruption and no-typesetter-on-rebind checks. |
| `racket math/run-style-checks.rkt` | **1,036 checks passed; 0 failed.** |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt` | **167 tests passed.** These are real-child shared-supervisor/source-project tests, including protocol/lifecycle/resource cases. |
| `racket geometry/run-tests.rkt` | **529 tests passed.** |
| `racket math/examples/quadratic-general.rkt --dark --fps 1 --workers 10 --width 160 --height 90 --supersample 1 /private/tmp/animate-pr-g-final-qgeneral-w10` | `Workers: requested 10, started 10, completing 10`; 52 frames and **0/52** direct-baseline PNG mismatches. |
| `raco test tests` (final post-edit rerun) | **11 / 13,579 failures**: the established seven color assertions (`scene-at`, `scene-au`, `scene-bc`, `scene-bg`, `scene-cr`) and four pict-identity assertions (`scene-j`, `scene-k`, `scene-m`, `scene-n`), with no PR-G-specific failure. |
| `git diff --check` | Passed with no whitespace errors. |

The real native matrix also covered nondefault odd PNG dimensions:
161 by 91 at supersample 2 rendered successfully as 322 by 182 PNG frames.
Forwarding the actual dimensions to parent-side MP4 encoding fixed the former
implicit-size mismatch.  H.264/yuv420p itself rejects the odd 161 by 91 MP4
and left a zero-byte requested file in that intentional failure experiment;
this existing encoder constraint/cleanup behavior is documented, not claimed
as a PR-G success.

### Process evidence and remaining risks

- Native reports confirm useful capacities of 2, 4, and 10 and the final
  ten-worker run reported 10 started and 10 completing workers.  The shared
  real-child test suite additionally checks parent-owned worker PIDs, ports,
  reader threads, shutdown, cancellation, and restart behavior.
- The available evidence is parent-supervisor reporting plus those focused
  tests.  Local permission restrictions prevented an independent system-wide
  `ps` enumeration during the run, so this record does **not** claim a global
  process count or independently verified arbitrary-descendant cleanup.
- The direct comparison baseline is a pre-migration capture of the dirty
  checkout rather than an isolated source archive, as described above.
- No full-resolution reviewed MP4 set or performance benchmark was produced in
  PR-G; low-resolution native pixel equivalence, rather than timing, closes
  this migration gate.  The known odd-dimension H.264 behavior remains outside
  this scope.
- PR-G does not change mathematical construction, sampling, case choreography,
  geometry, batch movie export, persistent preparation manifests, or any PR-H
  work.

## PR-G completion gate

All four reviewed math lessons now run through the existing generic
source/project/subprocess execution path.  The real native matrix establishes
worker-count-independent PNG output, and parent-only preparation instrumentation
establishes that cold formula preparation does not scale with ten workers.  The
shared test, math, style, geometry, and root-suite evidence above is recorded;
work stops here, before PR-H.

### PR-G full-resolution review render

After the migration and reduced-resolution parity gate, the requested normal
dark review outputs were rendered with the same explicit Racket 9.3.0.2
runtime and checkout-first `PLTCOLLECTS` used by the earlier PR-G evidence:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
PLTCOLLECTS="/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket v9.3.0.2/collects"
export PLTCOLLECTS
mkdir -p math-output/review-pr-g/frames
for example in linear-concrete linear-general quadratic-concrete quadratic-general
do
  "$RACKET" "math/examples/${example}.rkt" --dark --workers 10 \
    --mp4 "math-output/review-pr-g/${example}.mp4" \
    "math-output/review-pr-g/frames/${example}"
done
```

The runner used its documented defaults: 1280 by 720, 30 fps, and
supersampling 1. Each command exited successfully, created the listed PNG
sequence, and completed parent-side H.264 MP4 encoding.

| Lesson | Frames / video duration | Requested / started / completing | Frame directory and MP4 |
| --- | --- | --- | --- |
| linear-concrete | 324 / 10.800 s | 10 / 10 / 10 | `math-output/review-pr-g/frames/linear-concrete`; `math-output/review-pr-g/linear-concrete.mp4` |
| linear-general | 540 / 18.000 s | 10 / 10 / 10 | `math-output/review-pr-g/frames/linear-general`; `math-output/review-pr-g/linear-general.mp4` |
| quadratic-concrete | 528 / 17.600 s | 10 / 10 / 10 | `math-output/review-pr-g/frames/quadratic-concrete`; `math-output/review-pr-g/quadratic-concrete.mp4` |
| quadratic-general | 1,557 / 51.900 s | 10 / 10 / 10 | `math-output/review-pr-g/frames/quadratic-general`; `math-output/review-pr-g/quadratic-general.mp4` |

`ffprobe` confirmed every encoded video has 1280 by 720 video, 30/1 frame
rate, the listed frame count, and the listed duration.

The current documented dark probe command also completed successfully:

```sh
"$RACKET" math/run-probes.rkt --dark math-output/review-pr-g/probes
```

It completed **1,244 checks with 0 failures** and wrote the 618-entry probe
manifest: 68 linear-concrete probes, 108 linear-general probes, 111
quadratic-concrete probes, and 331 quadratic-general probes.

Full-resolution PNG inspection used that manifest to select matching frames
from the migrated ten-worker output, not merely the direct probe images. The
review covered linear-concrete subtraction/cancellation and numeric evaluation;
linear-general ordinary, identity, and inconsistent case starts;
quadratic-concrete's surviving `+` after cancelling five, the completing-square
inset, and the root split; and quadratic-general's common prefix, numerator
ordering, root split, and one-root/no-root/linear/all-real/none handoffs. No
missing operator, hybrid numeric expression, crossed branch copy, numerator
permutation, duplicate case-start row, or other choreography regression was
observed. No presentation code was changed.

No independently provenance-verified pre-PR-G **full-resolution** direct
reference exists in this checkout, so no optional full-resolution byte comparison
was manufactured. The complete reduced-resolution byte parity recorded above
remains the automated equivalence evidence. This review task changed only this
progress record and the status header; `racket math/run-tests.rkt` passed with
**1,817** checks, `racket math/run-style-checks.rkt` passed with **1,036**
checks, and `git diff --check` passed. No PR-H work was started.

## PR-H integrated validation, benchmark, documentation, and cleanup

### Scope and implementation decisions

- PR-H added only the reproducible validation tool
  `tools/benchmark-process-rendering.rkt` and the documentation records
  `docs/process-rendering-benchmark.md` and this section. It did not change
  scene construction, sampling, geometry/mathematics, worker policy, or the
  prior PR-A--PR-G implementation.
- The tool uses the existing `module-builder-source`, documented preparer and
  builder contracts, `plan-project` / `prepare-project!` /
  `execute-prepared-project!` lifecycle, and `project-frame-execution-report`.
  It adds no loader, renderer, or process supervisor.
- The driver creates an owned `PLTUSERHOME`, passes checkout-first collection
  roots and the local package roots explicitly, and verifies that
  `animate/main.rkt` resolves to this checkout before rendering. Every
  measured project invocation has a new Racket parent process, avoiding stale
  long-lived supervisor state while matching normal CLI execution.
- `racket/json` writes object keys as symbols. The tool initially converted
  them to strings and therefore left a one-byte partial JSON file after an
  otherwise successful matrix. That harness-only reporting defect was fixed,
  the incomplete owned run was removed, and the whole matrix was rerun. This
  did not modify renderer behavior.
- The first 10-fps matrix attempt would exceed the approximately 6.3 GiB free
  volume. Its exact harness-owned directory was stopped/removed, then the
  accepted matrix retained 1280 by 720 and supersample 1 but used 2 fps (115
  geometry frames and 104 math frames). The lower grid is explicit in the
  data; no full-resolution performance claim is made.

### Benchmark command and results

The accepted run used Racket 9.3.0.2 with:

```sh
export PLTCOLLECTS='/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket v9.3.0.2/collects'
/Applications/Racket\ v9.3.0.2/bin/racket tools/benchmark-process-rendering.rkt \
  --output logs/process-rendering-pr-h --workers 1,2,4,10 \
  --repetitions 2 --fps 2 --width 1280 --height 720
```

It completed and wrote ignored, harness-owned
`logs/process-rendering-pr-h/benchmark.json` and `benchmark.tsv`; the run label
is `2026-09-15T024321-benchmark1898`. The frozen environment was macOS 26.5
on `aarch64`, Animate 1.23.0 / `SCENE-3D-V`, FFmpeg 8.0.1, TeX Live 2019, and
dvisvgm 2.6.3. Sandboxed `sysctl` denied a logical-processor count. The
benchmark's checkout resolution was
`/Users/soegaard/Dropbox/GitHub/animate/main.rkt`.

| Workload | Workers | Raw frame-executor ms | Median ms | One-worker-relative speedup |
| --- | ---: | --- | ---: | ---: |
| geometry copy-angle | 1 | 8743.151, 8537.356 | 8640.253 | 1.000 |
| geometry copy-angle | 2 | 5316.172, 5237.555 | 5276.864 | 1.637 |
| geometry copy-angle | 4 | 4928.458, 4905.328 | 4916.893 | 1.757 |
| geometry copy-angle | 10 | 8809.082, 8909.772 | 8859.427 | 0.975 |
| math quadratic-general | 1 | 8438.555, 8412.000 | 8425.278 | 1.000 |
| math quadratic-general | 2 | 6871.613, 6861.919 | 6866.766 | 1.227 |
| math quadratic-general | 4 | 6955.188, 6757.879 | 6856.534 | 1.229 |
| math quadratic-general | 10 | 11405.959, 11528.652 | 11467.306 | 0.735 |

The timing is frame-executor time only, excluding parent preparation and media
assembly. The small two-repetition local sample establishes real worker
behavior, not an optimal worker-count recommendation. All post-oracle primary
outputs were byte-identical: 805 geometry PNG comparisons and 728 math PNG
comparisons, all zero mismatches. The one-worker oracle is the first sequence
for each workload.

All twelve primary subprocess cells started and completed exactly their
requested capacity and reported every parent-owned port/reader resource closed.
Geometry had 96 representative raster jobs plus 19 materialized held-frame
aliases: the two-worker splits were 48/48, four-worker 24/24, and every
ten-worker process completed 9--10 jobs. Math had 104 independent raster jobs:
the two-worker splits were 51/53 and 52/52, four-worker 27/25/26/26, and each
ten-worker process completed 9--12 jobs. Thus all requested multi-worker
capacities performed useful work.

The cold math observation reported one parent preparation, 31 parent typeset
calls, 15,863.911 ms parent preparation, and 12,075.744 ms frame execution.
Across the eight warm primary math runs the median parent preparation was
15,448.899 ms; every run again reported one preparation and 31 typeset calls.
The inherited opt-in logs have 14 preparation and 434 typeset events (14 × 31),
including cold, MP4, warm-up, primary, and cache observations. No worker
triggered math preparation/typesetting.

For cache accounting, geometry's same-root repeat was a full hit: 115
persistent hits/reused frames, zero workers/raster jobs, 48.741 ms wall time,
and byte-identical PNGs. Math's same-root fresh-parent repeat was byte-identical
but did not hit: it started/completed ten workers and rasterized all 104
frames. A focused reproduction found the source input-manifest identity stable
while the preparation-manifest/payload identities changed, with 104 differing
staged SVG descriptors out of 377. This is recorded as a current math
cross-parent frame-cache limitation; its timing is not presented as cache-hit
performance.

MP4 assembly was actually exercised once at one and ten workers for both
workloads. `ffprobe` found H.264, 1280 by 720, and 2 fps throughout:
copy-angle has 115 frames / 57.5 s and quadratic-general 104 / 52.0 s. The
four retained files are under `mp4-runs/{geometry-copy-angle,math-quadratic-general}/workers-{1,10}/movie.mp4`
within the benchmark run. The measured frame/wall/remainder milliseconds were
9131.502/9615.741/484.239 and 10147.839/15792.981/5645.142 for geometry
(one/ten), and 8592.102/9076.561/484.459 and
10886.282/11499.035/612.753 for math. The remainder includes execution
orchestration, so it is not claimed to be pure encoding time.

### Process, cleanup, and stale-architecture evidence

- During the accepted run, permitted `ps` sampling observed the benchmark
  driver, its isolated parent, and a fresh single-measurement parent (PIDs
  82743, 82744, and 83122). The persisted reports retain worker PIDs,
  nonzero assignment counts, and closed-resource state. This is evidence of
  the owned process tree and parent cleanup, not an independent global process
  count or proof of arbitrary descendant cleanup after exit.
- The focused real-child test command below exercises cancellation, crash,
  timeout, invalid executables/exports, malformed messages, noisy sources,
  non-ASCII/space paths, generation/reload behavior, and resource cleanup.
  Those cases are test evidence; the performance matrix itself does not claim
  to be a cancellation trial.
- An active-source search found no production geometry sharder or duplicate
  final process supervisor. `worker-shard` remains only in historical plan/
  progress text, the untracked archival `geometry 18/` copy, and the
  migration test's negative assertion. Those user-owned historical files were
  not edited.

### Verification actually run

| Command | Result |
| --- | --- |
| `raco make tools/benchmark-process-rendering.rkt tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt tests/process-render-preparation-test.rkt geometry/tests/process-render-migration-test.rkt math/tests/prepared-plan-codec-test.rkt` | Passed with the selected Racket 9.3.0.2 runtime. |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt tests/process-render-preparation-test.rkt geometry/tests/process-render-migration-test.rkt math/tests/prepared-plan-codec-test.rkt tests/typography-preview-worker-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt` | Exit 0; **210 tests passed**. Expected FFmpeg fixture diagnostics were emitted. |
| `racket geometry/run-tests.rkt` | Exit 0; **529 tests passed**. |
| `racket math/run-tests.rkt` | Exit 0; **1,817 checks passed; 0 failed**. |
| `racket math/run-style-checks.rkt` | Exit 0; **1,036 checks passed; 0 failed**. |
| `raco make tests/*.rkt examples/*.rkt` | Exit 0. |
| `raco test tests` | Exit 1 with the established **11 / 13,579** failures only: seven color assertions in `scene-at`, `scene-au`, `scene-bc`, `scene-bg`, and `scene-cr`, plus four pict-identity assertions in `scene-j`, `scene-k`, `scene-m`, and `scene-n`. Expected/actual values match the pre-PR-A evidence. |
| `scribble --htmls --dest /private/tmp/animate-process-rendering-docs-prh-20260915 scribblings/animate.scrbl` | Exit 0; produced 48 documentation files. |
| `raco animate check-repo` | Started successfully and completed its policy/tests, but was deliberately interrupted during `raco pkg create --source`: its owned temporary archive reached 1.1 GiB while only 704 MiB remained. It exited 1 with `user break` and automatically cleaned its temporary archive. This is not a passing package check. |
| `git diff --check` | Passed with no whitespace errors. |

### PR-H completion gate and remaining risks

The gate is met for the source-aware renderer: real child processes performed
balanced useful work, all tested worker counts produced exact PNG equivalence,
MP4 assembly completed, real-child failure/cancellation coverage passed, and
the benchmark reports separate fresh-frame timings from the verified geometry
cache hit. The new benchmark document records the reproducible command,
environment, data, limits, and retained evidence paths.

Remaining risks are deliberately visible: this is a two-repetition, 2-fps,
single-host benchmark; no global process count or arbitrary-descendant cleanup
was independently observable; math's fresh-parent preparation identity prevents
a persistent frame-cache hit even when PNGs match; and `raco animate check-repo`
could not complete its package archive safely on this dirty/output-heavy
checkout. No user-owned output, cache, or unrelated dirty file was deleted,
reset, staged, committed, or pushed. Work stops here; no post-PR-H stage was
started.

### PR-H completion-gate addendum — 10-fps scaling, cache identity, and source-only release check

This preserves the accepted two-fps record above and records the requested
normal-resolution follow-up. It does not begin a post-PR-H stage. The addendum
used the dark 1280 by 720, supersampling-1, 10-fps paths. Each cell had one
warm-up and two measured repetitions; no third was required because the
largest pair difference was 8.4% (the ten-worker geometry cell).

#### Decisions and changed files

- `private/process-frame-executor.rkt` now starts requested child workers
  concurrently and collects their outcomes in deterministic slot order. This
  removes serial child-startup delay without changing the job scheduler, scene
  construction, frame sampling, or source-loader contract.
- The first concurrent 10-fps geometry run exposed a real `copy-angle` frame
  158 mismatch. `geometry/private/frame-reuse.rkt` now mirrors the existing
  animated-clock arithmetic before sampling the timeline, with a regression
  in `geometry/tests/process-render-migration-test.rkt`: the renderer clock is
  `15.800000000000002`, while raw `15.8` crosses that boundary differently.
  This is reuse-plan alignment only; mathematical construction and sampling
  remain unchanged.
- `math/private/semantic-svg.rkt` canonicalizes direct glyph-path definitions
  in SVG `defs` blocks; `math/private/typeset.rkt` applies it after recoloring;
  `math/tests/property-test.rkt` covers the canonicalizer. This stabilizes
  preparation identity without changing formula geometry or presentation.
- `tools/benchmark-process-rendering.rkt` and the existing worker/project
  tests now retain per-frame SHA-256 manifests and worker timing evidence. The
  manifest schema is `animate-frame-digest-manifest-v1`.

#### 10-fps geometry result and useful-worker evidence

The final reports are in
`logs/process-rendering-pr-h-addendum-parallel-startup-evidence/matrix-geometry-after-clock-align/`.
Every measured sequence is byte-identical to the 574-frame one-worker oracle;
every subprocess report says its owned resources were closed. The one-worker
case is the direct renderer path, so it has no child PID or ready event.

| Requested workers | Measured executor ms | Midpoint ms | Speedup | Started / completing | Child PIDs by repetition | Startup / raster / publish ms by repetition | Useful assignments |
| ---: | --- | ---: | ---: | --- | --- | --- | --- |
| 1 | 44230.940, 44640.976 | 44435.958 | 1.000 | direct / n.a. | n.a. | n.a. | direct: 372 representative jobs, 202 aliases |
| 2 | 16428.839, 16574.676 | 16501.758 | 2.693 | 2 / 2, 2 / 2 | 22901,22900; 22960,22959 | 815.284 / 15394.484 / 213.157; 927.734 / 15486.557 / 155.750 | 187/185; 186/186 |
| 4 | 9248.330, 9425.650 | 9336.990 | 4.759 | 4 / 4, 4 / 4 | 23037--23034; 23066--23063 | 906.559 / 8141.471 / 195.617; 893.332 / 8347.783 / 173.619 | 93/93/93/93; 93/94/92/93 |
| 10 | 7350.446, 7998.224 | 7674.335 | 5.790 | 10 / 10, 10 / 10 | 23133--23124; 23169--23160 | 1399.123 / 5628.192 / 318.481; 1340.109 / 6295.001 / 356.601 | 37--38 per child in both runs |

Each report also includes per-child spawn, hello, source-ready, ready-latency,
and raster-span values. The startup column is the maximum ready-latency for
that invocation, so it measures the full readiness barrier. The initial
serial-startup evidence is in
`logs/process-rendering-pr-h-addendum-10fps-evidence/benchmark.json`; the
first concurrent matrix is in
`logs/process-rendering-pr-h-addendum-parallel-startup-evidence/benchmark.json`.
Its geometry result is deliberately not an acceptance result because it found
the frame-158 mismatch. The table above is the post-alignment acceptance
matrix. A 30-fps matrix was not run: the normal 10-fps workload already made
startup amortization and useful parallel work decisive.

#### Exact math cache identity

A fresh-parent investigation found stable input descriptors but differing path
definition order in 204 of 377 staged SVG artifacts. Sorting only those direct
definition paths made fresh preparation identities stable. The post-fix
same-root run requested and rendered 519 frames with zero persistent hits; its
immediate repeat rendered zero, reused all 519, reported 519 persistent hits,
started zero workers, and had an exactly matching SHA-256 manifest. Both
benchmark-owned roots were deleted after comparison.

#### Disk, process, and cleanup evidence

- The harness compares SHA-256 manifests before deleting primary PNG and
  frame-cache roots. The 12 final matrix roots, frame-158 investigation roots,
  and all eight benchmark-owned MP4 `movie-frames` directories were removed
  after their comparisons. The retained `.rktd` manifests occupy about 1.1
  MiB; two old harness-owned `pltuserhome` cache directories (14 MiB total)
  were removed in this review. The isolated source-check snapshot and its
  temporary compiled root were removed after recording their results. JSON/TSV
  records, manifests, and useful MP4 evidence remain. No user-owned output,
  cache, or unrelated dirty file was deleted.
- Permitted local `ps` samples observed an owned parent and explicitly launched
  worker children; retained reports record PIDs, nonzero assignments, ready
  events, completion counts, and closed resources. This is local process and
  parent-cleanup evidence, not a system-wide process count or proof that every
  arbitrary descendant has exited. Those checks were unavailable locally and
  are not claimed.

#### Verification rerun after the addendum

The first focused run exposed an old compiled artifact whose
`process-frame-execution-report` shape no longer matched source. The selected
Racket 9.3.0.2 recompiled the executor, project/worker modules, and affected
tests before the reruns below; no stale-bytecode failure remained.

| Command | Actual result |
| --- | --- |
| `raco test tests/process-render-source-model-test.rkt tests/render-worker-process-test.rkt tests/process-frame-executor-test.rkt tests/project-subprocess-execution-test.rkt tests/process-render-preparation-test.rkt` | Passed: 197 tests. |
| `raco test geometry/tests/process-render-migration-test.rkt math/tests/prepared-plan-codec-test.rkt tests/typography-preview-worker-test.rkt tests/color-worker-theme-test.rkt tests/scene-3d-d-preview-override-test.rkt` | Passed: 19 tests. |
| `/Applications/Racket v9.3.0.2/bin/racket geometry/run-tests.rkt` | Passed: 530 tests. |
| `/Applications/Racket v9.3.0.2/bin/racket math/run-tests.rkt` | Passed: 1,819 checks; 0 failed. |
| `/Applications/Racket v9.3.0.2/bin/racket math/run-style-checks.rkt` | Passed: 1,039 checks; 0 failed. |
| `/Applications/Racket v9.3.0.2/bin/raco make tests/*.rkt examples/*.rkt` | Passed. |
| `/Applications/Racket v9.3.0.2/bin/raco test tests` | Exit 1 with exactly the established 11 / 13,584 failures: seven color assertions and four pict-identity assertions; no new assertion location or value. |

For the source-only release check, a fresh source snapshot and isolated
`PLTUSERHOME` resolved `animate/project.rkt` to the snapshot, not the modified
checkout's package link. The isolated profile did not register the `animate`
`raco` command, so the same source entry point ran as
`racket -l animate/preview-cli -- check-repo`. It completed metadata, source
compile, documentation, and package creation. Its source test stage had the
same 11 assertions plus one environment failure in
`scene-fx-f-formula-parts-test.rkt`: independently linked
`latex-pict`/`racket-poppler` first exposed stale Racket 8.12 bytecode, then,
after recompilation into a temporary compiled root, unavailable
`libpoppler.163.dylib`. The fresh package-install stage could not resolve
`parsers-lib` because the Racket catalog hostname was unavailable. This is
source-resolution and source-compile evidence, not a passing isolated
package-install check; the external dependency and network limits remain
explicit risks rather than product-test regressions.

`git diff --check` was rerun after these documentation changes and passed.
PR-H remains complete with these limitations recorded; work stops here.

### PR-H production-rate math scaling addendum

The remaining realistic-math-scaling evidence is complete.  This used the
migrated `math/examples/quadratic-general.rkt` path in dark 1280 by 720,
supersampling 1, at the normal 30 fps: 1,557 frames and 51.9 seconds.  The
command was:

```sh
/Applications/Racket\ v9.3.0.2/bin/racket tools/benchmark-process-rendering.rkt \
  --output logs/process-rendering-pr-h-production-rate-math \
  --workloads math-quadratic-general --matrix-only \
  --workers 1,2,4,10 --repetitions 2 --fps 30 --width 1280 --height 720
```

One warm-up established a benchmark-owned SVG/preparation cache, followed by
two measured repetitions for each worker count.  The validation-only harness
now accepts `--workloads` and `--matrix-only`, forwarding those selections to
its isolated driver.  This is a measurement-scope change only: the workload
uses the existing PR-G source/preparation path and the existing PR-H executor;
there was no renderer, scheduler, scene, sampling, or worker-policy change.
The options avoided unrelated geometry, MP4, and cache probes, and the
previously accepted 519-frame persistent-cache-hit result was not rerun.

| Workers | Executor runs (ms) | Midpoint / speedup | Parent prep midpoint (ms) | End-to-end midpoint (ms) | Output / worker result |
| ---: | --- | --- | ---: | ---: | --- |
| 1 | 129015.751, 126463.778 | 127739.764 / 1.000x | 16704.309 | 145261.569 | direct path; 1,557-frame oracle retained |
| 2 | 68349.700, 72206.064 | 70277.882 / 1.818x | 15577.699 | 87245.092 | 2/2 ready and completing in both runs; 779/778 then 778/779 assignments |
| 4 | 41381.008, 41786.455 | 41583.732 / 3.072x | 15948.820 | 58781.617 | 4/4 ready and completing in both runs; all children assigned 387--392 jobs |
| 10 | 31409.308, 31324.708 | 31367.008 / 4.072x | 16362.422 | 48969.859 | 10/10 ready and completing in both runs; all children assigned 154--157 jobs |

End-to-end is parent planning (0.471--0.589 ms), parent preparation, and
execution wall time.  Each measured invocation reported one parent
preparation and 31 parent typesets; the nine-invocation event logs (warm-up
plus eight measurements) record exactly 9 preparations and 279 typesets, so
the prepared payload did not cause worker-side preparation/typesetting.  No
cell exceeded the 10% variation threshold (2.0%, 5.5%, 1.0%, and 0.3% for
1/2/4/10 workers), so no third repetition was needed.

The retained one-worker SHA-256 manifest is the compact oracle.  Every other
run compared all 1,557 frames against it and was byte-identical.  The
benchmark removed its owned PNG/frame-cache roots after comparison, then the
4 MiB benchmark-owned `pltuserhome` cache after recording results.  The
substantive retained evidence is limited to
`logs/process-rendering-pr-h-production-rate-math/` reports, JSON/TSV, and
event logs; no `math-output/review-pr-g`, user cache, or
source-relative staging was removed.

The subprocess evidence records PIDs 37413--37414 and 37609--37610 (two
workers), 37868--37871 and 38007--38010 (four), and 37171--37180 and
37309--37318 (ten), with closed owned resources in every report.  A permitted
local process snapshot also observed the benchmark parent, isolated driver,
one subprocess parent, and its two explicitly launched workers.  That is
local process-identity and parent-cleanup evidence only: permissions did not
allow a system-wide process count or independent verification of arbitrary
descendant cleanup after exit.

The longer workload shows why the earlier 2-fps sample was startup-heavy: the
ten-worker startup barrier was about 2.77--2.80 seconds while its raster span
was about 28.10--28.18 seconds.  Ten workers are therefore 4.072x faster than
direct execution on this loaded local host.  This is not a new default-worker
policy or a general hardware claim.

Verification after the validation-tool change:

| Command | Actual result |
| --- | --- |
| `/Applications/Racket v9.3.0.2/bin/raco make tools/benchmark-process-rendering.rkt` | Passed. |
| `/Applications/Racket v9.3.0.2/bin/racket math/run-tests.rkt` | Passed: 1,819 checks; 0 failed. |
| `/Applications/Racket v9.3.0.2/bin/racket math/run-style-checks.rkt` | Passed: 1,039 checks; 0 failed. |
| `git diff --check` | Passed after this documentation update. |

PR-H remains complete; work stops before any new architectural stage.
