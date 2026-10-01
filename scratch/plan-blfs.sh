#!/bin/bash
# Plan the desktop layer: resolve blfs/targets.conf against the BLFS 13.1
# book and generate build scripts, in the ultimate-blfs-plan volume.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
S=${BOOKS:-$here/out/books}
mkdir -p "$S"
[[ -d $S/blfs ]] || git clone -q --depth 1 --branch r13.1 https://git.linuxfromscratch.org/blfs.git "$S/blfs"
[[ -d $S/lfs ]] || git clone -q --depth 1 --branch r13.1 https://git.linuxfromscratch.org/lfs.git "$S/lfs"
# On a fresh machine the planner installs the BLFS tools from jhalfs
# (JHALFS_SRC, as build.sh uses it).
jh=${JHALFS_SRC:-$HOME/src/jhalfs}; jh_mount=(); [[ -d $jh ]] && jh_mount=(-v "$jh:/jhalfs-src:ro")
# STAGE=2 plans blfs/targets-2.conf on top of everything already built.
podman run --rm --security-opt label=disable -v ultimate-blfs-plan:/root "${jh_mount[@]}" \
  -e STAGE="${STAGE:-1}" -v ultimate-lfs-build:/built:ro \
  -v "$here:/work:ro" -v "$S/blfs:/books/blfs:ro" -v "$S/lfs:/books/lfs:ro" \
  -v ultimate-pacman-cache:/var/cache/pacman/pkg \
  docker.io/library/archlinux:latest bash /work/blfs/plan.sh
