#!/usr/bin/env python3
"""Check the shared manual-frame wiring (not a substitute for rendering)."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

HELPERS = ('illustrations.rkt', 'three-d-illustrations.rkt', 'learning-illustrations.rkt')

def check(root: Path) -> list[str]:
    manual = root / 'scribblings'
    private = manual / 'private'
    errors = []
    required = [private/'frame-style.rkt', private/'frame-style.css',
                private/'frame-style.tex', manual/'FRAME-STYLE.md']
    for file in required:
        if not file.is_file(): errors.append('missing frame-style file: '+str(file))
    if errors: return errors
    present = 0
    for name in HELPERS:
        path = private / name
        if not path.exists(): continue  # r3 and r4 are optional installations.
        text = path.read_text()
        present += 1
        if '"frame-style.rkt"' not in text or '(manual-frame-strip' not in text:
            errors.append(name+': use the shared frame renderer')
        if re.search(r'\((?:tabular|chunks|rows)\b', text):
            errors.append(name+': a private fixed-row implementation has returned')
        if '#:columns [columns #f]' not in text:
            errors.append(name+': automatic row sizing must be the default')
    if not present: errors.append('no manual illustration helpers found')
    css = (private/'frame-style.css').read_text()
    if not re.search(r'border:\s*1px\s+solid\s+#888888\s*;', css):
        errors.append('the frame border must be one CSS pixel')
    for selector in ('.AnimFramePicture img', '.AnimFramePicture object'):
        if selector not in css: errors.append('missing PNG/SVG border rule: '+selector)
    if 'flex-flow: row wrap' not in css or '--frame-min: 112px' not in css:
        errors.append('the HTML row/wrapping rule is missing')
    tex = (private/'frame-style.tex').read_text()
    if r'\setlength{\fboxrule}{0.75bp}' not in tex:
        errors.append('missing print-equivalent frame border')
    for name in ('One','Two','Three','Four','Five'):
        if '.AnimFrameRow'+name not in css or '\\AnimFrameRow'+name not in tex:
            errors.append('missing row-count style: '+name)
    colors = manual/'concepts/colors-and-themes.scrbl'
    if colors.exists() and '@image[' in colors.read_text():
        errors.append('color comparison frames still bypass the shared frame style')
    if not errors:
        print(f'Frame style: {present} helpers share one-pixel borders and automatic rows.')
        print('Run the Racket fixture check and build the manual to validate actual output.')
    return errors

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', nargs='?', default='.')
    args = parser.parse_args()
    try: issues = check(Path(args.repository).resolve())
    except (OSError, ValueError) as exc: issues = [str(exc)]
    for issue in issues: print(issue, file=sys.stderr)
    sys.exit(bool(issues))
