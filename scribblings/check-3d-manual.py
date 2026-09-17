#!/usr/bin/env python3
"""Check the reorganized 3D reference, teaching order, and optional frame captures.

This is a source/asset check. It does not replace a Scribble build or run Racket.
"""
from __future__ import annotations
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import importlib.util
import json
import re
import sys

RECEIPT = 'scribblings/reference/reorganization-3d-r3.json'
GUIDES = ['guide/3d-picture.scrbl', 'guide/3d-motion.scrbl', 'guide/3d-composition.scrbl']
TOKENS = {
    'box3d':'solid3d', 'cube3d':'solid3d', 'vec3':'spatial-coordinates',
    'material3d':'material3d', 'perspective-camera3d':'camera3d',
    'view3d':'view3d', 'rotate3d-by':'spatial-motion', 'move3d-to':'spatial-motion',
    'axis-angle':'spatial-motion', 'camera3d-orbit-by':'camera3d-motion',
    'follow-projected-spatial':'projected-label',
}

def check(root: Path, rendered: bool = False):
    errors = []
    manual = root/'scribblings'
    receipt = json.loads((root/RECEIPT).read_text())
    if receipt.get('schema') != 'animate-manual-3d-reorganization-v1':
        raise ValueError('unrecognized 3D reorganization receipt')
    includes = re.findall(r'@include-section\["([^"\n]+)"\]', (manual/'reference.scrbl').read_text())
    parser_spec = importlib.util.spec_from_file_location('animate_3d_source', manual/'private/three_d_source.py')
    source_parser = importlib.util.module_from_spec(parser_spec)
    sys.modules[parser_spec.name] = source_parser
    parser_spec.loader.exec_module(source_parser)
    chapter_tags = set()
    found_definitions = Counter()
    for entry in receipt['split']['chapters']:
        path = root/entry['path']
        text = path.read_text()
        if includes.count(str(path.relative_to(manual))) != 1:
            errors.append('chapter must occur once in Reference: '+entry['path'])
        # Every chapter was lifted to title level, never left as an orphan subsection.
        title = re.search(r'@title\[([^\]]*)\]', text)
        if not title or '#:tag' not in title.group(1) or entry['tag'] not in title.group(1):
            errors.append('missing stable chapter tag: '+entry['path'])
        if len(entry['tag']) > 38:
            errors.append('generated HTML page tag is too long: '+entry['tag'])
        if entry['tag'] in chapter_tags:
            errors.append('duplicate generated tag: '+entry['tag'])
        chapter_tags.add(entry['tag'])
        if any(c.name in ('subsection','subsubsection') for c in source_parser.commands(text)):
            errors.append('an inherited nested heading was not lifted: '+entry['path'])
        found_definitions.update(source_parser.definition_name(c)
                                 for c in source_parser.commands(text)
                                 if source_parser.DEFINITIONS.match(c.name))
    if found_definitions != Counter(receipt['split']['definition_names']):
        errors.append('3D reference definition inventory changed; inspect the redistribution audit')
    if includes.count('reference/3d-algebra.scrbl') != 1:
        errors.append('the old 3d-algebra link must still lead to the reference map')
    guide_order = re.findall(r'@include-section\["([^"\n]+)"\]', (manual/'guide.scrbl').read_text())
    positions = [guide_order.index(name) for name in GUIDES]
    if positions != list(range(positions[0], positions[0]+3)):
        errors.append('3D Guide chapters must be consecutive and in prerequisite order')
    if guide_order.index('guide/embedded-content.scrbl') > positions[0]:
        errors.append('3D slide composition uses embedded-content concepts before their introduction')
    # Reuse the established checker, extending only its vocabulary for this route.
    spec = importlib.util.spec_from_file_location('animate_manual_structure', manual/'check-structure.py')
    checker = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = checker
    spec.loader.exec_module(checker)
    checker.TOKENS.update(TOKENS)
    order_errors, _ = checker.guide_order(manual)
    errors.extend(order_errors)
    count = 0
    if rendered:
        directory = manual/'figures/3d-r3'
        data = json.loads((directory/'manifest.json').read_text())
        if data.get('schema') != 'animate-manual-3d-frames-v1':
            errors.append('unrecognized 3D frame schema')
        for name, digest in data['sources'].items():
            if '/' in name or '\\' in name:
                raise ValueError('unsafe example filename')
            actual = hashlib.sha1((manual/'examples'/name).read_bytes()).hexdigest()
            if actual != digest: errors.append('3D frames have stale example source: '+name)
        used = set()
        for relative in GUIDES + ['cookbook/3d-tasks.scrbl']:
            used.update(re.findall(r'@three-d-frames\["([^"\n]+)"\]', (manual/relative).read_text()))
        if used != set(data['strips']): errors.append('3D strip references and capture catalogue differ')
        for key, strip in data['strips'].items():
            n = len(strip['frames'])
            if n != (1 if key == 'first-picture' else 3) and n != 5:
                errors.append(key+': expected one still, or three/five animation frames')
            for frame in strip['frames']:
                file = directory/frame['file']
                if file.parent.resolve() != directory.resolve(): raise ValueError('unsafe frame path')
                b = file.read_bytes()
                if not b.startswith(b'\x89PNG\r\n\x1a\n'): errors.append('not a PNG: '+str(file))
                if hashlib.sha1(b).hexdigest() != frame['sha1']: errors.append('changed capture: '+str(file))
                count += 1
    if not errors:
        print(f"3D manual: {len(chapter_tags)} focused reference chapters; "
              f"{sum(found_definitions.values())} definition forms retained.")
        print('Guide: three new chapters checked against declared prerequisites and snippet calls.')
        print(f'3D captures: {count} verified.' if rendered else
              '3D captures not checked; add --rendered after running render-3d-illustrations.rkt --install.')
    return errors

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository',nargs='?',default='.')
    parser.add_argument('--rendered',action='store_true')
    args=parser.parse_args()
    try: errors=check(Path(args.repository).resolve(),args.rendered)
    except (OSError, ValueError, KeyError, IndexError) as exc: errors=[str(exc)]
    for error in errors: print(error,file=sys.stderr)
    sys.exit(bool(errors))
