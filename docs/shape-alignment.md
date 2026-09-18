# Circle and rectangle fill/outline alignment

## Cause

Racket's `draw-ellipse` and `draw-rectangle` apply device-grid adjustments in
`aligned` and `unsmoothed` modes. In the reported SVG, the circle fill was
centred at (640, 360), but the outline centreline was centred at (639, 359)
and had a smaller radius. This is already different vector geometry; increasing
PNG resolution is not the underlying correction.

The native Circle and Rectangle renderers used Pict primitives that inherited
the eventual destination DC's mode. An unconfigured SVG DC and Pict's default
bitmap conversion therefore produced different geometry from the animation
frame path, which explicitly requests `smoothed`.

See Racket's drawing-mode documentation:
https://docs.racket-lang.org/draw/dc___.html

## Rendering policy

`private/shape-smoothing.rkt` wraps the native circle and rectangle Picts. The
wrapper installs `smoothed` **during the delayed drawing callback**, and restores
the incoming DC mode in `dynamic-wind`, including on exceptions. The surrounding
DC, third-party renderers, and deliberate text rasterization policies are not
changed. Geometry, Pict dimensions, coordinates, camera mapping, and stroke-width
semantics are unchanged. No path translation or radius compensation is added.

The Circle and Rectangle renderer cache identities are bumped to v2-smoothed so
persistent caches that track renderer identity do not reuse the old appearance.

The three manual illustration generators also explicitly request `smoothed`
when converting Picts to bitmaps. The learning generator uses this for both the
saved frame and the repeatability comparison. The 3D generator records/checks
the drawing-policy stamp when deciding whether its installed frames are current.

## Verification

From the repository root:

```sh
raco test tests/shape-smoothing-test.rkt
python3 tools/check-shape-alignment.py --racket racket slides-output/shape-alignment-review
```

The first command checks draw-time mode selection, restoration, unchanged Pict
metrics, equivalence to an already-smoothed Pict, filled and unfilled circles and
rectangles, and grouped animation samples.

The second command uses `tools/probe-shape-alignment.rkt` to render 48 genuine
SVG/PNG pairs: circles and rectangles at three resolutions, fractional placements
and pen widths, and the actual source-block program at three times. Each case is
exported with the default, unsmoothed, aligned, and smoothed caller modes.
The default SVG case intentionally has no exporter `set-smoothing` call.

The Python checker reads vector paths, applies transforms, computes cubic-Bezier
extrema, and compares fill bounds, outline-centreline bounds, and the expected
scene bounds. It also checks stroke width. The 0.02 SVG-unit allowance covers
Cairo's serialized coordinate precision; it is not a raster-image tolerance.
A one-unit displacement fails. Embedded bitmap output and unsupported geometry
are not silently accepted as vector evidence.

`alignment-report.json`, the SVG/PNG files, and `stdout.txt`/`stderr.txt` remain
in the review directory. This checker does not regenerate or modify the manual.

## Stored illustrations

Code fixes cannot repair already stored PNGs. Regenerate them explicitly:

```sh
python3 scribblings/refresh-shape-illustrations.py --racket racket --install
```

This refreshes circle-motion and source-blocks in the main illustration catalog,
and all native learning illustrations. To refresh all three illustration
families, including the existing slide/math/geometry and software-3D captures:

```sh
python3 scribblings/refresh-shape-illustrations.py --racket racket --all --3d --install
```

The full variant needs the normal formula/construction toolchains used by those
examples. No MP4 encoding is requested. Omitting `--install` leaves the existing
manual assets untouched and only produces a review directory.

All requested render stages must finish successfully before installation.
Checksums, PNG dimensions, and unchanged sample times/captions are checked.
The script rejects tracked inputs changed during rendering, backs up overwritten
files under `tmp/shape-illustrations-backup-*`, and restores them if an installation
write raises an error. Publication of a family is multi-file: do not kill the
process during installation or build the manual concurrently with that step.
Backup receipts also describe recovery after a process termination.

The refresh retains existing image sizes. It replaces manifest hashes using
actual new files and records new per-strip provenance. Unselected strips keep
their data. It does not falsely describe a rerender as a byte-for-byte copy of a
previous review. The tracked source stamps do not fingerprint every dependency,
installed font, or system library.
