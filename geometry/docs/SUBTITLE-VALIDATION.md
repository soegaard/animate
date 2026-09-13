# Validation — geometry v0.10.2

v0.10.2 is a small media-output refinement over the previously validated
v0.10.0 subtitle bridge. The mathematical construction, timeline, caption cue,
compass, layout, and review semantics are unchanged.

## Checks executed for this delivery

The current container does not provide Racket, so the full Racket suite could
not be executed here. The following checks were executed instead:

- all modified Racket modules were checked for balanced reader delimiters;
- both MP4 production paths were inspected to confirm that single-process and
  process-sharded rendering call the same `encode-geometry-mp4!` finalizer;
- the SRT chosen for MP4 muxing is the explicit `#:srt` destination when given,
  otherwise the same-basename MP4 sidecar;
- the sidecar is written before muxing and is not deleted or modified by the
  MP4 replacement step;
- FFmpeg 7.1.5 was exercised with the same no-audio mux shape used by Animate's
  `mux-authored-video!`; `ffprobe` reported a `mov_text` subtitle stream with
  default disposition;
- source inspection confirmed that Animate's public `mux-authored-video!`
  performs video stream-copy (`-c:v copy`) when no authored audio is present.

QuickTime Player is not available in this environment, so final UI playback
verification must be done on macOS.

## Native regression tests added

`tests/subtitle-render-test.rkt` now includes native integration cases that:

- mux a generated visual MP4 through `mux-geometry-subtitles-into-mp4!` and use
  `ffprobe` to require `codec_name=mov_text`;
- retain the external SRT byte-for-byte after muxing; and
- run the actual geometry example CLI with both one process and process-sharded
  rendering, then require a `mov_text` stream in each resulting MP4.

`tests/subtitle-checks.rkt` also checks the pure MP4-sidecar selection rule.

## Run locally

Run the complete suite in the Animate checkout:

```sh
"/Applications/Racket v9.3.0.2/bin/racket" geometry/run-tests.rkt
```

Then render one short example and inspect the MP4 in QuickTime Player. The
subtitle menu should expose the embedded track while the `.srt` remains beside
the movie for YouTube upload.


## v0.10.2 language metadata

The native FFmpeg integration test now requires `language=eng` on the default
embedded subtitle stream and verifies that an explicit `DAN` request is
normalized to `dan`. The one- and two-worker CLI MP4 tests also require the
default `eng` tag.
