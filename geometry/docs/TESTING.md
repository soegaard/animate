# Validation — v0.7.0 standard constructions

## Executed in this delivery

A real minimal Racket CS runtime was obtained from the upstream Racket CI
artifact built at `dc4456af0d76f4193364e1879922ce0233f32529`. It reports
**Racket 9.3.0.8 [cs]**. The user's selected macOS runtime is 9.3.0.2; no macOS
rasterization test is claimed from a Linux run.

Executed successfully:

```sh
racket geometry/run-tests.rkt --library
```

Result: **68 named groups, 2,422 checks passed**. The source is
`tests/library-checks.rkt`; it requires only Racket base and the actual geometry
implementation. `tests/library-test.rkt` registers these same groups in RackUnit.
No mock geometry or substitute rendering backend is used to obtain this result.

Coverage includes the eight signatures/algorithm graphs; translations,
rotations, scales 0.01/1/40 and reflected inputs; internal angle bisectors for
acute/right/obtuse angles; both target sides of angle copying; invalid inputs;
independent midpoint/projection/angle/triangle-center oracles; false relations;
postcondition-vs-layout separation; step assertions; repeated/nested helper calls;
cleanup protecting caller inputs/results; and two prefixes for one re-exported
helper. It also loads all thirteen application modules in light and dark themes,
checks their results independently, samples forward/backward and in ten shards,
and checks reveal progress and repeatable estimated annotation placement.

The updated gallery passes estimated annotation preparation without warnings
in both themes. Some expanded helper intermediates in application examples
still produce label/curve-overlap warnings with the conservative estimated
font boxes. No application annotation is outside the safe region in these
checks. These results do not substitute for native font measurements.

Also checked: Racket reader acceptance of every Racket source, shell syntax of
the batch renderer, baseline tree hash, and archive contents/integrity.

## Not executed here

The minimal runtime does not include the complete Animate/pict/draw dependency
set or the RackUnit/raco-test packages. Therefore the **complete existing
RackUnit suite** and **native scene/bitmap/PNG tests** were not executed here.
No generated MP4 or native screenshot is included as purported evidence.

`tests/library-render-test.rkt` adds native scene sampling and rasterization
checks for all thirteen examples in both themes, plus still-image/subtitle
output. These are included for the full local environment.

## Run locally

From the `animate` repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
"$RACKET" geometry/run-tests.rkt --library
"$RACKET" geometry/run-tests.rkt
```

`--library` runs only the base-only new suite and stops immediately on failure.
The normal command uses the same Racket executable to run all registered
RackUnit modules and preserves a nonzero exit status. `--core` runs the
non-native RackUnit modules, including the library tests.

Render all thirteen application videos in both themes:

```sh
RACKET="$RACKET" WORKERS=10 sh geometry/examples/render-library.sh both
```

Render the updated gallery separately:

```sh
"$RACKET" geometry/examples/gallery.rkt --dark --workers 10 \
  --mp4 geometry-output/videos/dark/gallery.mp4 geometry-output/dark/gallery
```

For inexpensive first visual inspection, run an example without `--frames` or
`--mp4` to produce step stills. `--describe` reports native annotation warnings
without writing frames. Review the selected circle intersection, copied-side
orientation, auxiliary cleanup, equal-length/equal-angle marks, and label
collisions at the final output size.
