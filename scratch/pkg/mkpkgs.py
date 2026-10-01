#!/usr/bin/env python3
"""Turn the desktop layer's files into pacman packages, one per BLFS build
step, from attribute.py's map. Runs in an Arch container with the build tree
at /b (read-only is enough) and the planner's home at /p:

    mkpkgs.py <attribution.json> <outdir>

Per package:
  * name: the BLFS id, lower-cased; version from the book (packages.xml), or
    for hand steps from their source file name;
  * files: the files its build last wrote (plus their parent directories);
  * depends: the book's required and recommended dependencies that are
    themselves packages here or in the base system;
  * backup: every file under /etc, so upgrades never overwrite local edits;
  * an install script that creates the groups and users its build created.
BLFS rebuilt a few base packages (systemd with PAM, curl, the kernel, ...):
those become a new release of the same name holding the base package's
files and the rebuild's, so installing them replaces the base entry.

Writes <name>-<ver>-<rel>-x86_64.pkg.tar.zst into outdir and manifest.json.
"""
import glob, hashlib, json, os, re, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor
import xml.etree.ElementTree as ET

ROOT, PLAN = "/b", "/p/blfs_root"
att = json.load(open(sys.argv[1]))
outdir = sys.argv[2]
os.makedirs(outdir, exist_ok=True)
BUILDDATE = int(time.time())
PACKAGER = "Ultimate Linux build <https://github.com/cwoodall85/redcyfers-ultimate-linux>"

# --- the book: versions and dependencies -----------------------------------------
book = {}
# Packages, and the modules inside them (each KDE framework, Plasma part,
# X library, Python module...) which the BLFS tools build as their own steps.
# A module has the group's dependencies too: the book records the shared ones
# on the group only.
def deps_of(el):
    return [d.get("name") for d in el.findall("dependency")
            if d.get("status") in ("required", "recommended") and d.get("name")]
tree = ET.parse(os.path.join(PLAN, "packages.xml"))
for pkg in tree.iter("package"):
    name = pkg.findtext("name")
    if not name:
        continue
    book.setdefault(name, {"version": (pkg.findtext("version") or "").strip(), "deps": deps_of(pkg)})
    # In a group (plasma-build, kf6 frameworks, xorg libraries...) the shared
    # dependencies sit on the first module, and each module needs the ones
    # built before it: depend on those shared ones and on the previous module.
    mods = [m for m in pkg.iter("module") if m.findtext("name")]
    shared = deps_of(mods[0]) if mods else []
    for i, mod in enumerate(mods):
        mname = mod.findtext("name")
        deps = deps_of(mod) + [d for d in shared if d != mname]
        if i:
            deps.append(mods[i - 1].findtext("name"))
        book.setdefault(mname, {"version": (mod.findtext("version") or "").strip(),
                                "deps": list(dict.fromkeys(deps))})
def in_book(pid):
    """The book's entry for a build id ("gdk-pixbuf-pass1" is gdk-pixbuf)."""
    return book.get(pid) or book.get(re.sub(r"-pass\d+$", "", pid)) or {}

# Packages that aren't a book or hand-step build (secureboot/sign.sh's):
# the versions of what they carry.
VERSIONS = {"ultimate-secureboot": "2.14+shim16.1"}

def pkgname(pid):
    n = re.sub(r"[^a-z0-9@._+-]", "-", pid.lower())
    return n.lstrip("-.") or "unnamed"

# --- the base system's pacman packages -----------------------------------------------
base = {}   # name -> {"version": "x-y", "files": [...]}
# The base system as it was before the desktop layer was packaged (BASE_DB).
BASE_DB = os.environ.get("BASE_DB", os.path.join(ROOT, "var/lib/pacman/local"))
for d in glob.glob(os.path.join(BASE_DB, "*/")):
    desc = open(os.path.join(d, "desc")).read().split("\n\n")
    fields = {}
    for block in desc:
        lines = block.strip().split("\n")
        if lines and lines[0].startswith("%"):
            fields[lines[0]] = lines[1:]
    name, ver = fields["%NAME%"][0], fields["%VERSION%"][0]
    files = []
    sect = None
    for line in open(os.path.join(d, "files")).read().splitlines():
        if line.startswith("%"):
            sect = line; continue
        if sect == "%FILES%" and line:
            files.append("/" + line)
    base[name] = {"version": ver, "files": files}

