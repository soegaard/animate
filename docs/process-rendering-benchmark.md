# Process Rendering Benchmark

This record describes the PR-H local benchmark of the completed source-aware
project renderer. It is an evidence record for one machine, not a hardware
recommendation or a cross-platform performance claim.

## Environment and Reproduction

The measurement checkout was
`/Users/soegaard/Dropbox/GitHub/animate`, at base commit
`4b7573eb418d9d824c66c753e98a8b8961c28ad5`, with the user's existing dirty
PR-A--PR-G worktree retained. The benchmark's collection check resolved
`animate/main.rkt` to that checkout, rather than a package link.

| Component | Recorded value |
| --- | --- |
| Racket | `/Applications/Racket v9.3.0.2/bin/racket`, CS v9.3.0.2-2026-08-16-730f8aee54 |
| Host | macOS 26.5, `aarch64` |
| FFmpeg | 8.0.1 (Homebrew build) |
| TeX / SVG | TeX Live 2019 / dvisvgm 2.6.3 |
| Animate | 1.23.0, `SCENE-3D-V` |
| Logical processor count | unavailable: the local sandbox denied `sysctl hw.logicalcpu` and `hw.ncpu` |

The driver creates a benchmark-owned `PLTUSERHOME` and supplies the checkout,
installed package roots, and Racket collects explicitly. It does not copy or
change the user's package registry. It launches a fresh benchmark-parent
Racket process for every measured project invocation; this both matches normal
explicit CLI use and avoids retaining a supervisor/session across the matrix.

Run from the repository root with:

```sh
export PLTCOLLECTS='/Users/soegaard/Dropbox/GitHub:/Users/soegaard/Library/Racket/9.3.0.2/collects:/Applications/Racket v9.3.0.2/collects'
/Applications/Racket\ v9.3.0.2/bin/racket tools/benchmark-process-rendering.rkt \
  --output logs/process-rendering-pr-h --workers 1,2,4,10 \
  --repetitions 2 --fps 2 --width 1280 --height 720
```

The machine-readable result is
`logs/process-rendering-pr-h/benchmark.json`; its primary raw rows are also in
`logs/process-rendering-pr-h/benchmark.tsv`. The recorded run is
`2026-09-15T024321-benchmark1898`.

## Workloads and Method

Both normal migrated source/project paths used the dark theme, 1280 by 720
pixels, supersampling 1, and a two-frame-per-second sample grid. Geometry's
`copy-angle` rendered 115 output slots (57.5 seconds); math's
`quadratic-general` rendered 104 (52 seconds). A private warm-up was excluded
from statistics. Each primary cell used a new frame-cache root, so the timing
table measures rendering rather than persistent frame-cache reuse.

The reviewed full lessons initially made a two-repetition 10-fps matrix exceed
the approximately 6.3 GiB free local volume. That incomplete harness-owned
attempt was stopped and its exact output removed. The accepted matrix retained
the normal 1280 by 720 raster configuration but reduced the grid to 2 fps;
it is deliberately reported as such rather than presented as a full-review
render benchmark.

All post-oracle primary PNG sequences were compared byte-for-byte to the first
one-worker sequence for their workload. That is 805 geometry PNG comparisons
and 728 math PNG comparisons, all with zero mismatches. The repeated
one-worker run is included in those comparisons.

## Frame Rendering Measurements

Values are frame-executor elapsed milliseconds. Each cell has two raw runs;
the displayed median is their arithmetic midpoint. Speedup is the one-worker
median divided by the cell median. It excludes parent preparation and MP4
assembly, and therefore must not be read as end-to-end export speedup.

| Workload | Workers | Raw milliseconds | Median milliseconds | Speedup |
| --- | ---: | --- | ---: | ---: |
| copy-angle | 1 | 8743.151, 8537.356 | 8640.253 | 1.000 |
| copy-angle | 2 | 5316.172, 5237.555 | 5276.864 | 1.637 |
| copy-angle | 4 | 4928.458, 4905.328 | 4916.893 | 1.757 |
| copy-angle | 10 | 8809.082, 8909.772 | 8859.427 | 0.975 |
| quadratic-general | 1 | 8438.555, 8412.000 | 8425.278 | 1.000 |
| quadratic-general | 2 | 6871.613, 6861.919 | 6866.766 | 1.227 |
| quadratic-general | 4 | 6955.188, 6757.879 | 6856.534 | 1.229 |
| quadratic-general | 10 | 11405.959, 11528.652 | 11467.306 | 0.735 |

