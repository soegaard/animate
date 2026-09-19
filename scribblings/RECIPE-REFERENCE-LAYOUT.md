# Reference and worked-example ownership

## API reference

| Source | Contents |
|---|---|
| `reference/coordinate-decorations.scrbl` | Number lines, coordinate conversion, ticks, grid lines, and numeric labels. |
| `reference/markers-scatter-and-areas.scrbl` | Marker shapes, scatter plots, sampled function areas, and data areas. |
| `reference/statistical-diagrams.scrbl` | Bar charts, histograms, sample spaces, probability trees, box plots, error bars, and their named paths. |

## Worked examples in the Cookbook

| Source | Contents |
|---|---|
| `cookbook/appearance-and-text-effects.scrbl` | Entrance/exit/text effects; stroke width; fill/stroke colors; unified styles. |
| `cookbook/camera-views-and-overlays.scrbl` | Animated views; fitting/following; frame-fixed titles and callouts. |
| `cookbook/animation-timing-recipes.scrbl` | Local timing; succession; parallel and lagged composition; duration scaling. |
| `cookbook/path-motion-recipes.scrbl` | Arc-length following; tangent orientation; joined offsets; reversal and cyclic starts. |
| `cookbook/path-correspondence-recipes.scrbl` | One-loop/open-path alignment; compound pairing; mixed-topology correspondence. |
| `cookbook/topology-morph-recipes.scrbl` | Subpath birth/death; shared and per-subpath anchors/penalties; per-pair costs. |
| `cookbook/plot-styling-recipes.scrbl` | Combining a function area, graph, and observation markers. |

The former catch-all file is removed. Its original explicit heading tags follow
the moved content; links should use those tags, not generated HTML filenames.
No API declaration is copied into a Cookbook chapter. The original API defaults,
complete descriptions, code examples, and render commands are moved without
rewriting them. This operation does not change the separately maintained
Visuals reference inventory or renderer implementation.

`reference/recipe-redistribution-inventory.json` records the original source hash,
destination ownership, complete declaration and signature hashes, example hashes,
and the exact source-range allocation. Its size figures describe installation
time, not a permanent length restriction.

Run `python3 scribblings/check-reference-recipes.py .` for normal structural,
signature, example, and tag checks. When the prose guard is installed, this also
checks the migrated Cookbook pages for development-history labels. Immediately
after installation, add `--strict-preservation` to reconstruct the original
source exactly from the moved ranges. Later prose edits do not need a new
signature baseline, but intentional API/example changes require updating the
corresponding inventory entries after review.

Run `raco test tests/reference-recipes-test.rkt` to read and expand the ten
Scribble documents. Display-only `racketblock` and `verbatim` examples are not
executed by that test. The full manual build checks the combined reference
context and generated cross-references.
