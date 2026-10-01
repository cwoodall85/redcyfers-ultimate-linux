#!/usr/bin/env python3
"""For each kernel module name, the Kconfig options that build it (from the
kernel source's Makefiles), and whether a config enables them.

    module-options.py <kernel-source-dir> <file-of-module-names> <.config>

Prints one line per module: ok / MISSING / ?? (no Makefile rule found),
the module, and its options with their values in the config. Used by
check-host-drivers.sh.
"""
import os, re, sys
src, mods, cfg = sys.argv[1], sys.argv[2], sys.argv[3]
conf = {}
for l in open(cfg):
    m = re.match(r"(CONFIG_\w+)=(.*)", l)
    if m: conf[m.group(1)] = m.group(2)
    m = re.match(r"# (CONFIG_\w+) is not set", l)
    if m: conf[m.group(1)] = "n"
objmap = {}   # module name (underscored) -> set of (CONFIG, dir)
for root, _, files in os.walk(src):
    for f in files:
        if f not in ("Makefile", "Kbuild"): continue
        txt = open(os.path.join(root, f), errors="replace").read().replace("\\\n", " ")
        for m in re.finditer(r"obj-\$\((CONFIG_\w+)\)\s*[+:]?=\s*([^\n]+)", txt):
            for o in m.group(2).split():
                if o.endswith(".o"):
                    objmap.setdefault(o[:-2].replace("-", "_"), set()).add((m.group(1), os.path.relpath(root, src)))
for mod in open(mods).read().split():
    hits = objmap.get(mod)
    if not hits:
        print(f"??\t{mod}\t(no Makefile rule in 7.1.8)"); continue
    vals = sorted({(c, conf.get(c, "absent")) for c, _ in hits})
    ok = any(v in ("y", "m") for _, v in vals)
    print(("ok" if ok else "MISSING") + f"\t{mod}\t" + ", ".join(f"{c}={v}" for c, v in vals))