# Base packages a BLFS build of the same name rewrote (systemd with PAM, the
# kernel, ...) are replaced by that build. A few files a different package's
# build overwrote (whois's mkpasswd over expect's) stay with their base owner.
replaced = {}
for path, owner, pid in att["overlaps"]:
    bname = owner.rsplit("-", 2)[0]
    if pkgname(pid) == bname:
        replaced.setdefault(pid, set()).add(bname)

# --- scripts: hand-step versions, accounts -----------------------------------------------
scripts = {}
for d in glob.glob(os.path.join(ROOT, "blfs/scripts*")):
    for f in os.listdir(d):
        m = re.match(r"\d+-[a-z]+-(.+)$", f)
        if m:
            scripts.setdefault(m.group(1), []).append(os.path.join(d, f))

def hand_version(pid):
    for f in scripts.get(pid, []):
        text = open(f, errors="replace").read()
        m = (re.search(r"^FILE=\S*?-v?(\d[\w.]*?)(\.orig)?\.(tar|tgz|zip)", text, re.M)
             or re.search(r"/sources/[A-Za-z][\w.+-]*?-v?(\d[\w.]*?)\.(tar|tgz|zip)", text))
        if m:
            return m.group(1)
    return None

def accounts(pid):
    cmds = []
    for f in scripts.get(pid, []):
        for line in open(f, errors="replace").read().splitlines():
            s = line.strip()
            if re.match(r"^(/usr/sbin/)?(groupadd|useradd)\s", s) and "EDITME" not in s:
                cmds.append(s.rstrip("\\ ").split(" #")[0])
    return list(dict.fromkeys(cmds))

def pkgver(v):
    v = re.sub(r"[^A-Za-z0-9._+]", "_", v or "1")
    return v or "1"

# --- plan the packages ---------------------------------------------------------------------
names = {pid: pkgname(pid) for pid in att["packages"]}
by_name = {}
for pid, n in names.items():
    by_name.setdefault(n, []).append(pid)
plans = []
for n, pids in sorted(by_name.items()):
    files = sorted(set(f for pid in pids for f in att["packages"][pid]))
    pid = pids[0]
    ver = VERSIONS.get(pid) or in_book(pid).get("version") or hand_version(pid) or "13.1"
    rel = 1
    repl = sorted(set(b for p in pids for b in replaced.get(p, ())))
    if n in base:
        if n not in repl:
            repl.append(n)
    for b in repl:
        # a rebuild of a base package: carry the base package's files still
        # present, and release above it
        files = sorted(set(files) | {f for f in base[b]["files"]
                                     if not f.endswith("/") and os.path.lexists(ROOT + f)})
        if b == n:
            bver, brel = base[b]["version"].rsplit("-", 1)
            if pkgver(ver) == bver:
                rel = int(brel) + 1
    deps = []
    for p in pids:
        for dname in in_book(p).get("deps", []):
            dn = pkgname(dname)
            if dn != n and (dn in by_name or dn in base) and dn not in deps:
                deps.append(dn)
    plans.append({"name": n, "ids": pids, "version": f"{pkgver(ver)}-{rel}",
                  "files": files, "depends": deps, "replaces_base": [b for b in repl if b != n],
                  "accounts": [c for p in pids for c in accounts(p)]})

# Names of base packages replaced under another name must not linger: the
# replacing package "replaces" and "conflicts" with them.
# Names the Ultimate packages (shared with the Arch-based track) depend on,
# and which of our packages provides each.
PROVIDES = {"pygobject3": ["python-gobject"], "libadwaita1": ["libadwaita"],
            "webkitgtk": ["webkitgtk-6.0"], "vte": ["vte4"],
            "dejavu-fonts": ["ttf-dejavu"]}
for p in plans:
    p["provides"] = PROVIDES.get(p["name"], [])
