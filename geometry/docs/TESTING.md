# Testing — geometry v0.6.0

## Validation performed for this archive

The baseline geometry/example source hashes were checked against Animate commit
`1e6610cd4fbe6e6224c87a9e55e4949a6ca54a05`. New native API signatures were read
from the same revision. Local validation checks reader delimiters, module and
test-body structure, local require targets, the acyclic geometry dependency
graph, changed-file inventory, and ZIP integrity.

**Racket is not installed in this build environment.** The compiler, RackUnit
tests, example videos, and native font measurements have **not been executed**
here. The archive does not claim an execution pass or benchmark result.

## Local verification

From the Animate checkout root, after replacing `geometry/`:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt
```

There are 107 named RackUnit cases in the registered test files (74 retained,
33 new). To run the headless compiler/math/layout subset:

```sh
"$RACKET" geometry/run-tests.rkt --core
```

New test files:

| File | Cases | Focus |
|---|---:|---|
| `reveal-test.rkt` | 15 | Endpoint/clipping semantics, circle directions, progressive glyphs, helper metadata, unchanged marker dimensions. |
| `annotation-test.rkt` | 13 | Measurer callback, temporal masks, explicit hints, marker notation, conflicts, deterministic placement, theme inheritance. |
| `reveal-annotation-render-test.rkt` | 5 | Native font measurement, actual label strings, scene sampling, gallery construction, light/dark rasterization. |

## Gallery check

```sh
mkdir -p geometry-output/videos/light geometry-output/videos/dark
for mode in light dark
do
  "$RACKET" geometry/examples/gallery.rkt \
    --"$mode" --workers 10 \
    --mp4 "geometry-output/videos/${mode}/gallery.mp4" \
    "geometry-output/${mode}/gallery" || break
done
```

`--describe` also prints measured annotation warnings and label locations without
writing frames. It still loads the native adapter to measure text.

See `GALLERY.md` for visual review targets. Automatic placement is heuristic;
inspect warnings and use a hint when a diagram remains too dense. As before,
worker count alone is not a measurement of simultaneous CPU execution; the
example runner retains its process-based renderer and global-frame merge.
