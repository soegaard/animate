#!/usr/bin/env python3
"""Fixture tests for the static Complete Examples validator (no Racket needed)."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zlib

MANUAL = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('complete_check', MANUAL / 'check-complete-examples.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def png() -> bytes:
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b'\0\0\0\0')) + chunk(b'IEND', b'')


class CompleteExamplesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('scribblings/animate.scrbl', '\n'.join('@include-section["'+p+'"]' for p in checker.PARTS))
        self.write('scribblings/cookbook.scrbl', '#lang scribble/manual\n')
        shutil.copytree(MANUAL / 'complete-examples', self.root / 'scribblings/complete-examples')
        shutil.copy2(MANUAL / 'complete-examples.scrbl', self.root / 'scribblings/complete-examples.scrbl')
        self.data = json.loads((MANUAL / 'complete-examples/entries.json').read_text())
        for name in ['private/example-catalog.rkt', 'scribblings/private/frame-style.rkt',
                     'scribblings/private/frame-style.css', 'scribblings/private/frame-style.tex']:
            self.write(name, 'fixture\n')
        family_data = {name: {'schema': f['schema'], 'strips': {}} for name, f in self.data['families'].items()}
        for entry in self.data['entries']:
            for name in entry['sources']:
                self.write(name, '#lang racket/base\n;; fixture source; not executed\n')
            for run in entry['runs']:
                for name in run['inputs']:
                    if not (self.root / name).exists():
                        self.write(name, '#lang racket/base\n')
            for strip in entry['strips']:
                family = self.data['families'][strip['family']]
                parent = Path(family['manifest']).parent
                frames = []
                for i in range(max(strip['select']) + 1):
                    name = strip['key'] + '-' + str(i) + '.png'
                    self.write_bytes(str(parent / name), png())
                    frames.append(dict(file=name, width=1, height=1, caption=f't = {i} s',
                                       sha256=hashlib.sha256(png()).hexdigest()))
                family_data[strip['family']]['strips'][strip['key']] = {'frames': frames}
        for name, family in self.data['families'].items():
            self.write(family['manifest'], json.dumps(family_data[name]))

    def write(self, name, text):
        self.write_bytes(name, text.encode())

    def write_bytes(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def save_data(self):
        self.write('scribblings/complete-examples/entries.json', json.dumps(self.data))

    def errors(self, **kwargs):
        return checker.check(self.root, verbose=False, **kwargs)

    def test_valid_complete_fixture(self):
        self.assertEqual(self.errors(), [])

    def test_missing_source(self):
        (self.root / self.data['entries'][0]['sources'][0]).unlink()
        self.assertTrue(any('missing file' in e for e in self.errors()))

    def test_duplicate_id(self):
        self.data['entries'][1]['id'] = 'moving-circle'
        self.save_data()
        self.assertTrue(any('duplicate complete-example ID' in e for e in self.errors()))

    def test_outside_source(self):
        self.data['entries'][0]['sources'][0] = '../../outside.rkt'
        self.save_data()
        self.assertTrue(any('unsafe' in e for e in self.errors()))

    def test_symlink_escape(self):
        path = self.root / self.data['entries'][0]['sources'][0]
        path.unlink()
        path.symlink_to(self.root.parent / 'outside.rkt')
        self.assertTrue(any('leaves repository' in e for e in self.errors()))

    def test_missing_capture(self):
        (self.root / 'scribblings/figures/circle-motion-0.png').unlink()
        self.assertTrue(any('missing capture' in e for e in self.errors()))

    def test_changed_capture(self):
        self.write_bytes('scribblings/figures/circle-motion-0.png', b'changed')
        self.assertTrue(any('checksum mismatch' in e for e in self.errors()))

    def test_unknown_strip(self):
        self.data['entries'][0]['strips'][0]['key'] = 'does-not-exist'
        self.save_data()
        self.assertTrue(self.errors())

    def test_invalid_selections(self):
        for selection in ([], [1, 0, 2], [0, 0, 1], [-1], [99], [0, True, 2], [0, 1.0, 2], [0, 1]):
            with self.subTest(selection=selection):
                with self.assertRaises(ValueError):
                    checker.select_frames([1, 2, 3], selection)

    def test_good_selections(self):
        self.assertEqual(checker.select_frames(list(range(5)), [0, 2, 4]), [0, 2, 4])
        self.assertEqual(checker.select_frames([1], [0]), [1])

    def test_source_listing_mismatch(self):
        p = self.root / 'scribblings/complete-examples/moving-circle.scrbl'
        p.write_text(p.read_text().replace('@complete-source[', '@removed-source['))
        self.assertTrue(any('displayed sources' in e for e in self.errors()))

    def test_command_listing_mismatch(self):
        p = self.root / 'scribblings/complete-examples/moving-circle.scrbl'
        p.write_text(p.read_text().replace('@complete-command[', '@removed-command['))
        self.assertTrue(any('page commands' in e for e in self.errors()))

    def test_missing_run_input(self):
        (self.root / 'slides/render-example.rkt').unlink()
        self.assertTrue(any('slides/render-example.rkt' in e for e in self.errors()))

    def test_untagged_heading(self):
        p = self.root / 'scribblings/complete-examples/moving-circle.scrbl'
        p.write_text(p.read_text() + '\n@section{Missing tag}\n')
        self.assertTrue(any('explicit tag' in e for e in self.errors()))

    def test_legacy_tag_is_retained(self):
        p = self.root / 'scribblings/complete-examples/catalog.scrbl'
        p.write_text(p.read_text().replace('cookbook-canonical-examples', 'removed-old-tag'))
        self.assertTrue(any('cookbook-canonical-examples' in e for e in self.errors()))

    def test_wrong_part_order(self):
        p = self.root / 'scribblings/animate.scrbl'
        p.write_text(p.read_text().replace('complete-examples.scrbl', 'absent.scrbl'))
        self.assertTrue(any('manual parts' in e for e in self.errors()))

    def test_old_cookbook_include(self):
        self.write('scribblings/cookbook.scrbl', '@include-section["cookbook/canonical-examples.scrbl"]')
        self.assertTrue(any('old catalog' in e for e in self.errors()))

    def test_stale_source_stamp(self):
        path = self.root / self.data['families']['3d']['manifest']
        data = json.loads(path.read_text())
        data['strips']['lesson']['source'] = 'spatial-motion.rkt'
        data['sources'] = {'spatial-motion.rkt': '0'*40}
        path.write_text(json.dumps(data))
        self.assertTrue(any('stale source' in e for e in self.errors()))

    def test_overlay_skips_unavailable_dependencies(self):
        (self.root / 'slides/render-example.rkt').unlink()
        (self.root / 'scribblings/figures/circle-motion-0.png').unlink()
        self.assertEqual(self.errors(overlay=True), [])

    def test_sources_only_does_not_claim_capture_checks(self):
        (self.root / 'scribblings/figures/circle-motion-0.png').unlink()
        self.assertEqual(self.errors(sources_only=True), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
