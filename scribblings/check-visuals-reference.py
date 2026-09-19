#!/usr/bin/env python3
"""Check the reorganized Visuals source tree, tags, and preserved declarations.

This is a source check, not a Scribble expansion or Racket example execution.
When deliberately revising an API description later, review/update its inventory
entry; do not silently rebaseline a failed preservation check.
"""
from __future__ import annotations
from collections import Counter
from pathlib import Path
import json
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'private'))
from visuals_reference_scan import declarations, headings, heading_tags, inventory


def check(root: Path) -> list[str]:
    reference = root / 'scribblings/reference'
    metadata = json.loads((reference / 'visuals-reference-inventory.json').read_text(encoding='utf-8'))
    if metadata.get('schema') != 'animate-visuals-reference-inventory-v1':
        raise ValueError('unsupported Visuals reference inventory')
    hub = (reference / 'visuals-and-relations.scrbl').read_text(encoding='utf-8')
    includes = re.findall(r'^@include-section\["([^"\n]+)"\]', hub, re.M)
    expected_files = [page['file'] for page in metadata['pages']]
    errors = []
    if includes != expected_files:
        errors.append('hub does not include each expected child exactly once, in lookup order')
    if "#:style 'toc" not in hub:
        errors.append('hub has lost its multi-page table-of-contents style')
    texts = {'visuals-and-relations.scrbl': hub}
    for name in expected_files:
        # Do not allow an edited inventory to escape the reference directory.
        if Path(name).name != name or not name.endswith('.scrbl'):
            raise ValueError(f'invalid child path: {name}')
        texts[name] = (reference / name).read_text(encoding='utf-8')
    actual = inventory(list(texts.values()))
    expected = metadata['declarations']
    if actual != expected:
        before = Counter((x['kind'], x['name'], x['sha256']) for x in expected)
        after = Counter((x['kind'], x['name'], x['sha256']) for x in actual)
        missing = [f'{kind}:{name}' for kind, name, _ in (before-after).elements()]
        extra = [f'{kind}:{name}' for kind, name, _ in (after-before).elements()]
        errors.append(f'original API declarations changed/missing: {missing}; added/changed: {extra}')
    tags = sum((heading_tags(t) for t in texts.values()), Counter())
    for old in metadata['original_explicit_tags']:
        if tags[old] != 1:
            errors.append(f'original explicit tag must occur once: {old}')
    for name, count in tags.items():
        if count != 1:
            errors.append(f'duplicate explicit tag: {name}')
    levels = {'title': 0, 'section': 1, 'subsection': 2, 'subsubsection': 3}
    for name, text in texts.items():
        hs = headings(text)
        if not hs or hs[0].kind != 'title':
            errors.append(f'{name}: missing page title')
        previous = 0
        for h in hs:
            depth = levels[h.kind]
            if depth > previous + 1:
                errors.append(f'{name}: skipped heading level at {h.title}')
            previous = depth
        for link in re.findall(r'@secref\["(ref-visuals-[^"]+)"\]', text):
            if tags[link] != 1:
                errors.append(f'{name}: missing new local section target: {link}')
    for page in metadata['pages']:
        text = texts[page['file']]
        count = len(re.findall(r'^@; visuals-reference-r1 example:', text, re.M))
        if count != page['examples']:
            errors.append(f"{page['file']}: local example count changed")
        if '(close-eval reference-eval)' not in text:
            errors.append(f"{page['file']}: evaluator is not closed")
    # Structural regressions this revision is specifically intended to prevent.
    locations = {d.name: name for name, text in texts.items() for d in declarations(text)}
    for name, file in {
        'function-graph': 'visuals-plots.scrbl',
        'sample-function-path': 'visuals-plots.scrbl',
        'parametric-curve': 'visuals-plots.scrbl',
        'data-plot': 'visuals-plots.scrbl',
        'ode-flow-position': 'visuals-ode.scrbl',
        'prepare-ode-trajectory': 'visuals-ode.scrbl',
        'ellipse': 'visuals-shapes.scrbl',
        'regular-polygon': 'visuals-shapes.scrbl',
        'matrix': 'visuals-matrices.scrbl',
        'group': 'visuals-protocols.scrbl',
    }.items():
        if locations.get(name) != file:
            errors.append(f'{name}: expected declaration in {file}')
    if not errors:
        print(f"Visuals: {len(metadata['pages'])} lookup pages; "
              f"{len(actual)} complete API declaration forms preserved.")
        print(f"Original explicit tags retained: {len(metadata['original_explicit_tags'])}; "
              f"new executable example blocks: {metadata['inline_example_blocks']}.")
        print(f'Index: {len(hub.splitlines())} source lines.')
        for page in metadata['pages']:
            print(f"  {page['file']}: {len(texts[page['file']].splitlines())} lines; "
                  f"{len(declarations(texts[page['file']]))} declaration forms")
        print('Source preservation/structure passed. Run the Racket examples and full manual build separately.')
    return errors


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    try:
        errors = check(root)
    except (ValueError, OSError, KeyError) as exc:
        errors = [str(exc)]
    for error in errors:
        print('Visuals reference: ' + error, file=sys.stderr)
    return 1 if errors else 0

if __name__ == '__main__':
    raise SystemExit(main())
