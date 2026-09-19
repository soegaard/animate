#!/usr/bin/env python3
"""Reject internal development-stage labels in the rendered Reference prose.

Follows include-section from reference.scrbl. Ignores code/examples, signature
arguments, comment text, source paths, and link/tag identifiers. No Racket run.
"""
from pathlib import Path
import argparse
import sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent/'private'))
from reference_prose import check_reference

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('repository',nargs='?',default='.')
    args=ap.parse_args()
    count,bad=check_reference(Path(args.repository))
    for f in bad:
        print(f"{f['file']}:{f['line']}: internal stage {f['label']}: {f['text']}",file=sys.stderr)
    if bad:
        print(f'Reference prose: {len(bad)} stage references in {count} reachable files.',file=sys.stderr)
        return 1
    print(f'Reference prose: {count} reachable files; no internal stage labels in checked prose.')
    print('Source-level check only; build the manual to validate Scribble expansion and links.')
    return 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,UnicodeError,ValueError) as exc:
        print('Reference prose check: '+str(exc),file=sys.stderr)
        raise SystemExit(1)
