# v0.8.0 — sparse review bundles

- Three images per authored step, with recursively expanded helper steps by default.
- Authoritative compiled step boundaries and exact read/during/settled states.
- Mid-action selection excludes pauses and avoids shared action endpoints.
- Correct zero-delay/zero-pause captions; notes for no-op and instantaneous steps.
- Six-row contact-sheet pages, complete narration, offline HTML index, JSON manifest.
- `--review-stills DIR`, `--review-zip FILE`, optional top-level-only/no-contact-sheet.
- `review-examples.rkt --example NAME | --all | --library`, plus `--list` and theme selection.
- One ZIP per example/theme, staged writes and safe managed-directory replacement.
- All 17 example definitions can be loaded headlessly; native rendering is loaded on demand.
- Existing geometry, reveal shapes, layout policy, default timing and process movie renderer preserved.
- New base-only review test groups and native contact-sheet/PNG integration tests.

The implementation extends the complete delivered v0.7.0 folder; no outer Animate
repository files are replaced. Racket-native API usage was checked against commit
`74798a8a97be8778e46995c2c0d139f705c8cd8d`.
