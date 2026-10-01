#!/usr/bin/env python3
"""The Ultimate Dark palette, and everything generated from it.

    python3 palette.py OUTDIR

writes, under OUTDIR:
  usr/share/color-schemes/UltimateDark.colors     the KDE colour scheme
  etc/xdg/kdeglobals                              system default colours + fonts
  usr/share/konsole/UltimateDark.colorscheme    terminal colours
  usr/share/wallpapers/UltimateCognition/...         cognition still (login, lock)

One palette, so the desktop, the terminal and the login screen can't drift.
The look: near-black, soft mint-white text, one neon mint accent and a
teal second. Colour is the accent, not the paint; text stays readable.
"""
import os
import random
import sys

P = {
    "void":     (3, 6, 5),       # wallpaper base
    "bg":       (10, 15, 13),    # windows
    "view":     (7, 11, 9),      # lists, editors
    "alt":      (13, 20, 17),    # alternating rows
    "header":   (6, 10, 8),      # headers, title bars
    "button":   (17, 26, 22),
    "raised":   (22, 34, 28),
    "text":     (207, 232, 214), # soft mint-white
    "dim":      (111, 138, 122),
    "accent":   (0, 255, 156),   # neon mint
    "accent2":  (61, 255, 178),  # hover
    "deep":     (0, 199, 122),   # selection
    "on_acc":   (3, 20, 12),     # text on the accent
    "link":     (63, 224, 197),  # teal
    "visited":  (127, 209, 168),
    "neg":      (255, 77, 109),
    "neutral":  (245, 197, 66),
    "pos":      (0, 255, 156),
}


def rgb(name):
    return ",".join(str(c) for c in P[name])


def group(name, bg, alt, fg="text", dim="dim", active="accent"):
    return f"""[{name}]
BackgroundAlternate={rgb(alt)}
BackgroundNormal={rgb(bg)}
DecorationFocus={rgb('accent')}
DecorationHover={rgb('accent2')}
ForegroundActive={rgb(active)}
ForegroundInactive={rgb(dim)}
ForegroundLink={rgb('link')}
ForegroundNegative={rgb('neg')}
ForegroundNeutral={rgb('neutral')}
ForegroundNormal={rgb(fg)}
ForegroundPositive={rgb('pos')}
ForegroundVisited={rgb('visited')}
"""


def colour_groups():
    return "\n".join([
        """[ColorEffects:Disabled]
Color=10,15,13
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2
""",
        """[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=10,15,13
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0
""",
        group("Colors:Button", "button", "raised"),
        group("Colors:Complementary", "header", "bg"),
        group("Colors:Header", "header", "bg"),
        group("Colors:Header][Inactive", "header", "bg"),
        group("Colors:Selection", "deep", "accent", fg="on_acc", dim="on_acc", active="on_acc"),
        group("Colors:Tooltip", "header", "bg"),
        group("Colors:View", "view", "alt"),
        group("Colors:Window", "bg", "alt"),
        f"""[WM]
activeBackground={rgb('header')}
activeBlend={rgb('accent')}
activeForeground={rgb('text')}
inactiveBackground={rgb('header')}
inactiveBlend={rgb('dim')}
inactiveForeground={rgb('dim')}
""",
    ])


def colour_scheme():
    return colour_groups() + """
[General]
ColorScheme=UltimateDark
Name=Ultimate Dark
shadeSortColumn=true

[KDE]
contrast=4
"""


def kdeglobals():
    # Plasma reads colours from kdeglobals itself, not from the scheme name,
    # so the system default carries the whole scheme. Users who pick another
    # scheme override this in ~/.config/kdeglobals as usual.
    return colour_groups() + """
[General]
ColorScheme=UltimateDark
font=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
menuFont=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
toolBarFont=Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
smallestReadableFont=Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
fixed=JetBrains Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

[KDE]
LookAndFeelPackage=org.ultimatelinux.desktop
contrast=4

[Icons]
Theme=breeze-dark

[WM]
activeFont=JetBrains Mono,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1
"""


