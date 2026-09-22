# Inline TeX coverage inventory

This inventory is enforced by `slides/tests/inline-tex-conformance-test.rkt`.
Its first case enumerates `layout-names` and each layout's `slot-spec` records
at run time, so adding a text-capable built-in slot cannot silently bypass the
shared content path.

| Author-facing surface | Preparation route | Conformance destination |
| --- | --- | --- |
| Every built-in layout slot, title, subtitle, columns, theorem/quotation/caption text, and footer | `single-asset` → `text-asset` | Generated built-in-surface case, light/dark × wide/portrait × left/center/right |
| Custom roles and named text slots | `single-asset` → `text-asset` | `inline-tex-test.rkt`, custom-layout case |
| `make-slide`, `slot-content`, `paragraph-content`, literal and explicit content | `text-source` → `text-asset` | Conformance explicit-content case |
| Bullets and ordered markers | `bullet-assets` → `text-asset` | `inline-tex-test.rkt` and conformance semantic-child case |
| Semantic child text | `prepare-semantic-group` → `prepare-content` | Conformance semantic-child case |
| Hidden content, replacements, reveal/emphasis and Scene output | all variants measured by `resolve-slide` | `inline-tex-test.rkt` |
| Parent-prepared Pict and project workers | `codec.rkt` recorded Pict artifact | `inline-tex-worker-test.rkt` with two subprocess workers |
| Calculus `#:say` captions | `prepare-caption-assets` → shared `prepare-inline-text` | `calculus/tests/render-smoke-test.rkt` |
| SRT/WebVTT, speaker notes, audio metadata and low-level `draw-text` | intentionally literal/plain | Existing media/narration tests; excluded from TeX parsing |

The baseline for this implementation was `f1bd4f98` (the plan's stated
starting revision). Development validation uses Racket 9.3.0.2 and the
repository `latex-pict` backend. The inventory deliberately excludes source
code, URLs, diagnostics, and arbitrary Picts/Visuals: they do not travel
through a slide text slot and must remain literal.
