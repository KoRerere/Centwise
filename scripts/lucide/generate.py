#!/usr/bin/env python3
"""Generate App/LucideIcons.swift from Lucide's SVG sources.

Usage: python3 generate.py <lucide-repo-dir> <icons.txt> <output.swift> [--svg-out DIR]

Every icon listed in icons.txt is converted from its 24x24 SVG into SwiftUI
`Path` drawing calls, so the app needs no image assets, no SVG parser and no
third-party package at runtime. Arcs, smooth curves and relative commands are
normalised to absolute move/line/cubic/quadratic segments.

--svg-out writes the normalised geometry back out as plain SVG, which is only
used to check the conversion against the originals.
"""
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
ARGC = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def parse_path(d):
    """Return a list of (cmd, [floats]) with commands absolute, one segment per entry."""
    segs = []
    i, n = 0, len(d)
    cmd = None
    cx = cy = sx = sy = 0.0
    last_ctrl = None  # (x, y, kind) where kind in 'C', 'Q'

    def skip(i):
        while i < n and d[i] in " ,\t\n\r":
            i += 1
        return i

    def number(i):
        i = skip(i)
        m = NUM.match(d, i)
        if not m:
            raise ValueError(f"number expected at {i} in {d!r}")
        return float(m.group(0)), m.end()

    def flag(i):
        i = skip(i)
        if d[i] not in "01":
            raise ValueError(f"flag expected at {i} in {d!r}")
        return int(d[i]), i + 1

    while True:
        i = skip(i)
        if i >= n:
            break
        if d[i].isalpha():
            cmd = d[i]
            i += 1
        elif cmd is None:
            raise ValueError("path must start with a command")
        up = cmd.upper()
        rel = cmd.islower()
        if up == "Z":
            segs.append(("Z", []))
            cx, cy = sx, sy
            last_ctrl = None
            continue
        if up == "A":
            rx, i = number(i); ry, i = number(i); rot, i = number(i)
            laf, i = flag(i); sf, i = flag(i)
            x, i = number(i); y, i = number(i)
            if rel:
                x += cx; y += cy
            for c in arc_to_cubics(cx, cy, rx, ry, rot, laf, sf, x, y):
                segs.append(("C", c))
            cx, cy = x, y
            last_ctrl = None
            continue
        args = []
        for _ in range(ARGC[up]):
            v, i = number(i)
            args.append(v)
        if up == "M":
            x, y = args
            if rel:
                x += cx; y += cy
            segs.append(("M", [x, y]))
            cx, cy = sx, sy = x, y
            cmd = "l" if rel else "L"  # subsequent pairs are implicit linetos
            last_ctrl = None
        elif up in ("L", "H", "V"):
            if up == "L":
                x, y = args
                if rel:
                    x += cx; y += cy
            elif up == "H":
                x = args[0] + (cx if rel else 0); y = cy
            else:
                x = cx; y = args[0] + (cy if rel else 0)
            segs.append(("L", [x, y]))
            cx, cy = x, y
            last_ctrl = None
        elif up == "C":
            x1, y1, x2, y2, x, y = args
            if rel:
                x1 += cx; y1 += cy; x2 += cx; y2 += cy; x += cx; y += cy
            segs.append(("C", [x1, y1, x2, y2, x, y]))
            last_ctrl = (x2, y2, "C")
            cx, cy = x, y
        elif up == "S":
            x2, y2, x, y = args
            if rel:
                x2 += cx; y2 += cy; x += cx; y += cy
            if last_ctrl and last_ctrl[2] == "C":
                x1, y1 = 2 * cx - last_ctrl[0], 2 * cy - last_ctrl[1]
            else:
                x1, y1 = cx, cy
            segs.append(("C", [x1, y1, x2, y2, x, y]))
            last_ctrl = (x2, y2, "C")
            cx, cy = x, y
        elif up == "Q":
            x1, y1, x, y = args
            if rel:
                x1 += cx; y1 += cy; x += cx; y += cy
            segs.append(("Q", [x1, y1, x, y]))
            last_ctrl = (x1, y1, "Q")
            cx, cy = x, y
        elif up == "T":
            x, y = args
            if rel:
                x += cx; y += cy
            if last_ctrl and last_ctrl[2] == "Q":
                x1, y1 = 2 * cx - last_ctrl[0], 2 * cy - last_ctrl[1]
            else:
                x1, y1 = cx, cy
            segs.append(("Q", [x1, y1, x, y]))
            last_ctrl = (x1, y1, "Q")
            cx, cy = x, y
    return segs


