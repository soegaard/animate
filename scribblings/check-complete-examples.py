#!/usr/bin/env python3
"""Validate the Complete Example Programs part without running any renderer.

Checks source/page wiring, command input paths, selected captures and checksums.
This is not a Scribble expansion, API execution test, or visual-quality test.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import shlex
import sys

SCHEMA = 'animate-complete-examples-v1'
PARTS = ['concepts.scrbl', 'cookbook.scrbl', 'guide.scrbl',
         'complete-examples.scrbl', 'reference.scrbl']
INCLUDE = re.compile(r'@include-section\["([^"\n]+)"\]')
SOURCE = re.compile(r'@complete-source\["([^"\n]+)"\]')
FRAMES = re.compile(r'@complete-frames\["([^"\n]+)"\s+"([^"\n]+)"')
COMMAND = re.compile(r'@complete-command\["([^"\n]+)"\s+"([^"\n]+)"\]')
HEADING = re.compile(r'(?m)^@(title|section|subsection)(?:\[([^\n]*)\])?\{')
SAFE_ID = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')


def repository_path(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or '\\' in name:
        raise ValueError(f'invalid repository-relative path: {name!r}')
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError(f'unsafe repository-relative path: {name}')
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'path leaves repository: {name}')
    return path


def select_frames(frames: list, indices: list[int]) -> list:
    if not isinstance(frames, list) or not frames:
        raise ValueError('frame collection must be a nonempty list')
    if (not isinstance(indices, list) or not indices
            or any(type(i) is not int or i < 0 or i >= len(frames) for i in indices)
            or indices != sorted(set(indices))):
        raise ValueError('frame selection must be increasing, unique and in range')
    if len(indices) not in (1, 3, 5):
        raise ValueError('show one still, or three or five animation frames')
    return [frames[i] for i in indices]


def check(root: Path, overlay: bool = False, *, sources_only: bool = False,
          verbose: bool = True) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    omitted: list[str] = []
    verified = 0
    count_sources: set[str] = set()
    manifest_cache: dict[str, dict] = {}

    def require_file(name: str) -> Path | None:
        path = repository_path(root, name)
        if not path.is_file():
            (omitted if overlay else errors).append('missing file: ' + name)
            return None
        return path

    try:
        registry = root / 'scribblings/complete-examples/entries.json'
        data = json.loads(registry.read_text(encoding='utf-8'))
        if data.get('schema') != SCHEMA:
            return ['unknown complete-example catalogue schema']
        entries = data['entries']
        if not isinstance(entries, list) or not entries:
            return ['empty complete-example catalogue']
        ids = [e['id'] for e in entries]
        if any(not isinstance(i, str) or not SAFE_ID.fullmatch(i) for i in ids):
            errors.append('invalid complete-example ID')
        if len(ids) != len(set(ids)):
            errors.append('duplicate complete-example ID')
        main = require_file('scribblings/animate.scrbl')
        if main and INCLUDE.findall(main.read_text()) != PARTS:
            errors.append('manual parts must be Concepts, Cookbook, Guide, Complete Example Programs, Reference')
        cookbook = require_file('scribblings/cookbook.scrbl')
        if cookbook and 'cookbook/canonical-examples.scrbl' in INCLUDE.findall(cookbook.read_text()):
            errors.append('old catalog is still included in the Cookbook')
        index = require_file('scribblings/complete-examples.scrbl')
        expected_pages = ['complete-examples/' + e['chapter'] for e in entries]
        expected_pages.append('complete-examples/catalog.scrbl')
        if index and INCLUDE.findall(index.read_text()) != expected_pages:
            errors.append('Complete Examples table of contents differs from entries.json')
        catalog = require_file('scribblings/complete-examples/catalog.scrbl')
        if catalog:
            text = catalog.read_text()
            for token in ('canonical-example-catalog', 'cookbook-canonical-examples',
                          'complete-example-catalog'):
                if token not in text:
                    errors.append('More example programs is missing ' + token)
        require_file('private/example-catalog.rkt')
        require_file('scribblings/private/frame-style.rkt')
        require_file('scribblings/private/frame-style.css')
        require_file('scribblings/private/frame-style.tex')
        for entry in entries:
            label = entry['id']
            page = require_file('scribblings/complete-examples/' + entry['chapter'])
            text = page.read_text() if page else ''
            if page:
                if Counter(SOURCE.findall(text)) != Counter(entry['sources']):
                    errors.append(label + ': displayed sources differ from registered complete files')
                if Counter(FRAMES.findall(text)) != Counter((label, s['id']) for s in entry['strips']):
                    errors.append(label + ': page frame strips differ from entries.json')
                if Counter(COMMAND.findall(text)) != Counter((label, r['id']) for r in entry['runs']):
                    errors.append(label + ': page commands differ from entries.json')
                for match in HEADING.finditer(text):
                    if '#:tag' not in (match.group(2) or ''):
                        errors.append(label + ': every heading needs an explicit tag')
            for source in entry['sources']:
                require_file(source)
                count_sources.add(source)
            checks = entry['checks']
            if not checks:
                errors.append(label + ': no exported-value checks')
            for probe in checks:
                if probe['source'] not in entry['sources']:
                    errors.append(label + ': check source is not one of the displayed files')
                if probe['kind'] not in ('scene', 'storyboard', 'project', 'program'):
                    errors.append(label + ': unsupported check kind')
                duration = probe.get('duration')
                if duration is not None and (isinstance(duration, bool)
                        or not isinstance(duration, (int, float))
                        or not math.isfinite(duration) or duration < 0):
                    errors.append(label + ': invalid expected duration')
            for run in entry['runs']:
                argv = shlex.split(run['command'])
                if not argv or argv[0] not in ('racket', 'raco'):
                    errors.append(label + ': unsupported run command')
                for source in run['inputs']:
                    require_file(source)
                if run.get('output'):
                    repository_path(root, run['output'])
            if sources_only:
                continue
            for spec in entry['strips']:
                family = data['families'][spec['family']]
                name = family['manifest']
                manifest = require_file(name)
                if not manifest:
                    continue
                if name not in manifest_cache:
                    manifest_cache[name] = json.loads(manifest.read_text())
                content = manifest_cache[name]
                if content.get('schema') != family['schema']:
                    errors.append(name + ': unexpected capture schema')
                    continue
                raw_strip = content['strips'][spec['key']]
                frames = select_frames(raw_strip['frames'], spec['select'])
                # Newer native-capture manifests retain raw source digests.
                source_name = raw_strip.get('source')
                if source_name:
                    recorded = content.get('inputs', {}).get('sources', content.get('sources', {}))
                    expected = recorded.get(source_name)
                    source = require_file('scribblings/examples/' + source_name)
                    if expected and source and hashlib.sha1(source.read_bytes()).hexdigest() != expected:
                        errors.append(label + ': stored frames have stale source: ' + source_name)
                for frame in frames:
                    image = (manifest.parent / frame['file']).resolve()
                    if not image.is_relative_to(root):
                        errors.append(label + ': capture path leaves repository')
                        continue
                    if not image.is_file():
                        (omitted if overlay else errors).append('missing capture: ' + str(image))
                        continue
                    if any(isinstance(frame.get(k), bool)
                           or not isinstance(frame.get(k), (int, float))
                           or not 0 < frame[k] < math.inf for k in ('width', 'height')):
                        errors.append(label + ': invalid image dimensions')
                    if not isinstance(frame.get('caption'), str):
                        errors.append(label + ': missing frame caption')
                    # Complete Examples must not silently fall back
                    # to raster HTML when the canonical capture is PNG.
                    if image.suffix.lower() == '.png':
                        svg = image.with_suffix('.svg')
                        if not svg.is_file():
                            errors.append(label + ': missing SVG alternative: ' + str(svg))
                        elif b'<svg' not in svg.read_bytes()[:4096]:
                            errors.append(label + ': invalid SVG alternative: ' + str(svg))
                    raw = image.read_bytes()
                    for algorithm in ('sha1', 'sha256'):
                        expected = frame.get(algorithm)
                        if expected and hashlib.new(algorithm, raw).hexdigest() != expected:
                            errors.append(label + ': capture checksum mismatch: ' + str(image))
                    verified += 1
        if verbose and not errors:
            print(f'Complete examples: {len(entries)} chapters; {len(count_sources)} source files; '
                  f'{verified} selected captures verified.')
            if sources_only:
                print('Source-only mode: capture files and checksums were not checked.')
            if omitted:
                print(f'Overlay mode: {len(omitted)} existing dependencies unavailable; full checkout check still required.')
            print('No Racket examples, renderers, GUI, or encoder were executed by this Python check.')
    except (OSError, KeyError, ValueError, TypeError) as exc:
        errors.append('complete examples: ' + str(exc))
    return errors


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', nargs='?', default='.')
    parser.add_argument('--overlay', action='store_true')
    parser.add_argument('--sources-only', action='store_true')
    args = parser.parse_args()
    failures = check(Path(args.repository), args.overlay, sources_only=args.sources_only)
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(bool(failures))