The useful-work reports substantiate the capacity values. All twelve primary
subprocess cells reported exactly their requested worker count both started
and completing, with every parent-owned worker resource closed. `copy-angle`
has 96 representative raster jobs and 19 valid held-frame aliases; its
two-worker assignments were 48/48 and four-worker assignments 24/24. Its two
ten-worker runs assigned 9--10 representative jobs to every worker.
`quadratic-general` has 104 representative raster jobs; its two/four-worker
splits were 51/53 and 52/52, then 27/25/26/26 in both four-worker runs, and
each ten-worker run assigned 9--12 jobs to every worker. Thus no capacity is
being credited merely for configuration or startup.

These two runs are intentionally small samples, and the ten-worker startup
cost dominates both full lessons at this grid. The results demonstrate the
actual subprocess path and useful participation; they do not establish an
optimal default worker count for other machines or longer workloads.

## Preparation, Cache, and MP4 Observations

The cold math run used the benchmark's new preference root and reported one
parent preparation, 31 parent typesetting calls, 15,863.911 ms parent
preparation, and 12,075.744 ms frame execution. The eight warm-matrix math
runs each again reported one parent preparation and 31 typesetting calls; their
median parent-preparation time was 15,448.899 ms. The shared event log contains
14 preparation events and 434 typesetting events, exactly 14 times 31,
including cold, MP4, warm-up, primary, and cache observations. No child
typesetting/preparation events were observed.

The same-root geometry cache observation was a complete hit: 115 persistent
frame-cache hits, 115 reused frames, zero raster jobs, zero worker starts, a
48.741 ms execution wall time, and a byte-identical result. The same-root math
observation did **not** hit the persistent frame cache: it started and completed
ten workers, rasterized all 104 frames, and nevertheless produced a
byte-identical PNG sequence. A separate fresh-parent reproduction found the
same source input-manifest identity but differing preparation-manifest and
payload identities, with 104 differing staged-SVG artifact descriptors out of
377. This reflects re-created math preparation artifacts; it is an important
cache limitation, so no math cache-hit timing is included in the scaling table.

One MP4 assembly was exercised at one and ten workers for each workload. All
outputs are H.264, 1280 by 720, 2 fps, and have the expected frame count and
duration. The reported assembly remainder is execution wall time minus frame
executor time; it includes residual execution orchestration and is not a
pure encoder microbenchmark.

| Workload | Workers | Frame / wall / remainder milliseconds | MP4 result |
| --- | ---: | --- | --- |
| copy-angle | 1 | 9131.502 / 9615.741 / 484.239 | 115 frames, 57.5 s |
| copy-angle | 10 | 10147.839 / 15792.981 / 5645.142 | 115 frames, 57.5 s |
| quadratic-general | 1 | 8592.102 / 9076.561 / 484.459 | 104 frames, 52.0 s |
| quadratic-general | 10 | 10886.282 / 11499.035 / 612.753 | 104 frames, 52.0 s |

The files remain under the benchmark run:
`mp4-runs/geometry-copy-angle/workers-{1,10}/movie.mp4` and
`mp4-runs/math-quadratic-general/workers-{1,10}/movie.mp4`.

## Process, Cleanup, and Architecture Evidence

During the recorded run, local `ps` access showed the benchmark driver, its
isolated parent, and a fresh `--single` parent (for example PIDs 82743, 82744,
and 83122). Parent reports for every primary subprocess run retain child PIDs,
nonzero balanced assignments, started/completing counts, and closed port/reader
resource status. This is process-identity and parent-cleanup evidence only;
local permissions do not establish a system-wide count or independently prove
arbitrary descendant cleanup after the fact.

The focused real-child suite also exercises invalid source contracts, noisy
source output, paths with spaces/non-ASCII characters, malformed protocol
messages, crash/timeout/cancellation/reload behavior, output safety, and
resource shutdown. It passed 210 tests. It is the evidence for those adverse
paths; the benchmark itself is not a cancellation experiment.

An active-source search found no remaining production geometry sharder or
duplicate final-process supervisor. Remaining `worker-shard` occurrences are
the historical plan/progress text, an untracked archival `geometry 18/` copy,
and the migration test's negative assertion. Current production clients use
the shared project executor; old terminology is retained only where it records
history or tests that removal.

## Limitations

- The result is one loaded local host, two repetitions per cell, and 2-fps
  sampling after the storage constraint; it is not a general scaling claim.
- The generic report exposes preparation and frame-executor elapsed time, but
  not separate publication or preparation-verification durations.
- The current math preparation path does not provide a stable cross-parent
  frame-cache identity, as measured above. It still preserves byte-identical
  final PNG output at every tested worker count.
