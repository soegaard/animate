# Source and integration notes — v0.7.0

Baseline: `soegaard/animate` commit
`74798a8a97be8778e46995c2c0d139f705c8cd8d` ("Update geometry DSL").
The repository was read through the GitHub connector. The extracted v0.6.0
starting archive's Git tree hash was computed as
`dd6fa9deac1ab44528c08370acaf8e55f2f8fd31`, exactly matching that commit's
`geometry/` tree. The implementation therefore preserves the user's current
geometry changes rather than returning to an earlier prototype.

Only the replacement `geometry/` folder is delivered. The parent `main.rkt`,
`colors.rkt`, `render.rkt`, and native rendering implementations are not changed.
The process-based frame renderer is preserved. New examples use the same runner,
with lazy adapter loading so that their geometry can also be tested headlessly.

New headless entry point: `geometry/constructions.rkt`.
Eight algorithms: `geometry/constructions/foundations.rkt`.
The two manual copies (`docs/MANUAL.md` and
`animate-mathematical-authoring-dsl.md`) are identical.

Testing runtime: upstream Racket CS 9.3.0.8 CI build, commit
`dc4456af0d76f4193364e1879922ce0233f32529`. The downloaded runtime is used only
for validation and is not included in the archive. See TESTING.md for executed
checks versus native integration tests that still require the user's full
installation.
