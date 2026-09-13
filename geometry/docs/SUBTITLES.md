# Subtitle support — geometry v0.10.2

**On-screen captions remain enabled by default.** Exporting subtitles does not
remove them, add a second caption overlay, or change the construction timing.
This version uses Animate's public `subtitle`, `make-authored-timeline` and
`write-subtitles!` APIs instead of maintaining a separate SRT serializer.

## Normal video rendering

Run from the Animate repository root:

```sh
RACKET="/Applications/Racket v9.3.0.2/bin/racket"

"$RACKET" geometry/examples/copy-triangle-sas.rkt \
  --dark --workers 10 \
  --mp4 geometry-output/videos/dark/copy-triangle-sas.mp4 \
  geometry-output/dark/copy-triangle-sas
```

Output includes:

```text
geometry-output/videos/dark/copy-triangle-sas.mp4
geometry-output/videos/dark/copy-triangle-sas.srt
geometry-output/dark/copy-triangle-sas/narration.srt
geometry-output/dark/copy-triangle-sas/frame-000000.png
...
```

The sidecar next to the MP4 has the same text and timing as `narration.srt`.
The embedded subtitle track is tagged `eng` by default, so QuickTime Player can
identify it as English instead of showing `Unknown language`. Use
`--subtitle-language dan` for Danish, or another three-letter ISO 639-2 code.
The latter is retained for compatibility. The MP4 also contains that narration
as a selectable MP4 `mov_text` subtitle track. Animate performs the mux after
the visual encode and copies the video stream, so subtitle embedding does not
re-encode the picture. The separate SRT is still retained for YouTube or other
platform subtitle-file upload.

`geometry/render-all-dark.rkt` is included. Its existing command runs tests,
then every registered dark-theme example, with the gallery last:

```sh
"$RACKET" geometry/render-all-dark.rkt
```

Every MP4 now also gets its own matching SRT **and** an embedded selectable subtitle track. Workers still render frames; only
the parent writes/muxes subtitles, using the full, unsharded timeline.

## Explicit filenames and WebVTT

```sh
"$RACKET" geometry/examples/copy-angle.rkt \
  --dark --workers 10 \
  --mp4 output/copy-angle.mp4 \
  --srt output/copy-angle.en.srt \
  --vtt output/copy-angle.en.vtt \
  --subtitle-language eng \
  output/frames/copy-angle
```

`--subtitle-language CODE` controls the language metadata on an embedded MP4
subtitle track. `CODE` is a three-letter ISO 639-2 code such as `eng` or `dan`;
the default is `eng`. It does not modify the separate SRT/VTT files.

`--srt FILE` replaces the automatic MP4-sidecar filename, not the legacy
`narration.srt` in the frame directory. `--vtt FILE` is an additional, opt-in
WebVTT export. Parent directories are created as needed. Identical SRT targets
are written once; an SRT/VTT collision or a path that would overwrite the MP4
or one of its frame files is rejected before rendering.

## Export without rerendering

```sh
"$RACKET" geometry/examples/copy-triangle-sas.rkt \
  --dark --subtitles-only \
  --srt output/copy-triangle-sas.srt \
  --vtt output/copy-triangle-sas.vtt
```

This realizes the construction and compiles its timing, but renders no PNGs,
creates no frame directory, and invokes no FFmpeg. It still needs the enclosing
Animate installation, because Animate supplies the subtitle data and writer.
Use the same source version and timeline settings as the video: exporting from
a different timing revision cannot retime an already encoded movie.

`--subtitles-only` needs `--srt` and/or `--vtt`; it cannot be combined with movie,
frame, review or describe mode, or a positional frame directory.

## Captions and subtitle files are independent

No flag is needed to retain captions. `--captions` explicitly enables them;
`--no-captions` opts out of the visual caption layer. Neither flag suppresses
subtitle export. For example, this is available for a future caption-free video:

```sh
"$RACKET" geometry/examples/copy-angle.rkt \
  --dark --no-captions --mp4 output/clean-copy-angle.mp4 \
  output/frames/clean-copy-angle
```

