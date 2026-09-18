"""Numerical inspection of the vector shapes emitted by Racket's Cairo SVG DC.

No rasterization and no external dependencies. Bounds include exact cubic-Bezier
extrema after affine transformation. Unsupported path commands are errors, not
silently accepted approximations. This is a diagnostic reader, not an SVG engine.
"""
from __future__ import annotations
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

IDENTITY = (1., 0., 0., 1., 0., 0.)
TOKEN = re.compile(r"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?")
NUMBER = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?")


def multiply(a, b):
    """Affine composition a(b(point)), in SVG matrix order."""
    aa, ab, ac, ad, ae, af = a
    ba, bb, bc, bd, be, bf = b
    return (aa*ba+ac*bb, ab*ba+ad*bb, aa*bc+ac*bd, ab*bc+ad*bd,
            aa*be+ac*bf+ae, ab*be+ad*bf+af)


def point(matrix, p):
    a, b, c, d, e, f = matrix
    x, y = p
    return a*x+c*y+e, b*x+d*y+f


def transform(text):
    result = IDENTITY
    end = 0
    for match in re.finditer(r"([A-Za-z]+)\s*\(([^)]*)\)", text or ""):
        if (text[end:match.start()]).strip(" ,\t\n"):
            raise ValueError("unsupported SVG transform syntax")
        name, args = match.groups()
        values = [float(x) for x in NUMBER.findall(args)]
        if name == "matrix" and len(values) == 6:
            local = tuple(values)
        elif name == "translate" and len(values) in (1, 2):
            local = (1, 0, 0, 1, values[0], values[1] if len(values) == 2 else 0)
        elif name == "scale" and len(values) in (1, 2):
            local = (values[0], 0, 0, values[-1], 0, 0)
        elif name == "rotate" and len(values) in (1, 3):
            angle = math.radians(values[0]); c, s = math.cos(angle), math.sin(angle)
            local = (c, s, -s, c, 0, 0)
            if len(values) == 3:
                x, y = values[1:]
                local = multiply((1, 0, 0, 1, x, y),
                                 multiply(local, (1, 0, 0, 1, -x, -y)))
        else:
            raise ValueError(f"unsupported SVG transform: {name} {values}")
        result = multiply(result, local)
        end = match.end()
    if (text or "")[end:].strip(" ,\t\n"):
        raise ValueError("unsupported SVG transform suffix")
    return result


def cubic_extrema(p0, p1, p2, p3):
    # Derivative divided by three: a*t^2 + b*t + c.
    a = -p0+3*p1-3*p2+p3; b = 2*(p0-2*p1+p2); c = p1-p0
    if abs(a) < 1e-14:
        return [-c/b] if abs(b) > 1e-14 else []
    delta = b*b-4*a*c
    if delta < 0:
        return []
    r = math.sqrt(delta)
    return [(-b-r)/(2*a), (-b+r)/(2*a)]


def cubic_value(points, t):
    u = 1-t
    return tuple(u*u*u*points[0][i]+3*u*u*t*points[1][i]
                 +3*u*t*t*points[2][i]+t*t*t*points[3][i] for i in (0, 1))


def path_bounds(data, matrix=IDENTITY):
    tokens = TOKEN.findall(data)
    leftover = TOKEN.sub("", data).strip(" ,\n\t\r")
    if leftover:
        raise ValueError(f"invalid SVG path data: {leftover!r}")
    current = start = (0., 0.)
    samples = []
    command = None; index = 0
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]; index += 1
            if command.upper() == "Z":
                current = start
                samples.append(point(matrix, current))
                command = None
                continue
        if command is None:
            raise ValueError("SVG path data has no command")
        kind = command.upper()
        counts = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6}
        if kind not in counts:
            raise ValueError(f"unsupported SVG path command {command}")
        count = counts[kind]
        args = tokens[index:index+count]
        if len(args) != count or any(x.isalpha() for x in args):
            raise ValueError(f"incomplete SVG path command {command}")
        values = list(map(float, args)); index += count
        relative = command.islower()
        def xy(x, y):
            return (x+current[0], y+current[1]) if relative else (x, y)
        if kind in ("M", "L"):
            current = xy(*values)
            samples.append(point(matrix, current))
            if kind == "M":
                start = current
                command = "l" if relative else "L"
        elif kind == "H":
            current = (values[0]+current[0] if relative else values[0], current[1])
            samples.append(point(matrix, current))
        elif kind == "V":
            current = (current[0], values[0]+current[1] if relative else values[0])
            samples.append(point(matrix, current))
        elif kind == "C":
            controls = [current] + [xy(*values[i:i+2]) for i in (0, 2, 4)]
            transformed = [point(matrix, p) for p in controls]
            samples.extend([transformed[0], transformed[-1]])
            for dimension in (0, 1):
                for t in cubic_extrema(*(p[dimension] for p in transformed)):
                    if 0 < t < 1:
                        samples.append(cubic_value(transformed, t))
            current = controls[-1]
    if not samples:
        raise ValueError("empty SVG path")
    return (min(p[0] for p in samples), min(p[1] for p in samples),
            max(p[0] for p in samples), max(p[1] for p in samples))


