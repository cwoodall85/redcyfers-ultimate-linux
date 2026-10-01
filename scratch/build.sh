#!/bin/bash
# Build Ultimate Linux from source: Linux From Scratch 13.1 (systemd) via
# jhalfs, with every final package made into a pacman package.
#
#   scratch/build.sh           start or resume the build (hours)
#   scratch/build.sh --shell   a shell in the build container
#
# The build tree and downloaded sources live in the Podman volumes
# ultimate-lfs-build and ultimate-lfs-sources, so a rebuild reuses them.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
jhalfs=${JHALFS_SRC:-$HOME/src/jhalfs}
[[ -d $jhalfs/.git ]] || git clone -q https://git.linuxfromscratch.org/jhalfs.git "$jhalfs"

args=(--rm --privileged --security-opt label=disable
      -v "$here:/work" -v "$jhalfs:/jhalfs-src:ro"
      -v ultimate-lfs-build:/mnt/build_dir -v ultimate-lfs-sources:/sources-cache
      -v ultimate-pacman-cache:/var/cache/pacman/pkg)
if [[ ${1:-} == --shell ]]; then
  exec podman run -it "${args[@]}" docker.io/library/archlinux:latest bash
fi
exec podman run "${args[@]}" docker.io/library/archlinux:latest bash /work/tools/container-lfs.sh