def konsole():
    ansi = [  # normal, then bright
        ("void", (111, 138, 122)),
        ((255, 77, 109), (255, 120, 145)),
        ((0, 214, 130), (61, 255, 178)),
        ((245, 197, 66), (255, 222, 120)),
        ((63, 160, 224), (110, 190, 245)),
        ((180, 120, 255), (205, 160, 255)),
        ((63, 224, 197), (120, 245, 225)),
        ((207, 232, 214), (240, 255, 245)),
    ]
    def c(v):
        return ",".join(map(str, P[v] if isinstance(v, str) else v))
    out = [f"[Background]\nColor={c('void')}\n", f"[BackgroundIntense]\nColor={c('bg')}\n",
           f"[Foreground]\nColor={c('text')}\n", f"[ForegroundIntense]\nColor={c('accent')}\n"]
    for i, (n, b) in enumerate(ansi):
        out.append(f"[Color{i}]\nColor={c(n)}\n")
        out.append(f"[Color{i}Intense]\nColor={c(b)}\n")
    out.append("[General]\nDescription=Ultimate Dark\nOpacity=0.92\nBlur=true\n")
    return "\n".join(out)


# Fragments of the language of machine thought, for the wallpaper.
THOUGHTS = [
    "attn = softmax(Q·Kᵀ / √d)", "h₁₂ ← gelu(W·x + b)", "embed(\"why\") ∈ ℝ⁴⁰⁹⁶",
    "p(next | ctx) = 0.873", "∇L → 3.1e-4", "plan → act → observe",
    "recall(ctx, k=8)", "think { hypothesis₃ }", "token[4127] = \"reason\"",
    "score = ⟨q, k⟩", "layer 31 / head 7", "if uncertain: ask()",
    "memory.write(fact)", "chain = [obs, infer, check]", "Σ wᵢxᵢ", "argmax logits",
    "context: 128k", "loss ↓ 0.0112", "tool_use: search()", "verify(answer)",
    "weights ≈ 10¹¹", "residual += Δh", "latent ⊕ prompt", "self.reflect()",
]


def _mono(size):
    import subprocess
    from PIL import ImageFont
    files = []
    for q in ("DejaVu Sans Mono", "monospace"):
        try:
            files.append(subprocess.run(["fc-match", "-f", "%{file}", q],
                                        capture_output=True, text=True).stdout.strip())
        except OSError:
            pass
    files += ["/usr/share/fonts/TTF/DejaVuSansMono.ttf",
              "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf"]
    for f in files:
        if f and os.path.exists(f):
            return ImageFont.truetype(f, size)
    sys.exit("no monospace font found (install DejaVu Sans Mono)")


def cognition(w=3840, h=2160, seed=2026):
    """The network: layered nodes, faint connections, a few lit paths."""
    rnd = random.Random(seed)
    layers = 9
    nodes = []            # (x, y, layer)
    for L in range(layers):
        count = rnd.randint(7, 13)
        cx = w * (0.06 + 0.88 * L / (layers - 1))
        for i in range(count):
            y = h * (0.1 + 0.8 * (i + rnd.random() * 0.8) / count)
            x = cx + rnd.gauss(0, w * 0.018)
            nodes.append((x, y, L))
    edges = []
    by_layer = [[i for i, n in enumerate(nodes) if n[2] == L] for L in range(layers)]
    for L in range(layers - 1):
        for a in by_layer[L]:
            nxt = sorted(by_layer[L + 1], key=lambda b: abs(nodes[b][1] - nodes[a][1]))
            for b in nxt[:rnd.randint(2, 4)]:
                edges.append((a, b))
    # A few thoughts: paths through the network, one node per layer.
    paths = []
    for _ in range(4):
        cur = rnd.choice(by_layer[0])
        path = [cur]
        for L in range(1, layers):
            cur = rnd.choice([b for a, b in edges if a == cur])
            path.append(cur)
        paths.append(path)
    return nodes, edges, paths