The video has no on-screen geometry captions, but `output/clean-copy-angle.srt`
still contains the complete timed narration and the MP4 contains the same
selectable subtitle track. Point names and semantic mathematical labels are not
subtitles and remain part of the diagram.

## Racket API

```racket
(require "geometry/subtitles.rkt")

;; Native Animate subtitle values; exact times in seconds.
(define entries (geometry-timeline->subtitles timeline))

;; A real authored timeline containing the geometry scene AND subtitle metadata.
;; Captions default to #t, as they do for geometry-timeline->scene.
(define authored
  (geometry-timeline->authored-timeline timeline
                                      #:width 1280 #:height 720))

(write-geometry-subtitles! timeline "lesson.srt")
(write-geometry-subtitles! timeline "lesson.vtt" #:format 'webvtt)

;; Add an already-written SRT as a selectable track in an existing visual MP4.
(mux-geometry-subtitles-into-mp4! timeline "lesson.mp4" "lesson.srt")
(mux-geometry-subtitles-into-mp4! timeline "lesson-da.mp4" "lesson-da.srt"
                                    #:language "dan")
```

The bridge is also exported by `geometry/main.rkt`.
`geometry-timeline->authored-timeline` accepts `#:width`, `#:height`, `#:captions?`
and `#:labels`. It is intended for callers who want an actual scene with
Animate authoring metadata; it uses the existing geometry scene adapter.

The standalone writer uses a timing-only native scene as a host for Animate's
existing writer contract. It does not prepare the diagram's labels or render
its Visuals. Its output is written to a sibling temporary file and published
after successful serialization, preserving the previous file on a write failure.

The existing rendering functions also accept export destinations:

```racket
(require "geometry/render.rkt")

(render-geometry-frames! timeline "frames"
                         #:mp4 "lesson.mp4"
                         #:srt "lesson.en.srt"
                         #:vtt "lesson.en.vtt"
                         #:subtitle-language "eng")
```

`render-geometry-frames/report!` accepts the same options and retains its return
type. When `#:mp4` is supplied, the SRT selected by `#:srt` (or the automatic
same-basename SRT) is muxed into the MP4 as `mov_text`. `render-geometry-stills!`
accepts `#:srt` and `#:vtt` as well. Workers using
`render-geometry-frame-indices!` do not export fragments of a subtitle track.

## Timing and expanded helpers

`geometry-caption-cues`, now exported by the headless `geometry/core.rkt` and
focused `geometry/captions.rkt`, computes effective narration without loading
Animate. It collects cue boundaries, resolves each interval with the **same
shortest-enclosing-cue rule** as on-screen narration, and merges adjacent equal
text. A child helper's caption supersedes its parent's only for that child's
interval; the parent can resume afterward. Silent gaps are not bridged.

Zero-duration cues do not produce subtitle entries. Whitespace-only captions
are omitted when converting to native subtitle values. Exact/inexact numeric
representations of the same boundary are deduplicated numerically. Cue times
remain in seconds until Animate serializes them with millisecond precision;
they are not rounded to the movie's frame grid. Unicode point names and text
are retained, and Animate normalizes CRLF line endings in the output.

The ten-second compass default, pickup/lift/attention/transfer/sweep choreography,
and repeated five-circle construction are unchanged. Subtitle timing comes
from the final compiled timeline, so those durations and all reading pauses
are included automatically. No duration is inferred from text length.

## Review and batch integration

The gallery and all other existing examples use this support through the shared
runner. Their mathematical source and review sampling are unchanged. A direct
review command can also request external subtitle files, but those files must
remain outside the managed review directory and use a path different from the
review ZIP, so safe review reruns continue to work.

## Tests

```sh
"$RACKET" geometry/run-tests.rkt --subtitles  # base-only cue/target checks
"$RACKET" geometry/run-tests.rkt              # includes native integration
```

See `SUBTITLE-VALIDATION.md` for which checks were executed for this delivery.
