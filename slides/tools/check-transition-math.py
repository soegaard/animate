"""Independent reference checks of the documented transition equations.

This does NOT execute the Racket implementation. It checks mask partitioning,
travel geometry, and easing equations with exact fractions to help review the
algorithm. Runtime/renderer acceptance remains the RackUnit and visual suites.
"""
from fractions import Fraction as F
import json

count = 0

def check(condition):
    global count
    count += 1
    if not condition:
        raise AssertionError(f"reference check {count} failed")


def masks(w, h, direction, p):
    if direction == 'left':
        return (0, 0, w*(1-p), h), (w*(1-p), 0, w*p, h)
    if direction == 'right':
        return (w*p, 0, w*(1-p), h), (0, 0, w*p, h)
    if direction == 'up':
        return (0, 0, w, h*(1-p)), (0, h*(1-p), w, h*p)
    return (0, h*p, w, h*(1-p)), (0, 0, w, h*p)


def overlap(a, b):
    return (max(0, min(a[0]+a[2], b[0]+b[2])-max(a[0], b[0])) *
            max(0, min(a[1]+a[3], b[1]+b[3])-max(a[1], b[1])))


def easing(name, p):
    return {'linear': lambda: p, 'smooth': lambda: p*p*(3-2*p),
            'ease-in': lambda: p*p, 'ease-out': lambda: 1-(1-p)**2,
            'ease-in-out': lambda: 2*p*p if p < F(1, 2) else 1-2*(1-p)**2}[name]()

for w, h in [(16, 9), (12, 9), (9, 16), (12, 12)]:
    for direction in ['left', 'right', 'up', 'down']:
        for i in range(101):
            p = F(i, 100)
            a, b = masks(w, h, direction, p)
            check(a[2]*a[3] + b[2]*b[3] == w*h)
            check(overlap(a, b) == 0)
            for x, y, bw, bh in [a, b]:
                check(0 <= x <= x+bw <= w and 0 <= y <= y+bh <= h)
            # A translated source/destination canvas exactly occupies its
            # visible partition during push/cover/uncover.
            dx, dy = {'left': (-w, 0), 'right': (w, 0),
                      'up': (0, -h), 'down': (0, h)}[direction]
            source = (p*dx, p*dy, w, h)
            destination = ((p-1)*dx, (p-1)*dy, w, h)
            check(overlap(source, a) == a[2]*a[3])
            check(overlap(destination, b) == b[2]*b[3])

for name in ['linear', 'smooth', 'ease-in', 'ease-out', 'ease-in-out']:
    seq = [easing(name, F(i, 1000)) for i in range(1001)]
    check(seq[0] == 0 and seq[-1] == 1)
    for a, b in zip(seq, seq[1:]):
        check(0 <= a <= b <= 1)

print(json.dumps({'scope': 'independent mathematical reference; not Racket execution',
                  'checks': count, 'errors': []}, indent=2))