# "python" is the base system's "Python" (jhalfs keeps the book's name): an
# empty package of that name, depending on it, lets packages ask for either.
if "Python" in base and "python" not in by_name:
    plans.append({"name": "python", "ids": ["Python"], "version": base["Python"]["version"],
                  "files": [], "depends": ["Python"], "replaces_base": [], "accounts": [],
                  "provides": []})

# --- build them ---------------------------------------------------------------------------------
def parents(files):
    dirs = set()
    for f in files:
        d = os.path.dirname(f)
        while d not in ("/", ""):
            dirs.add(d); d = os.path.dirname(d)
    return sorted(dirs)

def build(p):
    n, v = p["name"], p["version"]
    out = os.path.join(outdir, f"{n}-{v}-x86_64.pkg.tar.zst")
    files = p["files"]
    size = 0
    for f in files:
        try:
            st = os.lstat(ROOT + f)
            if not os.path.islink(ROOT + f):
                size += st.st_size
        except OSError:
            pass
    with tempfile.TemporaryDirectory() as meta:
        ids = ", ".join(p["ids"])
        info = [f"pkgname = {n}", f"pkgbase = {n}", f"pkgver = {v}",
                f"pkgdesc = {ids} (BLFS 13.1, built from source for Ultimate Linux)",
                "url = https://www.linuxfromscratch.org/blfs/", f"builddate = {BUILDDATE}",
                f"packager = {PACKAGER}", f"size = {size}", "arch = x86_64", "license = custom"]
        for b in p["replaces_base"]:
            info += [f"replaces = {b}", f"conflicts = {b}", f"provides = {b}"]
        info += [f"provides = {x}" for x in p.get("provides", [])]
        info += [f"depend = {d}" for d in p["depends"]]
        info += [f"backup = {f[1:]}" for f in files if f.startswith("/etc/") and not os.path.islink(ROOT + f)]
        open(os.path.join(meta, ".PKGINFO"), "w").write("\n".join(info) + "\n")
        metafiles = [".PKGINFO"]
        if p["accounts"]:
            body = "\n".join(f"  {c} 2>/dev/null || true" for c in p["accounts"])
            open(os.path.join(meta, ".INSTALL"), "w").write(
                f"post_install() {{\n{body}\n}}\n\npost_upgrade() {{\n  post_install\n}}\n")
            metafiles.append(".INSTALL")
        entries = [d[1:] for d in parents(files)] + [f[1:] for f in files]
        # bsdtar reads options only before the first name; a -T list can
        # change directory itself ("-C" on one line, the directory on the next).
        def listing(names_meta):
            p = os.path.join(meta, "list")
            open(p, "w").write("\n".join(["-C", meta, *names_meta, "-C", ROOT, *entries]) + "\n")
            return p
        mt = "--options=!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link"
        subprocess.run(["bsdtar", "-czf", os.path.join(meta, ".MTREE"), "--format=mtree", mt,
                        "-n", "--numeric-owner", "--no-xattrs", "--no-acls", "--no-fflags", "-T", listing(metafiles)], check=True)
        subprocess.run(["bsdtar", "-cf", out, "--zstd", "--options=zstd:compression-level=3",
                        "-n", "--numeric-owner", "--no-xattrs", "--no-acls", "--no-fflags",
                        "-T", listing([".MTREE", *metafiles])], check=True)
    return n, v, len(files), size, os.path.getsize(out)

with ThreadPoolExecutor(max_workers=os.cpu_count()) as ex:
    results = list(ex.map(build, plans))
json.dump([{**p, "files": len(p["files"])} for p in plans], open(os.path.join(outdir, "manifest.json"), "w"), indent=1)
tot_u = sum(r[3] for r in results); tot_c = sum(r[4] for r in results)
print(f"{len(results)} packages, {sum(r[2] for r in results)} files, "
      f"{tot_u / 2**30:.1f} GiB installed, {tot_c / 2**30:.2f} GiB compressed")
for p in plans:
    if p["replaces_base"] or p["name"] in base:
        print(f"  replaces base: {p['name']} {p['version']}  (+{', '.join(p['replaces_base']) or 'same name'})")
