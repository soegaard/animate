#!/usr/bin/env python3
"""Check manual structure, prerequisite declarations, source snippets and figures.

This checks source, not Scribble expansion or the truth of prose. Run the Racket
example tests and tools/check-documentation.rkt as separate acceptance steps.
"""
from pathlib import Path
import argparse
from collections import Counter
import hashlib
import json
import re
import sys

INCLUDE=re.compile(r'@include-section\["([^"\n]+)"\]')
HEAD=re.compile(r'@(?:title|section|subsection|subsubsection)\[([^\]]*)\]',re.S)
PART_HEAD=re.compile(r'(?m)^@(title|section|subsection|subsubsection)(?:\[[^\]]*\])?\{')
SECTION_HEAD=re.compile(r'(?m)^@section(?:\[([^\]\n]*)\])?\{')
PART_LEVEL={'title':0,'section':1,'subsection':2,'subsubsection':3}
TAG=re.compile(r'#:tag\s+(?:"([^"\n]+)"|\x27?\(([^)]*)\))')
LINK=re.compile(r'@secref\["([^"\n]+)"\]')
EXAMPLE=re.compile(r'@example-(source|part)\["([^"\n]+)"(?:\s+"([^"\n]+)")?\]')
STRIP=re.compile(r'@frame-strip\["([^"\n]+)"\]')
PARTS=['concepts.scrbl','cookbook.scrbl','guide.scrbl','reference.scrbl']
LEGACY='''guide/getting-started.scrbl guide/source-programs.scrbl guide/interactive-preview.scrbl
 guide/rendering-a-video.scrbl guide/project-planning.scrbl guide/slides.scrbl
 concepts/immutable-scenes.scrbl concepts/formula-source-maps.scrbl concepts/relation-phases.scrbl
 concepts/spatial-coordinates.scrbl concepts/colors-and-themes.scrbl concepts/typography-and-text-styles.scrbl
 reference/module-boundaries.scrbl reference/colors.scrbl reference/authoring.scrbl reference/preview.scrbl
 reference/project.scrbl cookbook/canonical-examples.scrbl guide/package-source.scrbl reference/scene.scrbl
 reference/geometry-and-plots.scrbl reference/3d-algebra.scrbl reference/visuals-and-relations.scrbl
 reference/experimental.scrbl reference/rendering.scrbl cookbook/reference-recipes.scrbl cookbook/themed-mathematics.scrbl'''.split()
INTRO=re.compile(r'^@;\s*(requires|introduces):\s*(.*)$',re.M)
# Declared terms used by code snippets. This list checks the teaching spine;
# it is not an automatic proof that every sentence introduces a concept well.
TOKENS={
 'circle':'visual','vec2':'coordinates','make-scene':'scene','scene-add':'scene',
 'move-to':'request','scene-play':'request','scene-sample':'sampling','scene-state->pict':'pict',
 'scene-wait':'hold','render-frames!':'rendering','encode-mp4!':'encoding',
 'hold-slide':'slide-clip','build-slide':'beat','beat':'beat','reveal-slot':'slot-action',
 'conceal-slot':'slot-action','bullets':'bullet','storyboard':'storyboard','storyboard-shot':'shot',
 'slide-transition':'transition','storyboard-cut':'transition','lecture-light':'theme','lecture-dark':'theme',
 'portrait':'format','widescreen':'format','storyboard-with-format':'format','narration':'narration',
 'storyboard->timeline':'authored-timeline','make-camera':'camera','scene-content':'viewport',
 'play-content':'content-clock','prepare-storyboard!':'preparation','math-content':'math-plan',
 'geometry-content':'construction','semantic-group':'semantic-group','semantic-part':'semantic-part',
 'content-state':'checkpoint','animate-project':'project','define-scene-program':'source-program',
 'scene-block':'source-block','open-program-preview':'preview',
}
BLOCK=re.compile(r'@example-part\["([^"\n]+)"\s+"([^"\n]+)"\]|@verbatim\{(.*?)\}',re.S)

