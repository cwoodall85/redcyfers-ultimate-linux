#!/bin/bash
# Build packages natively ON Ultimate Linux, without installing anything:
# each finished package is unpacked into a staging root that the next
# builds see (headers, libraries, pkg-config files, tools), so a chain such
# as libslirp -> qemu -> libvirt builds in one go. Install the results
# afterwards with one `sudo pacman -Udd out/native/pkgs/*`.
#
#   tools/native-makepkg.sh packages/libslirp packages/qemu ...
#
# out/native/pkgs   the packages          out/native/stage  the staging root
# out/native/logs   one log per package   out/native/src    downloads
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
N=${NATIVE_OUT:-$here/out/native}
mkdir -p "$N"/{pkgs,stage,logs,src,build}
ST=$N/stage

# Every package already built is in the stage (re-extract: cheap, and keeps
# the stage right after a rebuild).
for f in "$N"/pkgs/*.pkg.tar.*; do
  [[ -e $f ]] && bsdtar -xf "$f" -C "$ST" --exclude '.PKGINFO' --exclude '.BUILDINFO' --exclude '.MTREE' --exclude '.INSTALL'
done

export PATH=$ST/usr/bin:$ST/usr/lib/go/bin:$ST/opt/protoc/bin:$PATH
# pkg-config files in the stage say prefix=/usr, which would send the
# compiler to the system's include directories (e.g. spice-1/): keep copies
# rewritten to point into the stage, refreshed after every package.
PC=$N/pc
restage_pc() {
  rm -rf "$PC"; mkdir -p "$PC"
  for f in "$ST"/usr/lib/pkgconfig/*.pc "$ST"/usr/share/pkgconfig/*.pc; do
    [[ -e $f ]] || continue
    sed -E "s#^(prefix|exec_prefix)=/usr\$#\1=$ST/usr#; s#=/usr/(include|lib|share)#=$ST/usr/\1#" "$f" > "$PC/${f##*/}"
  done
}
restage_pc
export PKG_CONFIG_PATH=$PC${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
export C_INCLUDE_PATH=$ST/usr/include CPLUS_INCLUDE_PATH=$ST/usr/include
export LIBRARY_PATH=$ST/usr/lib LD_LIBRARY_PATH=$ST/usr/lib
py=$(python3 -c 'import sys; print(f"python{sys.version_info[0]}.{sys.version_info[1]}")')
export PYTHONPATH=$ST/usr/lib/$py/site-packages
export GI_TYPELIB_PATH=$ST/usr/lib/girepository-1.0 XDG_DATA_DIRS=$ST/usr/share:${XDG_DATA_DIRS:-/usr/share}
export NATIVE_STAGE=$ST
export MAKEFLAGS=${MAKEFLAGS:--j$(nproc)}

for d in "$@"; do
  d=$(cd "$d" && pwd); name=${d##*/}
  printf '%-22s ' "$name"
  start=$SECONDS
  if (cd "$d" && BUILDDIR=$N/build SRCDEST=$N/src PKGDEST=$N/pkgs \
        makepkg -df --noconfirm --cleanbuild) >"$N/logs/$name.log" 2>&1; then
    for f in $(cd "$d" && BUILDDIR=$N/build PKGDEST=$N/pkgs makepkg --packagelist); do
      bsdtar -xf "$f" -C "$ST" --exclude '.PKGINFO' --exclude '.BUILDINFO' --exclude '.MTREE' --exclude '.INSTALL'
    done
    restage_pc
    echo "ok  $((SECONDS-start))s"
  else
    echo "FAILED  (see $N/logs/$name.log)"; tail -15 "$N/logs/$name.log"; exit 1
  fi
done
