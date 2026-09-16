"""Check packaged relative require paths. Not a Racket binding/phase checker."""
from pathlib import Path
import importlib.util
import json
import sys

root = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("source_shapes", Path(__file__).with_name("check-shapes.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
parse, Str, Atom = module.parse, module.Str, module.Atom
internal = []
external = []
errors = []

def require_strings(node):
    if isinstance(node, Str):
        yield str(node)
    elif isinstance(node, list):
        for part in node:
            yield from require_strings(part)

def walk(node, filename):
    if not isinstance(node, list) or not node:
        return
    head = node[0]
    if isinstance(head, Atom) and str(head) in ('quote', 'quasiquote', 'syntax', 'quasisyntax'):
        return
    if isinstance(head, Atom) and str(head) == 'require':
        for target in require_strings(node[1:]):
            if not target.endswith('.rkt'):
                continue
            resolved = (filename.parent / target).resolve()
            record = {'from': str(filename.relative_to(root)), 'require': target}
            try:
                relative = resolved.relative_to(root)
            except ValueError:
                record['resolved'] = str(resolved)
                external.append(record)
                continue
            record['resolved'] = str(relative)
            # Only missing paths owned by slides/ are errors; existing parent
            # modules are recorded as internal dependencies, and absent paths
            # outside slides/ are recorded as native dependencies.
            if str(relative).startswith('slides/'):
                internal.append(record)
                if not resolved.is_file():
                    errors.append(record)
            elif resolved.is_file():
                internal.append(record)
            else:
                external.append(record)
    for child in node:
        walk(child, filename)

for filename in sorted(root.rglob('*.rkt')):
    for node in parse(filename.read_text()):
        walk(node, filename)
print(json.dumps({'files': len(list(root.rglob('*.rkt'))),
                  'packaged_relative_requires': internal,
                  'native_repository_requires': external,
                  'errors': errors}, indent=2))
sys.exit(bool(errors))
