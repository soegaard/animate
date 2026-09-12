# Changes in v0.9.2

## Semantic-number formatting

Measured semantic labels with `#:precision 0` now omit the dangling decimal
point that `real->decimal-string` can produce. Thus a right angle renders as
`90°`, not `90.°`, and an integer length renders as `5`, not `5.`. Rounding
behaviour for all precisions is otherwise unchanged.

Regression checks cover both zero-precision angle and length labels.
