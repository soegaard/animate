"""Small, conservative Scribble source scanner; not a replacement for Scribble.

Commands inside code, verbatim examples, strings and comments are not treated
as document headings. Source positions are Unicode character offsets.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import re

HEADINGS = {'title': 0, 'section': 1, 'subsection': 2, 'subsubsection': 3}
DEFS = re.compile(r'def(?:proc|struct|thing|form|param|class|interface|method)\*?$')
BLOCKS = {'racketblock', 'racketblock0', 'racketinput', 'racketinput0',
          'racketmod', 'racketmod0', 'racketmodfile', 'interaction',
          'interaction0', 'interaction-eval', 'interaction-eval-show',
          'examples', 'examples*', 'defexamples', 'defexamples*', 'schemeblock',
          'codeblock', 'code', 'verbatim', 'example-source', 'example-part'}
NAME = re.compile(r'[A-Za-z][A-Za-z0-9_*!?+:/<>=.-]*')

def digest(value: str | bytes) -> str:
    return hashlib.sha256(value.encode('utf-8') if isinstance(value,str) else value).hexdigest()

def skip_space(s: str, i: int) -> int:
    while i < len(s) and s[i].isspace(): i += 1
    return i

def quote_end(s: str, i: int, delimiter: str = '"') -> int:
    i += 1
    while i < len(s):
        if s[i] == '\\': i += 2
        elif s[i] == delimiter: return i + 1
        else: i += 1
    raise ValueError('unterminated quoted value')

def group_end(s: str, i: int) -> int:
    close = {'(': ')', '[': ']', '{': '}'}[s[i]]
    i += 1
    while i < len(s):
        c = s[i]
        if c == close: return i + 1
        if s.startswith('#|',i):
            depth = 1; i += 2
            while i < len(s) and depth:
                if s.startswith('#|',i): depth += 1; i += 2
                elif s.startswith('|#',i): depth -= 1; i += 2
                else: i += 1
            if depth: raise ValueError('unterminated block comment')
        elif s.startswith('#\\',i):
            i += 2
            if i >= len(s): raise ValueError('unterminated character')
            first = s[i]; i += 1
            if first.isalpha():
                while i < len(s) and s[i].isalnum(): i += 1
        elif c == ';':
            end = s.find('\n',i); i = len(s) if end < 0 else end+1
        elif c in ('"','|'): i = quote_end(s,i,c)
        elif c == '@': i = command(s,i).end
        elif c in '([{': i = group_end(s,i)
        elif c in ')]}': raise ValueError(f'mismatched delimiter at character {i}')
        else: i += 1
    raise ValueError('unterminated Racket argument group')

def text_end(s: str, i: int) -> int:
    depth = 1; i += 1
    while i < len(s):
        if s[i] == '@': i = command(s,i).end
        elif s[i] == '{': depth += 1; i += 1
        elif s[i] == '}':
            depth -= 1; i += 1
            if not depth: return i
        else: i += 1
    raise ValueError('unterminated Scribble text group')

@dataclass(frozen=True)
class Command:
    start: int
    end: int
    name: str
    args_start: int | None = None
    args_end: int | None = None
    body_start: int | None = None
    body_end: int | None = None

    def args(self,s: str) -> str:
        return s[self.args_start+1:self.args_end-1] if self.args_start is not None else ''
    def body(self,s: str) -> str:
        return s[self.body_start+1:self.body_end-1] if self.body_start is not None else ''

def command(s: str, start: int) -> Command:
    i = start+1
    if i >= len(s): return Command(start,i,'literal')
    if s[i] == ';':
        i += 1
        if i < len(s) and s[i] == '{': return Command(start,text_end(s,i),'comment')
        end = s.find('\n',i)
        return Command(start,len(s) if end < 0 else end+1,'comment')
    if s[i] in '([': return Command(start,group_end(s,i),'expression')
    if s[i] == '"': return Command(start,quote_end(s,i),'literal')
    if s[i] == '|':
        # Scribble's standard @|identifier| form injects a Racket binding in
        # text, for example @tt{@|animate-version|}.  It is common in the
        # manual root and is not a document command such as @section or
        # @include-section.  Accept the conservative identifier-only form and
        # continue to reject arbitrary @|...| expressions that would require
        # a real at-expression parser.
        end = quote_end(s,i,'|')
        escaped = s[i+1:end-1]
        if not NAME.fullmatch(escaped):
            raise ValueError('complex Scribble @|...| expression requires review')
        return Command(start,end,'expression-escape')
    m = NAME.match(s,i)
    if not m: return Command(start,i+1,'literal')
    name = m.group(); i = m.end()
    a = ae = b = be = None
    if i < len(s) and s[i] == '[':
        a = i; ae = group_end(s,i); i = ae
    j = skip_space(s,i) if name in HEADINGS or DEFS.fullmatch(name) else i
    if j < len(s) and s[j] == '{':
        b = j; be = text_end(s,j); i = be
    return Command(start,i,name,a,ae,b,be)

def commands(s: str):
    i = 0
    while True:
        i = s.find('@',i)
        if i < 0: return
        c = command(s,i)
        yield c
        i = c.end

def tags(s: str) -> Counter:
    out = Counter()
    for c in commands(s):
        if c.name not in HEADINGS: continue
        for m in re.finditer(r'#:tag\s+("(?:\\.|[^"\\])+"|\x27?\([^)]*\))',c.args(s)):
            out.update(re.findall(r'"([^"\n]+)"',m.group(1)))
    return out

def primary_tag(s: str, c: Command) -> str:
    ts = tags(s[c.start:c.end])
    if len(ts) != 1 or next(iter(ts.values()),0) != 1:
        raise ValueError('expected one explicit heading tag: '+s[c.start:c.end])
    return next(iter(ts))

def declarations(s: str) -> list[dict]:
    out=[]
    for c in commands(s):
        if not DEFS.fullmatch(c.name): continue
        if c.args_end is None or c.body_end is None:
            raise ValueError('API declaration without signature/description')
        args = c.args(s)
        if c.name.startswith('defproc'):
            m = re.search(r'\(\s*([^\s()[\]{}"]+)',args)
        else:
            args = re.sub(r'^\s*#:kind\s+"(?:\\.|[^"\\])*"\s*','',args)
            m = re.search(r'^\s*([^\s()[\]{}"]+)',args)
        if not m: raise ValueError('cannot read API name: '+args[:100])
        out.append({'kind':c.name,'name':m.group(1),'start':c.start,'end':c.end,
                    'sha256':digest(s[c.start:c.end]),
                    'signature_sha256':digest(s[c.start:c.args_end])})
    return out

def definition_inventory(texts: list[str]) -> list[dict]:
    return sorted(({k:d[k] for k in ('kind','name','sha256','signature_sha256')}
                   for s in texts for d in declarations(s)),
                  key=lambda d:(d['kind'],d['name'],d['sha256']))

def example_inventory(s: str) -> Counter:
    out=Counter()
    for c in commands(s):
        if c.name in BLOCKS: out[(c.name,digest(s[c.start:c.end]))] += 1
        elif DEFS.fullmatch(c.name) and c.body_start is not None:
            out.update(example_inventory(c.body(s)))
    return out

def includes(s: str) -> list[str]:
    out=[]
    for c in commands(s):
        if c.name == 'include-section':
            a=c.args(s).strip()
            if not re.fullmatch(r'"[^"\n]+"',a):
                raise ValueError('include-section must use a literal filename')
            out.append(json.loads(a))
    return out

def links(s: str) -> set[str]:
    out=set()
    for c in commands(s):
        if c.name in {'secref','Secref','seclink'}:
            m=re.match(r'\s*"([^"\n]+)"',c.args(s))
            if m: out.add(m.group(1))
    return out
