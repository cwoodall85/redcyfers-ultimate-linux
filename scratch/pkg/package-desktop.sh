#!/bin/bash
# Package the desktop layer: every file the BLFS stages installed becomes part
# of a pacman package (one per build step), registered in the system's
# database, plus a repository of those packages for updating other machines.
#
#   scratch/pkg/package-desktop.sh         (after the BLFS stages; rerunnable)
#
# Output: scratch/out/desktop-pkgs/ (*.pkg.tar.zst, ultimate-desktop.db,
# manifest.json). The base system's database as it was before the first run
# is kept in the build tree (/blfs/base-pacman-local), so reruns still know
# which files are the desktop layer's.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$here/out/desktop-pkgs
rm -rf "$out" && mkdir -p "$out"
podman run --rm --security-opt label=disable -e MIN_DESKTOP_PKGS \
  -v ultimate-lfs-build:/b -v ultimate-blfs-plan:/p:ro -v "$here/pkg:/pkg:ro" \
  -v "$here/out:/logs:ro" -v "$out:/out" -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest bash -c '
set -euo pipefail
pacman -Sy --noconfirm --needed python >/dev/null 2>&1
if [[ ! -d /b/blfs/base-pacman-local ]]; then
  # first run: the database holds the base system (and the Ultimate layer) only
  if grep -qs "Ultimate Linux build" /b/var/lib/pacman/local/*/desc; then
    echo "the database already has desktop packages but no base snapshot" >&2; exit 1
  fi
  cp -a /b/var/lib/pacman/local /b/blfs/base-pacman-local
fi
export BASE_DB=/b/blfs/base-pacman-local
bash /pkg/fixups.sh /b >/dev/null
w=$(mktemp -d)
stat -c "%n %.9W %.9Y" /b/blfs/logs/*.log > $w/logs-times.txt
python3 /pkg/attribute.py /b /logs $w/attribution.json
python3 /pkg/mkpkgs.py $w/attribution.json /out
cp $w/attribution.json /out/
# Attribution goes by file change times. A build tree that was copied (a
# restore, a migration) has fresh ctimes, and almost nothing attributes.
# Stop before the database reset below throws the old registrations away.
n=$(ls /out/*.pkg.tar.zst 2>/dev/null | wc -l)
if (( n < ${MIN_DESKTOP_PKGS:-100} )); then
  echo "only $n desktop packages attributed (expected ~600): was the build tree copied?" >&2
  echo "the database is left as it was; set MIN_DESKTOP_PKGS=0 to force" >&2
  exit 1
fi
# Register from a clean slate: the base snapshot, plus any newer entries that
# are not ours (the Ultimate layer installed after the snapshot, say), then
# every desktop package. Reruns never pile on earlier registrations.
python3 - <<"PY"
import os, shutil
L, B = "/b/var/lib/pacman/local", "/b/blfs/base-pacman-local"
def name_of(d):
    lines = open(os.path.join(d, "desc")).read().split("\n")
    return lines[lines.index("%NAME%") + 1]
def ours(d):
    return "Ultimate Linux build" in open(os.path.join(d, "desc")).read()
keep = {}
for e in os.listdir(L):
    d = os.path.join(L, e)
    if os.path.isdir(d) and not ours(d):
        keep[name_of(d)] = d
shutil.rmtree(L + ".new", ignore_errors=True)
shutil.copytree(B, L + ".new", symlinks=True)
for e in os.listdir(L + ".new"):
    d = os.path.join(L + ".new", e)
    if os.path.isdir(d) and name_of(d) in keep and os.path.basename(keep[name_of(d)]) != e:
        shutil.rmtree(d)                      # a newer non-desktop entry replaces it
for n, d in keep.items():
    t = os.path.join(L + ".new", os.path.basename(d))
    if not os.path.exists(t):
        shutil.copytree(d, t, symlinks=True)
shutil.rmtree(L); os.rename(L + ".new", L)
print(f"database reset to the base snapshot plus {len(keep)} non-desktop entries")
PY
bash /pkg/register.sh /out/*.pkg.tar.zst
repo-add -q /out/ultimate-desktop.db.tar.gz /out/*.pkg.tar.zst
'
ls "$out" | grep -c 'pkg.tar.zst$' | sed 's/$/ packages in out\/desktop-pkgs/'
