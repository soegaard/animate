# v0.9.0 source provenance

Implementation baseline: the complete delivered
`animate-geometry-v0.8.3-example-refinements-20260912.zip`, SHA-256:

```text
1f7a45830a8c8dcbb69e538b9d20a204070cdac7f8f6e0e6dfce1e282d1fb797
```

The connected `soegaard/animate` repository's observed default-branch head was
`bf61135fabe059c5b8b98d6786a417c55062ac3e`. That checkout precedes delivered
geometry-only refinements, so its older geometry files were not used to overwrite
the v0.8.3 baseline. Native calls use existing Animate interfaces already used by
the adapter; no files outside `geometry/` are replaced.

The genuine minimal Racket CS 9.3.0.8 runtime was used for headless checks and a
reader pass. No runtime binaries, dependency packages, fonts, generated PNGs, or
native renderer substitutes are included in the ZIP. See
`TRANSFORM-LABEL-VALIDATION.md` for the executed-test boundary.

---

## Prior source records (historical)

# Source and integration notes — v0.8.3

This package extends the delivered **v0.8.2.2** archive, retaining the static-frame
renderer and its delimiter/import fixes rather than copying older repository
files over them. The connected repository was checked and returned commit
`bf61135fabe059c5b8b98d6786a417c55062ac3e` (geometry v0.8.1); its helper source was
read to verify the base algorithms and naming.

Baseline archive: `animate-geometry-v0.8.2.2-static-frame-reuse-import-fix-20260912.zip`

SHA-256: `e8dc5668457ceaaf95fa8e8141c55fb7753f59a366602b640829f58ed7b2c0f3`

Only `geometry/` is replaced. `render.rkt`, `tests/animate-test.rkt`, the process
runner and review-output implementations remain byte-identical to v0.8.2.2.
This version changes example geometry/presentation, shared helper point names,
annotation hints and the fixed ordering of drawable objects. Added regression
files and documentation are listed in `CHANGES-0.8.3.md`.

The manual copies are identical. Runtime binaries, third-party sources, fonts,
review images and temporary diagnostic scripts are not distributed in this ZIP.
See `TESTING.md` for executed checks and the native-rendering boundary.

---

## Historical baseline notes (v0.8.1)


This release extends the **delivered v0.8.0 review-bundle package**, not an older
checkout. That is the package used to generate the user's supplied native review
images. The repository main was read through the connected GitHub source and
was at `c6903574f2326778fe900f474317a3a186415569` during this audit (geometry v0.7.0).
Its older geometry files were not copied over the delivered v0.8.0 sources.

Baseline archive:
`animate-geometry-v0.8.0-review-bundles-20260912.zip`

SHA-256:
`4d53daa4482b6559d6cd05c5b7298115ca3b54643c7481a3ef404be5876b1006`

Review input:
`geometry-review-upload-20260912-022955.zip`

SHA-256:
`2627fdcbb060cb538fe29c557ff4d2a732fc421c385d2dabf1e7f48359df2bda`

Only a complete replacement `geometry/` directory is delivered. The outer
`main.rkt`, `render.rkt`, `colors.rkt`, renderer, codecs, and dependencies are not
modified. Process-based full-video rendering and sparse native review rendering
retain their existing implementations. The only rendering adapter change is
consistent world-relative caption sizing; new native tests use existing APIs.

The two manual copies (`docs/MANUAL.md` and
`animate-mathematical-authoring-dsl.md`) are identical. Runtime binaries, font
files, the user's review images, and temporary build scripts are not included.
Testing used the available upstream Racket CS 9.3.0.8 minimal runtime. Native
macOS/Pict/Draw validation is explicitly separate; see `TESTING.md`.
