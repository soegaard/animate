# Changes in geometry v0.10.1 — selectable MP4 subtitle tracks

- `--mp4` continues to write a same-basename `.srt` sidecar and now also muxes
  that SRT into the MP4 as a selectable `mov_text` subtitle stream.
- On-screen captions remain enabled by default. `--no-captions` affects only the
  rendered geometry caption layer; it does not suppress the SRT or MP4 track.
- Subtitle muxing delegates to Animate's existing `mux-authored-video!` API.
  The video stream is copied, so the subtitle step does not re-encode frames.
- The mux is published through a sibling temporary MP4. If FFmpeg fails, the
  visual-only MP4 remains intact and the SRT sidecar is preserved.
- Single-process and process-sharded example rendering both perform the final
  mux in the parent process from the complete geometry timeline.
- `mux-geometry-subtitles-into-mp4!` is available as a public geometry bridge
  for an already encoded MP4 plus SRT.

QuickTime Player should now expose the embedded track through its subtitle menu.
The separate SRT remains useful for YouTube upload and external editing.