def tags(text):
    for args in HEAD.findall(text):
        for one,multiple in TAG.findall(args):
            yield from ([one] if one else re.findall(r'"([^"\n]+)"',multiple))

def heading_depth_errors(path,text):
    errors=[]
    previous=None
    for match in PART_HEAD.finditer(text):
        kind=match.group(1);level=PART_LEVEL[kind]
        if previous is not None and level>previous[1]+1:
            line=text.count('\n',0,match.start())+1
            errors.append(f'{path}: heading level jumps from {previous[0]} to {kind} at line {line}')
        previous=(kind,level)
    return errors

def snippet(manual,name,part):
    text=(manual/'examples'/name).read_text()
    start=f';; doc: {part} begin';end=f';; doc: {part} end'
    if text.count(start)!=1 or text.count(end)!=1 or text.index(start)>text.index(end):
        raise ValueError(f'missing/ambiguous snippet {name}:{part}')
    return text.split(start,1)[1].split(end,1)[0]

def guide_order(manual):
    errors=[];known=set(); sequence=[]
    index=manual/'guide.scrbl'
    if not index.is_file():return ['missing Guide part'],[]
    for name in INCLUDE.findall(index.read_text()):
        path=manual/name
        if not path.is_file():errors.append('missing Guide chapter '+name);continue
        text=path.read_text()
        events=[(m.start(),'term',m) for m in INTRO.finditer(text)]
        events.extend((m.start(),'code',m) for m in BLOCK.finditer(text))
        for _,kind,m in sorted(events):
            if kind=='term':
                action,words=m.groups();terms=words.split()
                if action=='requires':
                    missing=set(terms)-known
                    if missing: errors.append(f'{name}: prerequisites not introduced: {sorted(missing)}')
                else:
                    for term in terms:
                        if term in known:errors.append(f'{name}: duplicate first introduction: {term}')
                        known.add(term);sequence.append((term,name))
            else:
                source,part,inline=m.groups()
                try:code=snippet(manual,source,part) if source else inline
                except (OSError,ValueError) as exc:errors.append(str(exc));continue
                # String content/comments are prose, not API use. Imports are
                # setup, so merely requiring a module does not introduce it.
                code=re.sub(r'"(?:\\.|[^"\\])*"','""',code)
                code=re.sub(r';[^\n]*','',code)
                calls=set(re.findall(r'\(\s*([^\s()\[\]{}]+)',code))
                for call in calls:
                    concept=TOKENS.get(call)
                    if concept and concept not in known:
                        errors.append(f'{name}: code uses {call} before {concept} is introduced')
    return errors,sequence

