#!/usr/bin/env python3
"""The Ultimate family's logos, in the Cognition style: each mark is drawn
from nodes and links (the wallpaper's thinking network), one hue per app,
three tones of it (bright nodes, mid links, dim background), on the same
dark tile.

    make-logos.py OUTDIR      writes <name>.svg (the app icon, a tile) and
                              <name>-mark.svg (the symbol alone) for each

Ultimate Linux is mint, the brand; Ultimate SSH teal; Ultimate Mail blue
(it was blue before); Ultimate Chat amber.
"""

import os
import sys

HUES = {  # bright, mid, dim
    "mint":  ("#00ff9c", "#00c77a", "#0d3b28"),
    "teal":  ("#3fe0c5", "#26a896", "#0e3a34"),
    "blue":  ("#5cb4ff", "#2f7fd6", "#10304f"),
    "amber": ("#f5c542", "#c9962a", "#3d2f10"),
}

# The faint network behind every mark: the same on each tile, so they read
# as one family. (x, y) nodes and index pairs for links.
BG_NODES = [(22, 26), (46, 16), (84, 20), (108, 34), (112, 70), (100, 106),
            (70, 112), (30, 104), (14, 66), (58, 38), (92, 60), (40, 78)]
BG_LINKS = [(0, 1), (1, 9), (9, 2), (2, 3), (3, 10), (10, 4), (4, 5), (5, 6),
            (6, 11), (11, 7), (7, 8), (8, 0), (9, 11), (10, 6), (1, 2)]


def node(x, y, r, fill):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>'


def links(points, pairs, stroke, width):
    return "".join(
        f'<line x1="{points[a][0]}" y1="{points[a][1]}" x2="{points[b][0]}" y2="{points[b][1]}" '
        f'stroke="{stroke}" stroke-width="{width}" stroke-linecap="round"/>' for a, b in pairs)


def path(d, stroke, width, fill="none"):
    return (f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


# --- the marks: (lines-and-paths, nodes) in the mid and bright tones ------------------

def mark_linux(b, m):
    # A "U" whose arms end in nodes, holding a small network -- a diamond of
    # thought resting on its base.
    lines = path("M34 26 V68 A30 30 0 0 0 94 68 V26", m, 8)
    net = [(64, 50), (51, 72), (77, 72), (64, 98)]
    lines += links(net, [(0, 1), (1, 2), (2, 0), (1, 3), (2, 3)], m, 3.5)
    nodes = "".join(node(x, y, 5.5, b) for x, y in net[:3])
    nodes += node(34, 26, 8, b) + node(94, 26, 8, b) + node(64, 98, 7.5, b)
    return lines, nodes


def mark_ssh(b, m):
    # A prompt: ">" of three linked nodes, a cursor, and a link out to the
    # remote machine in the corner.
    lines = path("M34 40 L64 64 L34 88", m, 8)
    lines += f'<line x1="74" y1="90" x2="98" y2="90" stroke="{b}" stroke-width="8" stroke-linecap="round"/>'
    lines += (f'<path d="M64 64 Q84 58 96 36" fill="none" stroke="{m}" stroke-width="3.5" '
              f'stroke-linecap="round" stroke-dasharray="0.1 7"/>')
    nodes = node(34, 40, 7, b) + node(64, 64, 8, b) + node(34, 88, 7, b) + node(96, 36, 6, b)
    return lines, nodes


def mark_mail(b, m):
    # An envelope: the outline as links between corner nodes, the flap
    # meeting at a bright node.
    c = [(24, 38), (104, 38), (104, 92), (24, 92)]
    lines = links(c, [(0, 1), (1, 2), (2, 3), (3, 0)], m, 7)
    lines += links([(24, 38), (64, 68), (104, 38)], [(0, 1), (1, 2)], m, 7)
    lines += links([(24, 92), (52, 70), (104, 92), (76, 70)], [(0, 1), (2, 3)], m, 3.5)
    nodes = "".join(node(x, y, 6, b) for x, y in c) + node(64, 68, 8.5, b)
    return lines, nodes


def mark_chat(b, m):
    # A speech bubble with a small conversation inside: three linked nodes.
    lines = path("M42 28 H86 A18 18 0 0 1 104 46 V66 A18 18 0 0 1 86 84 H56 L38 102 L40 84 "
                 "A18 18 0 0 1 24 66 V46 A18 18 0 0 1 42 28 Z", m, 7)
    inner = [(44, 62), (64, 48), (84, 62)]
    lines += links(inner, [(0, 1), (1, 2), (0, 2)], m, 3.5)
    nodes = "".join(node(x, y, 7, b) for x, y in inner)
    return lines, nodes


MARKS = {
    "ultimate-linux": (mark_linux, "mint", "Ultimate Linux"),
    "ultimate-ssh": (mark_ssh, "teal", "Ultimate SSH"),
    "ultimate-mail": (mark_mail, "blue", "Ultimate Mail"),
    "ultimate-chat": (mark_chat, "amber", "Ultimate Chat"),
}


def glow(name, color):
    return (f'<filter id="{name}" x="-50%" y="-50%" width="200%" height="200%">'
            f'<feGaussianBlur stdDeviation="2.6" result="b"/>'
            f'<feFlood flood-color="{color}" flood-opacity="0.75"/>'
            f'<feComposite in2="b" operator="in" result="g"/>'
            f'<feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')


def svg(key, tile=True):
    fn, hue, title = MARKS[key]
    b, m, d = HUES[hue]
    lines, nodes = fn(b, m)
    defs = glow("glow", b)
    body = ""
    if tile:
        defs += ('<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
                 '<stop offset="0" stop-color="#0d1512"/><stop offset="1" stop-color="#040806"/>'
                 '</linearGradient>')
        body += (f'<rect x="4" y="4" width="120" height="120" rx="28" fill="url(#bg)"/>'
                 f'<rect x="5" y="5" width="118" height="118" rx="27" fill="none" '
                 f'stroke="{m}" stroke-opacity="0.35" stroke-width="2"/>')
        body += f'<g opacity="0.55">{links(BG_NODES, BG_LINKS, d, 1.5)}'
        body += "".join(node(x, y, 2.2, d) for x, y in BG_NODES) + "</g>"
    body += f'<g>{lines}</g><g filter="url(#glow)">{nodes}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">'
            f'<title>{title}</title><defs>{defs}</defs>{body}</svg>\n')


def main(out):
    os.makedirs(out, exist_ok=True)
    for key in MARKS:
        for tile, suffix in ((True, ""), (False, "-mark")):
            with open(os.path.join(out, f"{key}{suffix}.svg"), "w") as fh:
                fh.write(svg(key, tile))
    print("wrote", ", ".join(MARKS), "to", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