- The profile and benchmark output are owned by the harness. Existing
  source-relative math SVG staging is intentionally left alone; it was already
  ignored and is not deleted by this validation.
- The benchmark JSON from this run records FFmpeg version probing as unavailable
  because the original harness probe did not resolve PATH. The external
  command and successful encoder runs establish FFmpeg 8.0.1; the harness now
  resolves the executable before probing for future runs.

## Startup Amortization and Longer-Render Scaling

The accepted two-fps measurements above remain the historical PR-H record.
This follow-up used the same dark 1280 by 720, supersampling-1 configuration
but a 10-fps `copy-angle` grid (574 frame slots). One warm-up preceded two
measured repetitions at each requested count. The harness compares the
per-frame SHA-256 manifest with the one-worker oracle before deleting each
benchmark-owned PNG/cache root.

The initial 10-fps run showed serial startup dominating higher worker counts.
`process-frame-executor.rkt` now starts requested children concurrently and
collects results in deterministic slot order. The first run after that change
found a frame-158 reuse mismatch, traced to the renderer's existing inexact
animated-clock arithmetic at a timeline boundary. The reuse planner now
mirrors that arithmetic; it does not change scene construction, sampling, or
the scheduler. The table is the rerun after that correction, not the invalid
intermediate geometry result.

| Workers | Raw executor ms | Midpoint ms | Speedup | Started / completing | Ready-barrier ms | Raster span ms | Publication ms |
| ---: | --- | ---: | ---: | --- | --- | --- | --- |
| 1 | 44230.940, 44640.976 | 44435.958 | 1.000 | direct / n.a. | n.a. | n.a. | n.a. |
| 2 | 16428.839, 16574.676 | 16501.758 | 2.693 | 2 / 2, 2 / 2 | 815.284, 927.734 | 15394.484, 15486.557 | 213.157, 155.750 |
| 4 | 9248.330, 9425.650 | 9336.990 | 4.759 | 4 / 4, 4 / 4 | 906.559, 893.332 | 8141.471, 8347.783 | 195.617, 173.619 |
| 10 | 7350.446, 7998.224 | 7674.335 | 5.790 | 10 / 10, 10 / 10 | 1399.123, 1340.109 | 5628.192, 6295.001 | 318.481, 356.601 |

Every 2/4/10-worker run launched the requested real children, reported every
child ready and completing, assigned useful representative jobs (185--187 per
child at two workers, 92--94 at four, and 37--38 at ten), and closed its owned
resources. The retained reports include child PIDs and per-child spawn, hello,
source-ready, ready-latency, and raster-span values. All 574 outputs in every
measured cell were byte-identical to the one-worker SHA-256 oracle. The
ten-worker pair differed by 8.4%, so no third repetition was required. A
30-fps matrix was not run because this normal 10-fps workload already made the
startup and useful-work conclusion clear.

The compact retained reports are in
`logs/process-rendering-pr-h-addendum-parallel-startup-evidence/matrix-geometry-after-clock-align/`.
The 12 primary frame/cache roots, older frame-158 investigation roots, all
eight benchmark-owned MP4 `movie-frames` directories, and two old
harness-owned profile caches were removed after comparison. The retained
manifest reports occupy about 1.1 MiB; JSON/TSV records and useful MP4 evidence
remain. No user-owned output or source-relative math staging was deleted.

The same follow-up repaired math preparation identity by canonicalizing direct
glyph-path definition order in staged SVG `defs` blocks. A fresh-parent
comparison had found 204 of 377 artifacts differing only in that order. After
the repair, a 519-frame run followed immediately by its same-root repeat had a
complete persistent hit: the first rendered 519; the repeat rendered zero,
reused 519, reported 519 persistent hits, started zero workers, and had the
same PNG manifest. This verifies cache identity without treating preparation
time as frame-executor scaling.

Process observations remain intentionally bounded: local permitted `ps`
sampling and the retained parent reports establish owned workers, useful work,
and parent-side closure. They do not establish a global process count or prove
cleanup of arbitrary descendants after exit.

## Production-Rate Math Scaling

This PR-H completion addendum measures the normal, migrated
`math/examples/quadratic-general.rkt` presentation at its actual 30-fps rate:
1,557 frames / 51.9 seconds, dark, 1280 by 720, and supersampling 1.  It is a
math-only matrix; it neither changes the production scheduler nor reruns the
separate 519-frame persistent-cache result recorded above.

The exact command was:

```sh
/Applications/Racket\ v9.3.0.2/bin/racket tools/benchmark-process-rendering.rkt \
  --output logs/process-rendering-pr-h-production-rate-math \
  --workloads math-quadratic-general --matrix-only \
  --workers 1,2,4,10 --repetitions 2 --fps 30 --width 1280 --height 720
```

