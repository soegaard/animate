#!/usr/bin/env python3
"""Check the added teaching sequence, snippet links, and stored frame captures.

These checks are conservative source checks, not Scribble expansion or a proof
of prose quality. The Racket tests and full documentation build remain required.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys

GUIDES=["guide/objects-and-groups.scrbl","guide/timing-and-visibility.scrbl",
        "guide/first-function-graph.scrbl"]
NEW_PAGES=GUIDES+["guide/troubleshooting.scrbl","cookbook/native-tasks.scrbl",
                 "concepts/words-and-values.scrbl","reference/find-a-task.scrbl"]
EXAMPLES=["objects-and-groups.rkt","timing-and-visibility.rkt","first-function-graph.rkt"]
TOKENS={"group":"group", "timed":"timed-request", "smooth":"native-easing",
        "fade-in":"entrance-exit", "fade-out":"entrance-exit", "fade-to":"opacity",
        "function-graph":"function-graph", "axes":"axes", "axis-range":"numeric-range",
        "create":"path-reveal"}
EXPECTED_COUNTS={"one-moves":3,"group-moves":3,"child-moves":3,"together":5,
                 "in-order":5,"overlapping":5,"eased":5,"appearing":3,
                 "invisible":3,"removed":3,"draw-graph":5,"move-graph":3}
INCLUDE=re.compile(r'@include-section\["([^"\n]+)"\]')
LINK=re.compile(r'@sec(?:ref|link)\["([^"\n]+)"\]')
HEAD=re.compile(r'@(title|section|subsection|subsubsection)\[([^\]]*)\]',re.S)

def sha1(path): return hashlib.sha1(path.read_bytes()).hexdigest()

def walk(manual):
    pages={};active=set()
    def visit(path):
        path=path.resolve()
        if path in active: raise ValueError('manual include cycle: '+str(path))
        if path in pages: raise ValueError('manual chapter included twice: '+str(path))
        text=path.read_text();pages[path]=text;active.add(path)
        for name in INCLUDE.findall(text):visit(path.parent/name)
        active.remove(path)
    visit(manual/'animate.scrbl')
    return pages

def check(root,rendered=False):
    errors=[];manual=root/'scribblings'
    spec=importlib.util.spec_from_file_location('manual_structure',manual/'check-structure.py')
    checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
    checker.TOKENS.update(TOKENS)
    issues,_=checker.guide_order(manual);errors.extend(issues)
    order=INCLUDE.findall((manual/'guide.scrbl').read_text())
    positions=[order.index(x) for x in GUIDES]
    if positions!=list(range(positions[0],positions[0]+3)):
        errors.append('the three new lessons must be consecutive and in order')
    if positions[0]<=order.index('guide/getting-started.scrbl') or positions[-1]>=order.index('guide/slides.scrbl'):
        errors.append('new Scene lessons belong between Quick Start and slides')
    pages=walk(manual)
    tags=set()
    for text in pages.values():
        for _name,args in HEAD.findall(text):
            m=re.search(r'#:tag\s+("[^"\n]+"|\x27?\([^)]*\))',args)
            if m: tags.update(re.findall(r'"([^"\n]+)"',m.group(1)))
    used=set()
    for relative in NEW_PAGES:
        p=(manual/relative).resolve()
        if p not in pages:errors.append('new chapter is not included: '+relative);continue
        text=pages[p]
        if len(text.splitlines())>190:errors.append('new learning chapter exceeds 190 source lines: '+relative)
        for link in LINK.findall(text):
            if link not in tags:errors.append(relative+': missing section link '+link)
        for key in re.findall(r'@learning-frames\["([^"\n]+)"\]',text):used.add(key)
        for command in re.finditer(r'@(title|section|subsection|subsubsection)(?=[\[{])',text):
            tail=text[command.end():]
            if not tail.startswith('[') or '#:tag' not in tail.split(']',1)[0]:
                errors.append(relative+': every new heading must have a short explicit tag')
    if used!=set(EXPECTED_COUNTS):errors.append('figure references and expected strip IDs differ')
    for name in EXAMPLES:
        text=(manual/'examples'/name).read_text()
        if len(text.splitlines())>100:errors.append('example is too long for a first lesson: '+name)
        begins=re.findall(r'^;; doc: (\S+) begin$',text,re.M)
        ends=re.findall(r'^;; doc: (\S+) end$',text,re.M)
        if len(begins)!=len(set(begins)) or begins!=ends:
            errors.append('unbalanced or repeated snippet markers: '+name)
    count=0
    if rendered:
        directory=manual/'figures/learning-r4'
        data=json.loads((directory/'manifest.json').read_text())
        if data.get('schema')!='animate-manual-learning-frames-v1':errors.append('unrecognized frame schema')
        inputs=data['inputs']
        for name in EXAMPLES:
            if inputs['sources'].get(name)!=sha1(manual/'examples'/name):errors.append('stale source for '+name)
        for key,name in [('recipe-sha1','private/learning-catalog.rkt'),
                         ('renderer-sha1','render-learning-illustrations.rkt')]:
            if inputs.get(key)!=sha1(manual/name):errors.append('stale frame input: '+name)
        if set(data['strips'])!=set(EXPECTED_COUNTS):errors.append('unexpected or missing strip')
        for key,strip in data['strips'].items():
            frames=strip['frames']
            if len(frames)!=EXPECTED_COUNTS.get(key):errors.append('wrong frame count: '+key)
            last=-1
            for frame in frames:
                name=frame['file']
                if not re.fullmatch(r'[a-z0-9-]+\.png',name):raise ValueError('unsafe capture path')
                image=directory/name;b=image.read_bytes()
                if b[:8]!=b'\x89PNG\r\n\x1a\n' or len(b)<24:errors.append('invalid PNG '+name);continue
                w,h=struct.unpack('>II',b[16:24])
                if (w,h)!=(frame['width'],frame['height']):errors.append('wrong PNG dimensions '+name)
                if sha1(image)!=frame['sha1']:errors.append('changed capture '+name)
                if frame['time']<last:errors.append('sample times out of order '+key)
                last=frame['time'];count+=1
    if not errors:
        print('Learning manual: three Guide lessons, one troubleshooting chapter, and three lookup/recipe chapters checked.')
        print(f'Figures: {len(used)} strips; {count} verified captures.' if rendered else
              f'Figures: {len(used)} planned strips; run with --rendered after rendering.')
        print('Source checks do not substitute for the Racket tests or Scribble build.')
    return errors

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('repository',nargs='?',default='.')
    p.add_argument('--rendered',action='store_true');a=p.parse_args()
    try: errors=check(Path(a.repository).resolve(),a.rendered)
    except (OSError,ValueError,KeyError,IndexError) as exc:errors=[str(exc)]
    for error in errors:print(error,file=sys.stderr)
    raise SystemExit(bool(errors))
