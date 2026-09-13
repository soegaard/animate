# Changes in geometry v0.10.0 — Animate subtitle bridge

On-screen captions remain **on by default**. Geometry's mathematical and visual
construction behavior is unchanged.

- Added `geometry-timeline->subtitles`, returning Animate `subtitle` values.
- Added `geometry-timeline->authored-timeline`, wrapping the existing geometry
  scene in native authored metadata without turning off captions.
- Replaced geometry's local SRT timestamp/serialization code with delegation to
  Animate's public `write-subtitles!`, including WebVTT support.
- Moved effective-caption interval projection into headless `captions.rkt` and
  re-exported `geometry-caption-cues` through `core.rkt`. Nested helper captions
  follow visual precedence, with adjacent equal-text merging and silence gaps.
- `--mp4` now automatically produces a same-basename `.srt` sidecar in addition to
  the existing frame-directory `narration.srt`.
- Added `--srt FILE`, `--vtt FILE`, `--subtitles-only` and explicit `--captions`.
  Existing `--no-captions` remains independent of subtitle output.
- Shared export planning ensures one-process and multi-process renders write
  the same complete track. Workers do not write individual subtitle tracks.
- Added destination conflict checks and atomic per-file subtitle publication.
- Included the Racket `render-all-dark.rkt` batch driver. It renders tests/examples/
  gallery in the same order, now obtaining sidecars from the shared runner.
- Added headless narration/target tests and genuine native serializer/scene
  integration tests; updated the manual and gallery usage notes.

No files outside `geometry/` are replaced. MP4 encoding, static-frame reuse,
review sampling and the accepted ten-second compass timing are unchanged.
