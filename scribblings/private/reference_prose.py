"""Source-level checks for Reference prose maintenance.

This scanner separates document prose from executable examples, declaration
signatures, module forms, links, and comment text. It is not a Scribble compiler.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import hashlib
import re
import unicodedata

HEADINGS = {'title', 'section', 'subsection', 'subsubsection'}
DEFINITIONS = re.compile(r'^def(?:proc|thing|form|struct|param|class|interface|method)\*?$')
NAME = re.compile(r'[A-Za-z][A-Za-z0-9_*!?+:/<>=.-]*')

@dataclass(frozen=True)
class Command:
    start: int
    end: int
    name: str
    args: str = ''
    body: str = ''


def quoted(s, i, stop='"'):
    i += 1
    while i < len(s):
        if s[i] == '\\':
            i += 2
        elif s[i] == stop:
            return i + 1
        else:
            i += 1
    raise ValueError('unterminated quoted value')


def racket_block(s, i):
    closer = {'(': ')', '[': ']', '{': '}'}[s[i]]
    i += 1
    while i < len(s):
        c = s[i]
        if c == closer:
            return i + 1
        if s.startswith('#|', i):
            depth = 1; i += 2
            while depth and i < len(s):
                if s.startswith('#|', i): depth += 1; i += 2
                elif s.startswith('|#', i): depth -= 1; i += 2
                else: i += 1
            if depth: raise ValueError('unterminated Racket block comment')
        elif s.startswith('#\\', i):
            i += 2
            if i < len(s):
                # One punctuation character or a named character, e.g. space.
                if s[i].isalpha():
                    while i < len(s) and s[i].isalpha(): i += 1
                else: i += 1
        elif c == ';':
            end = s.find('\n', i); i = len(s) if end < 0 else end + 1
        elif c in ('"', '|'):
            i = quoted(s, i, c)
        elif c == '@':
            i = command(s, i).end
        elif c in '([{':
            i = racket_block(s, i)
        elif c in ')]}':
            raise ValueError('unbalanced Racket argument near '+repr(s[max(0,i-40):i+40]))
        else:
            i += 1
    raise ValueError('unterminated Racket argument')


def text_block(s, i):
    depth = 1; i += 1
    while i < len(s):
        if s[i] == '@':
            i = command(s, i).end
        elif s[i] == '{':
            depth += 1; i += 1
        elif s[i] == '}':
            depth -= 1; i += 1
            if not depth: return i
        else:
            i += 1
    raise ValueError('unterminated Scribble text')


def command(s, start):
    i = start + 1
    if i >= len(s): return Command(start, i, '')
    if s[i] == ';':
        i += 1
        if i < len(s) and s[i] == '{':
            return Command(start, text_block(s, i), 'comment')
        end = s.find('\n', i)
        return Command(start, len(s) if end < 0 else end + 1, 'comment')
    if s[i] in '([':
        return Command(start, racket_block(s, i), 'expression')
    if s[i] == '"': return Command(start, quoted(s, i), 'literal')
    if s[i] == '|':
        # The maintained reference does not use custom |delimiter{...} forms.
        end = s.find('|', i+1)
        if end < 0: raise ValueError('unterminated Scribble escape')
        return Command(start, end+1, 'literal')
    m = NAME.match(s, i)
    if not m: return Command(start, i+1, 'literal')
    name = m.group(); i = m.end(); args = ''; body = ''
    if i < len(s) and s[i] == '[':
        end = racket_block(s, i); args = s[i+1:end-1]; i = end
    if i < len(s) and s[i] == '{':
        end = text_block(s, i); body = s[i+1:end-1]; i = end
    return Command(start, i, name, args, body)


def commands(text):
    i = 0
    while True:
        i = text.find('@', i)
        if i < 0: return
        c = command(text, i)
        yield c
        i = c.end


from pathlib import Path
from typing import Iterable
import os

# These forms are code, not author-facing descriptive prose. Never edit them.
CODE = {
 'racket', 'racket0', 'racketid', 'racketidfont', 'racketresult', 'racketvalfont', 'scheme',
 'racketblock', 'racketblock0', 'racketinput', 'racketinput0', 'racketmod',
 'racketmod0', 'racketmodfile', 'interaction', 'interaction0', 'interaction-eval',
 'interaction-eval-show', 'defexamples', 'defexamples*', 'examples', 'examples*',
 'schemeblock', 'codeblock', 'code', 'verbatim', 'filebox',
 'example-source', 'example-part', 'include-extracted', 'include-at/relative-to',
}
# An inline @racket[...] reference may be added as an editorial cross-reference;
# existing inline references, when surrounded by edited prose, remain untouched.
INLINE = {'racket', 'racket0', 'racketid', 'racketidfont', 'racketresult', 'racketvalfont', 'scheme'}
FIXED_ARGS = HEADINGS | {
 'include-section', 'include-section/relative', 'secref', 'Secref', 'seclink',
 'other-doc', 'racketmodname', 'defmodule', 'defmodule*', 'defmodulelang',
 'declare-exporting', 'hyperlink', 'url', 'image', 'elemtag', 'elemref',
 'index', 'index*', 'local-table-of-contents', 'table-of-contents',
}
FIXED_BODIES = {'filepath', 'deftech', 'tech', 'math'}
STAGE = re.compile(
 r'(?<!\w)(?:SCENE-(?:3D-|FX-)?[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*'
 r'(?:/(?:SCENE-)?(?:3D-)?[A-Z][A-Z0-9]*)*'
 r'|(?:3D-)[A-Z](?:\d+)?'
 r'|(?:V|T|U)-?\d+(?:[./-]\d+)*'
 r'|(?:AN|AO|AP|AQ|AR|Q|T)[-–—]{1,2}(?:AN|AO|AP|AQ|AR|Q|T)'
 r"|[A-Z]{1,3}[- ]stage|later [A-Z] stages|(?:[Tt]his|[Aa] later|[Aa] future) development stage|(?:AC|AD|AE|AF|AG|AH|AI|AJ|AK|AL|AM|AN|AO|AP|AQ|AR)['’]s"
 r'|(?:AA|AB|AC|AD|AE|AF|AG|AH|AI|AJ|AK|AL|AM|AN|AO|AP|AQ|AR|AS|AT|AU|AW|AX|CV|DK|DL|DP|DQ|DT|DW|DY|EC)'
 r"(?=(?:['’]s|\s+(?:adds|extends|does|now|originally|sequence|scheduler|structural|mode|anchor|endpoint|rule|behavior|example|composition|scheduled|seed|stage)))"
 r')(?![\w-])')


def command_parts(s: str, c: Command) -> tuple[tuple[int,int] | None, tuple[int,int] | None]:
    """Return ranges including delimiters for named-command args and body."""
    i=c.start+1+len(c.name)
    args=body=None
    if i < len(s) and s[i]=='[':
        j=racket_block(s,i);args=(i,j);i=j
    if i < len(s) and s[i]=='{':
        body=(i,text_block(s,i))
    return args,body


def regions(s: str, *, protect_inline: bool=True) -> list[tuple[int,int]]:
    """Non-prose ranges. Recursively inspect text inside document containers."""
    result=[]
    def walk(lo: int,hi: int):
        i=lo
        while i < hi:
            i=s.find('@',i,hi)
            if i < 0:break
            c=command(s,i)
            if c.end > hi:
                raise ValueError('command crosses its enclosing text boundary')
            name=c.name
            if name in {'expression','literal','comment'}:
                result.append((i,c.end))
            else:
                a,b=command_parts(s,c)
                if name in CODE and (protect_inline or name not in INLINE):
                    result.append((i,c.end))
                elif DEFINITIONS.fullmatch(name) or name in FIXED_ARGS:
                    if a:result.append(a)
                    if b:walk(b[0]+1,b[1]-1)
                elif name in FIXED_BODIES:
                    result.append((i,c.end))
                else:
                    # @itemlist[...] and @tabular[...] contain text-valued
                    # @item/@bold/etc. Their prose is part of the Reference too.
                    if a:walk(a[0]+1,a[1]-1)
                    if b:walk(b[0]+1,b[1]-1)
            i=c.end
    walk(0,len(s))
    if s.startswith('#lang'):
        e=s.find('\n');result.append((0,len(s) if e<0 else e))
    return sorted(result)


def hidden_at(start: int,end: int,hidden: Iterable[tuple[int,int]]) -> bool:
    return any(a<=start and end<=b for a,b in hidden)


def protected_parts(s: str) -> list[str]:
    return [s[a:b] for a,b in regions(s,protect_inline=False)]


def findings(s: str) -> list[dict]:
    excluded=regions(s)
    out=[]
    for m in STAGE.finditer(s):
        if hidden_at(m.start(),m.end(),excluded):continue
        lo=max(s.rfind('\n',0,m.start())+1,m.start()-75)
        hi=s.find('\n',m.end())
        if hi<0:hi=len(s)
        out.append({'line':s.count('\n',0,m.start())+1,
                    'label':m.group(), 'text':s[lo:min(hi,m.end()+110)].strip()})
    return out


def safe_path(root: Path,relative: str) -> Path:
    p=Path(relative)
    if p.is_absolute() or not p.parts or any(x in ('.','..') for x in p.parts):
        raise ValueError(f'unsafe checkout path: {relative}')
    cur=root
    for part in p.parts:
        cur=cur/part
        if cur.is_symlink():raise ValueError(f'refusing symlink: {cur}')
    return cur


def includes(text: str) -> list[str]:
    result=[]
    # Inspect commands, not regex-looking text inside examples or comments.
    for c in commands(text):
        if c.name!='include-section':continue
        m=re.fullmatch(r'\s*"([^"\n]+)"\s*',c.args)
        if not m:raise ValueError('include-section needs a literal relative source path')
        result.append(m.group(1))
    return result


def reference_sources(root: Path) -> dict[str,str]:
    """Follow the actual Reference include tree, including split Visuals pages."""
    root=root.resolve()
    found={};active=set()
    def visit(rel: str):
        if rel in active:raise ValueError('Reference include cycle: '+rel)
        if rel in found:raise ValueError('Reference chapter included twice: '+rel)
        p=safe_path(root,rel)
        if not p.is_file():raise ValueError('missing Reference chapter: '+rel)
        s=p.read_bytes().decode('utf-8')
        found[rel]=s;active.add(rel)
        for name in includes(s):
            if Path(name).is_absolute():raise ValueError('absolute Reference include: '+name)
            sub=os.path.normpath(str(Path(rel).parent/name))
            if not sub.startswith('scribblings'+os.sep):
                raise ValueError('Reference include leaves scribblings: '+sub)
            visit(Path(sub).as_posix())
        active.remove(rel)
    visit('scribblings/reference.scrbl')
    return found


def check_reference(root: Path) -> tuple[int,list[dict]]:
    sources=reference_sources(root)
    bad=[]
    for name,text in sources.items():
        bad.extend(dict(file=name,**f) for f in findings(text))
    return len(sources),bad
