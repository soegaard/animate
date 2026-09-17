# Frame illustrations in the manual

Show the result immediately after the example that produces it.

## Borders and rows

Give every captured frame a neutral **one-CSS-pixel border**. Add the border in
the manual, not in the captured PNG or SVG. Its thickness must not change when
an image is displayed at a different size. Do not crop or paint over an existing
capture to make it fit. The print equivalent is a 0.75-point rule (a big point,
1/72 inch); physical screens do not have a universal one-device-pixel size.

Prefer **one row of three or five frames**, in time order. Use the same displayed
width and preserve each image's aspect ratio. Keep each time caption immediately
below its own frame. Captions and their frames must wrap together, not as separate
rows. A width or format comparison may deliberately mix aspect ratios.

In HTML the shared layout wraps when the available content width cannot hold all
frames at 112 CSS pixels each, with 8-pixel gaps. Thus five fit on one row at
592 pixels of content width. On narrower pages the row wraps; it never forces
horizontal scrolling. Frames stay the same width when the last row is incomplete.
A single still is at most 360 pixels wide; other frames are at most 260 pixels.

Print output fits the chosen row to the current text width. For a text-heavy
example that is unreadable at that scale, select two or three columns explicitly
and explain the exception. Do not rely on a hidden, fixed two-column default.

## Use the shared helpers

The existing calls keep working:

```racket
@frame-strip["push-left"]
@three-d-frames["object-motion"]
@learning-frames["together"]
```

Each key must exist in its own catalogue; use the current catalogue's IDs.
No image regeneration is required after a border or layout change. The source
images and capture manifests remain unchanged. Legacy `columns` metadata in the
r2 capture catalogue is ignored by default.

A deliberate readability exception is explicit:

```racket
@frame-strip["semantic-math" #:columns 2]
```

For a new source of captures, call `manual-frame-strip` from
`scribblings/private/frame-style.rkt`. Pass a nonempty list of `manual-frame`
values: existing path, original width, original height, and caption. Optional
`#:label` describes the group to assistive technology; `#:note` explains what to
notice. `#:columns` is either `#f` (automatic, up to five) or an integer 1–5.
Use runtime paths, not the shell's current directory.

The helper only builds Scribble values. It does not launch Animate, a GUI,
LaTeX, or an encoder. Its CSS and TeX additions are collected by Scribble.
Both PNG `<img>` and SVG `<object>` output receive the same border.

## Check a change

```sh
python3 scribblings/check-frame-style.py .
"$RACKET" scribblings/check-frame-style.rkt
"$RACKET" tools/check-documentation.rkt slides-output/manual-frames
```

The r4 build driver runs the first two checks automatically when this patch is
installed. Its existing source/figure checks and strict Scribble check still run.

Inspect a three-frame strip, a five-frame strip, a portrait comparison, and a
light/dark pair in the rebuilt manual. Check a narrow browser window as well.
For print, inspect the row width and captions in the generated PDF. Source checks
are not a substitute for building the actual manual.
