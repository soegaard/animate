# Changes in geometry v0.10.2 — MP4 subtitle language metadata

- Embedded MP4 subtitle tracks now default to ISO 639-2 language code `eng`.
- QuickTime Player should therefore show **English** rather than **Unknown language**.
- Added `--subtitle-language CODE`; e.g. `--subtitle-language dan` for Danish.
- `encode-geometry-mp4!`, `render-geometry-frames!`, and
  `render-geometry-frames/report!` accept `#:subtitle-language`.
- `mux-geometry-subtitles-into-mp4!` accepts `#:language`.
- The language metadata pass uses FFmpeg stream copy; no video/audio re-encode.
- SRT and WebVTT sidecars remain byte-for-byte unchanged.
- On-screen captions remain enabled by default.
