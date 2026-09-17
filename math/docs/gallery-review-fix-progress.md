# Math gallery review repairs — local validation record

This record accompanies the September 17, 2026 gallery-review repair. It records
the local checkout and commands actually run; it does not identify a rendered
bundle with a Git commit.

## Baseline

- Checkout: `02728e0` with unrelated user work already present; none of that work
  was reset, staged, or included in this repair.
- Racket: `/Applications/Racket v9.3.0.2/bin/racket` (Racket 9.3.0.2).
- Collection resolution: the local `animate/math` checkout.
- Before the repair, `math/run-tests.rkt` and `math/run-gallery-tests.rkt` each
  had one failing gallery assertion: no active tree marker matched the expected
  `> ` form. `math/run-style-checks.rkt` passed.

## Implemented repairs

- Parent preparation now measures and freezes each gallery replay's headers,
  caption/API band, body rectangle, formula envelope, row origin, capacity, tree
  column, inset allocation, and nearby candidate-verdict location. Workers replay
  the versioned `animate-math-gallery-view-v2` payload without refitting.
- Implicit and explicit unit-factor cancellation establishes newly created unit
  material at a survivor-relative target arrangement before the common move. The
  final prepared endpoint and separate `remove-unit` step remain unchanged.
- Hierarchy markers and labels are separate left-anchored visuals; leaf emphasis
  uses bold text while markers remain stationary. Candidate wording is limited to
  the evidence actually available from `check-solution`.
- The grouping/history comparisons share the short `E0`–`E3` arithmetic
  derivation. The distribution plate has a trace-validated one-to-two witness, and
  recipe views show their actual calls.
- Review probes now include early/middle/late compact and reveal fractions. Review
  records have semantic keys and contact sheets use two readable label lines.

## Validation run after the repair

| Command | Result |
| --- | --- |
| `racket math/run-tests.rkt` | 16,760 checks passed; 0 failed |
| `racket math/run-gallery-tests.rkt` | 14,661 checks passed; 0 failed |
| `racket math/run-style-checks.rkt` | 1,335 checks passed; 0 failed |
| `racket math/run-process-contracts.rkt` | 6 fresh-process contracts / 12 processes passed |
| `raco make math/main.rkt math/render.rkt math/cas.rkt math/examples/*.rkt` | passed |
| `git diff --check` | passed |

Two real-native review selections also completed with Animate, TeX, and the local
Racket installation: 18 deterministic checkpoint stills covering factor
cancellation, distribution, and implication at 640×360; and 30 dense stills for
factor cancellation and distribution. Their output directories are temporary
paths outside the repository and are not delivery artifacts. The second selection
visually covered the compact fractions from 5% through 95% and the post-transition
copy witness. This is targeted native evidence, not a claim that a full 30-fps
gallery movie has received pacing review.