def color(text):
    text = (text or "").strip().lower()
    if text in ("tomato", "firebrick"):
        return (255, 99, 71) if text == "tomato" else (178, 34, 34)
    if re.fullmatch(r"#[0-9a-f]{6}", text):
        return tuple(int(text[i:i+2], 16) for i in (1, 3, 5))
    if re.fullmatch(r"#[0-9a-f]{3}", text):
        return tuple(int(x*2, 16) for x in text[1:])
    match = re.fullmatch(r"rgb\(([^)]+)\)", text)
    if match:
        parts = re.split(r"[,\s]+", match[1].strip())
        if len(parts) == 3:
            return tuple(float(x[:-1])*2.55 if x.endswith("%") else float(x)
                         for x in parts)
    return None


def same_color(text, rgb):
    actual = color(text)
    return actual is not None and all(abs(a-b) < .01 for a, b in zip(actual, rgb))


def inspect_svg(path: Path):
    root = ET.parse(path).getroot()
    fills, strokes = [], []
    def visit(element, inherited, parent):
        tag = element.tag.rsplit("}", 1)[-1]
        if tag in ("defs", "clipPath", "metadata", "title", "desc"):
            return
        if tag in ("image", "use", "mask"):
            raise ValueError(f"unexpected {tag}: expected direct vector test geometry")
        style = dict(inherited)
        style.update(element.attrib)
        for item in element.get("style", "").split(";"):
            if ":" in item:
                name, value = item.split(":", 1); style[name.strip()] = value.strip()
        matrix = multiply(parent, transform(element.get("transform", "")))
        is_fill = same_color(style.get("fill"), (255, 99, 71))
        is_stroke = same_color(style.get("stroke"), (178, 34, 34))
        if (is_fill or is_stroke) and tag in ("path", "rect", "circle", "ellipse"):
            if tag == "path":
                bounds = path_bounds(element.get("d", ""), matrix)
            elif tag == "rect":
                x, y, w, h = (float(element.get(k, 0)) for k in ("x", "y", "width", "height"))
                bounds = path_bounds(f"M{x} {y} h{w} v{h} h{-w} Z", matrix)
            else:
                cx, cy = float(element.get("cx", 0)), float(element.get("cy", 0))
                rx = float(element.get("r") if tag == "circle" else element.get("rx", 0))
                ry = float(element.get("r") if tag == "circle" else element.get("ry", 0))
                x, y = point(matrix, (cx, cy)); a, b, c, d, _, _ = matrix
                dx, dy = math.hypot(a*rx, c*ry), math.hypot(b*rx, d*ry)
                bounds = (x-dx, y-dy, x+dx, y+dy)
            if is_fill:
                fills.append(bounds)
            if is_stroke:
                raw = style.get("stroke-width", "1").removesuffix("px")
                a, b, c, d, _, _ = matrix
                sx, sy = math.hypot(a, b), math.hypot(c, d)
                if abs(sx-sy) > 1e-8 or abs(a*c+b*d) > 1e-8:
                    raise ValueError("nonuniform stroke transform is outside this probe")
                strokes.append((bounds, float(raw)*sx))
        for child in element:
            visit(child, style, matrix)
    visit(root, {"fill": "black", "stroke": "none"}, IDENTITY)
    if len(fills) != 1 or len(strokes) != 1:
        raise ValueError(f"expected one tomato fill and one firebrick stroke; got {len(fills)}, {len(strokes)}")
    return {"fill_bounds": fills[0], "stroke_bounds": strokes[0][0],
            "stroke_width": strokes[0][1]}


def check_alignment(path: Path, expected=None, stroke_width=None, tolerance=.02):
    result = inspect_svg(path)
    comparisons = [("fill/outline", result["fill_bounds"], result["stroke_bounds"])]
    if expected is not None:
        comparisons += [("fill/expected", result["fill_bounds"], expected),
                        ("outline/expected", result["stroke_bounds"], expected)]
    for name, actual, wanted in comparisons:
        error = max(abs(a-b) for a, b in zip(actual, wanted))
        if not math.isfinite(error) or error > tolerance:
            raise ValueError(f"{path.name}: {name} bounds differ by {error:.6f} SVG units: {actual} vs {wanted}")
    if stroke_width is not None and abs(result["stroke_width"]-stroke_width) > tolerance:
        raise ValueError(f"{path.name}: unexpected stroke width {result['stroke_width']}")
    return result
