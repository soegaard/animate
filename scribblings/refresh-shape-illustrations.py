#!/usr/bin/env python3
"""Regenerate real manual captures with smoothed drawing; install only on request.

Default: circle-motion, source-blocks, and native learning illustrations.
--all also rebuilds the slide/math/geometry strips (needs their normal tools).
--3d includes the software 3D illustration family. All subprocess logs are kept.
"""
from __future__ import annotations
import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

POLICY = 'animate-shapes-smoothed-v1'


def digest(path, algorithm='sha256'):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def safe_file(root, relative):
    relative = Path(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError(f'unsafe relative output path: {relative}')
    root = root.resolve()
    path = root/relative
    candidate = path
    while candidate != root:
        if candidate.is_symlink():
            raise ValueError(f'refusing symbolic link: {candidate}')
        candidate = candidate.parent
    return path


def verify_frames(directory, manifest):
    # Verify the canonical PNG and SVG/PDF siblings for every frame.
    verified = {}
    for spec in manifest['strips'].values():
        if not isinstance(spec.get('frames'), list) or not spec['frames']:
            raise ValueError('empty frame strip')
        for frame in spec['frames']:
            path = safe_file(directory, frame['file'])
            if not path.is_file():
                raise ValueError(f'missing rendered frame: {path}')
            found_hash = False
            for algorithm in ('sha1', 'sha256'):
                if algorithm in frame:
                    found_hash = True
                    if digest(path, algorithm) != frame[algorithm]:
                        raise ValueError(f'frame checksum mismatch: {path}')
            if not found_hash:
                raise ValueError(f'rendered frame has no checksum: {path}')
            header = path.read_bytes()[:24]
            if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
                raise ValueError(f'not a PNG capture: {path}')
            if struct.unpack('>II', header[16:24]) != (frame['width'], frame['height']):
                raise ValueError(f'capture dimensions differ from manifest: {path}')
            verified[path.relative_to(directory).as_posix()] = path.read_bytes()
            svg = path.with_suffix('.svg')
            pdf = path.with_suffix('.pdf')
            if not svg.is_file():
                raise ValueError(f'missing SVG alternative: {svg}')
            if not pdf.is_file():
                raise ValueError(f'missing PDF alternative: {pdf}')
            svg_raw = svg.read_bytes()
            pdf_raw = pdf.read_bytes()
            if b'<svg' not in svg_raw[:4096]:
                raise ValueError(f'not an SVG alternative: {svg}')
            if not pdf_raw.startswith(b'%PDF-'):
                raise ValueError(f'not a PDF alternative: {pdf}')
            verified[svg.relative_to(directory).as_posix()] = svg_raw
            verified[pdf.relative_to(directory).as_posix()] = pdf_raw
    return verified


def snapshot(root):
    """Guard the assets and known inputs against edits during a long refresh."""
    paths = list((root/'scribblings/figures').rglob('*'))
    paths += list((root/'scribblings/examples').glob('*.rkt'))
    paths += [root/p for p in (
        'private/shape-pict-renderers.rkt', 'private/shape-smoothing.rkt',
        'scribblings/render-illustrations.rkt',
        'scribblings/render-learning-illustrations.rkt',
        'scribblings/render-3d-illustrations.rkt',
        'scribblings/private/image-export.rkt',
        'scribblings/private/learning-catalog.rkt',
        'scribblings/private/three-d-catalog.rkt')]
    result = {}
    for path in paths:
        if path.is_symlink():
            raise ValueError(f'refusing symbolic link among tracked inputs: {path}')
        if path.is_file():
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, name = tempfile.mkstemp(prefix='.'+path.name+'.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(data); output.flush(); os.fsync(output.fileno())
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def install_files(root, replacements, before):
    if snapshot(root) != before:
        raise ValueError('tracked inputs changed during rendering; nothing was installed')
    destinations = {rel: safe_file(root, rel) for rel in replacements}
    for path in destinations.values():
        if path.exists() and not path.is_file():
            raise ValueError(f'not an ordinary file: {path}')
    safe_file(root, 'tmp').mkdir(exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='shape-illustrations-backup-', dir=root/'tmp'))
    absent = []
    for rel, path in destinations.items():
        if path.is_file():
            saved = backup/rel; saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
        else:
            absent.append(rel)
    (backup/'receipt.json').write_text(json.dumps(dict(created=absent, files=list(replacements)), indent=2)+'\n')
    written = []
    try:
        # Publish manifests after their images. Multi-file updates are not atomic
        # against process termination; backups also cover that recovery case.
        for rel in sorted(replacements, key=lambda p: p.endswith('.json')):
            path = destinations[rel]
            written.append(rel)
            atomic_write(path, replacements[rel])
    except BaseException:
        for rel in reversed(written):
            path = destinations[rel]; saved = backup/rel
            if saved.is_file():
                shutil.copy2(saved, path)
            elif path.exists():
                path.unlink()
        raise
    return backup


def combine_main(old, fresh, selected, origin):
    if fresh.get('schema') != 'animate-manual-illustrations-v1':
        raise ValueError('unexpected main capture schema')
    if set(fresh['strips']) != set(selected):
        raise ValueError('renderer did not produce exactly the selected strips')
    result = deepcopy(old)
    for key in selected:
        original, replacement = old['strips'][key], deepcopy(fresh['strips'][key])
        if replacement.get('recipe') != original.get('recipe'):
            raise ValueError(f'{key}: source recipe changed during refresh')
        if len(original['frames']) != len(replacement['frames']):
            raise ValueError(f'{key}: sample count changed')
        for a, b in zip(original['frames'], replacement['frames']):
            for field in ('time', 'caption', 'width', 'height'):
                if a.get(field) != b.get(field):
                    raise ValueError(f'{key}: {field} changed, not a like-for-like capture')
        replacement['capture-origin'] = origin
        result['strips'][key] = replacement
    # Do not leave the old root-level 'copied without pixel changes' claim on
    # newly generated PNGs. Preserve it as historical provenance instead.
    result.setdefault('original-origin', deepcopy(old.get('origin')))
    result['origin'] = dict(racket=origin.get('racket'), drawing_policy=POLICY,
                           note='Use each strip capture-origin for regenerated frames; '
                                'unrefreshed original strips retain original-origin.')
    result['last-refresh'] = dict(origin, strips=selected)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--racket', default=os.environ.get('RACKET', 'racket'))
    parser.add_argument('--all', action='store_true', help='also render all slide/math/geometry illustrations')
    parser.add_argument('--3d', dest='spatial', action='store_true')
    parser.add_argument('--install', action='store_true', help='back up and replace maintained captures after all stages pass')
    parser.add_argument('destination', nargs='?', help='fresh review directory; default is timestamped under slides-output/')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    racket = shutil.which(args.racket)
    if not racket:
        parser.error('Racket executable not found; supply --racket')
    if not (root/'private/shape-smoothing.rkt').is_file():
        parser.error('apply the shape-alignment fix first')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    out = Path(args.destination).expanduser().absolute() if args.destination else root/'slides-output'/('shape-refresh-'+stamp)
    if out.exists() or out.is_symlink():
        parser.error('choose a fresh review directory')
    if root/'scribblings' in out.parents or out == root:
        parser.error('review output must not be in maintained source')
    # Refuse symlinked output parents, even when the final path does not exist.
    if any(p.is_symlink() for p in (out, *out.parents)):
        parser.error('refusing symbolic-link output path')
    catalogue_path = root/'scribblings/figures/illustrations.json'
    old = json.loads(catalogue_path.read_text())
    selected = sorted(old['strips']) if args.all else ['circle-motion', 'source-blocks']
    if any(k not in old['strips'] for k in selected):
        parser.error('required circle/source-block illustration strips are missing')
    before = snapshot(root)
    out.mkdir(parents=True)
    logs = out/'logs'; logs.mkdir()
    report = dict(schema='animate-shape-illustration-refresh-v1', status='running',
                  started_utc=stamp, drawing_policy=POLICY, stages=[], installed=False)
    report_path = out/'refresh-report.json'
    def save_report():
        report_path.write_text(json.dumps(report, indent=2)+'\n')
    def run(name, command):
        stdout, stderr = logs/(name+'.stdout.txt'), logs/(name+'.stderr.txt')
        item = dict(name=name, command=command, stdout=str(stdout), stderr=str(stderr))
        report['stages'].append(item)
        print('Rendering '+name+' ...', flush=True)
        with stdout.open('wb') as a, stderr.open('wb') as b:
            code = subprocess.run(command, cwd=root, stdout=a, stderr=b).returncode
        item['exit_code'] = code
        save_report()
        if code:
            print(stderr.read_text(errors='replace'), file=sys.stderr)
            raise RuntimeError(f'{name} failed with exit code {code}; no captures installed')
    try:
        command = [racket, 'scribblings/render-illustrations.rkt']
        for key in selected:
            command += ['--strip', key]
        run('main', command+[str(out/'main')])
        run('learning', [racket, 'scribblings/render-learning-illustrations.rkt', str(out/'learning')])
        if args.spatial:
            run('3d', [racket, 'scribblings/render-3d-illustrations.rkt', str(out/'3d')])
        fresh = json.loads((out/'main/illustrations.json').read_text())
        replacements = {'scribblings/figures/'+rel: data
                        for rel, data in verify_frames(out/'main', fresh).items()}
        origin = dict(drawing_policy=POLICY, racket=fresh.get('origin', {}).get('racket'),
                      refreshed_utc=stamp, tracked_inputs={k:v for k,v in before.items()
                      if not k.startswith('scribblings/figures/')})
        combined = combine_main(old, fresh, selected, origin)
        replacements['scribblings/figures/illustrations.json'] = (json.dumps(combined, indent=2)+'\n').encode()
        for name, relative, schema in [('learning', 'scribblings/figures/learning-r4', 'animate-manual-learning-frames-v1')] + (
                [('3d', 'scribblings/figures/3d-r3', 'animate-manual-3d-frames-v1')] if args.spatial else []):
            directory = out/name
            data = json.loads((directory/'manifest.json').read_text())
            if data.get('schema') != schema:
                raise ValueError(f'{name}: unexpected capture schema')
            for rel, raw in verify_frames(directory, data).items():
                replacements[relative+'/'+rel] = raw
            replacements[relative+'/manifest.json'] = (directory/'manifest.json').read_bytes()
        if snapshot(root) != before:
            raise ValueError('tracked inputs changed while rendering; nothing was installed')
        report['replacement_files'] = sorted(replacements)
        if args.install:
            backup = install_files(root, replacements, before)
            report.update(installed=True, backup=str(backup))
            print(f'Installed {len(replacements)} files. Backup: {backup}')
        else:
            print(f'Review renders: {out}. Maintained captures were not changed.')
        report['status'] = 'passed'
        return 0
    except BaseException as error:
        report.update(status='failed', error=str(error))
        print(str(error), file=sys.stderr)
        return 130 if isinstance(error, KeyboardInterrupt) else 1
    finally:
        save_report()
        print(f'Refresh report: {report_path}')


if __name__ == '__main__':
    raise SystemExit(main())
