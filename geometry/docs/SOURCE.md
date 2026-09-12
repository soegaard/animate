# Source and integration notes — v0.8.1

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
