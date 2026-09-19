#!/usr/bin/env python3
"""Check the Reference/Cookbook redistribution and preserved source contracts.

Normal mode permits later prose editing. --strict-preservation additionally
reconstructs the original source from the installed migration ranges and checks
its exact hash. Neither mode executes Racket examples or expands Scribble.
"""
from __future__ import annotations
from collections import Counter
from pathlib import Path
import argparse
import importlib.util
import json
import os
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'private'))
from recipe_reference_scan import (HEADINGS, commands, declarations, digest,
                                  example_inventory, includes, tags)

INVENTORY='scribblings/reference/recipe-redistribution-inventory.json'
SOURCE='scribblings/cookbook/reference-recipes.scrbl'
REF=['coordinate-decorations','markers-scatter-and-areas','statistical-diagrams']
COOK=['appearance-and-text-effects','camera-views-and-overlays',
      'animation-timing-recipes','path-motion-recipes','path-correspondence-recipes',
      'topology-morph-recipes','plot-styling-recipes']


def safe_path(root: Path, relative: str) -> Path:
    p=Path(relative)
    if p.is_absolute() or not p.parts or any(x in ('.','..') for x in p.parts):
        raise ValueError('unsafe manual path: '+relative)
    cur=root
    for part in p.parts:
        cur=cur/part
        if cur.is_symlink(): raise ValueError('refusing symlink: '+str(cur))
    return cur


def piece_text(text: str,key: str) -> str:
    begin='@; recipe-redistribution begin: '+key+'\n'
    end='\n@; recipe-redistribution end: '+key+'\n'
    if text.count(begin)!=1 or text.count(end)!=1:
        raise ValueError('missing/duplicated source range markers: '+key)
    a=text.index(begin)+len(begin); b=text.index(end)
    if b<a: raise ValueError('reversed source range: '+key)
    return text[a:b]


