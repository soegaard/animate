#!/usr/bin/env python3
"""Split the checked 3D reference without executing Racket or rewriting contracts.

The small scanner distinguishes Scribble text from Racket arguments. It only
considers document-level headings, never heading-looking text in examples.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
import hashlib
import re
import unicodedata

SOURCE = 'scribblings/reference/3d-algebra.scrbl'
SOURCE_BLOB = '6b2bd2947b0d6290ec0be9dac66586a74c4a3576'
PREFIX = 'scribblings/reference/'
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


def definition_name(c):
    m = re.match(r'\s*\(?\s*([^\s()\[\]{}]+)', c.args)
    return m.group(1) if m else ''


def digest(data): return hashlib.sha256(data).hexdigest()

def blob_id(data):
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

