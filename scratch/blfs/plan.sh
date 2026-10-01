#!/bin/bash
# Runs INSIDE the planner container (see ../plan-blfs.sh). Marks the LFS
# base as installed, applies targets.conf, and has the BLFS tools resolve
# dependencies and generate one build script per package into
# /root/blfs_root/scripts, in build order.
set -euo pipefail
pacman -Sy --noconfirm --needed libxslt docbook-xml docbook-xsl git python which sudo wget lynx base-devel >/dev/null 2>&1

# A fresh machine (CI): set up the BLFS tools the way jhalfs's
# install-blfs-tools.sh does, unattended, from the jhalfs checkout and the
# books plan-blfs.sh mounts, then our saved tool settings.
if [[ ! -f /root/blfs_root/Makefile ]]; then
  [[ -d /jhalfs-src ]] || { echo "no /root/blfs_root and no jhalfs source (JHALFS_SRC)" >&2; exit 1; }
  rm -rf /tmp/jhalfs && cp -r /jhalfs-src /tmp/jhalfs && cd /tmp/jhalfs
  echo yes | HOME=/root BLFS_ROOT=/blfs_root TRACKING_DIR=/root/trackdir INITSYS=systemd \
    BLFS_BOOK=/books/blfs LFS_BOOK=/books/lfs BLFS_COMMIT=r13.1 LFS_COMMIT=r13.1 \
    ./install-blfs-tools.sh >/tmp/install-blfs-tools.log 2>&1 ||
    { tail -20 /tmp/install-blfs-tools.log >&2; exit 1; }
  [[ -f /root/blfs_root/packages.xml ]] || { tail -20 /tmp/install-blfs-tools.log >&2; exit 1; }
  cp /work/blfs/blfs-tools.configuration /root/blfs_root/configuration
  echo "BLFS tools installed in /root/blfs_root"
fi
cd /root/blfs_root

# Everything LFS 13.1 built is installed, at the book's version.
python3 - <<'PY'
import re
pk = open("packages.xml").read()
lfs = pk[pk.index("<name>LFS Packages</name>"):pk.index("<name>Post LFS Configuration")]
entries = re.findall(r"<package>\s*<name>([^<]+)</name>\s*<version>([^<]*)</version>", lfs)
out = ['<?xml version="1.0" encoding="ISO-8859-1"?>', "",
       '<!DOCTYPE sublist SYSTEM "/root/blfs_root/packdesc.dtd">', "<sublist>",
       "  <name>Installed</name>"]
for n, v in entries:
    out.append(f"  <package><name>{n}</name><version>{v}</version></package>")
out.append("</sublist>")
open("/root/trackdir/instpkg.xml", "w").write("\n".join(out) + "\n")
print(f"marked {len(entries)} LFS packages installed")
PY

STAGE=${STAGE:-1}
# Stage 2 onward: everything the earlier stages built is installed too, so
# the planner doesn't schedule it again. The done markers in the build
# volume (mounted at /built) name each finished script NNNN-z-<id>.
if [[ $STAGE != 1 && -d /built/blfs ]]; then
  python3 - <<'PY'
import os, re
pk = open("packages.xml").read()
versions = dict(re.findall(r"<package>\s*<name>([^<]+)</name>\s*<version>([^<]*)</version>", pk))
done = set()
for d in os.listdir("/built/blfs"):
    if d.startswith("done"):
        for f in os.listdir(os.path.join("/built/blfs", d)):
            m = re.match(r"\d+-z+-(.+)$", f)
            if m:
                done.add(m.group(1))
track = open("/root/trackdir/instpkg.xml").read()
have = set(re.findall(r"<name>([^<]+)</name>", track))
add = [f"  <package><name>{n}</name><version>{versions[n]}</version></package>"
       for n in sorted(done) if n in versions and n not in have]
track = track.replace("</sublist>", "\n".join(add) + "\n</sublist>")
open("/root/trackdir/instpkg.xml", "w").write(track)
print(f"marked {len(add)} earlier BLFS builds installed")
PY
fi
# The tools bake installed versions into packages.xml when it is generated;
# editing the tracking file alone changes nothing. Regenerate it (its make
# rule depends on the tracking file).
make -s "$PWD/packages.xml"
conf=/work/blfs/targets.conf
[[ $STAGE == 1 ]] || conf=/work/blfs/targets-$STAGE.conf
cp "$conf" configuration
rm -rf scripts dependencies/*.{tree,dep} 2>/dev/null || true
mkdir -p dependencies
yes yes 2>/dev/null | ./gen_pkg_book.sh /root/trackdir/instpkg.xml /root/blfs_root || [[ ${PIPESTATUS[1]} == 0 ]]
rm -rf /root/stage-$STAGE && cp -r scripts /root/stage-$STAGE
ls /root/stage-$STAGE | wc -l
