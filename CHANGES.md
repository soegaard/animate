# Changes

## 1.8.0 — SCENE-EM

This is an intentional API cleanup release, not a compatibility release.

- Rendering, encoding, and media assembly now belong to `animate/render`.
  `animate` remains headless and provides semantic scene construction and pure
  sampling.
- Live layout relations are named `follow-above`, `follow-below`,
  `follow-left-of`, and `follow-right-of`, making their continuing dependency
  explicit; the former `keep-*` spellings were removed.
- Complete render/preview declarations now live in `animate/project`, with a
  pure normalization and planning phase before source preparation or output.
- The registered Scribble manual is split into guide, concept, reference, and
  cookbook chapters.
- Formula string transitions retain immutable source-match plans for preview
  inspection.

Examples, tests, and documentation in this repository use the current module
layout. No deprecated aliases are provided.