def wallpaper(path, w=3840, h=2160):
    """A still of the cognition network, for login, lock and fallback."""
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
    rnd = random.Random(7)
    nodes, edges, paths = cognition(w, h)
    lit_edges = {(p[i], p[i + 1]) for p in paths for i in range(len(p) - 1)}
    lit_nodes = {n for p in paths for n in p}

    base = Image.new("RGB", (w, h), P["void"])
    # A soft teal nebula behind the network, off-centre.
    neb = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(neb).ellipse([w * 0.35, h * 0.1, w * 1.05, h * 0.95], fill=(0, 38, 34))
    base = ImageChops.add(base, neb.filter(ImageFilter.GaussianBlur(400)))

    lines = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(lines)
    for a, b in edges:
        if (a, b) not in lit_edges:
            d.line([nodes[a][:2], nodes[b][:2]], fill=(10, 60, 52), width=2)
    for a, b in lit_edges:
        d.line([nodes[a][:2], nodes[b][:2]], fill=(0, 230, 160), width=3)
    for i, (x, y, _L) in enumerate(nodes):
        r = 9 if i in lit_nodes else 5
        fill = (170, 255, 220) if i in lit_nodes else (30, 110, 92)
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)
    # Signal pulses part-way along the lit edges.
    for a, b in lit_edges:
        t = rnd.random()
        x = nodes[a][0] + (nodes[b][0] - nodes[a][0]) * t
        y = nodes[a][1] + (nodes[b][1] - nodes[a][1]) * t
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(220, 255, 240))

    # Thought fragments: dim across the field, brighter by the lit nodes.
    text = Image.new("RGB", (w, h), (0, 0, 0))
    td = ImageDraw.Draw(text)
    small, big = _mono(30), _mono(36)
    # Each bright label gets its own lit node, spread across the layers,
    # and stays inside the frame.
    lit = sorted(lit_nodes, key=lambda n: (nodes[n][2], nodes[n][1]))
    anchors = lit[::max(1, len(lit) // 8)][:8]
    taken = []

    def free(x, y, tw, th):
        box = (x - 20, y - 12, x + tw + 20, y + th + 12)
        if any(box[0] < b[2] and b[0] < box[2] and box[1] < b[3] and b[1] < box[3]
               for b in taken):
            return False
        taken.append(box)
        return True

    for k, phrase in enumerate(rnd.sample(THOUGHTS, len(THOUGHTS))):
        if k < len(anchors):
            x, y, _L = nodes[anchors[k]]
            tw = td.textlength(phrase, font=big)
            x = min(x + 22, w - tw - 40)
            if free(x, y - 44, tw, 40):
                td.text((x, y - 44), phrase, fill=(120, 240, 200), font=big)
            continue
        tw = td.textlength(phrase, font=small)
        for _try in range(40):
            x = rnd.uniform(0.03, 0.97) * w - tw * rnd.random()
            y = rnd.uniform(0.05, 0.92) * h
            if 0 < x < w - tw and free(x, y, tw, 34):
                td.text((x, y), phrase, fill=(34, 92, 80), font=small)
                break

    glow = ImageChops.add(lines, text).filter(ImageFilter.GaussianBlur(14))
    img = ImageChops.add(base, lines)
    img = ImageChops.add(img, text)
    img = ImageChops.add(img, glow.point(lambda v: int(v * 0.8)))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)


def main(out):
    def write(rel, text):
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(text)
    write("usr/share/color-schemes/UltimateDark.colors", colour_scheme())
    write("etc/xdg/kdeglobals", kdeglobals())
    write("usr/share/konsole/UltimateDark.colorscheme", konsole())
    wallpaper(os.path.join(out, "usr/share/wallpapers/UltimateCognition/contents/images/3840x2160.png"))


if __name__ == "__main__":
    main(sys.argv[1])