def arc_to_cubics(x1, y1, rx, ry, phi_deg, fa, fs, x2, y2):
    """SVG endpoint arc -> list of cubic segments (SVG spec F.6)."""
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [[x1, y1, x2, y2, x2, y2]]
    phi = math.radians(phi_deg % 360)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cp * dx + sp * dy
    y1p = -sp * dx + cp * dy
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        s = math.sqrt(lam)
        rx *= s; ry *= s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if fa == fs:
        coef = -coef
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi

    count = max(1, math.ceil(abs(dt) / (math.pi / 2) - 1e-9))
    step = dt / count
    k = 4 / 3 * math.tan(step / 4)
    out = []
    t = t1
    for _ in range(count):
        c1, s1 = math.cos(t), math.sin(t)
        c2, s2 = math.cos(t + step), math.sin(t + step)
        p1 = (c1 - k * s1, s1 + k * c1)
        p2 = (c2 + k * s2, s2 - k * c2)
        p3 = (c2, s2)
        pts = []
        for (ux, uy) in (p1, p2, p3):
            ux *= rx; uy *= ry
            pts += [cp * ux - sp * uy + cx, sp * ux + cp * uy + cy]
        out.append(pts)
        t += step
    out[-1][4], out[-1][5] = x2, y2  # land exactly on the endpoint
    return out


def f(v):
    v = round(v, 4)
    if v == 0:
        v = 0.0
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def num_attr(el, name, default=0.0):
    v = el.get(name)
    return float(v) if v is not None else default


def element_ops(el):
    """Return (ops, filled). ops: list of ('M'|'L'|'C'|'Q'|'Z', args) or ('ellipse', [x,y,w,h]) or ('rrect', [x,y,w,h,rx,ry])."""
    tag = el.tag.split("}")[-1]
    filled = el.get("fill") not in (None, "none")
    if tag == "path":
        return parse_path(el.get("d")), filled
    if tag == "circle":
        cx, cy, r = num_attr(el, "cx"), num_attr(el, "cy"), num_attr(el, "r")
        return [("ellipse", [cx - r, cy - r, 2 * r, 2 * r])], filled
    if tag == "ellipse":
        cx, cy, rx, ry = num_attr(el, "cx"), num_attr(el, "cy"), num_attr(el, "rx"), num_attr(el, "ry")
        return [("ellipse", [cx - rx, cy - ry, 2 * rx, 2 * ry])], filled
    if tag == "rect":
        x, y, w, h = num_attr(el, "x"), num_attr(el, "y"), num_attr(el, "width"), num_attr(el, "height")
        rx, ry = el.get("rx"), el.get("ry")
        rx = float(rx) if rx is not None else None
        ry = float(ry) if ry is not None else None
        if rx is None: rx = ry or 0.0
        if ry is None: ry = rx
        rx, ry = min(rx, w / 2), min(ry, h / 2)
        return [("rrect", [x, y, w, h, rx, ry])], filled
    if tag == "line":
        return [("M", [num_attr(el, "x1"), num_attr(el, "y1")]), ("L", [num_attr(el, "x2"), num_attr(el, "y2")])], filled
    if tag in ("polyline", "polygon"):
        nums = [float(v) for v in NUM.findall(el.get("points", ""))]
        pts = list(zip(nums[0::2], nums[1::2]))
        ops = [("M", list(pts[0]))] + [("L", list(p)) for p in pts[1:]]
        if tag == "polygon":
            ops.append(("Z", []))
        return ops, filled
    raise ValueError(f"unsupported SVG element <{tag}>")


def swift_ops(ops, var):
    lines = []
    for op, a in ops:
        if op == "M":
            lines.append(f"{var}.move(to: P({f(a[0])}, {f(a[1])}))")
        elif op == "L":
            lines.append(f"{var}.addLine(to: P({f(a[0])}, {f(a[1])}))")
        elif op == "C":
            lines.append(f"{var}.addCurve(to: P({f(a[4])}, {f(a[5])}), control1: P({f(a[0])}, {f(a[1])}), control2: P({f(a[2])}, {f(a[3])}))")
        elif op == "Q":
            lines.append(f"{var}.addQuadCurve(to: P({f(a[2])}, {f(a[3])}), control: P({f(a[0])}, {f(a[1])}))")
        elif op == "Z":
            lines.append(f"{var}.closeSubpath()")
        elif op == "ellipse":
            lines.append(f"{var}.addEllipse(in: R({f(a[0])}, {f(a[1])}, {f(a[2])}, {f(a[3])}))")
        elif op == "rrect":
            x, y, w, h, rx, ry = a
            if rx == 0 and ry == 0:
                lines.append(f"{var}.addRect(R({f(x)}, {f(y)}, {f(w)}, {f(h)}))")
            else:
                lines.append(f"{var}.addRoundedRect(in: R({f(x)}, {f(y)}, {f(w)}, {f(h)}), cornerSize: CGSize(width: {f(rx)}, height: {f(ry)}), style: .circular)")
    return lines


