"""Source scanner shared by the Visuals reference preservation checks.

The Racket/Scribble compiler remains the authority for syntax and expansion.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import hashlib
import re

DEF_RE = re.compile(r'@(?P<kind>defproc\*?|defstruct\*?|defthing)\[')
HEADING_RE = re.compile(r'^@(title|section|subsection|subsubsection)(?=[\[{])', re.M)

def digest(text: str | bytes) -> str:
    return hashlib.sha256(text.encode('utf-8') if isinstance(text, str) else text).hexdigest()


def space(text: str, i: int) -> int:
    while i < len(text) and text[i].isspace():
        i += 1
    return i


def racket_group(text: str, start: int) -> int:
    """Exclusive end of balanced Racket delimiters, with strings/comments/chars."""
    pairs = {'[': ']', '(': ')', '{': '}'}
    if start >= len(text) or text[start] not in pairs:
        raise ValueError('expected Racket group')
    stack = [pairs[text[start]]]
    i = start + 1
    while i < len(text):
        ch = text[i]
        if text.startswith('#|', i):
            depth = 1
            i += 2
            while depth and i < len(text):
                if text.startswith('#|', i):
                    depth += 1; i += 2
                elif text.startswith('|#', i):
                    depth -= 1; i += 2
                else:
                    i += 1
            if depth:
                raise ValueError('unterminated Racket block comment')
            continue
        if ch == ';':
            e = text.find('\n', i)
            i = len(text) if e == -1 else e + 1
            continue
        if text.startswith('#\\', i):
            i += 2
            if i >= len(text):
                raise ValueError('unterminated character literal')
            i += 1  # A delimiter can itself be the character.
            while i < len(text) and text[i].isalnum():
                i += 1
            continue
        if ch == '"':
            i += 1
            while i < len(text):
                if text[i] == '\\':
                    i += 2
                elif text[i] == '"':
                    i += 1; break
                else:
                    i += 1
            else:
                raise ValueError('unterminated Racket string')
            continue
        if ch in pairs:
            stack.append(pairs[ch])
        elif ch in '])}':
            if ch != stack.pop():
                raise ValueError(f'mismatched Racket delimiter near {text[max(start, i-50):i+1]!r}')
            if not stack:
                return i + 1
        i += 1
    raise ValueError('unterminated Racket group')


def text_group(text: str, start: int) -> int:
    """Exclusive end of Scribble {...}; skip strings in embedded code forms."""
    if text[start] != '{':
        raise ValueError('expected Scribble text group')
    depth = 1
    i = start + 1
    while i < len(text):
        ch = text[i]
        if ch == '@':
            if text.startswith('@;', i):
                j = i + 2
                if j < len(text) and text[j] == '{':
                    i = text_group(text, j); continue
                e = text.find('\n', j)
                i = len(text) if e == -1 else e + 1
                continue
            j = i + 1
            if j < len(text) and text[j] in '([':
                i = racket_group(text, j); continue
            match = re.match(r'[^\s\[\]{}()@]+', text[j:])
            if match:
                j += match.end()
            if j < len(text) and text[j] == '[':
                j = racket_group(text, j)
            if j < len(text) and text[j] == '{':
                j = text_group(text, j)
            if j > i + 1:
                i = j; continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unterminated Scribble text group')


@dataclass(frozen=True)
class Heading:
    kind: str
    title: str
    start: int
    end: int
    arguments: str


def headings(text: str) -> list[Heading]:
    result = []
    for match in HEADING_RE.finditer(text):
        i = match.end()
        args = ''
        if text[i] == '[':
            end = racket_group(text, i)
            args = text[i + 1:end - 1]
            i = end
        i = space(text, i)
        if i == len(text) or text[i] != '{':
            raise ValueError('heading without a title body')
        end = text_group(text, i)
        result.append(Heading(match.group(1), text[i+1:end-1],
                              match.start(), end, args))
    return result


def heading_tags(text: str) -> Counter:
    tags = []
    for h in headings(text):
        for match in re.finditer(r'#:tag\s+("(?:\\.|[^"\\])+"|\x27?\([^)]*\))', h.arguments):
            tags.extend(re.findall(r'"([^"\n]+)"', match.group(1)))
    return Counter(tags)


@dataclass(frozen=True)
class Declaration:
    kind: str
    name: str
    start: int
    end: int
    args_end: int
    text: str


def declarations(text: str) -> list[Declaration]:
    result = []
    pos = 0
    while True:
        match = DEF_RE.search(text, pos)
        if not match:
            return result
        args_end = racket_group(text, match.end()-1)
        begin_body = space(text, args_end)
        if begin_body == len(text) or text[begin_body] != '{':
            raise ValueError(f'{match.group(0)} has no description body')
        end = text_group(text, begin_body)
        args = text[match.end():args_end-1]
        kind = match.group('kind')
        if kind.startswith('defproc'):
            found = re.search(r'\(\s*([^\s()[\]{}"]+)', args)
        elif kind.startswith('defstruct'):
            found = re.search(r'^\s*([^\s()[\]{}"]+)', args)
        else:
            # The inspected defthing forms have at most a #:kind prefix.
            args = re.sub(r'^\s*#:kind\s+"(?:\\.|[^"\\])*"\s*', '', args)
            found = re.search(r'^\s*([^\s()[\]{}"]+)', args)
        if not found:
            raise ValueError(f'cannot identify declaration near {match.start()}')
        result.append(Declaration(kind, found.group(1), match.start(), end,
                                   args_end, text[match.start():end]))
        pos = end


def inventory(texts: list[str]) -> list[dict]:
    return sorted(({'kind': d.kind, 'name': d.name, 'sha256': digest(d.text)}
                   for text in texts for d in declarations(text)),
                  key=lambda x: (x['kind'], x['name'], x['sha256']))
