# Validation status — gallery, semantic matching, and geometry workers v0.4.0

17 September 2026

## Completed validation

Using `/Applications/Racket v9.3.0.2/bin/racket`, the public slide modules were
compiled and the complete command below passed with **105 named cases across 16
suite files** and no failures or errors.

The run covered the gallery catalogue and transition sampler, semantic matching,
actual TeX-backed math preparation, native geometry, media probing, ordinary
subprocess projects, prepared-geometry codec round trips, and parent-only
geometry preparation accounting. It also rendered a real gallery MP4 for the
`semantic-geometry` entry with two subprocess workers and exercised a mixed
math/geometry subprocess case.

This is functional and targeted native-rendering evidence. It does not claim a
full visual review of every gallery entry on every platform; use a fresh gallery
output directory for that acceptance step.

## Reproduce the suite

From the repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
RACO="/Applications/Racket v9.3.0.2/bin/raco"

"$RACO" make \
  -l animate/slides \
  -l animate/slides/pict \
  -l animate/slides/scene \
  -l animate/slides/render \
  -l animate/slides/math \
  -l animate/slides/geometry \
  -l animate/slides/project \
  -l animate/slides/gallery \
  slides/run-gallery.rkt

"$RACKET" slides/run-tests.rkt --math --geometry --media --project
```

## Visual acceptance

```sh
"$RACKET" slides/run-gallery.rkt --list

"$RACKET" slides/run-gallery.rkt --dark --videos --workers 10 \
  slides-output/gallery-v040

"$RACKET" slides/run-probes.rkt --repeat 2 --gallery --math --geometry \
  slides-output/layout-review-v040
```

Inspect the generated `index.html`, transition interiors and boundaries, light
and dark contrast, portrait layout, semantic continuity, and the manifest's
worker/preparation diagnostics. `slides-output/` and the root preparation cache
are intentionally ignored by Git.

## Deliberate limits

No distributed-host renderer, automatic speedup guarantee, portable custom
renderer factory, font-transfer system, or persistent cache reuse for opaque
prepared/native content is added. Geometry is portable only through the closed
prepared-data codec; unsupported opaque extensions are rejected rather than
silently rerun or rasterized in a worker.