def check(root: Path, overlay: bool=False, verbose: bool=True,
          strict_preservation: bool=False) -> list[str]:
    root=Path(root).resolve()
    meta=safe_path(root,INVENTORY)
    if not meta.exists():
        return [] if overlay else ['missing recipe redistribution inventory']
    r=json.loads(meta.read_text(encoding='utf-8'))
    if r.get('schema')!='animate-recipe-redistribution-inventory-v1':
        raise ValueError('unknown recipe redistribution inventory schema')
    expected=[f'scribblings/reference/{k}.scrbl' for k in REF]
    expected += [f'scribblings/cookbook/{k}.scrbl' for k in COOK]
    if [p['path'] for p in r['pages']]!=expected:
        raise ValueError('unexpected redistribution destination list')
    errors=[]; texts={}
    for f in expected:
        p=safe_path(root,f)
        if not p.is_file():
            errors.append('missing redistributed chapter: '+f); continue
        texts[f]=p.read_bytes().decode('utf-8')
    if len(texts)!=len(expected): return errors
    if safe_path(root,SOURCE).exists():
        errors.append('retired reference-recipes.scrbl has been restored; its content belongs in the focused pages')
    for part,names in [('reference',REF),('cookbook',COOK)]:
        root_file=safe_path(root,f'scribblings/{part}.scrbl')
        if not root_file.is_file():
            errors.append('missing manual part: '+str(root_file)); continue
        actual=includes(root_file.read_text(encoding='utf-8'))
        required=[f'{part}/{name}.scrbl' for name in names]
        for name in required:
            if actual.count(name)!=1: errors.append(f'{part}: needs one include for {name}')
        if [n for n in actual if n in required]!=required:
            errors.append(part+': redistributed chapters not in the planned reading order')
        if 'cookbook/reference-recipes.scrbl' in actual:
            errors.append(part+': still includes the retired recipe chapter')
        wrong=COOK if part=='reference' else REF
        other='cookbook' if part=='reference' else 'reference'
        for n in wrong:
            if f'{other}/{n}.scrbl' in actual:
                errors.append('misplaced chapter: '+f'{other}/{n}.scrbl')
    source_sigs=Counter((d['kind'],d['name'],d['signature_sha256']) for d in r['declarations'])
    got_sigs=Counter((d['kind'],d['name'],d['signature_sha256'])
                     for t in texts.values() for d in declarations(t))
    if source_sigs!=got_sigs:
        errors.append('API declarations/signatures missing, changed or duplicated')
    for f,t in texts.items():
        if '/cookbook/' in f and declarations(t):
            errors.append('API declaration is in Cookbook: '+f)
        hs=[c for c in commands(t) if c.name in HEADINGS]
        if not hs or hs[0].name!='title' or sum(c.name=='title' for c in hs)!=1:
            errors.append('chapter needs exactly one initial title: '+f)
        previous=0
        for h in hs:
            depth=HEADINGS[h.name]
            if depth>previous+1: errors.append('heading depth jumps in '+f)
            previous=depth
    all_tags=sum((tags(t) for t in texts.values()),Counter())
    for tag in r['original_explicit_tags']:
        if all_tags[tag]!=1: errors.append('original explicit tag missing/duplicated: '+tag)
    for tag,count in all_tags.items():
        if count!=1: errors.append('duplicate explicit heading tag: '+tag)
    old_examples=Counter({(row['kind'],row['sha256']):row['count'] for row in r['examples']})
    new_examples=sum((example_inventory(t) for t in texts.values()),Counter())
    if old_examples!=new_examples:
        errors.append('original displayed/executable example or shell block changed, missing or duplicated')
    # Continue the prose guard for recipes that no longer belong to the Reference
    # tree. No copied prose or arbitrary history token is silently rewritten.
    prose=safe_path(root,'scribblings/private/reference_prose.py')
    if prose.is_file():
        spec=importlib.util.spec_from_file_location('recipe_prose_guard',prose)
        mod=importlib.util.module_from_spec(spec)
        sys.modules[spec.name]=mod; spec.loader.exec_module(mod)
        for f,t in texts.items():
            for item in mod.findings(t):
                errors.append(f'{f}:{item.get("line", "?")}: development-stage prose: {item.get("label",item)}')
    if strict_preservation:
        first=texts[expected[0]]
        prelude=first[:r['prelude_characters']]
        if digest(prelude)!=r['prelude_sha256']: errors.append('shared source prelude changed')
        original=[prelude]; cursor=len(prelude)
        for p in r['pieces']:
            if p['source_start']!=cursor: errors.append('source allocation gap/overlap: '+p['key'])
            text=piece_text(texts[p['path']],p['key'])
            if digest(text)!=p['installed_sha256']: errors.append('installed source range changed: '+p['key'])
            if p['promoted']:
                if not text.startswith('@title'): errors.append('promoted title changed: '+p['key'])
                text='@section'+text[len('@title'):]
            if digest(text)!=p['source_sha256']: errors.append('preserved source bytes differ: '+p['key'])
            original.append(text); cursor=p['source_end']
        restored=''.join(original)
        if cursor!=r['source_characters'] or digest(restored)!=r['source_sha256']:
            errors.append('reconstructed original source does not match the recorded source')
    if verbose and not errors:
        print(f'Recipe redistribution: {len(REF)} Reference chapters; {len(COOK)} Cookbook chapters.')
        print(f'{sum(source_sigs.values())} API declaration forms; {sum(old_examples.values())} example/command blocks; '
              f'{len(r["original_explicit_tags"])} original explicit tags preserved.')
        if strict_preservation: print('Exact source reconstruction passed; no source-body text was dropped or duplicated.')
        for page in r['pages']:
            print(f'  {page["path"]}: {len(texts[page["path"]].splitlines())} lines')
        print('Source checks only. Scribble expansion and example execution are separate checks.')
    return errors


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('repository',nargs='?',default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument('--strict-preservation',action='store_true')
    args=ap.parse_args()
    try: errors=check(Path(args.repository),strict_preservation=args.strict_preservation)
    except (OSError,ValueError,KeyError) as exc: errors=[str(exc)]
    for e in errors: print('Recipe redistribution: '+e,file=sys.stderr)
    return int(bool(errors))

if __name__=='__main__': raise SystemExit(main())