def svg_ops(ops):
    """Normalised geometry back to SVG, for verification only."""
    parts = []
    for op, a in ops:
        if op in ("M", "L"):
            parts.append(f"{op}{f(a[0])} {f(a[1])}")
        elif op == "C":
            parts.append("C" + " ".join(f(v) for v in a))
        elif op == "Q":
            parts.append("Q" + " ".join(f(v) for v in a))
        elif op == "Z":
            parts.append("Z")
        elif op == "ellipse":
            x, y, w, h = a
            rx, ry = w / 2, h / 2
            parts.append(f"M{f(x)} {f(y+ry)}A{f(rx)} {f(ry)} 0 1 0 {f(x+w)} {f(y+ry)}A{f(rx)} {f(ry)} 0 1 0 {f(x)} {f(y+ry)}Z")
        elif op == "rrect":
            x, y, w, h, rx, ry = a
            parts.append(f"M{f(x+rx)} {f(y)}H{f(x+w-rx)}A{f(rx)} {f(ry)} 0 0 1 {f(x+w)} {f(y+ry)}V{f(y+h-ry)}"
                         f"A{f(rx)} {f(ry)} 0 0 1 {f(x+w-rx)} {f(y+h)}H{f(x+rx)}A{f(rx)} {f(ry)} 0 0 1 {f(x)} {f(y+h-ry)}"
                         f"V{f(y+ry)}A{f(rx)} {f(ry)} 0 0 1 {f(x+rx)} {f(y)}Z")
    return "".join(parts)


def case_name(slug):
    parts = re.split(r"[-_]", slug)
    name = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    if name[0].isdigit():
        name = "_" + name
    reserved = {"repeat", "import", "default", "case", "in", "is", "as", "where", "return", "class",
                "struct", "func", "let", "var", "switch", "for", "while", "if", "else", "self", "Type",
                "Protocol", "init", "deinit", "subscript", "extension", "protocol", "enum", "static",
                "public", "private", "internal", "operator", "do", "catch", "try", "throw", "throws",
                "guard", "defer", "break", "continue", "fallthrough", "true", "false", "nil", "super",
                "inout", "any", "some", "rethrows", "associatedtype", "typealias", "fileprivate", "open"}
    return f"`{name}`" if name in reserved else name


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    repo, manifest, out = Path(argv[1]), Path(argv[2]), Path(argv[3])
    svg_out = Path(argv[argv.index("--svg-out") + 1]) if "--svg-out" in argv else None
    version = (repo / ".lucide-version").read_text().strip() if (repo / ".lucide-version").exists() else "unknown"

    names = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line and line not in names:
            names.append(line)
    if not names:
        raise SystemExit("icons.txt lists no icons")

    missing = [n for n in names if not (repo / "icons" / f"{n}.svg").exists()]
    if missing:
        raise SystemExit("Unknown Lucide icon(s): " + ", ".join(missing) + "\nBrowse names at https://lucide.dev/icons/")

    cases, bodies = [], []
    for slug in names:
        root = ET.parse(repo / "icons" / f"{slug}.svg").getroot()
        if root.get("viewBox") != "0 0 24 24":
            raise SystemExit(f"{slug}: unexpected viewBox {root.get('viewBox')}")
        stroke_lines, fill_lines, svg_parts = [], [], []
        for el in root:
            if el.get("transform"):
                raise SystemExit(f"{slug}: transforms are not supported")
            ops, filled = element_ops(el)
            stroke_lines += swift_ops(ops, "s")
            if filled:
                fill_lines += swift_ops(ops, "f")
            svg_parts.append((svg_ops(ops), filled))
        cname = case_name(slug)
        cases.append(f'    case {cname} = "{slug}"')
        body = [f"        case .{cname}:"]
        body += ["            " + l for l in stroke_lines + fill_lines]
        bodies.append("\n".join(body))
        if svg_out:
            svg_out.mkdir(parents=True, exist_ok=True)
            fill_attr = ' fill="currentColor"'
            els = "".join('<path d="%s"%s/>' % (d, fill_attr if filled else "") for d, filled in svg_parts)
            (svg_out / f"{slug}.svg").write_text(
                '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
                'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
                + els + "</svg>")

    swift = f"""// GENERATED FILE — do not edit by hand.
// Source: Lucide {version} (https://lucide.dev), ISC License — see ThirdPartyNotices.md.
// To add or remove icons, edit scripts/lucide/icons.txt and run: bash scripts/update-lucide.sh

import SwiftUI

/// Lucide icons bundled with Centwise. Raw values are the official Lucide names.
enum Lucide: String, CaseIterable, Sendable {{
{chr(10).join(cases)}
}}

extension Lucide {{
    /// Geometry on Lucide's 24×24 grid. `stroke` is drawn with the icon's
    /// stroke width; `fill` holds the few solid dots some icons use.
    var paths: (stroke: Path, fill: Path) {{
        var s = Path()
        var f = Path()
        switch self {{
{chr(10).join(bodies)}
        }}
        return (s, f)
    }}
}}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {{ CGPoint(x: x, y: y) }}
private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {{ CGRect(x: x, y: y, width: w, height: h) }}
"""
    out.write_text(swift, encoding="utf-8")
    print(f"Wrote {len(names)} Lucide icons to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