def check(root,overlay=False):
    manual=root/'scribblings';errors=[];texts={};active=set();omitted=[]
    def visit(path):
        path=path.resolve()
        if path in active:errors.append('include cycle: '+str(path));return
        if path in texts:errors.append('chapter included twice: '+str(path));return
        if not path.is_file():
            if overlay:omitted.append(str(path.relative_to(manual.resolve())));return
            errors.append('missing chapter: '+str(path));return
        text=path.read_text();texts[path]=text;active.add(path)
        for name in INCLUDE.findall(text):visit(path.parent/name)
        active.remove(path)
    visit(manual/'animate.scrbl')
    if INCLUDE.findall((manual/'animate.scrbl').read_text())!=PARTS:
        errors.append('root must contain only Concepts, Cookbook, Guide, Reference, in that order')
    if not overlay:
        for name in LEGACY:
            if (manual/name).resolve() not in texts:errors.append('lost legacy chapter: '+name)
    for path,text in texts.items():
        errors.extend(heading_depth_errors(path,text))
    targets={}
    for path,text in texts.items():
        for tag in tags(text):
            if tag in targets:errors.append('duplicate tag: '+tag)
            targets[tag]=path
    for path,text in texts.items():
        for target in LINK.findall(text):
            if target not in targets and not overlay:errors.append(f'{path}: missing local link {target}')
        for kind,name,part in EXAMPLE.findall(text):
            if not (manual/'examples'/name).is_file():errors.append('missing example: '+name)
            elif kind=='part':
                try:snippet(manual,name,part)
                except ValueError as exc:errors.append(str(exc))
        for image in re.findall(r'@image\["([^"\n]+)"\]',text):
            if not (root/image).is_file() and not overlay:errors.append('missing old illustration: '+image)
    quick=manual/'guide/getting-started.scrbl'
    if len(quick.read_text().splitlines())>150:errors.append('Quick Start exceeds 150 source lines')
    if re.search(r'@(defproc|defthing|defform)',quick.read_text()):errors.append('reference definitions leaked into Quick Start')
    e,sequence=guide_order(manual);errors.extend(e)
    catalogue=json.loads((manual/'figures/illustrations.json').read_text())['strips']
    for path,text in texts.items():
        for key in STRIP.findall(text):
            if key not in catalogue:errors.append('unknown frame strip: '+key)
    captured=0;retained=0
    for key,spec in catalogue.items():
        frames=spec['frames']
        if spec.get('kind')=='animation' and len(frames) not in (3,5):
            errors.append(key+': use three or five animation frames')
        for frame in frames:
            image=(manual/'figures'/frame['file']).resolve()
            if not image.is_relative_to(manual.resolve()):errors.append('unsafe picture path: '+str(image));continue
            if not image.is_file():
                if overlay and str(frame.get('source','')).startswith('repository canonical '):retained+=1;continue
                errors.append('missing captured picture: '+str(image));continue
            digest=hashlib.sha256(image.read_bytes()).hexdigest()
            if 'sha256' in frame and digest!=frame['sha256']:errors.append('picture checksum mismatch: '+str(image))
            captured+=1
    receipt=manual/'reference/reorganization-r2.json'
    if receipt.is_file():
        r=json.loads(receipt.read_text())
        # This is a migration audit, not a prohibition on later documentation
        # edits. The updater checks exact hashes for a safe reapplication; a
        # normal manual check only requires the preserved chapters to exist.
        for name in r['outputs']:
            generated=root/name
            if not generated.is_file():
                errors.append('missing preserved reference chapter: '+name)
                continue
            # Multi-page Scribble may turn a direct section title into an HTML
            # filename. Generated split chapters therefore require explicit
            # short tags on sections instead of relying on title-derived names.
            generated_text=generated.read_text()
            for match in SECTION_HEAD.finditer(generated_text):
                args=match.group(1) or ''
                if '#:tag' not in args:
                    line=generated_text.count('\n',0,match.start())+1
                    errors.append(f'{name}: generated section at line {line} needs an explicit #:tag')
    elif not overlay:errors.append('missing reference redistribution audit')
    if not errors:
        print(f'{"Overlay" if overlay else "Manual"} source check: {len(texts)} included files; {len(targets)} explicit tags.')
        print(f'Guide: {len(sequence)} declared first introductions checked against snippet calls.')
        print(f'Figures: {len(catalogue)} strips; {captured} available captures; {retained} retained repository SVG references.')
        if overlay:print(f'{len(omitted)} unchanged/generated-on-apply chapters not available in overlay; full link/build check remains required.')
        print('This is a source check, not Scribble expansion or a Racket example run.')
    return errors

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository',nargs='?',default='.')
    parser.add_argument('--overlay',action='store_true',help='check only the partial distribution; not an acceptance build')
    args=parser.parse_args()
    try:errors=check(Path(args.repository).resolve(),args.overlay)
    except (OSError,ValueError,KeyError) as exc:errors=[str(exc)]
    for error in errors:print(error,file=sys.stderr)
    raise SystemExit(bool(errors))