The release-validation harness gained the narrowly scoped `--workloads` and
`--matrix-only` options so this evidence can select the existing math workload
without also measuring geometry, MP4, or cache probes.  The selected workload
still uses the normal direct one-worker path and the normal shared subprocess
executor above one worker.  A single warm-up established a benchmark-owned
SVG/preparation cache; it was not included in the table.  The existing matrix
order (1, 10, 2, 4) only avoids host spin between cells; it does not change the
scheduler or output order.

| Workers | Raw frame-executor ms (two repetitions) | Midpoint ms | Speedup vs. 1 | Execution-wall midpoint ms | Parent preparation midpoint ms | End-to-end midpoint ms |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 129015.751, 126463.778 | 127739.764 | 1.000 | 128556.760 | 16704.309 | 145261.569 |
| 2 | 68349.700, 72206.064 | 70277.882 | 1.818 | 71666.884 | 15577.699 | 87245.092 |
| 4 | 41381.008, 41786.455 | 41583.732 | 3.072 | 42832.310 | 15948.820 | 58781.617 |
| 10 | 31409.308, 31324.708 | 31367.008 | 4.072 | 32606.874 | 16362.422 | 48969.859 |

`End-to-end` is parent planning plus parent preparation plus execution wall
time (parent planning was 0.471--0.589 ms per measured invocation).  The
primary speedup number intentionally remains frame-executor time, so it is
not distorted by parent preparation which is outside the executor.  No cell
varied by more than 10% (1: 2.0%, 2: 5.5%, 4: 1.0%, 10: 0.3%), so the stated
two-repetition rule did not require a third run.

All invocations reported exactly one parent preparation and 31 parent typeset
events.  Worker processes consume that prepared payload; the combined event
logs contain 9 preparations and 279 typesets, exactly one warm-up plus eight
measurements, with no worker-side preparation/typeset activity.  The
one-worker reports are intentionally direct, so they have no worker PIDs or
subprocess timing breakdown.  The subprocess reports were:

| Workers | Ready / completing | Child PIDs (first; second repetition) | Startup / raster / publish ms (first; second repetition) | Assignments (first; second repetition) |
| ---: | --- | --- | --- | --- |
| 2 | 2 / 2; 2 / 2 | 37413,37414; 37609,37610 | 1363.952 / 66774.884 / 188.925; 1406.737 / 70566.868 / 209.436 | 779,778; 778,779 |
| 4 | 4 / 4; 4 / 4 | 37868--37871; 38007--38010 | 1667.216 / 39457.636 / 233.334; 1667.696 / 39831.138 / 253.728 | 388,390,390,389; 389,387,392,389 |
| 10 | 10 / 10; 10 / 10 | 37171--37180; 37309--37318 | 2798.539 / 28175.683 / 413.099; 2768.879 / 28103.257 / 430.826 | 157,156,156,154,157,155,156,156,156,154; 156,155,156,156,157,154,155,156,156,156 |

The compact one-worker SHA-256 manifest is retained in the benchmark JSON.
Each of the other seven runs compared every one of its 1,557 frames with that
oracle and was byte-identical.  Owned PNG frame roots and frame-cache roots
were deleted immediately after successful comparison.  After the reports were
retained, the benchmark-owned `pltuserhome` SVG/preparation cache (4 MiB) was
also deleted.  The substantive retained output is limited to the benchmark
JSON/TSV, event logs, and compact per-run reports under
`logs/process-rendering-pr-h-production-rate-math/`; no user-owned
`math-output`, review render, or source-relative cache was touched.

This longer render gives useful work enough time to amortize startup: ten
workers are 4.072x faster than direct execution on this host, and four are
3.072x faster.  The earlier 2-fps sample had only 104 frame slots and was
dominated by startup relative to work; at 30 fps the ten-worker startup
barrier is about 2.77--2.80 seconds while the raster span is about 28.10--28.18
seconds.  This is one host with two repetitions, not a default-worker-policy
change or a general hardware scaling claim.

Local `ps` snapshots observed the outer benchmark process (35682), isolated
driver (35683), a subprocess parent (37499), and its two explicitly launched
worker children (37609 and 37610).  Per-run reports additionally record the
listed PIDs, nonzero assignments, all ready/completing counts, and closed owned
resources.  This establishes local process identity and parent-side cleanup
for the observed runs.  Local permissions do not establish a system-wide
process count or independently prove arbitrary descendant cleanup after exit,
so neither is claimed.
