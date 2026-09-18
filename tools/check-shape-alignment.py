#!/usr/bin/env python3
"""Render real SVG/PNG probes, then check fill/stroke bounds numerically."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / 'private'))
from svg_shape_bounds import check_alignment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', help='fresh directory for SVG/PNG pairs and logs')
    parser.add_argument('--racket', default='racket')
    parser.add_argument('--existing', action='store_true', help='analyze an already generated probe directory')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    out = Path(args.destination).expanduser().absolute()
    if not args.existing:
        if out.exists() or out.is_symlink():
            parser.error('choose a fresh output directory')
        racket = shutil.which(args.racket)
        if not racket:
            parser.error('Racket executable not found; pass --racket with its full path')
        out.mkdir(parents=True)
        command = [racket, str(root/'tools/probe-shape-alignment.rkt'), str(out/'renders')]
        with (out/'stdout.txt').open('wb') as stdout, (out/'stderr.txt').open('wb') as stderr:
            code = subprocess.run(command, cwd=root, stdout=stdout, stderr=stderr).returncode
        if code:
            print((out/'stderr.txt').read_text(errors='replace'), file=sys.stderr)
            print(f'Probe failed; logs retained under {out}', file=sys.stderr)
            return 1
    else:
        command = None
    renders = out/'renders'
    if args.existing and not renders.exists():
        renders = out
    manifest = json.loads((renders/'manifest.json').read_text())
    if manifest.get('schema') != 'animate-shape-alignment-probe-v1':
        raise ValueError('unexpected probe manifest schema')
    cases = manifest.get('cases', [])
    if not cases:
        raise ValueError('empty probe manifest')
    expected_ids = {f'{kind}-{width}' for kind in ('circle', 'fractional-circle', 'rectangle')
                    for width in (160, 640, 1280)} | {f'source-blocks-t{t}' for t in (0, 2, 4)}
    expected = {(name, mode) for name in expected_ids
                for mode in ('default', 'unsmoothed', 'aligned', 'smoothed')}
    actual = [(case.get('id'), case.get('mode')) for case in cases]
    if len(actual) != len(expected) or set(actual) != expected:
        raise ValueError('probe matrix is incomplete or has duplicate cases; expected all 48 SVGs')
    entries, failures = [], []
    for case in cases:
        name = case['svg']
        if Path(name).name != name or Path(name).suffix != '.svg':
            raise ValueError('unsafe SVG filename')
        try:
            geometry = check_alignment(renders/name, case['bounds'], case['stroke-width'])
            entries.append(dict(case, status='passed', geometry=geometry))
        except (ValueError, OSError) as error:
            failures.append(str(error)); entries.append(dict(case, status='failed', error=str(error)))
    report = dict(schema='animate-shape-alignment-check-v1',
                  checked_utc=datetime.now(timezone.utc).isoformat(), command=command,
                  racket=manifest.get('racket'), sources=manifest.get('sources'),
                  tolerance_svg_units=.02, cases=entries,
                  status='failed' if failures else 'passed')
    (out/'alignment-report.json').write_text(json.dumps(report, indent=2)+'\n')
    for error in failures:
        print(error, file=sys.stderr)
    print(f"SVG alignment: {len(cases)-len(failures)}/{len(cases)} passed; report: {out/'alignment-report.json'}")
    return bool(failures)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(f'check-shape-alignment: {error}', file=sys.stderr)
        raise SystemExit(1)
