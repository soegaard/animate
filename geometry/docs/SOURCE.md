# Source and integration notes — v0.6.0

Repository baseline: `soegaard/animate` at
`1e6610cd4fbe6e6224c87a9e55e4949a6ca54a05` ("Updated geometry DSL").
The geometry source and example blob hashes were compared with the repository
through the GitHub connector. They match the v0.5.5 starting archive used here.

New integration points were reviewed against that revision:

- `private/pict-adapter.rkt`: `visual->pict` accepts a Visual and a positional
  camera argument and returns a Pict. Used for native text measurements.
- `private/text-visual.rkt`: `plain-text` and `paragraph` accept world-space font
  sizes and the existing family/face/style/weight properties.
- `private/visual-model.rkt`: `make-path-visual` accepts `#:id`, `#:fill`,
  `#:stroke`, and cosmetic `#:stroke-width`.

The adapter continues to require the parent checkout's public `main.rkt`,
`colors.rkt`, and `render.rkt`; it does not import a separate installed Animate
copy or replace parent repository files.

The old proposal at `geometry/animate-mathematical-authoring-dsl.md` is now kept
in sync with the implementation reference at `docs/MANUAL.md`. The original
proposal remains available in the baseline Git history.

No source/API inspection here constitutes an executed native render. See
`TESTING.md` for the validation boundary.
