#!/usr/bin/env python3
"""Render the Guide parabola and verify cubic tangent continuity in SVG."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
TOKEN_RE = re.compile(rf"[MLC]|{NUMBER}")
MATRIX_RE = re.compile(
    rf"^matrix\(\s*({NUMBER})[ ,]+({NUMBER})[ ,]+({NUMBER})[ ,]+"
    rf"({NUMBER})[ ,]+({NUMBER})[ ,]+({NUMBER})\s*\)$"
)


def parse_cubic_path(d: str):
    tokens = TOKEN_RE.findall(d)
    if not tokens or tokens[0] != "M":
        raise ValueError("curve path does not start with M")
    i = 1
    if i + 1 >= len(tokens):
        raise ValueError("truncated M command")
    current = (float(tokens[i]), float(tokens[i + 1])); i += 2
    segments = []
    while i < len(tokens):
        command = tokens[i]; i += 1
        if command != "C":
            raise ValueError(f"curve path contains non-cubic command {command!r}")
        if i + 5 >= len(tokens):
            raise ValueError("truncated C command")
        values = tuple(float(value) for value in tokens[i:i + 6]); i += 6
        c1 = values[0:2]; c2 = values[2:4]; end = values[4:6]
        segments.append((current, c1, c2, end))
        current = end
    return segments


def svg_linear_transform(attributes):
    """Return the 2x2 linear part of the path's SVG transform."""
    transform = attributes.get("transform")
    if not transform:
        return (1.0, 0.0, 0.0, 1.0)
    match = MATRIX_RE.match(transform.strip())
    if not match:
        raise ValueError(f"unsupported curve SVG transform {transform!r}")
    a, b, c, d, _e, _f = (float(value) for value in match.groups())
    return (a, b, c, d)


def transform_vector(vector, matrix):
    a, b, c, d = matrix
    x, y = vector
    return (a * x + c * y, b * x + d * y)


def inspect_svg(path: Path):
    root = ET.parse(path).getroot()
    candidates = []
    for element in root.iter():
        if not element.tag.endswith("path"):
            continue
        d = element.attrib.get("d", "")
        count = len(re.findall(r"(?:^|\s)C(?:\s|$)", d))
        if count:
            candidates.append((count, d, element.attrib))
    if not candidates:
        raise ValueError("SVG contains no cubic path")
    _, d, attributes = max(candidates, key=lambda item: item[0])
    segments = parse_cubic_path(d)
    if len(segments) != 80:
        raise ValueError(f"expected 80 cubic segments, found {len(segments)}")
    matrix = svg_linear_transform(attributes)
    raw_errors = []
    device_errors = []
    for left, right in zip(segments, segments[1:]):
        end = left[3]
        incoming = (end[0] - left[2][0], end[1] - left[2][1])
        outgoing = (right[1][0] - end[0], right[1][1] - end[1])
        delta = (outgoing[0] - incoming[0],
                 outgoing[1] - incoming[1])
        raw_errors.append(math.hypot(*delta))
        device_delta = transform_vector(delta, matrix)
        device_errors.append(math.hypot(*device_delta))

    maximum_raw = max(raw_errors, default=0.0)
    maximum_device = max(device_errors, default=0.0)

    # A smoothed Cairo path can still be serialized on its subpixel fixed-point
    # grid (typically 1/256 device pixel).  One tangent-continuity residual
    # combines four rounded coordinates, so exact equality is the wrong test.
    # 1/32 device pixel comfortably covers that subpixel residue while remaining
    # far below the old unsmoothed failure, which measured about one full pixel.
    tolerance_device = 1 / 32
    if maximum_device > tolerance_device:
        raise ValueError(
            f"cubic tangent discontinuity {maximum_device:.9g} device pixels "
            f"exceeds {tolerance_device:.9g}; path coordinates still show "
            "visible-scale snapping/quantization")
    return {
        "cubic_segments": len(segments),
        "joins": len(device_errors),
        "maximum_tangent_discontinuity_svg_units": maximum_raw,
        "maximum_tangent_discontinuity_device_pixels": maximum_device,
        "tolerance_device_pixels": tolerance_device,
        "transform": attributes.get("transform"),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", help="fresh directory for render and report")
    parser.add_argument("--racket", default="racket")
    parser.add_argument("--existing-svg", help="analyze an existing SVG instead of rendering")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    out = Path(args.destination).expanduser().absolute()
    if out.exists() or out.is_symlink():
        parser.error("choose a fresh destination directory")
    out.mkdir(parents=True)
    command = None
    if args.existing_svg:
        svg = Path(args.existing_svg).expanduser().absolute()
    else:
        racket = shutil.which(args.racket)
        if not racket:
            parser.error("Racket executable not found; pass --racket with its full path")
        renders = out / "renders"
        command = [racket, str(root / "tools/probe-path-smoothing.rkt"), str(renders)]
        with (out / "stdout.txt").open("wb") as stdout, (out / "stderr.txt").open("wb") as stderr:
            code = subprocess.run(command, cwd=root, stdout=stdout, stderr=stderr).returncode
        if code:
            print((out / "stderr.txt").read_text(errors="replace"), file=sys.stderr)
            return 1
        svg = renders / "guide-function-graph.svg"
    status = "passed"
    geometry = None
    error = None
    try:
        geometry = inspect_svg(svg)
    except (OSError, ValueError, ET.ParseError) as exc:
        status = "failed"; error = str(exc)
    report = {
        "schema": "animate-path-smoothing-check-v2",
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "command": command,
        "svg": str(svg),
        "geometry": geometry,
        "error": error,
    }
    (out / "path-smoothing-report.json").write_text(json.dumps(report, indent=2) + "\n")
    if error:
        print(error, file=sys.stderr)
        return 1
    print(f"Path smoothing passed: {geometry['cubic_segments']} cubics, "
          f"max join error {geometry['maximum_tangent_discontinuity_device_pixels']:.3g} device px; "
          f"report: {out/'path-smoothing-report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
