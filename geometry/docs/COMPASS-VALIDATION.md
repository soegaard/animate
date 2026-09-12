# Compass-transfer validation — v0.9.8

## Executed in the available Racket CS runtime

A genuine Racket CS 9.3.0.8 runtime was used against this package. The following
base-only geometry suites completed successfully:

| Suite | Result |
|---|---:|
| compass-transfer checks | **7 groups / 65 checks passed** |
| standard-library checks | **68 groups / 2,562 checks passed** |
| review checks | **66 groups / 234,055 checks passed** |
| audit checks | **53 groups / 3,571 checks passed** |
| example-refinement checks | **26 groups / 387 checks passed** |
| transformation/semantic-label checks | **69 groups / 1,055 checks passed** |
| Racket reader | **81 `.rkt` modules read successfully** |

The v0.9.8 compass checks exercise the full choreography: partial pickup over the
source, parallel lift, peak source attention pulse, rigid transport with constant
length, peak target attention pulse, sweep-tip/circle-tip identity, full `2π`
sweep, disappearance at completion, radius provenance, helper aliases, fallback
behavior, diagnostics, and light/dark guide/attention styles.

The review suite verifies the seven-sample compass rows
`read/pickup/source-attention/transport/target-attention/sweep/settled`, including
inversion of the timeline smoothstep so those stills land at the requested reveal
progress.

The standard-library, audit, and refinement suites re-realize the construction
examples, including `copy-triangle-sas`, `copy-angle`, and gallery plates, so the
new presentation semantics do not change their mathematical results.

## Not executed here

The available runtime does not contain the full enclosing Animate/Pict/Draw and
RackUnit dependency set. Native bitmap/PNG rendering and the complete no-option
`geometry/run-tests.rkt` suite therefore still require the user's full Animate
checkout.

A native integration test is included in `tests/animate-test.rkt`. At a source
attention sample it checks for both `c/compass-guide` and
`c/compass-attention`; at the settled endpoint both transient visuals must be
absent.

Run locally from the Animate repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/run-tests.rkt --compass &&
"$RACKET" geometry/run-tests.rkt
```

Then inspect a new dark review/video for `copy-triangle-sas`, `copy-angle`,
`divide-segment-five`, and the gallery.
